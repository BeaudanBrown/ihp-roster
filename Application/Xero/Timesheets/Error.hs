{-# LANGUAGE DeriveGeneric #-}

module Application.Xero.Timesheets.Error
    ( XeroPreparationError (..)
    ) where

import Application.Error.Domain (DomainError (..), retryableErrorProjection)
import GHC.Generics (Generic)
import IHP.Prelude

data XeroPreparationError
    = XeroPreparationStateUnavailable
    deriving (Eq, Generic, Show)

instance DomainError XeroPreparationError where
    appErrorProjection XeroPreparationStateUnavailable =
        retryableErrorProjection "Xero preparation could not load trustworthy payroll state. Try again."
