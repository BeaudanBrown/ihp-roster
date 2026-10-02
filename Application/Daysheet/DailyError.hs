{-# LANGUAGE DeriveGeneric #-}
module Application.Daysheet.DailyError (DailyStorageError (..), projectDailyFailure) where

import Prelude
import qualified Application.Daysheet.Daily as Daily
import Application.Error.Domain
import Application.Error.Types (AppError)
import GHC.Generics (Generic)

data DailyStorageError
    = DaysheetNotFound | SavedDaysheetInvalid | DailyFieldConflict
    | DailyRowDeleted | DailyDeletionConflict | InvalidDailyEdit | DailyCapacityReached
    deriving (Eq, Show, Generic)

instance DomainError DailyStorageError where
    appErrorProjection DaysheetNotFound = actionRequiredErrorProjection "This Daysheet is not available in the current venue."
    appErrorProjection SavedDaysheetInvalid = terminalErrorProjection "The saved Daysheet could not be read. Contact support."
    appErrorProjection DailyFieldConflict = actionRequiredErrorProjection "This field changed. Keep your unsaved value while comparing it with the saved value."
    appErrorProjection DailyRowDeleted = actionRequiredErrorProjection "This row was deleted. Your unsaved values must not recreate it; choose what to do next."
    appErrorProjection DailyDeletionConflict = actionRequiredErrorProjection "The row or its incoming links changed. Review a fresh deletion confirmation."
    appErrorProjection InvalidDailyEdit = actionRequiredErrorProjection "This value or operation is not permitted by the saved Daysheet definition."
    appErrorProjection DailyCapacityReached = actionRequiredErrorProjection "This Daysheet has reached a supported size or revision limit. Contact support."

projectDailyFailure :: Daily.DailyError -> AppError
projectDailyFailure = projectDomainError . \case
    Daily.CellRevisionConflict -> DailyFieldConflict
    Daily.RowNoLongerExists -> DailyRowDeleted
    Daily.DeletionConfirmationChanged -> DailyDeletionConflict
    Daily.DailyLimit -> DailyCapacityReached
    Daily.InvalidDailyDocument -> SavedDaysheetInvalid
    Daily.UnknownDailyField -> InvalidDailyEdit
    Daily.UnknownDailyList -> InvalidDailyEdit
    Daily.ReadOnlyDailyField -> InvalidDailyEdit
    Daily.ChecklistRowsAreFixed -> InvalidDailyEdit
    Daily.InvalidDailyReference -> InvalidDailyEdit
    Daily.InvalidDailyInput _ -> InvalidDailyEdit
