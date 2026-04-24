module Application.Helper.Profiling
    ( RequestProfile (..)
    , RequestProfileSpan (..)
    , emitRequestProfileResponseHeaders
    , initRequestProfiling
    , profileActionSpan
    , profileActionSpanWithDetail
    , renderProfiled
    , respondHtmlProfiled
    ) where

import qualified Data.Char as Char
import Data.IORef
import qualified Data.List as List
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import GHC.Clock (getMonotonicTimeNSec)
import IHP.Controller.Context (ControllerContext, maybeFromContext, putContext)
import IHP.Controller.Render (render, respondHtml)
import IHP.ControllerSupport (setHeader)
import IHP.Environment (Environment (Development))
import IHP.FrameworkConfig (isDevelopment)
import IHP.Prelude
import IHP.ViewSupport (View)
import Network.Wai (Request)
import qualified Network.Wai as Wai
import qualified Text.Blaze.Html as Blaze

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

initRequestProfiling :: (?context :: ControllerContext) => IO ()
initRequestProfiling = do
    existingProfile :: Maybe RequestProfile <- maybeFromContext
    case existingProfile of
        Just _ -> pure ()
        Nothing -> do
            startedAtNs <- getMonotonicTimeNSec
            let requestProfileId = "req-" <> tshow startedAtNs
            spansRef <- newIORef []
            nextSpanOrderRef <- newIORef 0
            emittedRef <- newIORef False
            putContext
                RequestProfile
                    { requestProfileId
                    , startedAtNs
                    , spansRef
                    , nextSpanOrderRef
                    , emittedRef
                    }

profileActionSpan :: (?context :: ControllerContext) => Text -> IO a -> IO a
profileActionSpan name action =
    profileActionSpanWithDetail name (fmap (, Nothing) action)

renderProfiled :: (View view, ?context :: ControllerContext, ?request :: Request) => view -> IO ()
renderProfiled view = do
    emitRequestProfileResponseHeaders
    render view

respondHtmlProfiled :: (?context :: ControllerContext, ?request :: Request) => Blaze.Html -> IO ()
respondHtmlProfiled html = do
    emitRequestProfileResponseHeaders
    respondHtml html

emitRequestProfileResponseHeaders :: (?context :: ControllerContext, ?request :: Request) => IO ()
emitRequestProfileResponseHeaders = do
    maybeProfile :: Maybe RequestProfile <- maybeFromContext
    forEach maybeProfile \profile -> do
        wasEmitted <- readIORef profile.emittedRef
        unless wasEmitted do
            writeIORef profile.emittedRef True
            completedAtNs <- getMonotonicTimeNSec
            spans <- List.sortOn spanOrder <$> readIORef profile.spansRef
            let totalDurationMs = durationBetweenMs profile.startedAtNs completedAtNs
            setHeader ("X-Request-Id", cs profile.requestProfileId)
            setHeader ("Server-Timing", cs (renderServerTiming totalDurationMs spans))
            when isDevelopment do
                TextIO.putStrLn (renderRequestProfileLog profile.requestProfileId totalDurationMs spans)

profileActionSpanWithDetail :: (?context :: ControllerContext) => Text -> IO (a, Maybe Text) -> IO a
profileActionSpanWithDetail name action = do
    startedAtNs <- getMonotonicTimeNSec
    (result, detail) <- action
    completedAtNs <- getMonotonicTimeNSec
    appendRequestProfileSpan
        RequestProfileSpan
            { spanOrder = 0
            , spanName = name
            , durationMs = durationBetweenMs startedAtNs completedAtNs
            , detail
            }
    pure result

appendRequestProfileSpan :: (?context :: ControllerContext) => RequestProfileSpan -> IO ()
appendRequestProfileSpan span = do
    maybeProfile :: Maybe RequestProfile <- maybeFromContext
    forEach maybeProfile \profile -> do
        spanOrder <- atomicModifyIORef' profile.nextSpanOrderRef \nextOrder -> (nextOrder + 1, nextOrder)
        atomicModifyIORef' profile.spansRef \spans ->
            (span { spanOrder } : spans, ())

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
