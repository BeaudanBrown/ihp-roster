module Web.Timesheets.Mutations
    ( TimesheetMaterializationKind (..)
    , approveTimesheetEntryMutation
    , createTimesheetEntryMutation
    , materializeAndApproveTimesheetSuggestionMutation
    , materializeTimesheetSuggestionMutation
    , deleteTimesheetEntryMutation
    , timesheetEntryTouchedResourcesForScopes
    , unapproveTimesheetEntryMutation
    , updateTimesheetEntryMutation
    ) where

import Application.Error.Domain (projectDomainError)
import Application.Error.Types (AppError, AppResult)
import Application.Helper.Audit (currentRequestAuditPayload)
import Application.Helper.FrontendContract.Surface.Timesheets.Live (activeTimesheetWindowScopes)
import Application.Helper.FrontendContract.Surface.Timesheets.Resource
import Application.Helper.Htmx (requestAuditSourceChannel)
import Application.Helper.Staff (isLinkedActiveStaff)
import Application.Helper.SurfaceResource
import Application.Helper.WeekBoundaries (startOfWeekFor)
import Application.PayAssignment (ShiftPayAssignment (..),
                                  StaffPayAssignment (..),
                                  shiftAssignmentAllowsTimesheets,
                                  staffAssignmentAllowsTimesheets)
import Application.RosterPublication.Mutations (withRosterCalendarLockInCurrentTransaction)
import Application.TimesheetApproval (ApprovalEngineMode (InitialApproval),
                                      approvalEngineEntry,
                                      runApprovalEngineInCurrentTransaction)
import Application.VenueTime.Model
import qualified Control.Exception as Exception
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Time.Calendar (Day, addDays)
import Data.Time.Clock (getCurrentTime)
import Data.Tuple.Only (Only (..))
import IHP.ModelSupport (sqlQuery)
import Web.Controller.Prelude
import Web.SurfaceInvalidation (withDurableLiveMutation,
                                withDurableLiveMutationOutcome)
import Web.Timesheets.FrontendSurface (TimesheetWeekScopeValue,
                                       timesheetWeekScopeMatchesConfig)
import Web.Timesheets.Projection (fetchTimesheetSuggestionForRosterSlot)
import Web.Timesheets.Suggestion (TimesheetSuggestion (..))
import Web.Timesheets.Validation (TimesheetCalendarConflict (..),
                                  TimesheetEditIntent, originalTimesheetEntry,
                                  resetApprovalOnEdit, submittedTimesheetEntry,
                                  timesheetCoreChanged)

withTimesheetCalendarMutationLock :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetWeekScopeValue -> IO value -> IO value
withTimesheetCalendarMutationLock scope action =
    withRosterCalendarLockInCurrentTransaction currentVenueId do
        venueConfig <- fetchVenueConfig
        if timesheetWeekScopeMatchesConfig venueConfig scope
            then action
            else Exception.throwIO TimesheetCalendarChanged

createTimesheetEntryMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetWeekScopeValue -> TimesheetEntry -> IO (Either TimesheetCalendarConflict (LiveMutationResult TimesheetEntry))
createTimesheetEntryMutation scope timesheetEntry = Exception.try @TimesheetCalendarConflict do
    accessDeniedUnless (isNothing timesheetEntry.sourceRosterSlotId)
    withDurableLiveMutation "timesheet.create" $
        withTimesheetCalendarMutationLock scope do
            createdEntry <- createTimesheetEntryWithVersion timesheetEntry
            timesheetCreationResult createdEntry

data TimesheetMaterializationKind = NewTimesheetSnapshot | ExistingTimesheetSnapshot
    deriving stock (Eq, Show)

materializationKind :: Bool -> TimesheetMaterializationKind
materializationKind wasCreated = if wasCreated then NewTimesheetSnapshot else ExistingTimesheetSnapshot

materializeTimesheetSuggestionMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetWeekScopeValue -> TimesheetSuggestion -> TimesheetEntry -> IO (Either TimesheetCalendarConflict (Maybe (TimesheetMaterializationKind, LiveMutationResult TimesheetEntry)))
materializeTimesheetSuggestionMutation scope expectedSuggestion timesheetEntry =
    Exception.try @TimesheetCalendarConflict $ fmap (fmap (\(_, kind, result) -> (kind, result))) $
        withDurableLiveMutationOutcome publicationFor $
            withTimesheetCalendarMutationLock scope do
                materializeTimesheetSuggestionInCurrentTransaction expectedSuggestion timesheetEntry >>= \case
                    Nothing -> pure Nothing
                    Just (materializedEntry, wasCreated) -> do
                        result <- timesheetCreationResult materializedEntry
                        let label = if wasCreated then "timesheet.suggestion.create" else "timesheet.suggestion.create.idempotent"
                        pure (Just (label, materializationKind wasCreated, result))
  where
    publicationFor = fmap (\(label, _, result) -> (label, result.liveMutationTouchedResources))

materializeAndApproveTimesheetSuggestionMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetWeekScopeValue -> TimesheetSuggestion -> TimesheetEntry -> IO (Either TimesheetCalendarConflict (AppResult (Maybe (TimesheetMaterializationKind, LiveMutationResult TimesheetEntry))))
materializeAndApproveTimesheetSuggestionMutation scope expectedSuggestion timesheetEntry = Exception.try @TimesheetCalendarConflict do
    approval <- Exception.try @TimesheetApprovalRollback $
        withDurableLiveMutationOutcome publicationFor $
            withTimesheetCalendarMutationLock scope do
                materialization <- materializeTimesheetSuggestionInCurrentTransaction expectedSuggestion timesheetEntry
                case materialization of
                    Nothing -> pure Nothing
                    Just (materializedEntry, wasCreated) -> do
                        approvedEntry <- approveTimesheetEntryInCurrentTransaction materializedEntry
                        venueConfig <- fetchVenueConfig
                        activeScopes <- activeTimesheetWindowScopes
                        pure (Just (materializationKind wasCreated, liveMutationResult approvedEntry (timesheetEntryTouchedResourcesForScopes venueConfig activeScopes [approvedEntry])))
    pure case approval of
        Left (TimesheetApprovalRollback appError) -> Left appError
        Right mutationResult                      -> Right mutationResult
  where
    publicationFor = fmap (\(_, result) -> ("timesheet.suggestion.approve", result.liveMutationTouchedResources))

materializeTimesheetSuggestionInCurrentTransaction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetSuggestion -> TimesheetEntry -> IO (Maybe (TimesheetEntry, Bool))
materializeTimesheetSuggestionInCurrentTransaction expectedSuggestion timesheetEntry = do
    let rosterSlotId = unpackId expectedSuggestion.suggestionRosterSlotId
    lockRosterSlot rosterSlotId
    existingEntry <- fetchActiveEntryForRosterSlot rosterSlotId
    case existingEntry of
        Just existingEntry
            | existingEntry.staffId == expectedSuggestion.suggestionStaffId
                && existingEntry.operationalDate == expectedSuggestion.suggestionOperationalDate
                && existingEntry.startsAt == authoritativeStartsAt expectedSuggestion.suggestionBoundaries
                && existingEntry.endsAt == authoritativeEndsAt expectedSuggestion.suggestionBoundaries
                && existingEntry.timezone == authoritativeTimezone expectedSuggestion.suggestionBoundaries ->
                pure (Just (existingEntry, False))
            | otherwise -> pure Nothing
        Nothing -> do
            targetAllowed <- timesheetTargetAllowsCreation timesheetEntry
            currentSuggestion <- fetchTimesheetSuggestionForRosterSlot expectedSuggestion.suggestionRosterSlotId
            if not targetAllowed || currentSuggestion /= Just expectedSuggestion
                then pure Nothing
                else Just . (, True) <$> createTimesheetEntryWithVersion timesheetEntry

