module Application.Helper.Profiling
    ( RequestProfile (..)
    , RequestProfileSpan (..)
    , emitRequestProfileResponseHeaders
    , initRequestProfiling
    , isRequestProfilingEnabled
    , profileActionSpan
    , profileActionSpanWithDetail
    , profileCounter
    , profileHtmlComponent
    , profileRenderCounter
    , profilingMiddleware
    , renderProfiled
    , respondHtmlProfiled
    ) where

import Application.Helper.Telemetry (addTelemetryAttributes, withTelemetrySpan,
                                     withTelemetrySpanAttributes)
import Control.Exception (evaluate)
import qualified Data.ByteString.Lazy as LByteString
import qualified Data.Char as Char
import Data.IORef
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import qualified Data.Text.Lazy.Encoding as LazyTextEncoding
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUIDv4
import qualified Data.Vault.Lazy as Vault
import GHC.Clock (getMonotonicTimeNSec)
import IHP.Controller.Context (ControllerContext, maybeFromContext, putContext)
import IHP.Controller.Render (renderHtml, respondHtml)
import IHP.ControllerSupport (Respond, respondAndExitWithHeaders, setHeader)
import IHP.Prelude
import IHP.ViewSupport (View)
import Network.HTTP.Types (status200)
import Network.HTTP.Types.Header (Header, hConnection, hContentType)
import Network.Wai (Middleware, Request, Response, responseLBS)
import qualified Network.Wai as Wai
import OpenTelemetry.Attributes (toAttribute)
import qualified System.Environment as Environment
import System.IO.Unsafe (unsafePerformIO)
import qualified Text.Blaze.Html as Blaze
import qualified Text.Blaze.Html.Renderer.Utf8 as BlazeUtf8

data RequestProfile = RequestProfile
    { requestProfileId :: !Text
    , startedAtNs      :: !Word64
    , spansRef         :: !(IORef [RequestProfileSpan])
    , countersRef      :: !(IORef (Map Text Int))
    , nextSpanOrderRef :: !(IORef Int)
    , emittedRef       :: !(IORef Bool)
    }

data RequestProfileSpan = RequestProfileSpan
    { spanOrder  :: !Int
    , spanName   :: !Text
    , durationMs :: !Double
    , detail     :: !(Maybe Text)
    }
    deriving (Eq, Show)

