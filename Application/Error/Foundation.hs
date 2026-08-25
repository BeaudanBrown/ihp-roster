{-# LANGUAGE DeriveGeneric #-}

module Application.Error.Foundation
    ( FoundationError (..)
    ) where

import Application.Error.Domain
import Application.Error.Types
import GHC.Generics (Generic)
import IHP.Prelude

-- | Boundary-owned fallback. The caught exception is telemetry-only and is
-- never retained in this value.
data FoundationError
    = UnexpectedSynchronousError
    deriving (Eq, Generic, Show)

instance DomainError FoundationError where
    appErrorProjection UnexpectedSynchronousError = AppErrorProjection
        { safeMessage = "We couldn't complete that request. Please try again."
        , severity = Critical
        , recovery = Retryable
        , retryDirective = RetryUsingBoundaryPolicy
        }