timesheetTargetAllowsCreation :: (?modelContext :: ModelContext) => TimesheetEntry -> IO Bool
timesheetTargetAllowsCreation entry = do
    maybeStaff <-
        query @Staff
            |> filterWhere (#id, Id entry.staffId)
            |> filterWhere (#venueId, entry.venueId)
            |> fetchOneOrNothing
    maybeShiftType <-
        query @ShiftType
            |> filterWhere (#id, Id entry.shiftTypeId)
            |> filterWhere (#venueId, entry.venueId)
            |> filterWhere (#isActive, True)
            |> filterWhere (#archivedAt, Nothing)
            |> fetchOneOrNothing
    pure $
        maybe False (\staff -> isLinkedActiveStaff staff && staffAssignmentAllowsTimesheets (staffAssignment staff)) maybeStaff
            && maybe False (shiftAssignmentAllowsTimesheets . shiftAssignment) maybeShiftType
  where
    staffAssignment staff =
        StaffPayAssignment staff.payAssignmentMode staff.defaultAwardLevelId staff.importedXeroPayItemId
    shiftAssignment shiftType =
        ShiftPayAssignment shiftType.payAssignmentMode shiftType.overrideAwardLevelId shiftType.importedXeroPayItemId

lockRosterSlot :: (?modelContext :: ModelContext) => UUID -> IO ()
lockRosterSlot rosterSlotId = do
    _lockedRosterSlotIds :: [Only UUID] <-
        sqlQuery
            "SELECT id FROM roster_slots WHERE id = ? FOR UPDATE"
            (Only rosterSlotId)
    pure ()

fetchActiveEntryForRosterSlot :: (?modelContext :: ModelContext) => UUID -> IO (Maybe TimesheetEntry)
fetchActiveEntryForRosterSlot rosterSlotId =
    query @TimesheetEntry
        |> filterWhere (#sourceRosterSlotId, Just rosterSlotId)
        |> filterWhere (#deletedAt, Nothing)
        |> fetchOneOrNothing

createTimesheetEntryWithVersion :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetEntry -> IO TimesheetEntry
createTimesheetEntryWithVersion timesheetEntry = do
    createdEntry <- timesheetEntry |> createRecord
    let versionPayload =
            case createdEntry.sourceRosterSlotId of
                Nothing -> Aeson.Null
                Just rosterSlotId ->
                    Aeson.object
                        [ "source" Aeson..= ("roster_suggestion" :: Text)
                        , "rosterSlotId" Aeson..= tshow rosterSlotId
                        ]
    void $ recordCurrentUserTimesheetEntryVersion (EntryVersionActionEnumCreated) createdEntry versionPayload
    pure createdEntry

timesheetCreationResult :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetEntry -> IO (LiveMutationResult TimesheetEntry)
timesheetCreationResult entry = do
    venueConfig <- fetchVenueConfig
    activeScopes <- activeTimesheetWindowScopes
    pure (liveMutationResult entry (timesheetEntryTouchedResourcesForScopes venueConfig activeScopes [entry]))

updateTimesheetEntryMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetWeekScopeValue -> TimesheetEditIntent -> IO (Either TimesheetCalendarConflict (Bool, LiveMutationResult TimesheetEntry))
updateTimesheetEntryMutation scope intent = Exception.try @TimesheetCalendarConflict do
    let existingEntry = originalTimesheetEntry intent
    let timesheetEntry = submittedTimesheetEntry intent
    let shouldResetApproval = existingEntry.isApproved && timesheetCoreChanged existingEntry timesheetEntry
    result <- withDurableLiveMutation "timesheet.update" $
        withTimesheetCalendarMutationLock scope do
            let updateAction = if shouldResetApproval then ApprovalReset else Updated
            updatedEntry <-
                timesheetEntry
                    |> resetApprovalOnEdit shouldResetApproval
                    |> updateRecord
            void $
                recordCurrentUserTimesheetEntryVersion
                    updateAction
                    updatedEntry
                    (Aeson.object
                        [ "previous" Aeson..= timesheetEntrySnapshot existingEntry
                        ]
                    )
            when shouldResetApproval do
                void $ recordCurrentUserAuditEvent
                    TimesheetApprovalResetAudit
                    "timesheet_entries"
                    (unpackId (get #id timesheetEntry))
                    (Aeson.object
                        [ "staffId" Aeson..= timesheetEntry.staffId
                        , "startsAt" Aeson..= timesheetEntry.startsAt
                        , "timezone" Aeson..= timesheetEntry.timezone
                        , "previousApprovedAt" Aeson..= timesheetEntry.approvedAt
                        , "previousApprovedByUserId" Aeson..= timesheetEntry.approvedByUserId
                        ]
                    )
            venueConfig <- fetchVenueConfig
            activeScopes <- activeTimesheetWindowScopes
            pure (liveMutationResult updatedEntry (timesheetEntryTouchedResourcesForScopes venueConfig activeScopes [existingEntry, updatedEntry]))
    pure (shouldResetApproval, result)

deleteTimesheetEntryMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetWeekScopeValue -> TimesheetEntry -> IO (Either TimesheetCalendarConflict (LiveMutationResult TimesheetEntry))
deleteTimesheetEntryMutation scope timesheetEntry =
    Exception.try @TimesheetCalendarConflict $ withDurableLiveMutation "timesheet.delete" $
        withTimesheetCalendarMutationLock scope do
            now <- getCurrentTime
            softDeletedEntry <-
                timesheetEntry
                    |> set #deletedAt (Just now)
                    |> set #deletedByUserId (Just (unpackId currentUser.id))
                    |> set #deleteReason (Just "user_deleted")
                    |> updateRecord
            void $
                recordCurrentUserTimesheetEntryVersion
                    (EntryVersionActionEnumDeleted)
                    softDeletedEntry
                    Aeson.Null
            void $ recordCurrentUserAuditEvent
                TimesheetDeletedAudit
                "timesheet_entries"
                (unpackId (get #id timesheetEntry))
                (Aeson.object
                    [ "staffId" Aeson..= timesheetEntry.staffId
                    , "startsAt" Aeson..= timesheetEntry.startsAt
                    , "timezone" Aeson..= timesheetEntry.timezone
                    , "wasApproved" Aeson..= timesheetEntry.isApproved
                    , "deletedAt" Aeson..= now
                    ]
                )
            venueConfig <- fetchVenueConfig
            activeScopes <- activeTimesheetWindowScopes
            pure (liveMutationResult softDeletedEntry (timesheetEntryTouchedResourcesForScopes venueConfig activeScopes [timesheetEntry]))

newtype TimesheetApprovalRollback = TimesheetApprovalRollback AppError
    deriving stock (Show)

instance Exception.Exception TimesheetApprovalRollback

approveTimesheetEntryMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetWeekScopeValue -> TimesheetEntry -> IO (Either TimesheetCalendarConflict (AppResult (LiveMutationResult TimesheetEntry)))
approveTimesheetEntryMutation scope timesheetEntry = Exception.try @TimesheetCalendarConflict do
    approval <- Exception.try @TimesheetApprovalRollback $
        withDurableLiveMutation "timesheet.approve" $
            withTimesheetCalendarMutationLock scope do
                updatedEntry <- approveTimesheetEntryInCurrentTransaction timesheetEntry
                venueConfig <- fetchVenueConfig
                activeScopes <- activeTimesheetWindowScopes
                pure (liveMutationResult updatedEntry (timesheetEntryTouchedResourcesForScopes venueConfig activeScopes [updatedEntry]))
    pure case approval of
        Left (TimesheetApprovalRollback appError) -> Left appError
        Right mutationResult                      -> Right mutationResult

approveTimesheetEntryInCurrentTransaction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetEntry -> IO TimesheetEntry
approveTimesheetEntryInCurrentTransaction timesheetEntry =
    runApprovalEngineInCurrentTransaction currentUser.id InitialApproval currentRequestAuditPayload requestAuditSourceChannel timesheetEntry >>= \case
        Left approvalError ->
            Exception.throwIO (TimesheetApprovalRollback (projectDomainError approvalError))
        Right approvalResult -> pure approvalResult.approvalEngineEntry

unapproveTimesheetEntryMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetWeekScopeValue -> TimesheetEntry -> IO (Either TimesheetCalendarConflict (LiveMutationResult TimesheetEntry))
unapproveTimesheetEntryMutation scope timesheetEntry =
    Exception.try @TimesheetCalendarConflict $ withDurableLiveMutation "timesheet.unapprove" $
        withTimesheetCalendarMutationLock scope do
            updatedEntry <-
                timesheetEntry
                    |> set #isApproved False
                    |> set #activePayCalculationId Nothing
                    |> set #legacyPayBackfillPending False
                    |> set #staffPayVersionId Nothing
                    |> set #shiftTypePayVersionId Nothing
                    |> set #approvedAt Nothing
                    |> set #approvedByUserId Nothing
                    |> updateRecord
            void $
                recordCurrentUserTimesheetEntryVersion
                    (Unapproved)
                    updatedEntry
                    (Aeson.object
                        [ "previous" Aeson..= timesheetEntrySnapshot timesheetEntry
                        ]
                    )
            void $ recordCurrentUserAuditEvent
                TimesheetUnapprovedAudit
                "timesheet_entries"
                (unpackId (get #id timesheetEntry))
                (Aeson.object
                    [ "staffId" Aeson..= timesheetEntry.staffId
                    , "startsAt" Aeson..= timesheetEntry.startsAt
                    , "timezone" Aeson..= timesheetEntry.timezone
                    , "wasApproved" Aeson..= timesheetEntry.isApproved
                    , "previousApprovedAt" Aeson..= timesheetEntry.approvedAt
                    , "previousApprovedByUserId" Aeson..= timesheetEntry.approvedByUserId
                    ]
                )
            venueConfig <- fetchVenueConfig
            activeScopes <- activeTimesheetWindowScopes
            pure (liveMutationResult updatedEntry (timesheetEntryTouchedResourcesForScopes venueConfig activeScopes [updatedEntry]))

timesheetEntryTouchedResourcesForScopes :: VenueConfig -> [(UUID, Day, Day, Int)] -> [TimesheetEntry] -> [SurfaceResourceValue]
timesheetEntryTouchedResourcesForScopes venueConfig activeScopes entries =
    Set.toList $ Set.fromList $
        timesheetEntryTouchedResources venueConfig entries
            <> [ timesheetWeekResource activeVenueId windowStart windowEnd
               | (activeVenueId, windowStart, windowEnd, _calendarRevision) <- activeScopes
               , any (entryOverlapsWindow activeVenueId windowStart windowEnd) entries
               ]
  where
    entryOverlapsWindow activeVenueId windowStart windowEnd entry =
        entry.venueId == activeVenueId
            && timesheetEntryOperationalDate entry >= windowStart
            && timesheetEntryOperationalDate entry < windowEnd

timesheetEntryTouchedResources :: VenueConfig -> [TimesheetEntry] -> [SurfaceResourceValue]
timesheetEntryTouchedResources venueConfig =
    concatMap entryResources
    where
        entryResources entry =
            let workedOn = timesheetEntryOperationalDate entry
                windowStart = startOfWeekFor venueConfig.rosterWeekStartsOn workedOn
                windowEnd = addDays 7 windowStart
             in [ timesheetWeekResource entry.venueId windowStart windowEnd
                , timesheetDayResource entry.venueId workedOn
                ]
