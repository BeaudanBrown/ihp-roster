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
import Data.Data (Data, toConstr)
import qualified Data.HashMap.Strict as HashMap
import IHP.Prelude
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
    middleware <- getTelemetryMiddleware
    middleware app request respond

-- | Annotates the current WAI root span with the low-cardinality IHP action
-- constructor name, e.g. ShowRosterWeekAction. This avoids path ids and query
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

withTelemetrySpanAttributes :: Text -> [(Text, Attribute)] -> IO a -> IO a
withTelemetrySpanAttributes name attributes action = do
    enabled <- telemetryEnabled
    if enabled
        then do
            tracerProvider <- Otel.getGlobalTracerProvider
            let tracer = Otel.makeTracer tracerProvider "ihp-roster" Otel.tracerOptions
            Otel.inSpan tracer name (spanArguments attributes) action
        else action

spanArguments :: [(Text, Attribute)] -> Otel.SpanArguments
spanArguments attributes =
    Otel.defaultSpanArguments { Otel.attributes = HashMap.fromList attributes }

getTelemetryMiddleware :: IO Wai.Middleware
getTelemetryMiddleware = do
    enabled <- telemetryEnabled
    if enabled
        then pure initializedTelemetryMiddleware
        else pure id

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

telemetryEnabled :: IO Bool
telemetryEnabled = (== Just "1") <$> lookupEnv "IHP_ROSTER_OTEL"
