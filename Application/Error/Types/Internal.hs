{-# LANGUAGE DeriveGeneric #-}

module Application.Error.Types.Internal
    ( AppError (..)
    , AppResult
    , ErrorSeverity (..)
    , Recovery (..)
    , RetryDirective (..)
    , mkAppError
    ) where

import GHC.Generics (Generic)
import IHP.Prelude

data AppError = AppError
    { appErrorCode           :: !Text
    , appErrorSafeMessage    :: !Text
    , appErrorSeverity       :: !ErrorSeverity
    , appErrorRecovery       :: !Recovery
    , appErrorRetryDirective :: !RetryDirective
    }
    deriving (Eq, Generic, Show)

type AppResult value = Either AppError value

data ErrorSeverity
    = Blocking
    | Critical
    deriving (Eq, Generic, Show)

data Recovery
    = UserFixRequired
    | UserActionRequired
    | Retryable
    | Terminal
    deriving (Eq, Generic, Show)

data RetryDirective
    = DoNotRetry
    | RetryUsingBoundaryPolicy
    | RetryAfter !NominalDiffTime
    deriving (Eq, Generic, Show)

mkAppError :: Text -> Text -> ErrorSeverity -> Recovery -> RetryDirective -> AppError
mkAppError = AppError