requestProfileVaultKey :: Vault.Key (IORef (Maybe RequestProfile))
requestProfileVaultKey = unsafePerformIO Vault.newKey
{-# NOINLINE requestProfileVaultKey #-}

profilingMiddleware :: Middleware
profilingMiddleware app request respond = do
    maybeProfile <- newRequestProfileIfEnabled
    profileRef <- newIORef maybeProfile
    let request' = request { Wai.vault = Vault.insert requestProfileVaultKey profileRef request.vault }
    app request' \response -> do
        finalizedResponse <- finalizeResponseProfileHeaders request' profileRef response
        respond finalizedResponse

initRequestProfiling :: (?context :: ControllerContext) => IO ()
initRequestProfiling = do
    existingProfile :: Maybe RequestProfile <- maybeFromContext
    case existingProfile of
        Just _ -> pure ()
        Nothing -> do
            maybeProfile <- currentRequestProfileFromVault ?context.request
            case maybeProfile of
                Just profile -> putContext profile
                Nothing -> do
                    -- Fallback for controller tests or non-standard entrypoints that
                    -- call initContext without the app middleware stack.
                    maybeStandaloneProfile <- newRequestProfileIfEnabled
                    forEach maybeStandaloneProfile putContext

profileActionSpan :: (?context :: ControllerContext) => Text -> IO a -> IO a
profileActionSpan name action =
    profileActionSpanWithDetail name (fmap (, Nothing) action)

profileCounter :: (?context :: ControllerContext) => Text -> Int -> IO ()
profileCounter name amount = do
    maybeProfile :: Maybe RequestProfile <- maybeFromContext
    forEach maybeProfile \profile -> appendRequestProfileCounter profile name amount

profileRenderCounter :: (?context :: ControllerContext) => Text -> Int -> Blaze.Html
profileRenderCounter name amount =
    unsafePerformIO do
        profileCounter name amount
        pure mempty
{-# NOINLINE profileRenderCounter #-}

profileHtmlComponent :: (?context :: ControllerContext) => Text -> Blaze.Html -> Blaze.Html
profileHtmlComponent name html =
    unsafePerformIO do
        maybeProfile :: Maybe RequestProfile <- maybeFromContext
        case maybeProfile of
            Nothing -> pure html
            Just profile ->
                withTelemetrySpanAttributes name [("bepis.profile.diagnostic", toAttribute True)] do
                    startedAtNs <- getMonotonicTimeNSec
                    let !htmlBytes = BlazeUtf8.renderHtml html
                    byteCount <- evaluate (LByteString.length htmlBytes)
                    completedAtNs <- getMonotonicTimeNSec
                    addTelemetryAttributes [("html.bytes", toAttribute (fromIntegral byteCount :: Int))]
                    appendRequestProfileSpan profile
                        RequestProfileSpan
                            { spanOrder = 0
                            , spanName = name
                            , durationMs = durationBetweenMs startedAtNs completedAtNs
                            , detail = Just ("bytes=" <> tshow byteCount)
                            }
                    pure (Blaze.preEscapedToHtml (LazyTextEncoding.decodeUtf8 htmlBytes))
{-# NOINLINE profileHtmlComponent #-}

renderProfiled :: (View view, ?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => view -> IO ()
renderProfiled view = do
    html <- profileActionSpan "render.ihp_view" (renderHtml view)
    respondHtmlProfiled html

respondHtmlProfiled :: (?context :: ControllerContext, ?request :: Request) => Blaze.Html -> IO ()
respondHtmlProfiled html = do
    maybeProfile :: Maybe RequestProfile <- maybeFromContext
    case maybeProfile of
        Nothing -> respondHtml html
        Just profile -> do
            (htmlBytes, byteCount) <-
                withTelemetrySpanAttributes "render.respond_html" [("bepis.profile.diagnostic", toAttribute True)] do
                    startedAtNs <- getMonotonicTimeNSec
                    let !htmlBytes = BlazeUtf8.renderHtml html
                    byteCount <- evaluate (LByteString.length htmlBytes)
                    completedAtNs <- getMonotonicTimeNSec
                    addTelemetryAttributes [("html.bytes", toAttribute (fromIntegral byteCount :: Int))]
                    appendRequestProfileSpan profile
                        RequestProfileSpan
                            { spanOrder = 0
                            , spanName = "render.respond_html"
                            , durationMs = durationBetweenMs startedAtNs completedAtNs
                            , detail = Just ("bytes=" <> tshow byteCount)
                            }
                    pure (htmlBytes, byteCount)
            respondAndExitWithHeaders $
                responseLBS
                    status200
                    [ (hContentType, "text/html; charset=utf-8")
                    , (hConnection, "keep-alive")
                    , ("X-Profile-Response-Bytes", cs (tshow byteCount))
                    ]
                    htmlBytes

emitRequestProfileResponseHeaders :: (?context :: ControllerContext, ?request :: Request) => IO ()
emitRequestProfileResponseHeaders = do
    maybeProfile :: Maybe RequestProfile <- maybeFromContext
    forEach maybeProfile \profile -> do
        maybeHeaders <- finalizeRequestProfile ?request profile
        forEach maybeHeaders (`forEach` setHeader)

isRequestProfilingEnabled :: IO Bool
isRequestProfilingEnabled = do
    maybeValue <- Environment.lookupEnv "IHP_ROSTER_PROFILING"
    pure (maybe False isEnabledValue maybeValue)
    where
        isEnabledValue value =
            value `elem` ["1", "true", "TRUE", "yes", "YES", "on", "ON"]

profileActionSpanWithDetail :: (?context :: ControllerContext) => Text -> IO (a, Maybe Text) -> IO a
profileActionSpanWithDetail name action =
    withTelemetrySpan name do
        maybeProfile :: Maybe RequestProfile <- maybeFromContext
        case maybeProfile of
            Nothing -> fst <$> action
            Just profile -> do
                startedAtNs <- getMonotonicTimeNSec
                (result, detail) <- action
                completedAtNs <- getMonotonicTimeNSec
                appendRequestProfileSpan profile
                    RequestProfileSpan
                        { spanOrder = 0
                        , spanName = name
                        , durationMs = durationBetweenMs startedAtNs completedAtNs
                        , detail
                        }
                pure result

appendRequestProfileSpan :: RequestProfile -> RequestProfileSpan -> IO ()
appendRequestProfileSpan profile span = do
    spanOrder <- atomicModifyIORef' profile.nextSpanOrderRef \nextOrder -> (nextOrder + 1, nextOrder)
    atomicModifyIORef' profile.spansRef \spans ->
        (span { spanOrder } : spans, ())

appendRequestProfileCounter :: RequestProfile -> Text -> Int -> IO ()
appendRequestProfileCounter profile name amount =
    when (amount /= 0) do
        atomicModifyIORef' profile.countersRef \counters ->
            (Map.insertWith (+) name amount counters, ())

newRequestProfileIfEnabled :: IO (Maybe RequestProfile)
newRequestProfileIfEnabled = do
    profilingEnabled <- isRequestProfilingEnabled
    if profilingEnabled
        then Just <$> newRequestProfile
        else pure Nothing

newRequestProfile :: IO RequestProfile
newRequestProfile = do
    startedAtNs <- getMonotonicTimeNSec
    requestProfileId <- UUID.toText <$> UUIDv4.nextRandom
    spansRef <- newIORef []
    countersRef <- newIORef Map.empty
    nextSpanOrderRef <- newIORef 0
    emittedRef <- newIORef False
    pure
        RequestProfile
            { requestProfileId
            , startedAtNs
            , spansRef
            , countersRef
            , nextSpanOrderRef
            , emittedRef
            }

currentRequestProfileFromVault :: Request -> IO (Maybe RequestProfile)
currentRequestProfileFromVault request =
    case Vault.lookup requestProfileVaultKey request.vault of
        Nothing  -> pure Nothing
        Just ref -> readIORef ref

finalizeResponseProfileHeaders :: Request -> IORef (Maybe RequestProfile) -> Response -> IO Response
finalizeResponseProfileHeaders request profileRef response = do
    maybeProfile <- readIORef profileRef
    case maybeProfile of
        Nothing -> pure response
        Just profile -> do
            maybeHeaders <- finalizeRequestProfile request profile
            pure case maybeHeaders of
                Nothing -> response
                Just headers ->
                    Wai.mapResponseHeaders (headers <>) response

finalizeRequestProfile :: Request -> RequestProfile -> IO (Maybe [Header])
finalizeRequestProfile request profile = do
    wasEmitted <- readIORef profile.emittedRef
    if wasEmitted
        then pure Nothing
        else do
            writeIORef profile.emittedRef True
            completedAtNs <- getMonotonicTimeNSec
            spans <- List.sortOn spanOrder <$> readIORef profile.spansRef
            counters <- readIORef profile.countersRef
            let totalDurationMs = durationBetweenMs profile.startedAtNs completedAtNs
            let counterHeaders =
                    [ ("X-Profile-Counters", cs (renderProfileCounters counters))
                    | not (Map.null counters)
                    ]
            let headers =
                    [ ("X-Request-Id", cs profile.requestProfileId)
                    , ("Server-Timing", cs (renderServerTiming totalDurationMs spans))
                    ] <> counterHeaders
            pure (Just headers)

durationBetweenMs :: Word64 -> Word64 -> Double
durationBetweenMs startedAtNs completedAtNs =
    fromIntegral (completedAtNs - startedAtNs) / 1000000

renderServerTiming :: Double -> [RequestProfileSpan] -> Text
renderServerTiming totalDurationMs spans =
    Text.intercalate ", " (renderTimingMetric "app_total" totalDurationMs Nothing : map renderSpan spans)
    where
        renderSpan RequestProfileSpan { spanName, durationMs, detail } =
            renderTimingMetric (sanitizeTimingToken spanName) durationMs detail

renderProfileCounters :: Map Text Int -> Text
renderProfileCounters counters =
    Text.intercalate "," (map renderCounter (Map.toAscList counters))
    where
        renderCounter (name, amount) = sanitizeTimingToken name <> "=" <> tshow amount

renderTimingMetric :: Text -> Double -> Maybe Text -> Text
renderTimingMetric metricName durationMs detail =
    Text.intercalate ";" (baseParts <> detailParts)
    where
        baseParts =
            [ metricName
            , "dur=" <> renderDuration durationMs
            ]
        detailParts =
            maybe [] (\value -> ["desc=\"" <> sanitizeTimingDescription value <> "\""]) detail

renderDuration :: Double -> Text
renderDuration durationMs =
    tshow (fromIntegral (round (durationMs * 10)) / 10 :: Double)

sanitizeTimingToken :: Text -> Text
sanitizeTimingToken =
    Text.map (\char -> if Char.isAlphaNum char then char else '_')

sanitizeTimingDescription :: Text -> Text
sanitizeTimingDescription =
    Text.filter (\char -> char /= '"' && char /= '\n' && char /= '\r')

renderRequestProfileLog :: (?request :: Request) => Text -> Double -> [RequestProfileSpan] -> Text
renderRequestProfileLog requestProfileId totalDurationMs spans =
    Text.intercalate
        " "
        [ "[perf]"
        , requestMethodText
        , requestPathText
        , "request_id=" <> requestProfileId
        , "total_ms=" <> renderDuration totalDurationMs
        , "spans=" <> renderSpanSummary spans
        ]
    where
        requestMethodText = cs (Wai.requestMethod ?request)
        requestPathText = cs (Wai.rawPathInfo ?request)

renderSpanSummary :: [RequestProfileSpan] -> Text
renderSpanSummary spans =
    Text.intercalate "|" (map renderSpan spans)
    where
        renderSpan RequestProfileSpan { spanName, durationMs, detail } =
            spanName
                <> "="
                <> renderDuration durationMs
                <> maybe "" (\value -> "[" <> value <> "]") detail
