module Web.Controller.Timesheets where

import Application.Helper.Pay (ensurePayVersionsForTimesheetApproval,
                               lockPayVersionsForApproval,
                               payVersionManifestForEntry)
import Application.Helper.LiveSurface (ensureTypedLiveSurfaceAuthorized)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Data.Time.Clock (getCurrentTime)
import Web.Controller.Prelude
import Web.Timesheets.Paths (timesheetWeekUrl)
import Web.Timesheets.Projection
import Web.Timesheets.Responses
import Web.Timesheets.Validation
import Web.View.Timesheets.Edit
import Web.View.Timesheets.New

instance Controller TimesheetsController where
    beforeAction = do
        ensureIsUser
        ensureCurrentVenueOrSupportRedirect
        ensureProfileCompleted

    action TimesheetsAction = do
        currentOffset <- currentTimesheetWeekOffset
        let (showApproved, showAllStaff, selectedStaffFilterId) = timesheetViewFiltersFromRequest
        if isHtmxRequest
            then do
                setHtmxPushUrl (timesheetWeekUrl currentOffset showApproved showAllStaff selectedStaffFilterId)
                renderTimesheetWeekPage currentOffset showApproved showAllStaff selectedStaffFilterId
            else redirectToPath (timesheetWeekUrl currentOffset showApproved showAllStaff selectedStaffFilterId)

    action ShowTimesheetWeekAction { weekOffset } = do
        let (showApproved, showAllStaff, selectedStaffFilterId) = timesheetViewFiltersFromRequest
        renderTimesheetWeekPage weekOffset showApproved showAllStaff selectedStaffFilterId

    action ShowTimesheetDaySectionFragmentAction { weekOffset, dayOffset } = do
        let (showApproved, showAllStaff, selectedStaffFilterId) = timesheetViewFiltersFromRequest
        ensureTypedLiveSurfaceAuthorized timesheetLiveSurfaceDefinition (TimesheetProjectionRequest weekOffset showApproved showAllStaff selectedStaffFilterId)
        respondWithTimesheetDaySectionFragment weekOffset dayOffset showApproved showAllStaff selectedStaffFilterId

    action NewTimesheetEntryAction = do
        weekOffset <- weekOffsetFromParamOrCurrent
        let (showApproved, showAllStaff, selectedStaffFilterId) = timesheetViewFiltersFromRequest
        staffMembers <- fetchStaffForForm
        shiftTypes <- fetchShiftTypesForForm
        currentUserStaff <- fetchCurrentUserStaff
        let currentViewerStaffId = unpackId . get #id <$> currentUserStaff
        let maybeWorkedOn = paramOrNothing @Day "workedOn"

        case (staffMembers, shiftTypes, maybeWorkedOn) of
            ([], _, _) -> do
                setErrorMessage "No staff record found. Contact an administrator."
                redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff selectedStaffFilterId)
            (_, [], _) -> do
                setErrorMessage "Add at least one shift type before creating a timesheet entry."
                redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff selectedStaffFilterId)
            (_, _, Nothing) -> do
                setErrorMessage "Please choose a day before creating a timesheet entry."
                redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff selectedStaffFilterId)
            (_, defaultShiftType : _, Just workedOn) -> do
                let timesheetEntry =
                        newRecord @TimesheetEntry
                            |> set #venueId (unpackId currentVenueId)
                            |> (\entry -> maybe entry (\staff -> set #staffId (unpackId (get #id staff)) entry) currentUserStaff)
                            |> set #shiftTypeId (unpackId (get #id defaultShiftType))
                            |> set #workedOn workedOn
                            |> set #startTime (TimeOfDay 12 0 0)
                            |> set #endTime (TimeOfDay 20 0 0)
                            |> set #hadBreak False
                            |> set #breakStartTime Nothing
                            |> set #breakEndTime Nothing
                            |> set #breakMinutes 0
                if isHtmxRequest
                    then respondHtml (renderNewTimesheetDialog timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff selectedStaffFilterId currentViewerStaffId)
                    else render NewView { .. }

    action CreateTimesheetEntryAction = do
        ensureVenueWritable
        weekOffset <- weekOffsetFromParamOrCurrent
        let (showApproved, showAllStaff, selectedStaffFilterId) = timesheetViewFiltersFromRequest
        staffMembers <- fetchStaffForForm
        shiftTypes <- fetchShiftTypesForForm
        currentUserStaff <- fetchCurrentUserStaff
        let currentViewerStaffId = unpackId . get #id <$> currentUserStaff
        let timesheetEntryRecord =
                newRecord @TimesheetEntry
                    |> set #venueId (unpackId currentVenueId)
                    |> buildTimesheetEntry currentViewerStaffId

        timesheetEntryRecord
            |> ifValid \case
                Left timesheetEntry -> do
                    if isHtmxRequest
                        then respondHtml (renderNewTimesheetDialog timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff selectedStaffFilterId currentViewerStaffId)
                        else render NewView { .. }
                Right timesheetEntry -> do
                    ensureStaffAssignmentAllowed timesheetEntry.staffId
                    ensureShiftTypeAllowed timesheetEntry.shiftTypeId
                    createdEntry <- withTransaction do
                        createdEntry <- timesheetEntry |> createRecord
                        void $ recordCurrentUserTimesheetEntryVersion (unsafeEnumFromText @EntryVersionActionEnum "created") createdEntry Aeson.Null
                        pure createdEntry
                    broadcastTimesheetDayInvalidation weekOffset createdEntry.workedOn
                    if isHtmxRequest
                        then respondWithTimesheetDaySectionUpdate weekOffset createdEntry.workedOn showApproved showAllStaff selectedStaffFilterId "Timesheet entry created" True True
                        else do
                            setSuccessMessage "Timesheet entry created"
                            redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff selectedStaffFilterId)

    action EditTimesheetEntryAction { timesheetEntryId } = do
        timesheetEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue timesheetEntry.venueId
        ensureTimesheetVisibility timesheetEntry
        ensureEditWindowOrManager timesheetEntry.workedOn

        weekOffset <- weekOffsetFromParamOrEntry timesheetEntry.workedOn
        let (showApproved, showAllStaff, selectedStaffFilterId) = timesheetViewFiltersFromRequest
        staffMembers <- fetchStaffForForm
        shiftTypes <- fetchShiftTypesForForm
        currentUserStaff <- fetchCurrentUserStaff
        let currentViewerStaffId = unpackId . get #id <$> currentUserStaff
        if isHtmxRequest
            then respondHtml (renderEditTimesheetDialog timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff selectedStaffFilterId currentViewerStaffId)
            else render EditView { .. }

    action UpdateTimesheetEntryAction { timesheetEntryId } = do
        ensureVenueWritable
        existingEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue existingEntry.venueId
        ensureTimesheetVisibility existingEntry
        ensureEditWindowOrManager existingEntry.workedOn

        weekOffset <- weekOffsetFromParamOrEntry existingEntry.workedOn
        let (showApproved, showAllStaff, selectedStaffFilterId) = timesheetViewFiltersFromRequest
        staffMembers <- fetchStaffForForm
        shiftTypes <- fetchShiftTypesForForm
        currentUserStaff <- fetchCurrentUserStaff
        let currentViewerStaffId = unpackId . get #id <$> currentUserStaff

        let wasApproved = existingEntry.isApproved
        existingEntry
            |> buildTimesheetEntry currentViewerStaffId
            |> ifValid \case
                Left timesheetEntry -> do
                    if isHtmxRequest
                        then respondHtml (renderEditTimesheetDialog timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff selectedStaffFilterId currentViewerStaffId)
                        else render EditView { .. }
                Right timesheetEntry -> do
                    ensureStaffAssignmentAllowed timesheetEntry.staffId
                    ensureShiftTypeAllowed timesheetEntry.shiftTypeId
                    let coreChanged = timesheetCoreChanged existingEntry timesheetEntry
                    when (wasApproved && coreChanged) do
                        ensureTimesheetEntryNotPayrollLocked existingEntry weekOffset showApproved showAllStaff selectedStaffFilterId
                    let oldWorkedOn = existingEntry.workedOn
                    let successMessage =
                            if wasApproved && coreChanged
                                then "Timesheet entry updated (approval reset)"
                                else "Timesheet entry updated"
                    let updateAction = unsafeEnumFromText @EntryVersionActionEnum (if wasApproved && coreChanged then "approval_reset" else "updated")
                    updatedEntry <- withTransaction do
                        updatedEntry <- timesheetEntry
                            |> resetApprovalOnEdit (wasApproved && coreChanged)
                            |> updateRecord
                        void $
                            recordCurrentUserTimesheetEntryVersion
                                updateAction
                                updatedEntry
                                (Aeson.object
                                    [ "previous" Aeson..= timesheetEntrySnapshot existingEntry
                                    ]
                                )
                        when (wasApproved && coreChanged) do
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
                    broadcastTimesheetEntryMoveInvalidation oldWorkedOn updatedEntry.workedOn
                    if isHtmxRequest
                        then respondWithTimesheetDateMoveUpdate weekOffset oldWorkedOn updatedEntry.workedOn showApproved showAllStaff selectedStaffFilterId successMessage
                        else do
                            setSuccessMessage successMessage
                            redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff selectedStaffFilterId)

    action DeleteTimesheetEntryAction { timesheetEntryId } = do
        ensureVenueWritable
        timesheetEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue timesheetEntry.venueId
        ensureTimesheetVisibility timesheetEntry
        ensureEditWindowOrManager timesheetEntry.workedOn

        weekOffset <- weekOffsetFromParamOrEntry timesheetEntry.workedOn
        let (showApproved, showAllStaff, selectedStaffFilterId) = timesheetViewFiltersFromRequest
        ensureTimesheetEntryNotPayrollLocked timesheetEntry weekOffset showApproved showAllStaff selectedStaffFilterId
        now <- getCurrentTime
        withTransaction do
            softDeletedEntry <- timesheetEntry
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
        broadcastTimesheetDayInvalidation weekOffset timesheetEntry.workedOn
        if isHtmxRequest
            then respondWithTimesheetDaySectionUpdate weekOffset timesheetEntry.workedOn showApproved showAllStaff selectedStaffFilterId "Timesheet entry removed" True True
            else setSuccessMessage "Timesheet entry removed"
        unless isHtmxRequest do
            redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff selectedStaffFilterId)

    action ApproveTimesheetEntryAction { timesheetEntryId } = do
        ensureManagerRole
        ensureVenueWritable
        timesheetEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue timesheetEntry.venueId
        accessDeniedUnless (isNothing timesheetEntry.deletedAt)
        weekOffset <- weekOffsetFromParamOrEntry timesheetEntry.workedOn
        let (showApproved, showAllStaff, selectedStaffFilterId) = timesheetViewFiltersFromRequest

        now <- getCurrentTime
        (staffPayVersion, shiftTypePayVersion) <- ensurePayVersionsForTimesheetApproval currentUser.id timesheetEntry
        withTransaction do
            lockPayVersionsForApproval currentUser.id now staffPayVersion shiftTypePayVersion
            updatedEntry <- timesheetEntry
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
        broadcastTimesheetDayInvalidation weekOffset timesheetEntry.workedOn
        if isHtmxRequest
            then respondWithTimesheetDaySectionUpdate weekOffset timesheetEntry.workedOn showApproved showAllStaff selectedStaffFilterId "Timesheet entry approved" False False
            else do
                setSuccessMessage "Timesheet entry approved"
                redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff selectedStaffFilterId)

    action UnapproveTimesheetEntryAction { timesheetEntryId } = do
        ensureManagerRole
        ensureVenueWritable
        timesheetEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue timesheetEntry.venueId
        accessDeniedUnless (isNothing timesheetEntry.deletedAt)
        weekOffset <- weekOffsetFromParamOrEntry timesheetEntry.workedOn
        let (showApproved, showAllStaff, selectedStaffFilterId) = timesheetViewFiltersFromRequest
        ensureTimesheetEntryNotPayrollLocked timesheetEntry weekOffset showApproved showAllStaff selectedStaffFilterId

        withTransaction do
            updatedEntry <- timesheetEntry
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
        broadcastTimesheetDayInvalidation weekOffset timesheetEntry.workedOn
        if isHtmxRequest
            then respondWithTimesheetDaySectionUpdate weekOffset timesheetEntry.workedOn showApproved showAllStaff selectedStaffFilterId "Timesheet entry unapproved" False False
            else do
                setSuccessMessage "Timesheet entry unapproved"
                redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff selectedStaffFilterId)
