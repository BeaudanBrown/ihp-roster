module Web.Timesheets.Mutations
    ( approveTimesheetEntryMutation
    , createTimesheetEntryMutation
    , materializeAndApproveTimesheetSuggestionMutation
    , materializeTimesheetSuggestionMutation
    , deleteTimesheetEntryMutation
    , timesheetEntryTouchedResources
    , unapproveTimesheetEntryMutation
    , updateTimesheetEntryMutation
    ) where

import Application.Helper.FrontendContract.Surface.Timesheets.Resource
import Application.Helper.Pay (ensurePayVersionsForTimesheetApproval,
                               lockPayVersionsForApproval,
                               payVersionManifestForEntry)
import Application.Helper.Staff (isLinkedActiveStaff)
import Application.Helper.SurfaceResource
import Application.Helper.TimesheetPayLedger (persistApprovedTimesheetPayCalculation)
import Application.Helper.WeekBoundaries (startOfWeekFor)
import Application.PayAssignment (ShiftPayAssignment (..),
                                  StaffPayAssignment (..),
                                  shiftAssignmentAllowsTimesheets,
                                  staffAssignmentAllowsTimesheets)
import Application.RosterPublication.Mutations (withRosterCalendarLock)
import Application.VenueTime.Model
import Application.WageSourceEnforcement (enforceFinalWageEntries,
                                          renderWageEntryFailures)
import Control.Exception (IOException, try)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import Data.Time.Calendar (addDays)
import Data.Time.Clock (getCurrentTime)
import Data.Tuple.Only (Only (..))
import IHP.ModelSupport (sqlQuery)
import Network.HTTP.Types.Status (status409)
import qualified Network.Wai as Wai
import Web.Controller.Prelude
import Web.SurfaceInvalidation (invalidateTouchedResources)
import Web.Timesheets.Projection (fetchTimesheetSuggestionForRosterSlot)
import Web.Timesheets.Suggestion (TimesheetSuggestion (..))
import Web.Timesheets.Validation (resetApprovalOnEdit)

withTimesheetCalendarMutationLock :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> IO value -> IO value
withTimesheetCalendarMutationLock expectedRevision action =
    withRosterCalendarLock currentVenueId do
        venueConfig <- fetchVenueConfig
        if expectedRevision == venueConfig.rosterCalendarRevision
            then action
            else
                if isHtmxRequest
                    then do
                        respondAndExit
                            ( Wai.responseLBS
                                status409
                                [("Content-Type", "text/plain"), ("HX-Refresh", "true")]
                                "The roster calendar changed. Review the refreshed window and try again."
                            )
                        error "unreachable"
                    else do
                        accessDeniedUnless False
                        action

createTimesheetEntryMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> Int -> TimesheetEntry -> IO (LiveMutationResult TimesheetEntry)
createTimesheetEntryMutation _weekOffset expectedRevision timesheetEntry = do
    accessDeniedUnless (isNothing timesheetEntry.sourceRosterSlotId)
    createdEntry <- withTimesheetCalendarMutationLock expectedRevision $ withTransaction (createTimesheetEntryWithVersion timesheetEntry)
    invalidateTimesheetCreation "timesheet.create" createdEntry

materializeTimesheetSuggestionMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> Int -> TimesheetSuggestion -> TimesheetEntry -> IO (Maybe (LiveMutationResult TimesheetEntry))
materializeTimesheetSuggestionMutation _weekOffset expectedRevision expectedSuggestion timesheetEntry = do
    materialization <- withTimesheetCalendarMutationLock expectedRevision $ withTransaction (materializeTimesheetSuggestionInCurrentTransaction expectedSuggestion timesheetEntry)
    case materialization of
        Nothing -> pure Nothing
        Just (materializedEntry, wasCreated) ->
            Just <$> invalidateTimesheetCreation (if wasCreated then "timesheet.suggestion.create" else "timesheet.suggestion.create.idempotent") materializedEntry

materializeAndApproveTimesheetSuggestionMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> Int -> TimesheetSuggestion -> TimesheetEntry -> IO (Either Text (Maybe (LiveMutationResult TimesheetEntry)))
materializeAndApproveTimesheetSuggestionMutation _weekOffset expectedRevision expectedSuggestion timesheetEntry = do
    approval :: Either IOException (Maybe TimesheetEntry) <- try $ withTimesheetCalendarMutationLock expectedRevision $ withTransaction do
        materialization <- materializeTimesheetSuggestionInCurrentTransaction expectedSuggestion timesheetEntry
        case materialization of
            Nothing -> pure Nothing
            Just (materializedEntry, _) -> Just <$> approveTimesheetEntryInCurrentTransaction materializedEntry
    case approval of
        Left reason -> pure (Left (tshow reason))
        Right Nothing -> pure (Right Nothing)
        Right (Just approvedEntry) -> do
            venueConfig <- fetchVenueConfig
            result <- invalidateTouchedResources "timesheet.suggestion.approve" (liveMutationResult approvedEntry (timesheetEntryTouchedResources venueConfig [approvedEntry]))
            pure (Right (Just result))

materializeTimesheetSuggestionInCurrentTransaction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetSuggestion -> TimesheetEntry -> IO (Maybe (TimesheetEntry, Bool))
materializeTimesheetSuggestionInCurrentTransaction expectedSuggestion timesheetEntry = do
    let rosterSlotId = unpackId expectedSuggestion.suggestionRosterSlotId
    lockRosterSlot rosterSlotId
    existingEntry <- fetchActiveEntryForRosterSlot rosterSlotId
    case existingEntry of
        Just existingEntry
            | existingEntry.staffId == expectedSuggestion.suggestionStaffId
                && existingEntry.startsAt == authoritativeStartsAt expectedSuggestion.suggestionBoundaries
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

invalidateTimesheetCreation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Text -> TimesheetEntry -> IO (LiveMutationResult TimesheetEntry)
invalidateTimesheetCreation eventName entry = do
    venueConfig <- fetchVenueConfig
    invalidateTouchedResources eventName (liveMutationResult entry (timesheetEntryTouchedResources venueConfig [entry]))

updateTimesheetEntryMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> Int -> TimesheetEntry -> TimesheetEntry -> Bool -> IO (LiveMutationResult TimesheetEntry)
updateTimesheetEntryMutation _weekOffset expectedRevision existingEntry timesheetEntry shouldResetApproval = do
    let updateAction = if shouldResetApproval then ApprovalReset else Updated
    updatedEntry <- withTimesheetCalendarMutationLock expectedRevision $ withTransaction do
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
        pure updatedEntry
    venueConfig <- fetchVenueConfig
    invalidateTouchedResources "timesheet.update" (liveMutationResult updatedEntry (timesheetEntryTouchedResources venueConfig [existingEntry, updatedEntry]))

deleteTimesheetEntryMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> Int -> TimesheetEntry -> IO (LiveMutationResult TimesheetEntry)
deleteTimesheetEntryMutation _weekOffset expectedRevision timesheetEntry = do
    now <- getCurrentTime
    softDeletedEntry <- withTimesheetCalendarMutationLock expectedRevision $ withTransaction do
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
        pure softDeletedEntry
    venueConfig <- fetchVenueConfig
    invalidateTouchedResources "timesheet.delete" (liveMutationResult softDeletedEntry (timesheetEntryTouchedResources venueConfig [timesheetEntry]))

approveTimesheetEntryMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> Int -> TimesheetEntry -> IO (Either Text (LiveMutationResult TimesheetEntry))
approveTimesheetEntryMutation _weekOffset expectedRevision timesheetEntry = do
    approval :: Either IOException TimesheetEntry <- try $ withTimesheetCalendarMutationLock expectedRevision $ withTransaction (approveTimesheetEntryInCurrentTransaction timesheetEntry)
    case approval of
        Left reason -> pure (Left (tshow reason))
        Right updatedEntry -> do
            venueConfig <- fetchVenueConfig
            Right <$> invalidateTouchedResources "timesheet.approve" (liveMutationResult updatedEntry (timesheetEntryTouchedResources venueConfig [updatedEntry]))

