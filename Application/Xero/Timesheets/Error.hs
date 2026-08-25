{-# LANGUAGE DeriveGeneric #-}

module Application.Xero.Timesheets.Error
    ( XeroPreparationError (..)
    ) where

import Application.Error.Domain (AppErrorProjection (..), DomainError (..))
import Application.Error.Types
import GHC.Generics (Generic)
import IHP.Prelude

data XeroPreparationError
    = XeroPreparationStateUnavailable
    deriving (Eq, Generic, Show)

instance DomainError XeroPreparationError where
    appErrorProjection XeroPreparationStateUnavailable =
        AppErrorProjection
            { safeMessage = "Xero preparation could not load trustworthy payroll state. Try again."
            , severity = Critical
            , recovery = Retryable
            , retryDirective = RetryUsingBoundaryPolicy
            }
