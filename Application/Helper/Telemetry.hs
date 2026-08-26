{-# LANGUAGE ScopedTypeVariables #-}

module Application.Helper.Telemetry
    ( annotateTelemetryAction
    , addTelemetryAttributes
    , addTelemetryEvent
    , telemetryMiddleware
    , withTelemetrySpan
    , withTelemetrySpanAttributes
    ) where

import Control.Exception (SomeException, try)
import qualified Control.Exception as Exception
import Data.ByteString (ByteString)
import qualified Data.CaseInsensitive as CaseInsensitive
import Data.Data (Data, toConstr)
import qualified Data.HashMap.Strict as HashMap
import qualified Data.Text.Encoding as TextEncoding
import qualified Data.Text.Encoding.Error as TextEncodingError
import IHP.Controller.Response (ResponseException)
import IHP.Prelude
import Network.HTTP.Types.Header (Header)
import qualified Network.Wai as Wai
import OpenTelemetry.Attributes (Attribute, toAttribute)
import qualified OpenTelemetry.Context as OtelContext
import qualified OpenTelemetry.Context.ThreadLocal as OtelContextThreadLocal
import qualified OpenTelemetry.Instrumentation.Wai as OtelWai
import qualified OpenTelemetry.Trace as Otel
import System.Environment (lookupEnv)
import System.IO.Unsafe (unsafePerformIO)

-- | WAI middleware for lightweight OpenTelemetry request tracing.
--
-- The middleware is completely inert unless IHP_ROSTER_OTEL=1. The underlying
-- WAI instrumentation is project-patched in Config/nix/flake/overlays.nix to
-- avoid emitting raw query strings in url.query/http.target attributes.
telemetryMiddleware :: Wai.Middleware
telemetryMiddleware app request respond = do
    enabled <- telemetryEnabled
    if enabled
        then initializedTelemetryMiddleware (diagnosticHeaderMiddleware app) request respond
        else app request respond

-- | Annotates the current WAI root span with the low-cardinality IHP action
-- constructor name, e.g. ShowRosterWindowAction. This avoids path ids and query
-- strings while still making traces navigable.
annotateTelemetryAction :: forall action. (Data action, ?theAction :: action, ?request :: Wai.Request) => IO ()
annotateTelemetryAction = whenTelemetryEnabled do
    case OtelWai.requestContext ?request >>= OtelContext.lookupSpan of
        Nothing -> pure ()
        Just span' -> do
            let actionName = show (toConstr ?theAction)
            Otel.addAttributes span' $ HashMap.fromList
                [ ("http.route", toAttribute actionName)
                , ("bepis.ihp.action", toAttribute actionName)
                ]
            Otel.updateName span' actionName

-- | Runs an action in a named child span when OTel is enabled. This is the
-- lightweight hook used by the existing profiling helpers in later slices.
addTelemetryAttributes :: [(Text, Attribute)] -> IO ()
addTelemetryAttributes attributes = whenTelemetryEnabled do
    context <- OtelContextThreadLocal.getContext
    forEach (OtelContext.lookupSpan context) \span' ->
        Otel.addAttributes span' (HashMap.fromList attributes)

addTelemetryEvent :: Text -> [(Text, Attribute)] -> IO ()
addTelemetryEvent name attributes = whenTelemetryEnabled do
    context <- OtelContextThreadLocal.getContext
    forEach (OtelContext.lookupSpan context) \span' ->
        Otel.addEvent span' Otel.NewEvent
            { Otel.newEventName = name
            , Otel.newEventAttributes = HashMap.fromList attributes
            , Otel.newEventTimestamp = Nothing
            }

withTelemetrySpan :: Text -> IO a -> IO a
withTelemetrySpan name = withTelemetrySpanAttributes name []

withTelemetrySpanAttributes :: forall a. Text -> [(Text, Attribute)] -> IO a -> IO a
withTelemetrySpanAttributes name attributes action = do
    enabled <- telemetryEnabled
    if enabled
        then do
            tracerProvider <- Otel.getGlobalTracerProvider
            let tracer = Otel.makeTracer tracerProvider "ihp-roster" Otel.tracerOptions
            result <- Otel.inSpan tracer name (spanArguments attributes) (try action :: IO (Either ResponseException a))
            case result of
                Left responseException -> Exception.throwIO responseException
                Right value            -> pure value
        else action

spanArguments :: [(Text, Attribute)] -> Otel.SpanArguments
spanArguments attributes =
    Otel.defaultSpanArguments { Otel.attributes = HashMap.fromList attributes }

diagnosticHeaderMiddleware :: Wai.Middleware
diagnosticHeaderMiddleware app request respond = do
    annotateDiagnosticHeaders request
    app request respond

annotateDiagnosticHeaders :: Wai.Request -> IO ()
annotateDiagnosticHeaders request = do
    enabled <- diagnosticHeadersEnabled
    when enabled do
        let requestHeaders = Wai.requestHeaders request
        let maybeRun = headerText "X-Bepis-Trace-Run" requestHeaders
        let maybeStep = headerText "X-Bepis-Trace-Step" requestHeaders
        addTelemetryAttributes $
            catMaybes
                [ fmap (\value -> ("bepis.trace.run", toAttribute value)) maybeRun
                , fmap (\value -> ("bepis.trace.step", toAttribute value)) maybeStep
                ]

headerText :: ByteString -> [Header] -> Maybe Text
headerText name headers =
    decodeHeaderValue <$> lookup (CaseInsensitive.mk name) headers

decodeHeaderValue :: ByteString -> Text
decodeHeaderValue =
    TextEncoding.decodeUtf8With TextEncodingError.lenientDecode

initializedTelemetryMiddleware :: Wai.Middleware
initializedTelemetryMiddleware = unsafePerformIO do
    initializeTelemetry
    OtelWai.newOpenTelemetryWaiMiddleware
{-# NOINLINE initializedTelemetryMiddleware #-}

initializeTelemetry :: IO ()
initializeTelemetry = do
    result :: Either SomeException Otel.TracerProvider <- try Otel.initializeGlobalTracerProvider
    case result of
        Right _ -> pure ()
        Left exception -> putStrLn ("otel_init_failure: " <> cs (displayException exception))

whenTelemetryEnabled :: IO () -> IO ()
whenTelemetryEnabled action = do
    enabled <- telemetryEnabled
    when enabled action

diagnosticHeadersEnabled :: IO Bool
diagnosticHeadersEnabled = (== Just "1") <$> lookupEnv "IHP_ROSTER_OTEL_DIAGNOSTIC_HEADERS"

telemetryEnabled :: IO Bool
telemetryEnabled = (== Just "1") <$> lookupEnv "IHP_ROSTER_OTEL"
