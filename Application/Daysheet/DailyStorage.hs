{-# LANGUAGE RankNTypes #-}
-- | One authorized latest-state transaction per daily operation. The venue lock
-- also orders creation against publication/reference changes and submission
-- against future report capture. Never persist a caller's replacement document.
module Application.Daysheet.DailyStorage
    ( DailyState (..), createDailySheet, readDailySheet, readDailyForDate
    , editDailyCell, addDailyRow, prepareDailyDeletion, deleteDailyRow, submitDailySheet
    , withScheduledDaily
    ) where

import Application.Daysheet.Authority (DaysheetAccess, venueId, userId, withAuthority, recordDaysheetAuditEvent)
import qualified Application.Daysheet.Cutoff as Cutoff
import Application.Daysheet.CutoffCapture (CutoffClock, withScheduledCutoff)
import Application.Daysheet.CutoffJob (enqueueCutoffCapture)
import qualified Application.Daysheet.Contract as D
import qualified Application.Daysheet.Daily as Daily
import Application.Daysheet.DailyError
import Application.Daysheet.DefinitionCodec
import qualified Application.Daysheet.Evaluation as E
import Application.Daysheet.ReferenceCodec
import Application.Daysheet.References (ReferenceData, ReferenceKey, ReferenceValue)
import Application.Daysheet.Storage (withDefinitionCapture)
import Application.Error.Domain (projectDomainError)
import Application.Error.Types
import Application.Helper.Audit.Vocabulary
import Control.Monad.Trans.Except (ExceptT (..), runExceptT, throwE)
import qualified Data.Aeson as Aeson
import qualified Data.UUID.V4 as UUID
import Data.Traversable (traverse)
import Generated.Types
import IHP.ControllerPrelude

data DailyState = DailyState
    { daysheet :: Daysheet
    , captured :: DaysheetDefinitionCapture
    , definition :: D.Definition
    , references :: ReferenceData
    , content :: Daily.DailyDocument
    }

type StoreM = ExceptT AppError IO

failure :: DailyStorageError -> StoreM a
failure = throwE . projectDomainError

checked :: Either Daily.DailyError a -> StoreM a
checked = either (throwE . projectDailyFailure) pure

owner :: Daysheet -> E.SnapshotKey
owner record = E.SnapshotKey (unpackId record.venueId) (unpackId record.id)

meaning :: (?modelContext :: ModelContext) => DaysheetDefinitionCapture -> StoreM (D.Definition, ReferenceData)
meaning captured = do
    stored <- liftIO (query @DaysheetDefinitionVersion
        |> filterWhere (#id, Id captured.definitionVersionId)
        |> filterWhere (#venueId, captured.venueId) |> fetchOneOrNothing)
    version <- maybe (failure SavedDaysheetInvalid) pure stored
    definition <- either (const (failure SavedDaysheetInvalid)) pure (decodeDefinition version.definition)
    references <- either (const (failure SavedDaysheetInvalid)) pure (decodeReferenceData captured.referenceData)
    pure (definition, references)

load :: (?modelContext :: ModelContext) => Daysheet -> StoreM DailyState
load record = do
    stored <- liftIO (query @DaysheetDefinitionCapture
        |> filterWhere (#id, record.definitionCaptureId)
        |> filterWhere (#venueId, unpackId record.venueId)
        |> filterWhere (#operationalDate, record.operationalDate) |> fetchOneOrNothing)
    captured <- maybe (failure SavedDaysheetInvalid) pure stored
    (definition, references) <- meaning captured
    content <- either (const (failure SavedDaysheetInvalid)) pure (Daily.decodeDaily definition references (owner record) record.savedData)
    pure DailyState { daysheet = record, captured, definition, references, content }

withDay :: (?modelContext :: ModelContext) => DaysheetAccess -> Id Daysheet -> ((?modelContext :: ModelContext) => DailyState -> StoreM a) -> IO (AppResult a)
withDay member key action = withAuthority member [Manager, VenueAdmin, VenueOwner] do
    stored <- liftIO (query @Daysheet |> filterWhere (#id, key) |> filterWhere (#venueId, Id member.venueId) |> fetchOneOrNothing)
    record <- maybe (failure DaysheetNotFound) pure stored
    state <- load record
    action state

-- Views call these reads, never creation. Neither midnight nor a missing date
-- creates a business record as a side effect of navigation.
readDailySheet :: (?modelContext :: ModelContext) => DaysheetAccess -> Id Daysheet -> IO (AppResult DailyState)
readDailySheet member key = withDay member key pure

readDailyForDate :: (?modelContext :: ModelContext) => DaysheetAccess -> Day -> IO (AppResult (Maybe DailyState))
readDailyForDate member date = withAuthority member [Manager, VenueAdmin, VenueOwner] do
    stored <- liftIO (query @Daysheet |> filterWhere (#venueId, Id member.venueId) |> filterWhere (#operationalDate, date) |> fetchOneOrNothing)
    traverse load stored

-- Background authority is the verified venue cutoff transaction, never a
-- fabricated membership. Missing/unsubmitted days skip without creation/jobs.
withScheduledDaily :: (?modelContext :: ModelContext) => CutoffClock -> UUID -> Cutoff.CutoffPlan
    -> ((?modelContext :: ModelContext) => DailyState -> UTCTime -> IO (AppResult value))
    -> IO (AppResult (Maybe value))
withScheduledDaily clock venueId plan capture = fmap (fmap join) $
    withScheduledCutoff clock venueId plan \_ capturedAt -> runExceptT do
        stored <- liftIO (query @Daysheet |> filterWhere (#venueId, Id venueId)
            |> filterWhere (#operationalDate, Cutoff.operationalDate plan) |> fetchOneOrNothing)
        case stored of
            Just record
                | maybe False (<= Cutoff.cutoffAt plan) record.submittedAt
                  && record.lastEditedAt <= Cutoff.cutoffAt plan -> do
                state <- load record
                Just <$> ExceptT (capture state capturedAt)
            _ -> pure Nothing

createDailySheet :: (?modelContext :: ModelContext) => DaysheetAccess -> Day -> IO (AppResult DailyState)
createDailySheet member date = withDefinitionCapture member date \captured -> do
    existing <- liftIO (query @Daysheet |> filterWhere (#venueId, Id member.venueId) |> filterWhere (#operationalDate, date) |> fetchOneOrNothing)
    case existing of
        Just record -> load record
        Nothing -> do
            (definition, references) <- meaning captured
            key <- liftIO UUID.nextRandom
            content <- checked (Daily.emptyDaily definition references (E.SnapshotKey member.venueId key))
            encoded <- checked (Daily.encodeDaily content)
            now <- liftIO getCurrentTime
            record <- liftIO (newRecord @Daysheet |> set #id (Id key)
                |> set #venueId (Id member.venueId) |> set #operationalDate date
                |> set #definitionCaptureId captured.id |> set #savedData encoded
                |> set #createdBy (Id member.userId) |> set #lastEditedBy (Id member.userId)
                |> set #createdAt now |> set #lastEditedAt now |> createRecord)
            plan <- either (const (failure SavedDaysheetInvalid)) pure (Cutoff.planCutoff captured.timezone date)
            liftIO (enqueueCutoffCapture now record plan)
            _ <- liftIO (recordDaysheetAuditEvent member DaysheetCreatedAudit "daysheets" key
                (Aeson.object ["operationalDate" Aeson..= date]) ApplicationAuditSource)
            pure DailyState { daysheet = record, captured, definition, references, content }

advance :: Int -> StoreM Int
advance revision
    | revision < 0 || revision >= 2147483647 = failure DailyCapacityReached
    | otherwise = pure (revision + 1)

persist :: (?modelContext :: ModelContext) => DaysheetAccess -> DailyState -> Daily.DailyDocument -> StoreM DailyState
persist member state content
    | content == state.content = pure state
    | otherwise = do
        encoded <- checked (Daily.encodeDaily content)
        revision <- advance state.daysheet.revision
        now <- liftIO getCurrentTime
        record <- liftIO (state.daysheet |> set #savedData encoded |> set #revision revision
            |> set #lastEditedAt now |> set #lastEditedBy (Id member.userId) |> updateRecord)
        pure state { daysheet = record, content }

editDailyCell :: (?modelContext :: ModelContext) => DaysheetAccess -> Id Daysheet -> Daily.CellAddress -> Integer -> Maybe ReferenceValue -> IO (AppResult DailyState)
editDailyCell member key address expected value = withDay member key \state -> do
    updated <- checked (Daily.saveCell state.definition state.references (owner state.daysheet) address expected value state.content)
    persist member state updated

addDailyRow :: (?modelContext :: ModelContext) => DaysheetAccess -> Id Daysheet -> ReferenceKey -> IO (AppResult DailyState)
addDailyRow member key row = withDay member key \state -> do
    updated <- checked (Daily.addOpenRow state.definition state.references (owner state.daysheet) row state.content)
    persist member state updated

prepareDailyDeletion :: (?modelContext :: ModelContext) => DaysheetAccess -> Id Daysheet -> ReferenceKey -> IO (AppResult Daily.DeletionPlan)
prepareDailyDeletion member key row = withDay member key \state -> checked (Daily.planDeletion state.definition row state.content)

deleteDailyRow :: (?modelContext :: ModelContext) => DaysheetAccess -> Id Daysheet -> Daily.DeletionPlan -> IO (AppResult DailyState)
deleteDailyRow member key approval = withDay member key \state -> do
    updated <- checked (Daily.confirmDeletion state.definition state.references (owner state.daysheet) approval state.content)
    persist member state updated

-- Browser orchestration must first settle its own pending saves/conflicts.
-- The server submits the latest consistent saved state, not a stale client copy.
-- Blank values and advisory concerns are deliberately NOT completeness gates.
submitDailySheet :: (?modelContext :: ModelContext) => DaysheetAccess -> Id Daysheet -> IO (AppResult DailyState)
submitDailySheet member key = withDay member key \state -> case state.daysheet.submittedAt of
    Just _ -> pure state
    Nothing -> do
        now <- liftIO getCurrentTime
        revision <- advance state.daysheet.revision
        record <- liftIO (state.daysheet |> set #submittedAt (Just now) |> set #submittedBy (Just (Id member.userId)) |> set #revision revision |> updateRecord)
        _ <- liftIO (recordDaysheetAuditEvent member DaysheetSubmittedAudit "daysheets" (unpackId record.id)
            (Aeson.object ["revision" Aeson..= revision]) ApplicationAuditSource)
        pure state { daysheet = record }
