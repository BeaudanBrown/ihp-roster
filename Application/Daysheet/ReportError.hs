{-# LANGUAGE DeriveGeneric #-}
module Application.Daysheet.ReportError (ReportStorageError (..)) where

import Prelude
import Application.Error.Domain
import GHC.Generics (Generic)

data ReportStorageError = ReportRequiresSubmission | ReportNotEnabled | ReportRequestConflict | ReportCaptureInvalid | ReportCaptureTooLarge
    deriving (Eq, Show, Generic)

instance DomainError ReportStorageError where
    appErrorProjection ReportRequiresSubmission = actionRequiredErrorProjection "Submit this Daysheet before sending a report."
    appErrorProjection ReportNotEnabled = actionRequiredErrorProjection "This configured report is not available for sending."
    appErrorProjection ReportRequestConflict = actionRequiredErrorProjection "This Send action belongs to a different report request. Open a fresh Send confirmation."
    appErrorProjection ReportCaptureInvalid = terminalErrorProjection "The saved report could not be captured. Contact support."
    appErrorProjection ReportCaptureTooLarge = actionRequiredErrorProjection "The selected report or recipient list exceeds the supported capture size. Contact support."
