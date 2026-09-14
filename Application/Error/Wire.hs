{-# LANGUAGE OverloadedRecordDot #-}

module Application.Error.Wire
    ( AppErrorWire (..)
    , appErrorToWire
    , errorRecoveryWireValue
    , errorSeverityWireValue
    ) where

import Application.Error.Types
import qualified Data.Aeson as Aeson
import IHP.Prelude

-- | The complete operation-failure browser envelope. Retry directives and all
-- technical/domain context are intentionally absent.
data AppErrorWire = AppErrorWire
    { code        :: !Text
    , severity    :: !Text
    , recovery    :: !Text
    , safeMessage :: !Text
    }
    deriving (Eq, Show)

instance Aeson.ToJSON AppErrorWire where
    toJSON wire = Aeson.object
        [ "code" Aeson..= wire.code
        , "severity" Aeson..= wire.severity
        , "recovery" Aeson..= wire.recovery
        , "safeMessage" Aeson..= wire.safeMessage
        ]

appErrorToWire :: AppError -> AppErrorWire
appErrorToWire appError = AppErrorWire
    { code = appErrorCode appError
    , severity = errorSeverityWireValue (appErrorSeverity appError)
    , recovery = errorRecoveryWireValue (appErrorRecovery appError)
    , safeMessage = appErrorSafeMessage appError
    }

errorSeverityWireValue :: ErrorSeverity -> Text
errorSeverityWireValue Blocking = "blocking"
errorSeverityWireValue Critical = "critical"

errorRecoveryWireValue :: Recovery -> Text
errorRecoveryWireValue UserFixRequired    = "user-fix-required"
errorRecoveryWireValue UserActionRequired = "user-action-required"
errorRecoveryWireValue Retryable          = "retryable"
errorRecoveryWireValue Terminal           = "terminal"