approveTimesheetEntryInCurrentTransaction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetEntry -> IO TimesheetEntry
approveTimesheetEntryInCurrentTransaction timesheetEntry = do
    now <- getCurrentTime
    -- QueryBuilder has no row-lock combinator; keep this narrow FOR UPDATE
    -- seam here so concurrent approvals cannot create duplicate ledgers.
    lockedEntryIds :: [Only UUID] <- sqlQuery
        "SELECT id FROM timesheet_entries WHERE id = ? FOR UPDATE"
        (Only (unpackId timesheetEntry.id))
    lockedEntryId <- maybe (ioError (userError "timesheet entry disappeared during approval")) (\(Only entryId) -> pure entryId) (listToMaybe lockedEntryIds)
    lockedEntry <- fetch (Id lockedEntryId :: Id TimesheetEntry)
    case (lockedEntry.isApproved, lockedEntry.activePayCalculationId) of
        (True, Just _) -> pure lockedEntry
        _ -> do
            (staffPayVersion, shiftTypePayVersion) <- ensurePayVersionsForTimesheetApproval currentUser.id lockedEntry
            lockPayVersionsForApproval currentUser.id now staffPayVersion shiftTypePayVersion
            let approvalEntry =
                    lockedEntry
                        |> set #isApproved True
                        |> set #staffPayVersionId (Just (unpackId (get #id staffPayVersion)))
                        |> set #shiftTypePayVersionId (Just (unpackId (get #id shiftTypePayVersion)))
                        |> set #approvedAt (Just now)
                        |> set #approvedByUserId (Just (unpackId (get #id currentUser)))
                        |> set #updatedAt now
            sourceEnforcement <- enforceFinalWageEntries [approvalEntry |> set #isApproved False]
            case sourceEnforcement of
                Left failures -> ioError (userError (Text.unpack (renderWageEntryFailures "Approval blocked: " failures)))
                Right _       -> pure ()
            persistedCalculation <- persistApprovedTimesheetPayCalculation approvalEntry
            calculation <- case persistedCalculation of
                Left reason  -> ioError (userError (Text.unpack reason))
                Right result -> pure result
            activeEntry <- approvalEntry
                |> set #activePayCalculationId (Just calculation.id)
                |> updateRecord
            void $
                recordCurrentUserTimesheetEntryVersion
                    (EntryVersionActionEnumApproved)
                    activeEntry
                    (Aeson.object
                        [ "previous" Aeson..= timesheetEntrySnapshot lockedEntry
                        ]
                    )
            void $ recordCurrentUserAuditEvent
                TimesheetApprovedAudit
                "timesheet_entries"
                (unpackId (get #id lockedEntry))
                (Aeson.object
                    [ "staffId" Aeson..= lockedEntry.staffId
                    , "startsAt" Aeson..= lockedEntry.startsAt
                    , "timezone" Aeson..= lockedEntry.timezone
                    , "wasApproved" Aeson..= lockedEntry.isApproved
                    , "payConfigVersionManifest" Aeson..= payVersionManifestForEntry activeEntry
                    , "approvedAt" Aeson..= now
                    ]
                )
            pure activeEntry

unapproveTimesheetEntryMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> Int -> TimesheetEntry -> IO (LiveMutationResult TimesheetEntry)
unapproveTimesheetEntryMutation _weekOffset expectedRevision timesheetEntry = do
    updatedEntry <- withTimesheetCalendarMutationLock expectedRevision $ withTransaction do
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
        pure updatedEntry
    venueConfig <- fetchVenueConfig
    invalidateTouchedResources "timesheet.unapprove" (liveMutationResult updatedEntry (timesheetEntryTouchedResources venueConfig [updatedEntry]))

timesheetEntryTouchedResources :: VenueConfig -> [TimesheetEntry] -> [SurfaceResourceValue]
timesheetEntryTouchedResources venueConfig =
    concatMap entryResources
    where
        entryResources entry =
            let workedOn = timesheetEntryWorkedOn entry
                windowStart = startOfWeekFor venueConfig.rosterWeekStartsOn workedOn
                windowEnd = addDays 7 windowStart
             in [ timesheetWeekResource entry.venueId windowStart windowEnd
                , timesheetDayResource entry.venueId workedOn
                ]
