{-# LANGUAGE ScopedTypeVariables #-}

module Application.Helper.Telemetry
    ( addJobRetryExhaustedTelemetryEvent
    , addJobRetryScheduledTelemetryEvent
    , addProviderTelemetryStatusClass
    , addTelemetryAttributes
    , addTelemetryEvent
    , annotateTelemetryAction
    , diagnosticHeaderValue
    , flushTelemetry
    , telemetryMiddleware
    , withExportTelemetrySpan
    , withJobTelemetrySpan
    , withLiveUpdateTelemetrySpan
    , withProviderTelemetrySpan
    , withTelemetryRuntime
    , withTelemetrySpan
    , withTelemetrySpanAttributes
    ) where

import Application.Helper.Telemetry.Semantic (JobRetryState (..),
                                              boundedAttempt,
                                              boundedRetryNumber, jobRetryState)
import Control.Exception (bracket, try)
import qualified Control.Exception as Exception
import qualified Control.Exception.Safe as SafeException
import Control.Monad (guard)
import qualified Data.ByteString as ByteString
import qualified Data.CaseInsensitive as CaseInsensitive
import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.Data (Data (toConstr))
import qualified Data.HashMap.Strict as HashMap
import qualified Data.IORef as IORef
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import IHP.Controller.Response (EarlyReturnException)
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
annotateTelemetryAction = runTelemetryAnnotation do
    case OtelWai.requestContext ?request >>= OtelContext.lookupSpan of
        Nothing -> pure ()
        Just span' -> do
            let actionName = show (toConstr ?theAction)
            Otel.addAttributes span' $ HashMap.fromList
                [ ("http.route", toAttribute actionName)
                , ("bepis.ihp.action", toAttribute actionName)
                ]
            Otel.updateName span' actionName

addJobRetryScheduledTelemetryEvent :: Text -> Int -> IO ()
addJobRetryScheduledTelemetryEvent jobKind retryNumber =
    addJobRetryTelemetryEvent "bepis.job.retry_scheduled" jobKind retryNumber "retry_scheduled"

addJobRetryExhaustedTelemetryEvent :: Text -> Int -> IO ()
addJobRetryExhaustedTelemetryEvent jobKind retryNumber =
    addJobRetryTelemetryEvent "bepis.job.retry_exhausted" jobKind retryNumber "failed"

addJobRetryTelemetryEvent :: Text -> Text -> Int -> Text -> IO ()
addJobRetryTelemetryEvent eventName jobKind retryNumber outcome =
    addTelemetryEvent
        eventName
        [ ("bepis.job.kind", toAttribute jobKind)
        , ("bepis.job.retry_number", toAttribute (boundedRetryNumber retryNumber))
        , ("bepis.outcome", toAttribute outcome)
        ]

addProviderTelemetryStatusClass :: Text -> IO ()
addProviderTelemetryStatusClass statusClass =
    addTelemetryAttributes [("bepis.provider.status_class", toAttribute statusClass)]

addTelemetryAttributes :: [(Text, Attribute)] -> IO ()
addTelemetryAttributes attributes = runTelemetryAnnotation do
    context <- OtelContextThreadLocal.getContext
    forEach (OtelContext.lookupSpan context) \span' ->
        Otel.addAttributes span' (HashMap.fromList attributes)

addTelemetryEvent :: Text -> [(Text, Attribute)] -> IO ()
addTelemetryEvent name attributes = runTelemetryAnnotation do
    context <- OtelContextThreadLocal.getContext
    forEach (OtelContext.lookupSpan context) \span' ->
        Otel.addEvent span' Otel.NewEvent
            { Otel.newEventName = name
            , Otel.newEventAttributes = HashMap.fromList attributes
            , Otel.newEventTimestamp = Nothing
            }

runTelemetryAnnotation :: IO () -> IO ()
runTelemetryAnnotation action = whenTelemetryEnabled do
    Exception.try action >>= \case
        Left exception
            | SafeException.isAsyncException exception -> Exception.throwIO (exception :: SomeException)
            | otherwise -> putStrLn "otel_annotation_failure"
        Right () -> pure ()

withTelemetrySpan :: Text -> IO a -> IO a
withTelemetrySpan name = withTelemetrySpanAttributes name []

-- | One root-capable span per application job execution. Job kinds supplied by
-- callers must already be projected onto their closed registry. Attempts are
-- bounded by the worker policy and no job or customer identity is attached.
withJobTelemetrySpan :: Text -> Int -> Int -> IO a -> IO a
withJobTelemetrySpan jobKind attempt maximumAttempts =
    withClassifiedTelemetrySpan
        Otel.Internal
        "bepis.job.run"
        [ ("bepis.job.kind", toAttribute jobKind)
        , ("bepis.job.attempt", toAttribute boundedCurrentAttempt)
        , ("bepis.job.max_attempts", toAttribute boundedMaximumAttempts)
        , ("bepis.job.retry_state", toAttribute retryState)
        ]
        (const True)
  where
    boundedMaximumAttempts = max 1 maximumAttempts
    boundedCurrentAttempt = boundedAttempt boundedMaximumAttempts attempt
    retryState = case jobRetryState boundedMaximumAttempts boundedCurrentAttempt of
        RetryPossible -> "retry_possible" :: Text
        FinalAttempt  -> "final_attempt"

-- | A selected external boundary. Provider, operation, and method are closed
-- constants; the result classifier records only success/failure. Callers may
-- attach a status class or bounded count while the span is current.
withProviderTelemetrySpan :: Text -> Text -> Text -> (a -> Bool) -> IO a -> IO a
withProviderTelemetrySpan provider operation method succeeded action =
    withClassifiedTelemetrySpan
        Otel.Client
        ("provider." <> provider <> "." <> operation)
        [ ("bepis.provider", toAttribute provider)
        , ("bepis.provider.operation", toAttribute operation)
        , ("bepis.provider.method", toAttribute method)
        ]
        succeeded
        providerAction
  where
    providerAction = do
        actionResult <- Exception.try action
        case actionResult of
            Left exception
                | isJust (Exception.fromException @EarlyReturnException exception) -> Exception.throwIO (exception :: SomeException)
                | SafeException.isAsyncException exception -> Exception.throwIO (exception :: SomeException)
                | otherwise -> do
                    addProviderTelemetryStatusClass "unavailable"
                    Exception.throwIO (exception :: SomeException)
            Right value -> do
                -- The SDK keeps the first value for an attribute key. Provider
                -- response/SMTP code records its specific class inside the
                -- action; this later fallback fills only the no-response case.
                addProviderTelemetryStatusClass (if succeeded value then "success" else "unavailable")
                pure value

withLiveUpdateTelemetrySpan :: Text -> IO a -> IO a
withLiveUpdateTelemetrySpan command =
    withClassifiedTelemetrySpan
        Otel.Internal
        "bepis.live_update.process"
        [("bepis.live_update.command", toAttribute command)]
        (const True)

withExportTelemetrySpan :: Text -> (a -> Bool) -> IO a -> IO a
withExportTelemetrySpan exportKind =
    withClassifiedTelemetrySpan
        Otel.Internal
        "bepis.export.generate"
        [("bepis.export.kind", toAttribute exportKind)]

withClassifiedTelemetrySpan :: forall a. Otel.SpanKind -> Text -> [(Text, Attribute)] -> (a -> Bool) -> IO a -> IO a
withClassifiedTelemetrySpan spanKind name attributes succeeded action =
    if not telemetryEnabledFlag
        then action
        else do
            actionResultRef <- IORef.newIORef Nothing
            spanResult <- Exception.try do
                tracerProvider <- Otel.getGlobalTracerProvider
                let tracer = Otel.makeTracer tracerProvider "ihp-roster" Otel.tracerOptions
                Otel.inSpan tracer name arguments do
                    actionResult <- Exception.try action :: IO (Either SomeException a)
                    IORef.writeIORef actionResultRef (Just actionResult)
                    case actionResult of
                        Left exception
                            | isJust (Exception.fromException @EarlyReturnException exception) -> recordOutcome True
                            | SafeException.isAsyncException exception -> pure ()
                            | otherwise -> recordOutcome False
                        Right value -> recordOutcome (succeeded value)
                    pure actionResult
            case spanResult of
                Right actionResult -> resolveActionResult actionResult
                Left exception
                    | SafeException.isAsyncException exception -> Exception.throwIO (exception :: SomeException)
                    | otherwise -> do
                        putStrLn "otel_span_failure"
                        IORef.readIORef actionResultRef >>= maybe action resolveActionResult
  where
    arguments = (spanArguments attributes) { Otel.kind = spanKind }
    resolveActionResult = either Exception.throwIO pure
    recordOutcome successful = do
        addTelemetryAttributes [("bepis.outcome", toAttribute (if successful then ("succeeded" :: Text) else "failed"))]
        unless successful do
            context <- OtelContextThreadLocal.getContext
            forEach (OtelContext.lookupSpan context) \span' -> Otel.setStatus span' (Otel.Error "operation failed")

withTelemetrySpanAttributes :: forall a. Text -> [(Text, Attribute)] -> IO a -> IO a
withTelemetrySpanAttributes name attributes action =
    -- Close spans before propagating explicit early-return control. Genuine
    -- failures receive a bounded outcome/status, never SDK exception payloads
    -- that could contain SQL, provider data or request/session values.
    withClassifiedTelemetrySpan Otel.Internal name attributes (const True) action

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
