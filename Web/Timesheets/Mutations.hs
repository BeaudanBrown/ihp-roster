module Web.Timesheets.Mutations
    ( approveTimesheetEntryMutation
    , createTimesheetEntryMutation
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
import Application.Helper.SurfaceResource
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Data.Time.Calendar (diffDays)
import Data.Time.Clock (getCurrentTime)
import Data.Tuple.Only (Only (..))
import IHP.ModelSupport (sqlQuery)
import Web.Controller.Prelude
import Web.SurfaceInvalidation (invalidateTouchedResources)
import Web.Timesheets.Projection (fetchTimesheetSuggestionForRosterSlot)
import Web.Timesheets.Suggestion (TimesheetSuggestion (..))
import Web.Timesheets.Validation (resetApprovalOnEdit)

createTimesheetEntryMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> TimesheetEntry -> IO (LiveMutationResult TimesheetEntry)
createTimesheetEntryMutation _weekOffset timesheetEntry = do
    accessDeniedUnless (isNothing timesheetEntry.sourceRosterSlotId)
    createdEntry <- withTransaction (createTimesheetEntryWithVersion timesheetEntry)
    invalidateTimesheetCreation "timesheet.create" createdEntry

materializeTimesheetSuggestionMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> TimesheetSuggestion -> TimesheetEntry -> IO (Maybe (LiveMutationResult TimesheetEntry))
materializeTimesheetSuggestionMutation _weekOffset expectedSuggestion timesheetEntry = do
    materialization <- withTransaction do
        let rosterSlotId = unpackId expectedSuggestion.suggestionRosterSlotId
        lockRosterSlot rosterSlotId
        existingEntry <- fetchActiveEntryForRosterSlot rosterSlotId
        case existingEntry of
            Just existingEntry
                | existingEntry.staffId == expectedSuggestion.suggestionStaffId
                    && existingEntry.workedOn == expectedSuggestion.suggestionWorkedOn ->
                    pure (Just (existingEntry, False))
                | otherwise -> pure Nothing
            Nothing -> do
                currentSuggestion <- fetchTimesheetSuggestionForRosterSlot expectedSuggestion.suggestionRosterSlotId
                if currentSuggestion /= Just expectedSuggestion
                    then pure Nothing
                    else Just . (, True) <$> createTimesheetEntryWithVersion timesheetEntry
    case materialization of
        Nothing -> pure Nothing
        Just (materializedEntry, wasCreated) ->
            Just <$> invalidateTimesheetCreation (if wasCreated then "timesheet.suggestion.create" else "timesheet.suggestion.create.idempotent") materializedEntry

lockRosterSlot :: (?modelContext :: ModelContext) => UUID -> IO ()
lockRosterSlot rosterSlotId = do
    _lockedRosterSlots :: [RosterSlot] <-
        sqlQuery
            "SELECT roster_slots.* FROM roster_slots WHERE id = ? FOR UPDATE"
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
    void $ recordCurrentUserTimesheetEntryVersion (unsafeEnumFromText @EntryVersionActionEnum "created") createdEntry versionPayload
    pure createdEntry

invalidateTimesheetCreation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Text -> TimesheetEntry -> IO (LiveMutationResult TimesheetEntry)
invalidateTimesheetCreation eventName entry = do
    venueConfig <- fetchVenueConfig
    invalidateTouchedResources eventName (liveMutationResult entry (timesheetEntryTouchedResources venueConfig [entry]))

updateTimesheetEntryMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> TimesheetEntry -> TimesheetEntry -> Bool -> IO (LiveMutationResult TimesheetEntry)
updateTimesheetEntryMutation _weekOffset existingEntry timesheetEntry shouldResetApproval = do
    let updateAction = unsafeEnumFromText @EntryVersionActionEnum (if shouldResetApproval then "approval_reset" else "updated")
    updatedEntry <- withTransaction do
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
                "timesheet_approval_reset"
                "timesheet_entries"
                (unpackId (get #id timesheetEntry))
                (Aeson.object
                    [ "staffId" Aeson..= timesheetEntry.staffId
                    , "workedOn" Aeson..= timesheetEntry.workedOn
                    , "previousApprovedAt" Aeson..= timesheetEntry.approvedAt
                    , "previousApprovedByUserId" Aeson..= timesheetEntry.approvedByUserId
                    ]
                )
        pure updatedEntry
    venueConfig <- fetchVenueConfig
    invalidateTouchedResources "timesheet.update" (liveMutationResult updatedEntry (timesheetEntryTouchedResources venueConfig [existingEntry, updatedEntry]))

deleteTimesheetEntryMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> TimesheetEntry -> IO (LiveMutationResult TimesheetEntry)
deleteTimesheetEntryMutation _weekOffset timesheetEntry = do
    now <- getCurrentTime
    softDeletedEntry <- withTransaction do
        softDeletedEntry <-
            timesheetEntry
                |> set #deletedAt (Just now)
                |> set #deletedByUserId (Just (unpackId currentUser.id))
                |> set #deleteReason (Just "user_deleted")
                |> updateRecord
        void $
            recordCurrentUserTimesheetEntryVersion
                (unsafeEnumFromText @EntryVersionActionEnum "deleted")
                softDeletedEntry
                Aeson.Null
        void $ recordCurrentUserAuditEvent
            "timesheet_deleted"
            "timesheet_entries"
            (unpackId (get #id timesheetEntry))
            (Aeson.object
                [ "staffId" Aeson..= timesheetEntry.staffId
                , "workedOn" Aeson..= timesheetEntry.workedOn
                , "wasApproved" Aeson..= timesheetEntry.isApproved
                , "deletedAt" Aeson..= now
                ]
            )
        pure softDeletedEntry
    venueConfig <- fetchVenueConfig
    invalidateTouchedResources "timesheet.delete" (liveMutationResult softDeletedEntry (timesheetEntryTouchedResources venueConfig [timesheetEntry]))

approveTimesheetEntryMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> TimesheetEntry -> IO (LiveMutationResult TimesheetEntry)
approveTimesheetEntryMutation _weekOffset timesheetEntry = do
    now <- getCurrentTime
    (staffPayVersion, shiftTypePayVersion) <- ensurePayVersionsForTimesheetApproval currentUser.id timesheetEntry
    updatedEntry <- withTransaction do
        lockPayVersionsForApproval currentUser.id now staffPayVersion shiftTypePayVersion
        updatedEntry <-
            timesheetEntry
                |> set #isApproved True
                |> set #staffPayVersionId (Just (unpackId (get #id staffPayVersion)))
                |> set #shiftTypePayVersionId (Just (unpackId (get #id shiftTypePayVersion)))
                |> set #approvedAt (Just now)
                |> set #approvedByUserId (Just (unpackId (get #id currentUser)))
                |> updateRecord
        void $
            recordCurrentUserTimesheetEntryVersion
                (unsafeEnumFromText @EntryVersionActionEnum "approved")
                updatedEntry
                (Aeson.object
                    [ "previous" Aeson..= timesheetEntrySnapshot timesheetEntry
                    ]
                )
        void $ recordCurrentUserAuditEvent
            "timesheet_approved"
            "timesheet_entries"
            (unpackId (get #id timesheetEntry))
            (Aeson.object
                [ "staffId" Aeson..= timesheetEntry.staffId
                , "workedOn" Aeson..= timesheetEntry.workedOn
                , "wasApproved" Aeson..= timesheetEntry.isApproved
                , "payConfigVersionManifest" Aeson..= payVersionManifestForEntry updatedEntry
                , "approvedAt" Aeson..= now
                ]
            )
        pure updatedEntry
    venueConfig <- fetchVenueConfig
    invalidateTouchedResources "timesheet.approve" (liveMutationResult updatedEntry (timesheetEntryTouchedResources venueConfig [updatedEntry]))

unapproveTimesheetEntryMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> TimesheetEntry -> IO (LiveMutationResult TimesheetEntry)
unapproveTimesheetEntryMutation _weekOffset timesheetEntry = do
    updatedEntry <- withTransaction do
        updatedEntry <-
            timesheetEntry
                |> set #isApproved False
                |> set #staffPayVersionId Nothing
                |> set #shiftTypePayVersionId Nothing
                |> set #approvedAt Nothing
                |> set #approvedByUserId Nothing
                |> updateRecord
        void $
            recordCurrentUserTimesheetEntryVersion
                (unsafeEnumFromText @EntryVersionActionEnum "unapproved")
                updatedEntry
                (Aeson.object
                    [ "previous" Aeson..= timesheetEntrySnapshot timesheetEntry
                    ]
                )
        void $ recordCurrentUserAuditEvent
            "timesheet_unapproved"
            "timesheet_entries"
            (unpackId (get #id timesheetEntry))
            (Aeson.object
                [ "staffId" Aeson..= timesheetEntry.staffId
                , "workedOn" Aeson..= timesheetEntry.workedOn
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
            let weekOffset = venueWeekOffsetForDay venueConfig entry.workedOn
                dayOffset = timesheetEntryDayOffset venueConfig entry
             in [ timesheetWeekResource entry.venueId weekOffset
                , timesheetDayResource entry.venueId weekOffset dayOffset
                ]

timesheetEntryDayOffset :: VenueConfig -> TimesheetEntry -> Int
timesheetEntryDayOffset venueConfig entry =
    fromIntegral (diffDays entry.workedOn (venueWeekStartDate venueConfig (venueWeekOffsetForDay venueConfig entry.workedOn)))
