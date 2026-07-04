module Web.Controller.Timesheets where

import Application.Helper.SurfaceResource (LiveMutationResult (..))
import Web.Controller.Prelude
import Web.Timesheets.Mutations
import Web.Timesheets.Paths (timesheetWeekUrl)
import Web.Timesheets.Projection
import Web.Timesheets.Responses
import Web.Timesheets.Validation
import Web.View.Timesheets.Edit
import Web.View.Timesheets.New

instance Controller TimesheetsController where
    beforeAction = bepisBeforeAction BepisAuthenticatedVenueController do
        annotateTelemetryAction
        ensureIsUser
        ensureCurrentVenueOrSupportRedirect
        ensureProfileCompleted

    action currentAction@TimesheetsAction = runBepis currentAction BepisPageAction do
        currentOffset <- currentTimesheetWeekOffset
        let (showApproved, showAllStaff, selectedStaffFilterId) = timesheetViewFiltersFromRequest
        if isHtmxRequest
            then respondWithTimesheetWeekFragmentsUpdate currentOffset showApproved showAllStaff selectedStaffFilterId
            else redirectToPath (timesheetWeekUrl currentOffset showApproved showAllStaff selectedStaffFilterId)

    action currentAction@ShowTimesheetWeekAction { weekOffset } = runBepis currentAction BepisPageAction do
        let (showApproved, showAllStaff, selectedStaffFilterId) = timesheetViewFiltersFromRequest
        renderTimesheetWeekPage weekOffset showApproved showAllStaff selectedStaffFilterId

    action currentAction@ShowtimesheetToolbarLiveFragmentAction { weekOffset } = runBepis currentAction BepisFragmentAction do
        let (showApproved, showAllStaff, selectedStaffFilterId) = timesheetViewFiltersFromRequest
        let requestKey = TimesheetProjectionRequest weekOffset showApproved showAllStaff selectedStaffFilterId
        respondWithTimesheetFragment requestKey TimesheetProjectionToolbar

    action currentAction@ShowtimesheetDayColumnsLiveFragmentAction { weekOffset } = runBepis currentAction BepisFragmentAction do
        let (showApproved, showAllStaff, selectedStaffFilterId) = timesheetViewFiltersFromRequest
        let requestKey = TimesheetProjectionRequest weekOffset showApproved showAllStaff selectedStaffFilterId
        respondWithTimesheetFragment requestKey TimesheetProjectionDayColumns

    action currentAction@ShowTimesheetDaySectionFragmentAction { weekOffset, dayOffset } = runBepis currentAction BepisFragmentAction do
        let (showApproved, showAllStaff, selectedStaffFilterId) = timesheetViewFiltersFromRequest
        let requestKey = TimesheetProjectionRequest weekOffset showApproved showAllStaff selectedStaffFilterId
        let fragment = TimesheetProjectionDaySection dayOffset
        respondWithTimesheetFragment requestKey fragment

    action currentAction@NewTimesheetEntryAction = runBepis currentAction BepisFormAction do
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

    action currentAction@CreateTimesheetEntryAction = runBepis currentAction BepisMutationAction do
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
                    mutationResult <- createTimesheetEntryMutation weekOffset timesheetEntry
                    let createdEntry = mutationResult.liveMutationValue
                    if isHtmxRequest
                        then respondWithTimesheetDaySectionUpdate weekOffset createdEntry.workedOn showApproved showAllStaff selectedStaffFilterId "Timesheet entry created" True
                        else do
                            setSuccessMessage "Timesheet entry created"
                            redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff selectedStaffFilterId)

    action currentAction@EditTimesheetEntryAction { timesheetEntryId } = runBepis currentAction BepisFormAction do
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

    action currentAction@UpdateTimesheetEntryAction { timesheetEntryId } = runBepis currentAction BepisMutationAction do
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
                    mutationResult <- updateTimesheetEntryMutation weekOffset existingEntry timesheetEntry (wasApproved && coreChanged)
                    let updatedEntry = mutationResult.liveMutationValue
                    if isHtmxRequest
                        then respondWithTimesheetDateMoveUpdate weekOffset oldWorkedOn updatedEntry.workedOn showApproved showAllStaff selectedStaffFilterId successMessage
                        else do
                            setSuccessMessage successMessage
                            redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff selectedStaffFilterId)

    action currentAction@DeleteTimesheetEntryAction { timesheetEntryId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        timesheetEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue timesheetEntry.venueId
        ensureTimesheetVisibility timesheetEntry
        ensureEditWindowOrManager timesheetEntry.workedOn

        weekOffset <- weekOffsetFromParamOrEntry timesheetEntry.workedOn
        let (showApproved, showAllStaff, selectedStaffFilterId) = timesheetViewFiltersFromRequest
        ensureTimesheetEntryNotPayrollLocked timesheetEntry weekOffset showApproved showAllStaff selectedStaffFilterId
        _ <- deleteTimesheetEntryMutation weekOffset timesheetEntry
        if isHtmxRequest
            then respondWithTimesheetDaySectionUpdate weekOffset timesheetEntry.workedOn showApproved showAllStaff selectedStaffFilterId "Timesheet entry removed" True
            else setSuccessMessage "Timesheet entry removed"
        unless isHtmxRequest do
            redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff selectedStaffFilterId)

    action currentAction@ApproveTimesheetEntryAction { timesheetEntryId } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        timesheetEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue timesheetEntry.venueId
        accessDeniedUnless (isNothing timesheetEntry.deletedAt)
        weekOffset <- weekOffsetFromParamOrEntry timesheetEntry.workedOn
        let (showApproved, showAllStaff, selectedStaffFilterId) = timesheetViewFiltersFromRequest

        _ <- approveTimesheetEntryMutation weekOffset timesheetEntry
        if isHtmxRequest
            then respondWithTimesheetDaySectionUpdate weekOffset timesheetEntry.workedOn showApproved showAllStaff selectedStaffFilterId "Timesheet entry approved" False
            else do
                setSuccessMessage "Timesheet entry approved"
                redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff selectedStaffFilterId)

    action currentAction@UnapproveTimesheetEntryAction { timesheetEntryId } = runBepis currentAction BepisPageAction do
        ensureManagerRole
        ensureVenueWritable
        timesheetEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue timesheetEntry.venueId
        accessDeniedUnless (isNothing timesheetEntry.deletedAt)
        weekOffset <- weekOffsetFromParamOrEntry timesheetEntry.workedOn
        let (showApproved, showAllStaff, selectedStaffFilterId) = timesheetViewFiltersFromRequest
        ensureTimesheetEntryNotPayrollLocked timesheetEntry weekOffset showApproved showAllStaff selectedStaffFilterId

        _ <- unapproveTimesheetEntryMutation weekOffset timesheetEntry
        if isHtmxRequest
            then respondWithTimesheetDaySectionUpdate weekOffset timesheetEntry.workedOn showApproved showAllStaff selectedStaffFilterId "Timesheet entry unapproved" False
            else do
                setSuccessMessage "Timesheet entry unapproved"
                redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff selectedStaffFilterId)
