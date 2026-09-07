module Application.Helper.Profiling
    ( isRequestProfilingEnabled
    , profileActionSpan
    , profileActionSpanWithDetail
    , profileHtmlComponent
    , profileRenderCounter
    , profilingMiddleware
    , renderProfiled
    , respondHtmlProfiled
    ) where

import Application.Bepis.Response (bepisHtmlResponse, bepisHtmxFragmentResponse)
import Application.Helper.Telemetry (addTelemetryAttributes, addTelemetryEvent,
                                     withTelemetrySpan,
                                     withTelemetrySpanAttributes)
import Control.Concurrent (ThreadId, myThreadId)
import Control.Exception (bracket, bracket_, evaluate)
import qualified Data.ByteString.Lazy as LByteString
import qualified Data.Char as Char
import Data.IORef
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUIDv4
import qualified Data.Vault.Lazy as Vault
import GHC.Clock (getMonotonicTimeNSec)
import IHP.Controller.Render (renderHtml, respondHtml)
import IHP.ControllerSupport (ControllerContext, Respond, ResponseReceived, respondWith)
import IHP.Prelude
import IHP.ViewSupport (View)
import Network.HTTP.Types (status200)
import Network.HTTP.Types.Header (Header, hConnection, hContentType)
import Network.Wai (Middleware, Request, Response, responseLBS)
import qualified Network.Wai as Wai
import OpenTelemetry.Attributes (Attribute, toAttribute)
import qualified System.Environment as Environment
import System.IO.Unsafe (unsafePerformIO)
import qualified IHP.HSX.Markup as Markup

