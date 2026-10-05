{-# LANGUAGE RankNTypes #-}
-- | Request mutation boundary: saved data/audit and typed durable freshness share
-- one transaction. Convergent create/add/submit retries retain a focused event.
module Application.Daysheet.Mutations
    ( createSheet, editCell, addRow, deleteRow, submitSheet ) where

import qualified Application.Daysheet.Daily as Daily
import Application.Daysheet.DailyError (DailyStorageError (..))
import qualified Application.Daysheet.DailyStorage as Storage
import Application.Daysheet.Entry (DaysheetDeletionToken, deletionToken)
import qualified Application.Daysheet.Evaluation as Evaluation
import Application.Daysheet.References (ReferenceKey, ReferenceValue)
import Application.Error.Domain (projectDomainError)
import Application.Error.Types (AppResult)
import Application.Helper.FrontendContract.Surface.Daysheet.Resource
import Application.Helper.SurfaceResource
import Generated.Types
import IHP.ControllerPrelude hiding (Result)
import Web.SurfaceInvalidation (withDurableLiveMutationOutcome)

type MutationContext = (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request)
type Result = LiveMutationResult (AppResult Storage.DailyState)

mutate :: MutationContext => Text -> ((?modelContext :: ModelContext) => IO (AppResult Storage.DailyState)) -> IO Result
mutate label action = withDurableLiveMutationOutcome publication do
    result <- action
    pure (liveMutationResult result (case result of
        Left _ -> []
        Right state -> [daysheetDataResource (unpackId state.daysheet.venueId) (unpackId state.daysheet.id)]))
  where
    publication result = case result.liveMutationValue of
        Left _ -> Nothing
        Right _ -> Just (label, result.liveMutationTouchedResources)

createSheet :: MutationContext => VenueMembership -> Day -> IO Result
createSheet member date = mutate "daysheet.create" (Storage.createDailySheet member date)

editCell :: MutationContext => VenueMembership -> Id Daysheet -> Daily.CellAddress -> Integer -> Maybe ReferenceValue -> IO Result
editCell member key address revision value = mutate "daysheet.edit-cell" (Storage.editDailyCell member key address revision value)

addRow :: MutationContext => VenueMembership -> Id Daysheet -> ReferenceKey -> IO Result
addRow member key row = mutate "daysheet.add-row" (Storage.addDailyRow member key row)

deleteRow :: MutationContext => VenueMembership -> Id Daysheet -> ReferenceKey -> DaysheetDeletionToken -> IO Result
deleteRow member key row token = mutate "daysheet.delete-row" do
    prepared <- Storage.prepareDailyDeletion member key row
    case prepared of
        Left failure -> pure (Left failure)
        Right plan
            | deletionToken (Evaluation.SnapshotKey member.venueId (unpackId key)) plan == token -> Storage.deleteDailyRow member key plan
            | otherwise -> pure (Left (projectDomainError DailyDeletionConflict))

submitSheet :: MutationContext => VenueMembership -> Id Daysheet -> IO Result
submitSheet member key = mutate "daysheet.submit" (Storage.submitDailySheet member key)
