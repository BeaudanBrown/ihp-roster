module Web.Timesheets.Mutations
    ( approveTimesheetEntryMutation
    , createTimesheetEntryMutation
    , deleteTimesheetEntryMutation
    , timesheetEntryTouchedResources
    , unapproveTimesheetEntryMutation
    , updateTimesheetEntryMutation
    ) where

import Application.Helper.Pay (ensurePayVersionsForTimesheetApproval,
                               lockPayVersionsForApproval,
                               payVersionManifestForEntry)
import Application.Helper.SurfaceResource
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Data.Time.Calendar (diffDays)
import Data.Time.Clock (getCurrentTime)
import Web.Controller.Prelude
import Web.SurfaceInvalidation (invalidateTouchedResources)
import Web.Timesheets.Validation (resetApprovalOnEdit)

createTimesheetEntryMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> TimesheetEntry -> IO (LiveMutationResult TimesheetEntry)
createTimesheetEntryMutation _weekOffset timesheetEntry = do
    createdEntry <- withTransaction do
        createdEntry <- timesheetEntry |> createRecord
        void $ recordCurrentUserTimesheetEntryVersion (unsafeEnumFromText @EntryVersionActionEnum "created") createdEntry Aeson.Null
        pure createdEntry
    venueConfig <- fetchVenueConfig
    invalidateTouchedResources "timesheet.create" (liveMutationResult createdEntry (timesheetEntryTouchedResources venueConfig [createdEntry]))

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