data RequestProfile = RequestProfile
    { requestProfileId :: !Text
    , startedAtNs      :: !Word64
    , spansRef         :: !(IORef [RequestProfileSpan])
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

activeRenderCounterRefs :: IORef (Map ThreadId [IORef (Map Text Int)])
activeRenderCounterRefs = unsafePerformIO (newIORef Map.empty)
{-# NOINLINE activeRenderCounterRefs #-}

profilingMiddleware :: Middleware
profilingMiddleware app request respond = do
    maybeProfile <- newRequestProfileIfEnabled
    profileRef <- newIORef maybeProfile
    let request' = request { Wai.vault = Vault.insert requestProfileVaultKey profileRef request.vault }
    app request' \response -> do
        finalizedResponse <- finalizeResponseProfileHeaders request' profileRef response
        respond finalizedResponse

profileActionSpan :: (?context :: ControllerContext) => Text -> IO a -> IO a
profileActionSpan name action =
    profileActionSpanWithDetail name (fmap (, Nothing) action)

profileCounter :: (?context :: ControllerContext) => Text -> Int -> IO ()
profileCounter name amount = do
    maybeProfile <- currentRequestProfileFromVault ?context
    forEach maybeProfile \_ ->
        appendActiveRenderCounter name amount

profileRenderCounter :: (?context :: ControllerContext) => Text -> Int -> Markup.Html
profileRenderCounter name amount =
    unsafePerformIO do
        profileCounter name amount
        pure mempty
{-# NOINLINE profileRenderCounter #-}

profileHtmlComponent :: (?context :: ControllerContext) => Text -> Markup.Html -> Markup.Html
profileHtmlComponent name html =
    unsafePerformIO do
        maybeProfile <- currentRequestProfileFromVault ?context
        case maybeProfile of
            Nothing -> pure html
            Just profile ->
                withTelemetrySpanAttributes name [("bepis.profile.diagnostic", toAttribute True)] do
                    withRenderCounterScope \counterRef -> do
                        startedAtNs <- getMonotonicTimeNSec
                        let !htmlBytes = Markup.renderMarkup html
                        byteCount <- evaluate (LByteString.length htmlBytes)
                        completedAtNs <- getMonotonicTimeNSec
                        counters <- readIORef counterRef
                        addTelemetryAttributes $
                            [("html.bytes", toAttribute (fromIntegral byteCount :: Int))]
                                <> telemetryCounterAttributes counters
                        unless (Map.null counters) $
                            addTelemetryEvent "bepis.render.counters" (telemetryCounterAttributes counters)
                        appendRequestProfileSpan profile
                            RequestProfileSpan
                                { spanOrder = 0
                                , spanName = name
                                , durationMs = durationBetweenMs startedAtNs completedAtNs
                                , detail = Nothing
                                }
                        pure (mconcat (map Markup.rawByteString (LByteString.toChunks htmlBytes)))
{-# NOINLINE profileHtmlComponent #-}

renderProfiled :: (View view, ?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => view -> IO ResponseReceived
renderProfiled view = do
    html <- profileActionSpan "render.ihp_view" (renderHtml view)
    respondHtmlProfiled html

respondHtmlProfiled :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => Markup.Html -> IO ResponseReceived
respondHtmlProfiled html =
    annotateHtmlResponse do
        maybeProfile <- currentRequestProfileFromVault ?context
        case maybeProfile of
            Nothing -> respondHtml html
            Just profile -> do
                (htmlBytes, byteCount) <-
                    withTelemetrySpanAttributes "render.respond_html" [("bepis.profile.diagnostic", toAttribute True)] do
                        startedAtNs <- getMonotonicTimeNSec
                        let !htmlBytes = Markup.renderMarkup html
                        byteCount <- evaluate (LByteString.length htmlBytes)
                        completedAtNs <- getMonotonicTimeNSec
                        addTelemetryAttributes [("html.bytes", toAttribute (fromIntegral byteCount :: Int))]
                        appendRequestProfileSpan profile
                            RequestProfileSpan
                                { spanOrder = 0
                                , spanName = "render.respond_html"
                                , durationMs = durationBetweenMs startedAtNs completedAtNs
                                , detail = Nothing
                                }
                        pure (htmlBytes, byteCount)
                respondWith $
                    responseLBS
                        status200
                        [ (hContentType, "text/html; charset=utf-8")
                        , (hConnection, "keep-alive")
                        ]
                        htmlBytes
    where
        annotateHtmlResponse =
            if isProfilingHtmxRequest
                then bepisHtmxFragmentResponse
                else bepisHtmlResponse

isProfilingHtmxRequest :: (?context :: ControllerContext) => Bool
isProfilingHtmxRequest = lookup "HX-Request" ?context.requestHeaders == Just "true"

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
        maybeProfile <- currentRequestProfileFromVault ?context
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

appendActiveRenderCounter :: Text -> Int -> IO ()
appendActiveRenderCounter name amount =
    when (amount /= 0) do
        threadId <- myThreadId
        counterRefsByThread <- readIORef activeRenderCounterRefs
        forEach (Map.findWithDefault [] threadId counterRefsByThread) \counterRef ->
            atomicModifyIORef' counterRef \counters ->
                (Map.insertWith (+) name amount counters, ())

withRenderCounterScope :: (IORef (Map Text Int) -> IO a) -> IO a
withRenderCounterScope action = do
    threadId <- myThreadId
    counterRef <- newIORef Map.empty
    bracket_
        (atomicModifyIORef' activeRenderCounterRefs \refsByThread -> (Map.insertWith (<>) threadId [counterRef] refsByThread, ()))
        (atomicModifyIORef' activeRenderCounterRefs \refsByThread -> (removeRenderCounterRef threadId counterRef refsByThread, ()))
        (action counterRef)

removeRenderCounterRef :: ThreadId -> IORef (Map Text Int) -> Map ThreadId [IORef (Map Text Int)] -> Map ThreadId [IORef (Map Text Int)]
removeRenderCounterRef threadId counterRef refsByThread =
    case List.delete counterRef (Map.findWithDefault [] threadId refsByThread) of
        []   -> Map.delete threadId refsByThread
        refs -> Map.insert threadId refs refsByThread

telemetryCounterAttributes :: Map Text Int -> [(Text, Attribute)]
telemetryCounterAttributes counters =
    [ (name, toAttribute amount)
    | (name, amount) <- Map.toAscList counters
    , amount /= 0
    ]

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
    nextSpanOrderRef <- newIORef 0
    emittedRef <- newIORef False
    pure
        RequestProfile
            { requestProfileId
            , startedAtNs
            , spansRef
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
            let totalDurationMs = durationBetweenMs profile.startedAtNs completedAtNs
            let headers =
                    [ ("X-Request-Id", cs profile.requestProfileId)
                    , ("Server-Timing", cs (renderServerTiming totalDurationMs spans))
                    ]
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
