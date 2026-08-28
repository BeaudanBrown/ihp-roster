{-# LANGUAGE ScopedTypeVariables #-}

module Application.Helper.Telemetry
    ( addTelemetryAttributes
    , addTelemetryEvent
    , annotateTelemetryAction
    , diagnosticHeaderValue
    , flushTelemetry
    , telemetryMiddleware
    , withTelemetryRuntime
    , withTelemetrySpan
    , withTelemetrySpanAttributes
    ) where

import Control.Exception (SomeException, bracket, try)
import qualified Control.Exception as Exception
import Control.Monad (guard)
import Data.ByteString (ByteString)
import qualified Data.ByteString as ByteString
import qualified Data.CaseInsensitive as CaseInsensitive
import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.Data (Data, toConstr)
import qualified Data.HashMap.Strict as HashMap
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import IHP.Controller.Response (ResponseException)
import IHP.Prelude
import Network.HTTP.Types.Header (Header)
import qualified Network.Wai as Wai
import OpenTelemetry.Attributes (Attribute, toAttribute)
import qualified OpenTelemetry.Context as OtelContext
import qualified OpenTelemetry.Context.ThreadLocal as OtelContextThreadLocal
import qualified OpenTelemetry.Instrumentation.Wai as OtelWai
import qualified OpenTelemetry.Trace as Otel
import qualified OpenTelemetry.Trace.Core as OtelCore
import System.Environment (lookupEnv)
import System.IO.Unsafe (unsafePerformIO)
import qualified System.Timeout as Timeout
import Text.Read (readMaybe)

-- | Owns the process-level SDK lifecycle. Disabled mode executes the supplied
-- action directly: it creates no provider, exporter, worker thread, or timer.
-- Initialization and exporter shutdown failures are reported but never replace
-- the application's result or prevent shutdown.
withTelemetryRuntime :: IO a -> IO a
withTelemetryRuntime action
    | not telemetryEnabledFlag = action
    | otherwise = bracket initializeTelemetry shutdownTelemetry (const action)

-- | WAI request tracing. Provider initialization belongs to
-- 'withTelemetryRuntime', not middleware construction.
telemetryMiddleware :: Wai.Middleware
telemetryMiddleware
    | telemetryEnabledFlag = initializedTelemetryMiddleware . diagnosticHeaderMiddleware
    | otherwise = id

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
withTelemetrySpanAttributes name attributes action =
    if not telemetryEnabledFlag
        then action
        else do
            tracerProvider <- Otel.getGlobalTracerProvider
            let tracer = Otel.makeTracer tracerProvider "ihp-roster" Otel.tracerOptions
            -- IHP uses ResponseException for successful response control flow.
            -- Catch it inside inSpan so the SDK does not classify it as an error.
            result <- Otel.inSpan tracer name (spanArguments attributes) (try action :: IO (Either ResponseException a))
            case result of
                Left responseException -> Exception.throwIO responseException
                Right value            -> pure value

spanArguments :: [(Text, Attribute)] -> Otel.SpanArguments
spanArguments attributes =
    Otel.defaultSpanArguments { Otel.attributes = HashMap.fromList attributes }

diagnosticHeaderMiddleware :: Wai.Middleware
diagnosticHeaderMiddleware app request respond = do
    annotateDiagnosticHeaders request
    app request respond

annotateDiagnosticHeaders :: Wai.Request -> IO ()
annotateDiagnosticHeaders request = when diagnosticHeadersEnabledFlag do
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
    lookup (CaseInsensitive.mk name) headers >>= diagnosticHeaderValue

-- | Accepts only bounded printable identifiers used by trusted diagnostic
-- tooling. Invalid UTF-8, whitespace, control characters, and free-form text
-- are discarded rather than normalized into searchable trace attributes.
diagnosticHeaderValue :: ByteString -> Maybe Text
diagnosticHeaderValue raw
    | ByteString.length raw > diagnosticHeaderMaxBytes = Nothing
    | otherwise = do
        value <- either (const Nothing) Just (TextEncoding.decodeUtf8' raw)
        guard (not (Text.null value))
        guard (Text.all isDiagnosticHeaderCharacter value)
        pure value
  where
    isDiagnosticHeaderCharacter character =
        isAsciiLower character
            || isAsciiUpper character
            || isDigit character
            || character `elem` ("-_.:/" :: String)

diagnosticHeaderMaxBytes :: Int
diagnosticHeaderMaxBytes = 96

initializedTelemetryMiddleware :: Wai.Middleware
initializedTelemetryMiddleware = unsafePerformIO OtelWai.newOpenTelemetryWaiMiddleware
{-# NOINLINE initializedTelemetryMiddleware #-}

initializeTelemetry :: IO (Maybe Otel.TracerProvider)
initializeTelemetry = do
    result :: Either SomeException Otel.TracerProvider <- try Otel.initializeGlobalTracerProvider
    case result of
        Right provider -> pure (Just provider)
        Left exception -> do
            reportTelemetryFailure "init" exception
            pure Nothing

flushTelemetry :: IO ()
flushTelemetry = whenTelemetryEnabled do
    provider <- Otel.getGlobalTracerProvider
    runBoundedTelemetryOperation "flush" (flushTracerProvider provider)

shutdownTelemetry :: Maybe Otel.TracerProvider -> IO ()
shutdownTelemetry Nothing = pure ()
shutdownTelemetry (Just provider) = do
    flushTelemetry
    runBoundedTelemetryOperation "shutdown" (Otel.shutdownTracerProvider provider)

flushTracerProvider :: Otel.TracerProvider -> IO ()
flushTracerProvider provider = do
    result <- OtelCore.forceFlushTracerProvider provider (Just telemetryShutdownTimeoutMicros)
    case result of
        OtelCore.FlushSuccess -> pure ()
        OtelCore.FlushTimeout -> putStrLn "otel_flush_export_timeout"
        OtelCore.FlushError   -> putStrLn "otel_flush_export_failure"

runBoundedTelemetryOperation :: Text -> IO () -> IO ()
runBoundedTelemetryOperation operation action = do
    result <- Timeout.timeout telemetryShutdownTimeoutMicros (try action :: IO (Either SomeException ()))
    case result of
        Nothing -> putStrLn ("otel_" <> cs operation <> "_timeout")
        Just (Left exception) -> reportTelemetryFailure operation exception
        Just (Right ()) -> pure ()

reportTelemetryFailure :: Text -> SomeException -> IO ()
reportTelemetryFailure operation exception =
    putStrLn ("otel_" <> cs operation <> "_failure: " <> cs (displayException exception))

whenTelemetryEnabled :: IO () -> IO ()
whenTelemetryEnabled = when telemetryEnabledFlag

telemetryEnabledFlag :: Bool
telemetryEnabledFlag = unsafePerformIO ((== Just "1") <$> lookupEnv "IHP_ROSTER_OTEL")
{-# NOINLINE telemetryEnabledFlag #-}

diagnosticHeadersEnabledFlag :: Bool
diagnosticHeadersEnabledFlag = unsafePerformIO ((== Just "1") <$> lookupEnv "IHP_ROSTER_OTEL_DIAGNOSTIC_HEADERS")
{-# NOINLINE diagnosticHeadersEnabledFlag #-}

telemetryShutdownTimeoutMicros :: Int
telemetryShutdownTimeoutMicros = unsafePerformIO do
    configured <- lookupEnv "IHP_ROSTER_OTEL_SHUTDOWN_TIMEOUT_MS"
    let milliseconds = fromMaybe 2000 (configured >>= readMaybe)
    pure (max 100 (min 10000 milliseconds) * 1000)
{-# NOINLINE telemetryShutdownTimeoutMicros #-}
