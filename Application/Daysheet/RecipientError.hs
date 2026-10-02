{-# LANGUAGE DeriveGeneric #-}
module Application.Daysheet.RecipientError (RecipientError (..)) where

import Application.Error.Domain
import GHC.Generics (Generic)
import Prelude

data RecipientError = InvalidAddress | UnknownReport | UnknownRecipient | InvalidReportDefinition
    deriving (Eq, Show, Generic)
instance DomainError RecipientError where
    appErrorProjection InvalidAddress = actionRequiredErrorProjection "Enter a valid email address."
    appErrorProjection UnknownReport = actionRequiredErrorProjection "That report is not available in this venue."
    appErrorProjection UnknownRecipient = actionRequiredErrorProjection "That recipient is not available for this report."
    appErrorProjection InvalidReportDefinition = terminalErrorProjection "The saved report definition could not be read. Contact support."
