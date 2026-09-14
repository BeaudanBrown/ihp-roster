module Application.Error.Telemetry
    ( recordAppError
    ) where

import Application.Error.Types
import Application.Error.Wire (errorRecoveryWireValue, errorSeverityWireValue)
import Application.Helper.Telemetry (addTelemetryEvent)
import IHP.Prelude
import qualified OpenTelemetry.Attributes as OtelAttributes
import qualified OpenTelemetry.Context as OtelContext
import qualified OpenTelemetry.Context.ThreadLocal as OtelContextThreadLocal
import qualified OpenTelemetry.Trace as Otel

-- | Emits only bounded classification. No message, identifier, domain payload,
-- exception text, retry delay, or correlation id is recorded here.
recordAppError :: AppError -> IO ()
recordAppError appError = do
    let attributes =
            [ ("bepis.app_error.code", OtelAttributes.toAttribute (appErrorCode appError))
            , ("bepis.app_error.severity", OtelAttributes.toAttribute (errorSeverityWireValue (appErrorSeverity appError)))
            , ("bepis.app_error.recovery", OtelAttributes.toAttribute (errorRecoveryWireValue (appErrorRecovery appError)))
            , ("bepis.app_error.count", OtelAttributes.toAttribute (1 :: Int))
            ]
    addTelemetryEvent "bepis.app_error" attributes
    when (appErrorSeverity appError == Critical) do
        context <- OtelContextThreadLocal.getContext
        forEach (OtelContext.lookupSpan context) \span' ->
            Otel.setStatus span' (Otel.Error "critical application error")
