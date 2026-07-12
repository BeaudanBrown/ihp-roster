{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Web.Controller.RosterWeeks where

import Application.Helper.Controller
import Application.Helper.FrontendContract.AppShell (ConfirmRemoveRosterRowOverlay,
                                                     DeleteRosterSlotOverlay)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             appShellActionByMarker,
                                                             appShellDialogAutoSubmitOnceAttr,
                                                             renderAppShellActionForm)
import Application.Helper.Profiling
import Application.Helper.RosterGroups
import Application.Helper.SurfaceResource (LiveMutationResult (..))
import Application.Helper.TimeRules (defaultShiftTimesForVenueConfig,
                                     isQuarterHourMinutes,
                                     minuteOfDayToTimeOfDay,
                                     shiftDurationMinutes,
                                     validRosterShiftDurationMinutes,
                                     venueTimePickerFinalSelectableTimeText,
                                     venueTimePickerStartTimeText)
import Application.Helper.UserPreferences
import Application.Helper.View (DialogOverlayConfig (..), OverlayButton (..),
                                OverlayButtonAction (..),
                                ToastOverlayPosition (ToastBottomCenter),
                                dialogOverlayMountId, errorToast,
                                renderDialogOverlay, renderToastOob,
                                successToast)
import Control.Monad (guard)
import Data.Coerce (coerce)
import Data.List (find, nub)
import qualified Data.Map.Strict as Map
import Data.Maybe (catMaybes, fromMaybe, isJust, mapMaybe)
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Time (getCurrentTime, utctDay)
import qualified Data.Time.Calendar as Calendar
import Data.Time.LocalTime (TimeOfDay)
import qualified Data.UUID as UUID
import qualified Text.Blaze.Html as Blaze
import qualified Text.Read as TextRead
import Web.Controller.Prelude
import Web.Controller.RosterWeeks.Validation
import Web.Controller.Sessions (passkeySetupPromptSessionKey)
import Web.RosterWeeks.Capabilities (buildRosterViewCapabilities)
import Web.RosterWeeks.Dom
import Web.RosterWeeks.Filters
import Web.RosterWeeks.Mutations
import Web.RosterWeeks.Overview
import Web.RosterWeeks.Paths (rosterDayTimelineUrl, rosterWeekUrl)
import Web.RosterWeeks.Projection
import Web.RosterWeeks.RenderData
import Web.RosterWeeks.Responses (respondWithRosterContent,
                                  respondWithRosterContentError,
                                  respondWithRosterContentUpdate,
                                  respondWithRosterFragmentsUpdate,
                                  respondWithRosterResourceInvalidation,
                                  respondWithRosterToast)
import Web.RosterWeeks.Rows
import Web.RosterWeeks.Service
import Web.RosterWeeks.StaffOptions (buildRosterStaffOptionStates)
import Web.RosterWeeks.StaffSelfServiceLeaveFragments (buildDefaultRosterStaffSelfServiceLeaveRequest)
import Web.RosterWeeks.Types
import Web.View.RosterWeeks.Overview (renderWeekOverviewPanelFragment)
import Web.View.RosterWeeks.ShiftDialog
import Web.View.RosterWeeks.Show (renderRosterWeekShell)
import Web.View.RosterWeeks.StaffPanel (renderrosterStaffPanelLiveFragment)
import Web.View.RosterWeeks.StaffSelfServicePanel (renderRosterStaffSelfServiceLeaveFormFragmentForRoster)
import Web.View.RosterWeeks.Timeline (renderRosterDayTimelineContent)

instance Controller RosterWeeksController where
    beforeAction = bepisBeforeAction BepisAuthenticatedVenueController do
        annotateTelemetryAction
        ensureIsUser
        ensureCurrentVenueOrSupportRedirect
        ensureProfileCompleted

    action currentAction@RosterWeeksAction = runBepis currentAction BepisPageAction do
        -- Redirect to the current week's offset based on today's date
        currentWeekOffset <- fetchCurrentRosterWeekOffset
        currentRosterGroup <- resolveRequestedRosterGroup
        currentWeekPath <- case paramOrNothing @Text "rosterView" of
            Just "timeline" -> do
                venueConfig <- fetchVenueConfig
                today <- utctDay <$> getCurrentTime
                let todayDayOffset = fromInteger (Calendar.diffDays today (venueWeekStartDate venueConfig currentWeekOffset))
                pure (rosterDayTimelineUrl currentWeekOffset currentRosterGroup.id (max 0 (min 6 todayDayOffset)))
            _ -> pure (rosterWeekUrl currentWeekOffset currentRosterGroup.id)

        if isHtmxRequest
            then case (paramOrNothing @Text "rosterView", paramOrNothing @Int "dayOffset") of
                (Just "timeline", Nothing) -> do
                    setHeader ("HX-Redirect", cs currentWeekPath)
                    respondHtmlProfiled mempty
                _ -> do
                    setHtmxPushUrl currentWeekPath
                    renderRosterWeekPage currentWeekOffset currentRosterGroup.id
            else redirectToPath currentWeekPath

    action currentAction@ShowRosterWeekAction { weekOffset } = runBepis currentAction BepisPageAction do
        rosterGroup <- resolveRequestedRosterGroup
        case paramOrNothing @Calendar.Day "weekDate" of
            Just weekDate -> do
                venueConfig <- fetchVenueConfig
                let selectedWeekOffset = venueWeekOffsetForDay venueConfig weekDate
                let targetPath = rosterWeekUrl selectedWeekOffset rosterGroup.id
                if isHtmxRequest
                    then do
                        setHtmxPushUrl targetPath
                        renderRosterWeekPage selectedWeekOffset rosterGroup.id
                    else redirectToPath targetPath
            Nothing ->
                renderRosterWeekPage weekOffset rosterGroup.id

    action currentAction@ShowRosterDayTimelineAction { weekOffset, rosterDayId } = runBepis currentAction BepisPageAction do
        rosterGroup <- resolveRequestedRosterGroup
        maybeRosterData <- fetchVisibleRosterReadModel rosterGroup.id weekOffset
        case maybeRosterData of
            Nothing -> do
                setErrorMessage "Roster week not found."
                redirectToPath (rosterWeekUrl weekOffset rosterGroup.id)
            Just rosterData -> do
                let canViewTimeline = rosterData.rosterWeek.isLive || hasRole ManagerRole'
                accessDeniedUnless canViewTimeline
                case find (\rosterDay -> rosterDay.id == rosterDayId) rosterData.rosterDays of
                    Nothing -> do
                        setErrorMessage "Roster day not found."
                        redirectToPath (rosterWeekUrl weekOffset rosterGroup.id)
                    Just rosterDay ->
                        redirectToPath (rosterDayTimelineUrl weekOffset rosterGroup.id rosterDay.dayOffset)

    action currentAction@ShowRosterDayTimelineContentFragmentAction { weekOffset, rosterDayId } = runBepis currentAction BepisFragmentAction do
        rosterGroup <- resolveRequestedRosterGroup
        maybeRosterData <- fetchVisibleRosterReadModel rosterGroup.id weekOffset
        case maybeRosterData of
            Nothing -> respondHtmlProfiled mempty
            Just rosterData -> do
                let canViewTimeline = rosterData.rosterWeek.isLive || hasRole ManagerRole'
                accessDeniedUnless canViewTimeline
                let maybeRosterDay = find (\rosterDay -> rosterDay.id == rosterDayId) rosterData.rosterDays
                respondHtmlProfiled (maybe mempty (renderRosterDayTimelineContent Nothing rosterData) maybeRosterDay)

    action currentAction@ShowRosterWeekOverviewFragmentAction { weekOffset } = runBepis currentAction BepisFragmentAction do
        rosterGroup <- resolveRequestedRosterGroup
        respondHtmlProfiled =<< renderRosterWeekOverviewFragment weekOffset rosterGroup.id

    action currentAction@ShowRosterWeekContentFragmentAction { weekOffset } = runBepis currentAction BepisFragmentAction do
        rosterGroup <- resolveRequestedRosterGroup
        respondWithRosterContent rosterGroup.id weekOffset

    action currentAction@ShowRosterWeekGridToolbarFragmentAction { weekOffset } = runBepis currentAction BepisFragmentAction do
        rosterGroup <- resolveRequestedRosterGroup
        toolbarHtml <- renderVisibleRosterReadModelFragment rosterGroup.id weekOffset RosterProjectionGridToolbar
        respondHtmlProfiled (fromMaybe mempty toolbarHtml)

    action currentAction@ShowRosterWeekGridFrameFragmentAction { weekOffset } = runBepis currentAction BepisFragmentAction do
        rosterGroup <- resolveRequestedRosterGroup
        frameHtml <- renderVisibleRosterReadModelFragment rosterGroup.id weekOffset RosterProjectionGridFrame
        respondHtmlProfiled (fromMaybe mempty frameHtml)

    action currentAction@ShowRosterWeekDayColumnsFragmentAction { weekOffset } = runBepis currentAction BepisFragmentAction do
        rosterGroup <- resolveRequestedRosterGroup
        fragmentHtml <- renderVisibleRosterReadModelFragment rosterGroup.id weekOffset RosterProjectionDayColumns
        respondHtmlProfiled (fromMaybe mempty fragmentHtml)

    action currentAction@ShowRosterWeekDayRailFragmentAction { weekOffset } = runBepis currentAction BepisFragmentAction do
        rosterGroup <- resolveRequestedRosterGroup
        fragmentHtml <- renderVisibleRosterReadModelFragment rosterGroup.id weekOffset RosterProjectionDayRail
        respondHtmlProfiled (fromMaybe mempty fragmentHtml)

    action currentAction@ShowRosterWeekWageRailFragmentAction { weekOffset } = runBepis currentAction BepisFragmentAction do
        rosterGroup <- resolveRequestedRosterGroup
        fragmentHtml <- renderVisibleRosterReadModelFragment rosterGroup.id weekOffset RosterProjectionWageRail
        respondHtmlProfiled (fromMaybe mempty fragmentHtml)

    action currentAction@ShowRosterWeekSlotsGridFragmentAction { weekOffset } = runBepis currentAction BepisFragmentAction do
        rosterGroup <- resolveRequestedRosterGroup
        fragmentHtml <- renderVisibleRosterReadModelFragment rosterGroup.id weekOffset RosterProjectionSlotsGrid
        respondHtmlProfiled (fromMaybe mempty fragmentHtml)

    action currentAction@ShowRosterWeekStaffPanelFragmentAction { weekOffset } = runBepis currentAction BepisFragmentAction do
        rosterGroup <- resolveRequestedRosterGroup
        let panelScope = rosterStaffPanelScopeFromParams
        rosterGroups <- fetchCurrentVenueRosterGroups
        panelStaff <- fetchVisibleRosterStaffPanelEntries panelScope rosterGroup.id weekOffset
        respondHtmlProfiled $
            maybe mempty (renderrosterStaffPanelLiveFragment weekOffset rosterGroup.id (length rosterGroups > 1) panelScope) panelStaff

    action currentAction@ShowRosterStaffSelfServiceLeaveFormFragmentAction { weekOffset } = runBepis currentAction BepisFragmentAction do
        rosterGroup <- resolveRequestedRosterGroup
        leaveRequest <- buildDefaultRosterStaffSelfServiceLeaveRequest
        respondHtmlProfiled (renderRosterStaffSelfServiceLeaveFormFragmentForRoster rosterGroup.id weekOffset leaveRequest)

    action currentAction@ShowRosterWeekDaySectionFragmentAction { weekOffset, rosterDayId } = runBepis currentAction BepisFragmentAction do
        rosterGroupId <- resolveRosterGroupIdForFragmentRosterDay weekOffset rosterDayId
        daySectionHtml <- renderVisibleRosterReadModelFragment rosterGroupId weekOffset (RosterProjectionDaySection (unpackId rosterDayId))
        respondHtmlProfiled (fromMaybe mempty daySectionHtml)

    action currentAction@ShowRosterWeekRowFragmentAction { weekOffset, rosterDayId, rowIndex } = runBepis currentAction BepisFragmentAction do
        rosterGroupId <- resolveRosterGroupIdForFragmentRosterDay weekOffset rosterDayId
        rowHtml <- renderVisibleRosterReadModelFragment rosterGroupId weekOffset (RosterProjectionRow (unpackId rosterDayId) rowIndex)
        respondHtmlProfiled (fromMaybe mempty rowHtml)

    action currentAction@UpdateRosterAssignmentFiltersAction { weekOffset = _ } = runBepis currentAction BepisPreferenceAction do
        ensureManagerRole
        _ <- resolveRequestedRosterGroup
        setRosterAssignmentFiltersSession rosterAssignmentFiltersFromParams
        respondHtmlProfiled mempty

    action currentAction@CreateRosterWeekAction { weekOffset } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        rosterGroup <- resolveRequestedRosterGroup
        mutationResult <- ensureRosterWeekExistsMutation rosterGroup.id weekOffset
        let (rosterWeek, wasCreated) = mutationResult.liveMutationValue

        let successMessage =
                if wasCreated
                    then "Roster week created successfully"
                    else "Roster week already exists."
        let targetPath = rosterWeekUrl rosterWeek.weekOffset rosterGroup.id
        if isHtmxRequest
            then do
                setHtmxPushUrl targetPath
                respondWithRosterContentUpdate rosterGroup.id rosterWeek.weekOffset mutationResult.liveMutationTouchedResources successMessage
            else do
                setSuccessMessage successMessage
                redirectToPath targetPath

    action currentAction@CopyRosterWeekAction { sourceWeekOffset, targetWeekOffset } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        rosterGroup <- resolveRequestedRosterGroup

        if sourceWeekOffset == targetWeekOffset
            then do
                let errorMessage = "Cannot copy a roster week onto itself."
                if isHtmxRequest
                    then respondWithRosterToast errorMessage "app-toast-error"
                    else do
                        setErrorMessage errorMessage
                        redirectToPath (rosterWeekUrl targetWeekOffset rosterGroup.id)
            else do
                sourceWeekOrNothing <- query @RosterWeek
                    |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
                    |> filterWhere (#weekOffset, sourceWeekOffset)
                    |> fetchOneOrNothing
                case sourceWeekOrNothing of
                    Nothing -> do
                        let errorMessage = "Source week not found. Cannot copy."
                        if isHtmxRequest
                            then respondWithRosterToast errorMessage "app-toast-error"
                            else do
                                setErrorMessage errorMessage
                                redirectToPath (rosterWeekUrl targetWeekOffset rosterGroup.id)
                    Just sourceWeek -> do
                        mutationResult <- copyRosterWeekFromSourceMutation rosterGroup.id sourceWeek targetWeekOffset
                        let successMessage = "Roster week copied from the previous week."
                        let targetPath = rosterWeekUrl targetWeekOffset rosterGroup.id
                        if isHtmxRequest
                            then do
                                setHtmxPushUrl targetPath
                                respondWithRosterContentUpdate rosterGroup.id targetWeekOffset mutationResult.liveMutationTouchedResources successMessage
                            else do
                                setSuccessMessage successMessage
                                redirectToPath targetPath

    action currentAction@ToggleRosterWeekLiveStatusAction { rosterWeekId } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        rosterWeek <- fetch rosterWeekId
        ensureRecordInCurrentVenue rosterWeek.venueId
        let nextLiveStatus = isJust (paramOrNothing @Text "isLive")
        let rosterGroupId = coerce rosterWeek.rosterGroupId
        publishValidationError <- validateRosterWeekCanGoLive rosterWeek nextLiveStatus
        case publishValidationError of
            Just errorMessage ->
                if isHtmxRequest
                    then respondWithRosterContentError rosterGroupId rosterWeek.weekOffset errorMessage
                    else do
                        setErrorMessage errorMessage
                        redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)
            Nothing -> do
                mutationResult <- toggleRosterWeekLiveStatusMutation rosterGroupId rosterWeek nextLiveStatus
                let (_, queuedTimesheetJobCount) = mutationResult.liveMutationValue
                let successMessage =
                        if nextLiveStatus
                            then
                                if queuedTimesheetJobCount == 0
                                    then "Roster week is now live."
                                    else "Roster week is now live. Pending timesheet jobs queued for " <> tshow queuedTimesheetJobCount <> " shifts."
                            else "Roster week moved back to draft."
                let targetPath = rosterWeekUrl rosterWeek.weekOffset rosterGroupId
                if isHtmxRequest
                    then do
                        setHtmxPushUrl targetPath
                        respondWithRosterContentUpdate rosterGroupId rosterWeek.weekOffset mutationResult.liveMutationTouchedResources successMessage
                    else do
                        setSuccessMessage successMessage
                        redirectToPath targetPath

    action currentAction@CreateRosterWeekSlotDefinitionAction { rosterWeekId } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        rosterWeek <- fetch rosterWeekId
        ensureRecordInCurrentVenue rosterWeek.venueId
        ensureRosterWeekIsDraftForEdit rosterWeek

        let rosterGroupId = coerce rosterWeek.rosterGroupId
        requestedSlotName <- resolveRosterSlotDefinitionNameForCreate rosterWeek
        case requestedSlotName of
            Left errorMessage -> respondToRosterSlotDefinitionError rosterWeek errorMessage
            Right slotName -> do
                duplicate <- activeRosterWeekSlotDefinitionWithName rosterWeek slotName
                case duplicate of
                    Just _ -> respondToRosterSlotDefinitionError rosterWeek "A column with that name already exists for this week."
                    Nothing -> do
                        mutationResult <- appendRosterWeekSlotDefinitionMutation rosterGroupId rosterWeek slotName
                        respondToRosterSlotDefinitionSuccess rosterWeek mutationResult "Roster column added."

    action currentAction@DeleteRosterWeekSlotDefinitionAction { rosterWeekSlotDefinitionId } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        slotDefinition <- fetch rosterWeekSlotDefinitionId
        rosterWeek <- fetch (Id slotDefinition.rosterWeekId :: Id RosterWeek)
        ensureRecordInCurrentVenue rosterWeek.venueId
        ensureRosterWeekIsDraftForEdit rosterWeek

        activeDefinitions <- query @RosterWeekSlotDefinition
            |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
            |> filterWhere (#deletedAt, Nothing)
            |> fetch
        if length activeDefinitions <= 1
            then respondToRosterSlotDefinitionError rosterWeek "Roster weeks need at least one column."
            else do
                let rosterGroupId = coerce rosterWeek.rosterGroupId
                mutationResult <- removeRosterWeekSlotDefinitionMutation rosterGroupId rosterWeek slotDefinition
                respondToRosterSlotDefinitionSuccess rosterWeek mutationResult "Roster column removed."

    action currentAction@SortRosterWeekAction { rosterWeekId } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        rosterWeek <- fetch rosterWeekId
        ensureRecordInCurrentVenue rosterWeek.venueId
        ensureRosterWeekIsDraftForEdit rosterWeek

        let rosterGroupId = coerce rosterWeek.rosterGroupId
        mutationResult <- repackRosterWeekMutation rosterWeek

        if isHtmxRequest
            then
                respondWithRosterResourceInvalidation
                    rosterGroupId
                    rosterWeek.weekOffset
                    mutationResult.liveMutationTouchedResources
                    rosterGridInnerAndStaffPanelFragments
                    clearDialogOverlayOob
            else do
                setSuccessMessage "Roster sorted."
                redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)

    action currentAction@ToggleRosterDayClosedAction { rosterDayId } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable

        rosterDay <- fetch rosterDayId
        let rosterWeekId = (coerce rosterDay.rosterWeekId :: Id RosterWeek)
        rosterWeek <- fetch rosterWeekId
        ensureRecordInCurrentVenue rosterWeek.venueId
        ensureRosterWeekIsDraftForEdit rosterWeek

        let rosterGroupId = coerce rosterWeek.rosterGroupId
        let nextClosedState = not rosterDay.isClosed

        mutationResult <- toggleRosterDayClosedMutation rosterGroupId rosterWeek rosterDay nextClosedState closedRosterDayRows

        let successMessage =
                if nextClosedState
                    then "Roster day marked closed."
                    else "Roster day reopened."
        let targetPath = rosterWeekUrl rosterWeek.weekOffset rosterGroupId
        if isHtmxRequest
            then do
                setHtmxPushUrl targetPath
                respondWithRosterResourceInvalidation
                    rosterGroupId
                    rosterWeek.weekOffset
                    mutationResult.liveMutationTouchedResources
                    rosterGridInnerAndStaffPanelFragments
                    clearDialogOverlayOob
            else do
                setSuccessMessage successMessage
                redirectToPath targetPath

    action currentAction@AddRosterRowAction { rosterDayId } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable

        rosterDay <- fetch rosterDayId
        let rosterWeekId = (coerce rosterDay.rosterWeekId :: Id RosterWeek)
        rosterWeek <- fetch rosterWeekId
        ensureRecordInCurrentVenue rosterWeek.venueId
        ensureRosterWeekIsDraftForEdit rosterWeek

        when rosterDay.isClosed do
            let rosterGroupId = coerce rosterWeek.rosterGroupId
            let errorMessage = "Closed days stay locked at two blank rows until reopened."
            if isHtmxRequest
                then respondWithRosterToast errorMessage "app-toast-error"
                else do
                    setErrorMessage errorMessage
                    redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)

        let rosterGroupId = coerce rosterWeek.rosterGroupId
        slotTemplate <- fetchRosterWeekSlotTemplate rosterWeek

        if null slotTemplate
            then do
                let errorMessage = "Add at least one active slot to the selected roster group before adding roster rows."
                if isHtmxRequest
                    then respondWithRosterToast errorMessage "app-toast-error"
                    else do
                        setErrorMessage errorMessage
                        redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)
            else do
                mutationResult <- addRosterDayRowMutation rosterGroupId rosterWeek rosterDay

                if isHtmxRequest
                    then
                        respondWithRosterResourceInvalidation
                            rosterGroupId
                            rosterWeek.weekOffset
                            mutationResult.liveMutationTouchedResources
                            rosterGridInnerAndStaffPanelFragments
                            clearDialogOverlayOob
                    else do
                        setSuccessMessage "Roster row added."
                        redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)

    action currentAction@RemoveRosterRowAction { rosterDayId } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable

        rosterDay <- fetch rosterDayId
        let rosterWeekId = (coerce rosterDay.rosterWeekId :: Id RosterWeek)
        rosterWeek <- fetch rosterWeekId
        ensureRecordInCurrentVenue rosterWeek.venueId
        ensureRosterWeekIsDraftForEdit rosterWeek

        when rosterDay.isClosed do
            let rosterGroupId = coerce rosterWeek.rosterGroupId
            let errorMessage = "Closed days stay locked at two blank rows until reopened."
            if isHtmxRequest
                then respondWithRosterToast errorMessage "app-toast-error"
                else do
                    setErrorMessage errorMessage
                    redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)

        let rowCount = rosterDay.rowCount
        let confirmDeletePopulatedRow = paramOrDefault @Text "false" "confirmDeletePopulatedRow" == "true"

        when (rowCount <= minimumOpenRosterRows) do
            let rosterGroupId = coerce rosterWeek.rosterGroupId
            let errorMessage = "Roster days must keep at least two rows."
            if isHtmxRequest
                then respondWithRosterToast errorMessage "app-toast-error"
                else do
                    setErrorMessage errorMessage
                    redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)

        let rosterGroupId = coerce rosterWeek.rosterGroupId
        activeDefinitions <- fetchRosterWeekOrderedSlotNames rosterWeek
        preview <- previewRemoveRosterRowPacking rosterDay activeDefinitions
        if preview.removeRosterRowOverflowCount > 0 && not confirmDeletePopulatedRow
            then respondWithRemoveRosterRowConfirmation rosterDay preview
            else do
                mutationResult <- removeRosterDayRowMutation rosterGroupId rosterWeek rosterDay activeDefinitions

                if isHtmxRequest
                    then
                        respondWithRosterResourceInvalidation
                            rosterGroupId
                            rosterWeek.weekOffset
                            mutationResult.liveMutationTouchedResources
                            rosterGridInnerAndStaffPanelFragments
                            clearDialogOverlayOob
                    else do
                        setSuccessMessage "Roster row removed."
                        redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)

    action currentAction@UpdateRosterLayoutPreferenceAction { weekOffset } = runBepis currentAction BepisPreferenceAction do
        rosterGroup <- resolveRequestedRosterGroup
        let requestedLayoutMode = paramOrDefault @Text "day_rows" "rosterLayoutMode"
        case parseRosterLayoutMode requestedLayoutMode of
            Nothing -> do
                let errorMessage = "Choose a valid roster layout."
                if isHtmxRequest
                    then respondWithRosterToast errorMessage "app-toast-error"
                    else do
                        setErrorMessage errorMessage
                        redirectToPath (rosterWeekUrl weekOffset rosterGroup.id)
            Just layoutMode -> do
                _ <- upsertCurrentUserRosterLayoutMode layoutMode
                if isHtmxRequest
                    then respondWithRosterFragmentsUpdate rosterGroup.id weekOffset rosterGridStructuralFragments (successToast "Roster layout preference saved.")
                    else do
                        setSuccessMessage "Roster layout preference saved."
                        redirectToPath (rosterWeekUrl weekOffset rosterGroup.id)

    action currentAction@MoveRosterShiftToSlotAction { weekOffset } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        rosterGroup <- resolveRequestedRosterGroup
        if paramOrDefault @Text "" "targetDropzoneKey" == "delete"
            then do
                result <- validateRosterShiftDeleteDropIntent rosterGroup.id weekOffset
                case result of
                    Left message -> respondWithMoveRosterShiftFailure rosterGroup.id weekOffset message
                    Right rosterSlot -> respondWithDeleteRosterSlotDropConfirmation rosterSlot
            else do
                result <- validateMoveRosterShiftIntent rosterGroup.id weekOffset
                case result of
                    Left message -> respondWithMoveRosterShiftFailure rosterGroup.id weekOffset message
                    Right MoveRosterShiftIntent { moveIsNoOp = True } -> respondWithSilentRosterNoOp rosterGroup.id weekOffset
                    Right MoveRosterShiftIntent { sourceSlot, sourceRosterDay, targetRosterDay, targetSlotDefinition, targetRowIndex } -> do
                        let updatedSlot = sourceSlot
                                |> set #rosterDayId (unpackId targetRosterDay.id)
                                |> set #rosterWeekSlotDefinitionId (unpackId targetSlotDefinition.id)
                                |> set #slotSortOrder targetSlotDefinition.sortOrder
                                |> set #rowIndex targetRowIndex
                        rosterWeek <- fetch (Id targetRosterDay.rosterWeekId :: Id RosterWeek)
                        mutationResult <- moveRosterSlotMutation rosterGroup.id rosterWeek sourceRosterDay targetRosterDay sourceSlot updatedSlot
                        let shouldWarnSourceTimesheetUnchanged = mutationResult.liveMutationValue.rosterSlotMutationShouldWarnSourceTimesheetUnchanged
                        let impactedRows = nub [(sourceSlot.rosterDayId, sourceSlot.rowIndex), (unpackId targetRosterDay.id, targetRowIndex)]
                        respondToRosterSlotMove rosterGroup.id rosterWeek mutationResult impactedRows shouldWarnSourceTimesheetUnchanged

    action currentAction@MoveRosterTimelineShiftAction { weekOffset } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        rosterGroup <- resolveRequestedRosterGroup
        result <- validateMoveRosterTimelineShiftIntent rosterGroup.id weekOffset
        case result of
            Left message -> respondWithMoveRosterShiftFailure rosterGroup.id weekOffset message
            Right MoveRosterTimelineShiftIntent { timelineMoveIsNoOp = True } -> respondWithSilentRosterNoOp rosterGroup.id weekOffset
            Right MoveRosterTimelineShiftIntent { timelineSourceSlot, timelineSourceRosterDay, timelineTargetRosterDay, timelineTargetSlotDefinition, timelineTargetRowIndex, timelineTargetStartTime, timelineTargetEndTime } -> do
                let updatedSlot = timelineSourceSlot
                        |> set #rosterDayId (unpackId timelineTargetRosterDay.id)
                        |> set #rosterWeekSlotDefinitionId (unpackId timelineTargetSlotDefinition.id)
                        |> set #slotSortOrder timelineTargetSlotDefinition.sortOrder
                        |> set #rowIndex timelineTargetRowIndex
                        |> set #startTime (Just timelineTargetStartTime)
                        |> set #endTime (Just timelineTargetEndTime)
                        |> applyRosterSlotDuration
                rosterWeek <- fetch (Id timelineTargetRosterDay.rosterWeekId :: Id RosterWeek)
                mutationResult <- moveRosterSlotMutation rosterGroup.id rosterWeek timelineSourceRosterDay timelineTargetRosterDay timelineSourceSlot updatedSlot
                let shouldWarnSourceTimesheetUnchanged = mutationResult.liveMutationValue.rosterSlotMutationShouldWarnSourceTimesheetUnchanged
                respondToRosterTimelineSlotMove rosterGroup.id rosterWeek mutationResult shouldWarnSourceTimesheetUnchanged

    action currentAction@DuplicateRosterShiftToDayAction { weekOffset } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        rosterGroup <- resolveRequestedRosterGroup
        if paramOrDefault @Text "" "targetDropzoneKey" == "delete"
            then do
                result <- validateRosterShiftDeleteDropIntent rosterGroup.id weekOffset
                case result of
                    Left message -> respondWithMoveRosterShiftFailure rosterGroup.id weekOffset message
                    Right rosterSlot -> respondWithDeleteRosterSlotDropConfirmation rosterSlot
            else do
                result <- validateDuplicateRosterShiftIntent rosterGroup.id weekOffset
                case result of
                    Left message -> respondWithMoveRosterShiftFailure rosterGroup.id weekOffset message
                    Right MoveRosterShiftIntent { sourceSlot, targetRosterDay, targetSlotDefinition, targetRowIndex } -> do
                        rosterWeek <- fetch (Id targetRosterDay.rosterWeekId :: Id RosterWeek)
                        let copiedSlot = newRecord @RosterSlot
                                |> set #rosterDayId (unpackId targetRosterDay.id)
                                |> set #staffId sourceSlot.staffId
                                |> set #rosterWeekSlotDefinitionId (unpackId targetSlotDefinition.id)
                                |> set #slotSortOrder targetSlotDefinition.sortOrder
                                |> set #rowIndex targetRowIndex
                                |> set #startTime sourceSlot.startTime
                                |> set #endTime sourceSlot.endTime
                                |> set #shiftTypeId sourceSlot.shiftTypeId
                                |> set #durationMinutes sourceSlot.durationMinutes
                        mutationResult <- saveRosterSlotMutation rosterGroup.id rosterWeek targetRosterDay Nothing copiedSlot
                        respondToRosterSlotMutation rosterGroup.id rosterWeek targetRosterDay targetRowIndex mutationResult "Roster shift duplicated."

    action currentAction@DropRosterStaffAction { weekOffset } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        rosterGroup <- resolveRequestedRosterGroup
        result <- validateRosterStaffDropIntent rosterGroup.id weekOffset
        case result of
            Left message -> respondWithMoveRosterShiftFailure rosterGroup.id weekOffset message
            Right RosterStaffExistingShiftDropIntent { staffDropStaff, staffDropSlot, staffDropRosterDay, staffDropRosterWeek } -> do
                let updatedSlot = staffDropSlot |> set #staffId (Just (coerce staffDropStaff.id))
                mutationResult <- updateRosterSlotMutation rosterGroup.id staffDropRosterWeek staffDropRosterDay staffDropSlot updatedSlot
                let warningToast = mutationResult.liveMutationValue.rosterSlotMutationShouldWarnSourceTimesheetUnchanged
                respondToRosterSlotMutation rosterGroup.id staffDropRosterWeek staffDropRosterDay updatedSlot.rowIndex mutationResult $
                    if warningToast then "Staff assigned. A pending timesheet already exists for this roster slot, so the timesheet was not changed." else "Staff assigned."
            Right RosterStaffCreateShiftDropIntent { staffDropStaff, staffDropRosterDay, staffDropRosterWeek, staffDropSlotDefinition, staffDropRowIndex } ->
                respondWithRosterShiftCreateDialogOob staffDropRosterDay staffDropRosterWeek staffDropSlotDefinition staffDropRowIndex emptyRosterShiftDialogValues { rosterShiftStaffId = Just (coerce staffDropStaff.id) }

    action currentAction@UpdateRosterWarningPreferenceAction { weekOffset } =
        runBepis currentAction BepisMutationAction do
            ensureManagerRole
            rosterGroup <- resolveRequestedRosterGroup
            let showRosterWarnings = paramOrDefault @Text "false" "showRosterWarnings" == "true"
            _ <- upsertCurrentUserShowRosterWarnings showRosterWarnings
            if isHtmxRequest
                then respondWithRosterFragmentsUpdate rosterGroup.id weekOffset [RosterProjectionGridToolbar, RosterProjectionGridFrame] (successToast "Roster warning preference saved.")
                else do
                    setSuccessMessage "Roster warning preference saved."
                    redirectToPath (rosterWeekUrl weekOffset rosterGroup.id)

    action currentAction@UpdateRosterWageEstimatePreferenceAction { weekOffset } = runBepis currentAction BepisPreferenceAction do
        accessDeniedUnless (hasRole VenueAdminRole)
        rosterGroup <- resolveRequestedRosterGroup
        let showWageEstimates = paramOrDefault @Text "false" "showWageEstimates" == "true"
        _ <- upsertCurrentUserShowWageEstimates showWageEstimates
        if isHtmxRequest
            then respondWithRosterFragmentsUpdate rosterGroup.id weekOffset rosterGridStructuralFragments (successToast "Roster wage estimate preference saved.")
            else do
                setSuccessMessage "Roster wage estimate preference saved."
                redirectToPath (rosterWeekUrl weekOffset rosterGroup.id)

    action currentAction@NewRosterSlotDialogAction { rosterDayId, rosterWeekSlotDefinitionId, rowIndex } = runBepis currentAction BepisDialogAction do
        ensureManagerRole
        ensureVenueWritable
        (rosterDay, rosterWeek, slotDefinition) <- fetchRosterSlotCreateContext rosterDayId rosterWeekSlotDefinitionId rowIndex
        shiftTypes <- fetchCurrentVenueRosterShiftTypesForDialog
        if null shiftTypes
            then respondWithRosterToast "Create at least one shift type in Admin > Shift Types before adding roster shifts." "app-toast-error"
            else do
                venueConfig <- fetchVenueConfig
                renderRosterShiftDialogForCreate rosterDay rosterWeek slotDefinition rowIndex (defaultRosterShiftDialogValuesForVenue venueConfig)

    action currentAction@EditRosterSlotDialogAction { rosterSlotId } = runBepis currentAction BepisDialogAction do
        ensureManagerRole
        ensureVenueWritable
        (rosterSlot, rosterDay, rosterWeek) <- fetchRosterSlotEditContext rosterSlotId
        renderRosterShiftDialogForEdit rosterSlot rosterDay rosterWeek (rosterShiftDialogValuesFromSlot rosterSlot)

    action currentAction@CreateRosterSlotAction { rosterDayId, rosterWeekSlotDefinitionId, rowIndex } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        (rosterDay, rosterWeek, slotDefinition) <- fetchRosterSlotCreateContext rosterDayId rosterWeekSlotDefinitionId rowIndex
        let rosterGroupId = coerce rosterWeek.rosterGroupId
        existingSlot <- query @RosterSlot
            |> filterWhere (#rosterDayId, unpackId rosterDay.id)
            |> filterWhere (#rosterWeekSlotDefinitionId, unpackId slotDefinition.id)
            |> filterWhere (#rowIndex, rowIndex)
            |> filterWhere (#deletedAt, Nothing)
            |> fetchOneOrNothing
        validation <- validateRosterShiftDialogSubmission rosterGroupId rosterWeek Nothing
        case validation of
            Left values -> renderRosterShiftDialogForCreate rosterDay rosterWeek slotDefinition rowIndex values
            Right valid -> do
                let newSlot =
                        fromMaybe
                            ( newRecord @RosterSlot
                            |> set #rosterDayId (unpackId rosterDay.id)
                            |> set #rosterWeekSlotDefinitionId (unpackId slotDefinition.id)
                            |> set #slotSortOrder slotDefinition.sortOrder
                            |> set #rowIndex rowIndex
                            )
                            existingSlot
                            |> applyValidatedRosterShift valid
                mutationResult <- saveRosterSlotMutation rosterGroupId rosterWeek rosterDay existingSlot newSlot
                respondToRosterSlotMutation rosterGroupId rosterWeek rosterDay rowIndex mutationResult "Roster shift saved."

    action currentAction@UpdateRosterSlotAction { rosterSlotId } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        (rosterSlot, rosterDay, rosterWeek) <- fetchRosterSlotEditContext rosterSlotId
        let rosterGroupId = coerce rosterWeek.rosterGroupId
        validation <- validateRosterShiftDialogSubmission rosterGroupId rosterWeek (Just rosterSlot)
        case validation of
            Left values -> renderRosterShiftDialogForEdit rosterSlot rosterDay rosterWeek values
            Right valid -> do
                let updatedSlot = applyValidatedRosterShift valid rosterSlot
                mutationResult <- updateRosterSlotMutation rosterGroupId rosterWeek rosterDay rosterSlot updatedSlot
                let RosterSlotMutationResult { rosterSlotMutationPreviousStaffId = previousStaffId, rosterSlotMutationShouldWarnSourceTimesheetUnchanged = shouldWarnSourceTimesheetUnchanged } = mutationResult.liveMutationValue
                relatedSlots <- fetchRelatedSlotsForStaffIdsInRosterWeek rosterWeek (catMaybes [previousStaffId, Just valid.validRosterShiftStaffId])
                let impactedRowKeys = impactedRowKeysForSlotUpdate previousStaffId updatedSlot relatedSlots
                respondToRosterSlotUpdate rosterGroupId rosterWeek mutationResult impactedRowKeys shouldWarnSourceTimesheetUnchanged

    action currentAction@DeleteRosterSlotAction { rosterSlotId } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        (rosterSlot, rosterDay, rosterWeek) <- fetchRosterSlotEditContext rosterSlotId
        let rosterGroupId = coerce rosterWeek.rosterGroupId
        mutationResult <- deleteRosterSlotMutation rosterGroupId rosterWeek rosterDay rosterSlot
        respondToRosterSlotUpdate rosterGroupId rosterWeek mutationResult [(rosterSlot.rosterDayId, rosterSlot.rowIndex)] False

data ValidatedRosterShift = ValidatedRosterShift
    { validRosterShiftStaffId   :: !UUID.UUID
    , validRosterShiftStartTime :: !TimeOfDay
    , validRosterShiftEndTime   :: !(Maybe TimeOfDay)
    , validRosterShiftTypeId    :: !UUID.UUID
    }

data MoveRosterShiftIntent = MoveRosterShiftIntent
    { sourceSlot           :: !RosterSlot
    , sourceRosterDay      :: !RosterDay
    , targetRosterDay      :: !RosterDay
    , targetSlotDefinition :: !RosterWeekSlotDefinition
    , targetRowIndex       :: !Int
    , moveIsNoOp           :: !Bool
    }

data RosterShiftDropTarget
    = PreciseRosterShiftDropTarget !(Id RosterDay) !(Id RosterWeekSlotDefinition) !Int
    | DayRosterShiftDropTarget !(Id RosterDay)

data TimelineShiftDropTarget = TimelineShiftDropTarget
    { timelineTargetRosterDayId       :: !(Id RosterDay)
    , timelineTargetSlotDefinitionId  :: !(Id RosterWeekSlotDefinition)
    , timelineTargetOperationalMinute :: !Int
    }

data MoveRosterTimelineShiftIntent = MoveRosterTimelineShiftIntent
    { timelineSourceSlot           :: !RosterSlot
    , timelineSourceRosterDay      :: !RosterDay
    , timelineTargetRosterDay      :: !RosterDay
    , timelineTargetSlotDefinition :: !RosterWeekSlotDefinition
    , timelineTargetRowIndex       :: !Int
    , timelineTargetStartTime      :: !TimeOfDay
    , timelineTargetEndTime        :: !TimeOfDay
    , timelineMoveIsNoOp           :: !Bool
    }

data RosterStaffDropIntent
    = RosterStaffExistingShiftDropIntent
        { staffDropStaff      :: !Staff
        , staffDropSlot       :: !RosterSlot
        , staffDropRosterDay  :: !RosterDay
        , staffDropRosterWeek :: !RosterWeek
        }
    | RosterStaffCreateShiftDropIntent
        { staffDropStaff          :: !Staff
        , staffDropRosterDay      :: !RosterDay
        , staffDropRosterWeek     :: !RosterWeek
        , staffDropSlotDefinition :: !RosterWeekSlotDefinition
        , staffDropRowIndex       :: !Int
        }

validateMoveRosterShiftIntent :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (Either Text MoveRosterShiftIntent)
validateMoveRosterShiftIntent rosterGroupId weekOffset =
    validateRosterShiftDropIntent rosterGroupId weekOffset True

validateDuplicateRosterShiftIntent :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (Either Text MoveRosterShiftIntent)
validateDuplicateRosterShiftIntent rosterGroupId weekOffset =
    validateRosterShiftDropIntent rosterGroupId weekOffset False

validateMoveRosterTimelineShiftIntent :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (Either Text MoveRosterTimelineShiftIntent)
validateMoveRosterTimelineShiftIntent rosterGroupId weekOffset = do
    let sourceToken = paramOrDefault @Text "" "sourceItemKey"
    let targetToken = paramOrDefault @Text "" "targetDropzoneKey"
    case (parseExistingSlotToken sourceToken, parseTimelineShiftDropTargetToken targetToken) of
        (Just sourceSlotId, Just target) -> do
            maybeResult <- validateRosterTimelineShiftDropTarget rosterGroupId weekOffset sourceSlotId target
            pure (maybe (Left "Drag the shift onto an open timeline time target.") Right maybeResult)
        _ -> pure (Left "Drag the shift onto an open timeline time target.")

validateRosterShiftDropIntent :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Bool -> IO (Either Text MoveRosterShiftIntent)
validateRosterShiftDropIntent rosterGroupId weekOffset allowSemanticDayNoOp = do
    let sourceToken = paramOrDefault @Text "" "sourceItemKey"
    let targetToken = paramOrDefault @Text "" "targetDropzoneKey"
    case (parseExistingSlotToken sourceToken, parseRosterShiftDropTargetToken targetToken) of
        (Just sourceSlotId, Just target) -> do
            maybeResult <- validateRosterShiftDropTarget rosterGroupId weekOffset allowSemanticDayNoOp sourceSlotId target
            pure (maybe (Left "Choose an open roster day in this week.") Right maybeResult)
        _ -> pure (Left "Drag the shift onto an open roster day.")

validateRosterShiftDeleteDropIntent :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (Either Text RosterSlot)
validateRosterShiftDeleteDropIntent rosterGroupId weekOffset = do
    let sourceToken = paramOrDefault @Text "" "sourceItemKey"
    let targetToken = paramOrDefault @Text "" "targetDropzoneKey"
    case (parseExistingSlotToken sourceToken, targetToken) of
        (Just rosterSlotId, "delete") -> do
            maybeSlot <- fetchOneOrNothing (query @RosterSlot |> filterWhere (#id, rosterSlotId) |> filterWhere (#deletedAt, Nothing))
            case maybeSlot of
                Nothing -> pure (Left "Drag an editable shift to the delete area.")
                Just rosterSlot -> do
                    rosterDay <- fetch (Id rosterSlot.rosterDayId :: Id RosterDay)
                    rosterWeek <- fetch (Id rosterDay.rosterWeekId :: Id RosterWeek)
                    let matchesScope = rosterWeek.rosterGroupId == unpackId rosterGroupId && rosterWeek.weekOffset == weekOffset
                    if matchesScope && not rosterWeek.isLive && not rosterDay.isClosed
                        then pure (Right rosterSlot)
                        else pure (Left "Drag an editable shift from this roster week to the delete area.")
        _ -> pure (Left "Drag a shift to the delete area.")

validateRosterStaffDropIntent :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (Either Text RosterStaffDropIntent)
validateRosterStaffDropIntent rosterGroupId weekOffset = do
    let sourceToken = paramOrDefault @Text "" "sourceItemKey"
    let targetToken = paramOrDefault @Text "" "targetDropzoneKey"
    case (parseStaffToken sourceToken, parseExistingSlotToken targetToken, parseRosterShiftDropTargetToken targetToken) of
        (Just staffId, Just rosterSlotId, _) -> do
            maybeResult <- validateRosterStaffExistingShiftDropTarget rosterGroupId weekOffset staffId rosterSlotId
            pure (maybe (Left "Drop staff onto an editable shift in this roster week.") Right maybeResult)
        (Just staffId, _, Just createTarget) -> do
            maybeResult <- validateRosterStaffCreateShiftDropTarget rosterGroupId weekOffset staffId createTarget
            pure (maybe (Left "Drop staff onto an open add-shift target in this roster week.") Right maybeResult)
        _ -> pure (Left "Drag a staff member onto a shift or add-shift target.")

validateRosterStaffExistingShiftDropTarget :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> Id Staff -> Id RosterSlot -> IO (Maybe RosterStaffDropIntent)
validateRosterStaffExistingShiftDropTarget rosterGroupId weekOffset staffId rosterSlotId = do
    maybeStaff <- fetchActiveStaffForCurrentVenue staffId
    staffEligible <- staffIsEligibleForRosterGroup staffId rosterGroupId
    maybeSlot <- fetchOneOrNothing (query @RosterSlot |> filterWhere (#id, rosterSlotId) |> filterWhere (#deletedAt, Nothing))
    case (maybeStaff, maybeSlot) of
        (Just staff, Just rosterSlot) -> do
            rosterDay <- fetch (Id rosterSlot.rosterDayId :: Id RosterDay)
            rosterWeek <- fetch (Id rosterDay.rosterWeekId :: Id RosterWeek)
            let matchesScope = rosterWeek.rosterGroupId == unpackId rosterGroupId && rosterWeek.weekOffset == weekOffset
            pure do
                guard matchesScope
                guard (not rosterWeek.isLive)
                guard (not rosterDay.isClosed)
                guard staffEligible
                pure RosterStaffExistingShiftDropIntent { staffDropStaff = staff, staffDropSlot = rosterSlot, staffDropRosterDay = rosterDay, staffDropRosterWeek = rosterWeek }
        _ -> pure Nothing

validateRosterStaffCreateShiftDropTarget :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> Id Staff -> RosterShiftDropTarget -> IO (Maybe RosterStaffDropIntent)
validateRosterStaffCreateShiftDropTarget rosterGroupId weekOffset staffId dropTarget = do
    maybeStaff <- fetchActiveStaffForCurrentVenue staffId
    staffEligible <- staffIsEligibleForRosterGroup staffId rosterGroupId
    maybeTargetRosterDay <- fetchOneOrNothing (query @RosterDay |> filterWhere (#id, dropTargetRosterDayId dropTarget))
    case (maybeStaff, maybeTargetRosterDay) of
        (Just staff, Just targetRosterDay) -> do
            rosterWeek <- fetch (Id targetRosterDay.rosterWeekId :: Id RosterWeek)
            maybeResolvedTarget <- resolveRosterShiftDropPlacement rosterWeek targetRosterDay dropTarget
            let matchesScope = rosterWeek.rosterGroupId == unpackId rosterGroupId && rosterWeek.weekOffset == weekOffset
            pure do
                guard matchesScope
                guard (not rosterWeek.isLive)
                guard (not targetRosterDay.isClosed)
                guard staffEligible
                (slotDefinition, rowIndex) <- maybeResolvedTarget
                pure RosterStaffCreateShiftDropIntent { staffDropStaff = staff, staffDropRosterDay = targetRosterDay, staffDropRosterWeek = rosterWeek, staffDropSlotDefinition = slotDefinition, staffDropRowIndex = rowIndex }
        _ -> pure Nothing

fetchActiveStaffForCurrentVenue :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id Staff -> IO (Maybe Staff)
fetchActiveStaffForCurrentVenue staffId =
    fetchOneOrNothing $ query @Staff
        |> filterWhere (#id, staffId)
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#isActive, True)
        |> filterWhere (#archivedAt, Nothing)

validateRosterShiftDropTarget :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> Bool -> Id RosterSlot -> RosterShiftDropTarget -> IO (Maybe MoveRosterShiftIntent)
validateRosterShiftDropTarget rosterGroupId weekOffset allowSemanticDayNoOp sourceSlotId dropTarget = do
    maybeSourceSlot <- fetchOneOrNothing (query @RosterSlot |> filterWhere (#id, sourceSlotId))
    case maybeSourceSlot of
        Nothing -> pure Nothing
        Just sourceSlot -> do
            sourceRosterDay <- fetch (Id sourceSlot.rosterDayId :: Id RosterDay)
            sourceRosterWeek <- fetch (Id sourceRosterDay.rosterWeekId :: Id RosterWeek)
            let targetRosterDayId = dropTargetRosterDayId dropTarget
            maybeTargetRosterDay <- fetchOneOrNothing (query @RosterDay |> filterWhere (#id, targetRosterDayId))
            case maybeTargetRosterDay of
                Nothing -> pure Nothing
                Just targetRosterDay -> do
                    targetRosterWeek <- fetch (Id targetRosterDay.rosterWeekId :: Id RosterWeek)
                    maybeResolvedTarget <- resolveRosterShiftDropPlacement targetRosterWeek targetRosterDay dropTarget
                    let sourceMatchesScope = sourceRosterWeek.rosterGroupId == unpackId rosterGroupId && sourceRosterWeek.weekOffset == weekOffset
                    let targetMatchesScope = targetRosterWeek.rosterGroupId == unpackId rosterGroupId && targetRosterWeek.weekOffset == weekOffset
                    let sourceIsStaffed = isJust sourceSlot.staffId
                    let targetIsOpen = not targetRosterDay.isClosed
                    let semanticSameDayNoOp = allowSemanticDayNoOp && isDayDropTarget dropTarget && sourceSlot.rosterDayId == unpackId targetRosterDay.id
                    pure do
                        guard sourceMatchesScope
                        guard targetMatchesScope
                        guard sourceIsStaffed
                        guard targetIsOpen
                        case (semanticSameDayNoOp, maybeResolvedTarget) of
                            (True, Just (targetSlotDefinition, _)) ->
                                pure MoveRosterShiftIntent { sourceSlot, sourceRosterDay, targetRosterDay, targetSlotDefinition, targetRowIndex = sourceSlot.rowIndex, moveIsNoOp = True }
                            (False, Just (targetSlotDefinition, targetRowIndex)) ->
                                pure MoveRosterShiftIntent { sourceSlot, sourceRosterDay, targetRosterDay, targetSlotDefinition, targetRowIndex, moveIsNoOp = False }
                            _ -> Nothing

validateRosterTimelineShiftDropTarget :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> Id RosterSlot -> TimelineShiftDropTarget -> IO (Maybe MoveRosterTimelineShiftIntent)
validateRosterTimelineShiftDropTarget rosterGroupId weekOffset sourceSlotId target = do
    maybeSourceSlot <- fetchOneOrNothing (query @RosterSlot |> filterWhere (#id, sourceSlotId) |> filterWhere (#deletedAt, Nothing))
    case maybeSourceSlot of
        Nothing -> pure Nothing
        Just sourceSlot -> do
            sourceRosterDay <- fetch (Id sourceSlot.rosterDayId :: Id RosterDay)
            sourceRosterWeek <- fetch (Id sourceRosterDay.rosterWeekId :: Id RosterWeek)
            maybeTargetRosterDay <- fetchOneOrNothing (query @RosterDay |> filterWhere (#id, target.timelineTargetRosterDayId))
            maybeTargetSlotDefinition <- fetchOneOrNothing (query @RosterWeekSlotDefinition |> filterWhere (#id, target.timelineTargetSlotDefinitionId))
            case (maybeTargetRosterDay, maybeTargetSlotDefinition, sourceSlot.startTime, sourceSlot.endTime) of
                (Just targetRosterDay, Just targetSlotDefinition, Just sourceStart, Just sourceEnd) -> do
                    targetRosterWeek <- fetch (Id targetRosterDay.rosterWeekId :: Id RosterWeek)
                    let duration = shiftDurationMinutes sourceStart sourceEnd
                        targetStartTime = minuteOfDayToTimeOfDay target.timelineTargetOperationalMinute
                        targetEndTime = minuteOfDayToTimeOfDay (target.timelineTargetOperationalMinute + duration)
                        sourceMatchesScope = sourceRosterWeek.rosterGroupId == unpackId rosterGroupId && sourceRosterWeek.weekOffset == weekOffset
                        targetMatchesScope = targetRosterWeek.rosterGroupId == unpackId rosterGroupId && targetRosterWeek.weekOffset == weekOffset
                        targetDefinitionMatchesWeek = targetSlotDefinition.rosterWeekId == unpackId targetRosterWeek.id
                        validTargetTime = isQuarterHourMinutes target.timelineTargetOperationalMinute && isJust (validRosterShiftDurationMinutes targetStartTime targetEndTime)
                    maybeRowIndex <- resolveTimelineTargetRowIndex sourceSlot targetRosterDay targetSlotDefinition
                    pure do
                        targetRowIndex <- maybeRowIndex
                        guard sourceMatchesScope
                        guard targetMatchesScope
                        guard (not sourceRosterWeek.isLive)
                        guard (not targetRosterWeek.isLive)
                        guard (not targetRosterDay.isClosed)
                        guard (isJust sourceSlot.staffId)
                        guard targetDefinitionMatchesWeek
                        guard (isNothing targetSlotDefinition.deletedAt)
                        guard (duration > 0)
                        guard validTargetTime
                        let isNoOp = sourceSlot.rosterDayId == unpackId targetRosterDay.id
                                && sourceSlot.rosterWeekSlotDefinitionId == unpackId targetSlotDefinition.id
                                && sourceSlot.startTime == Just targetStartTime
                                && sourceSlot.endTime == Just targetEndTime
                        pure MoveRosterTimelineShiftIntent
                            { timelineSourceSlot = sourceSlot
                            , timelineSourceRosterDay = sourceRosterDay
                            , timelineTargetRosterDay = targetRosterDay
                            , timelineTargetSlotDefinition = targetSlotDefinition
                            , timelineTargetRowIndex = targetRowIndex
                            , timelineTargetStartTime = targetStartTime
                            , timelineTargetEndTime = targetEndTime
                            , timelineMoveIsNoOp = isNoOp
                            }
                _ -> pure Nothing

resolveTimelineTargetRowIndex :: (?modelContext :: ModelContext) => RosterSlot -> RosterDay -> RosterWeekSlotDefinition -> IO (Maybe Int)
resolveTimelineTargetRowIndex sourceSlot targetRosterDay targetSlotDefinition = do
    daySlots <- query @RosterSlot
        |> filterWhere (#rosterDayId, unpackId targetRosterDay.id)
        |> filterWhere (#rosterWeekSlotDefinitionId, unpackId targetSlotDefinition.id)
        |> filterWhere (#deletedAt, Nothing)
        |> fetch
    let occupiedRows = Set.fromList [ slot.rowIndex | slot <- daySlots, slot.id /= sourceSlot.id ]
        preferredRow = sourceSlot.rowIndex
        candidateRows = preferredRow : filter (/= preferredRow) [0 .. max preferredRow targetRosterDay.rowCount]
        fallbackRow = max preferredRow targetRosterDay.rowCount
    pure (listToMaybe (filter (`Set.notMember` occupiedRows) candidateRows) <|> Just fallbackRow)

parseStaffToken :: Text -> Maybe (Id Staff)
parseStaffToken token =
    case Text.splitOn ":" token of
        ["staff", rawStaffId] -> Id <$> parseUUIDText rawStaffId
        _                     -> Nothing

parseExistingSlotToken :: Text -> Maybe (Id RosterSlot)
parseExistingSlotToken token =
    case Text.splitOn ":" token of
        ["existing", rawSlotId] -> Id <$> parseUUIDText rawSlotId
        _                       -> Nothing

parseRosterShiftDropTargetToken :: Text -> Maybe RosterShiftDropTarget
parseRosterShiftDropTargetToken token =
    case Text.splitOn ":" token of
        ["day", rawRosterDayId] ->
            DayRosterShiftDropTarget . Id <$> parseUUIDText rawRosterDayId
        ["new", rawRosterDayId, rawSlotDefinitionId, rawRowIndex] -> do
            rosterDayId <- Id <$> parseUUIDText rawRosterDayId
            slotDefinitionId <- Id <$> parseUUIDText rawSlotDefinitionId
            rowIndex <- TextRead.readMaybe (cs rawRowIndex)
            pure (PreciseRosterShiftDropTarget rosterDayId slotDefinitionId rowIndex)
        _ -> Nothing

parseTimelineShiftDropTargetToken :: Text -> Maybe TimelineShiftDropTarget
parseTimelineShiftDropTargetToken token =
    case Text.splitOn ":" token of
        ["time", rawRosterDayId, rawSlotDefinitionId, rawMinute] -> do
            rosterDayId <- Id <$> parseUUIDText rawRosterDayId
            slotDefinitionId <- Id <$> parseUUIDText rawSlotDefinitionId
            minute <- TextRead.readMaybe (cs rawMinute)
            pure TimelineShiftDropTarget
                { timelineTargetRosterDayId = rosterDayId
                , timelineTargetSlotDefinitionId = slotDefinitionId
                , timelineTargetOperationalMinute = minute
                }
        _ -> Nothing

dropTargetRosterDayId :: RosterShiftDropTarget -> Id RosterDay
dropTargetRosterDayId = \case
    PreciseRosterShiftDropTarget rosterDayId _ _ -> rosterDayId
    DayRosterShiftDropTarget rosterDayId -> rosterDayId

isDayDropTarget :: RosterShiftDropTarget -> Bool
isDayDropTarget = \case
    DayRosterShiftDropTarget {} -> True
    _ -> False

resolveRosterShiftDropPlacement :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterWeek -> RosterDay -> RosterShiftDropTarget -> IO (Maybe (RosterWeekSlotDefinition, Int))
resolveRosterShiftDropPlacement targetRosterWeek targetRosterDay = \case
    PreciseRosterShiftDropTarget _ targetSlotDefinitionId targetRowIndex -> do
        maybeTargetSlotDefinition <- fetchOneOrNothing (query @RosterWeekSlotDefinition |> filterWhere (#id, targetSlotDefinitionId))
        targetExists <- rosterSlotCellExists targetRosterDay.id targetSlotDefinitionId targetRowIndex
        pure do
            targetSlotDefinition <- maybeTargetSlotDefinition
            guard (targetRowIndex >= 0)
            guard (targetSlotDefinition.rosterWeekId == unpackId targetRosterWeek.id)
            guard (isNothing targetSlotDefinition.deletedAt)
            guard (not targetExists)
            pure (targetSlotDefinition, targetRowIndex)
    DayRosterShiftDropTarget _ -> do
        targetSlotDefinitions <- fetchActiveRosterWeekSlotDefinitions targetRosterWeek
        daySlots <- query @RosterSlot
            |> filterWhere (#rosterDayId, unpackId targetRosterDay.id)
            |> filterWhere (#deletedAt, Nothing)
            |> fetch
        pure (firstAvailableRosterDayPlacement targetRosterDay targetSlotDefinitions daySlots)

firstAvailableRosterDayPlacement :: RosterDay -> [RosterWeekSlotDefinition] -> [RosterSlot] -> Maybe (RosterWeekSlotDefinition, Int)
firstAvailableRosterDayPlacement targetRosterDay targetSlotDefinitions daySlots = do
    firstDefinition <- listToMaybe targetSlotDefinitions
    let occupiedCells = Set.fromList [(slot.rowIndex, slot.rosterWeekSlotDefinitionId) | slot <- daySlots]
    let candidateRows = [0 .. max 0 targetRosterDay.rowCount]
    let candidates = [(definition, rowIndex) | rowIndex <- candidateRows, definition <- targetSlotDefinitions, (rowIndex, unpackId definition.id) `Set.notMember` occupiedCells]
    pure (fromMaybe (firstDefinition, max 0 targetRosterDay.rowCount) (listToMaybe candidates))

rosterSlotCellExists :: (?modelContext :: ModelContext) => Id RosterDay -> Id RosterWeekSlotDefinition -> Int -> IO Bool
rosterSlotCellExists rosterDayId targetSlotDefinitionId targetRowIndex =
    query @RosterSlot
        |> filterWhere (#rosterDayId, unpackId rosterDayId)
        |> filterWhere (#rosterWeekSlotDefinitionId, unpackId targetSlotDefinitionId)
        |> filterWhere (#rowIndex, targetRowIndex)
        |> filterWhere (#deletedAt, Nothing)
        |> fetchExists

respondWithMoveRosterShiftFailure :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Text -> IO ()
respondWithMoveRosterShiftFailure rosterGroupId weekOffset message =
    if isHtmxRequest
        then do
            setHeader ("HX-Reswap", "none")
            respondHtmlProfiled (clearDialogOverlayOob <> renderToastOob ToastBottomCenter (errorToast message))
        else do
            setErrorMessage message
            redirectToPath (rosterWeekUrl weekOffset rosterGroupId)

respondWithSilentRosterNoOp :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO ()
respondWithSilentRosterNoOp rosterGroupId weekOffset =
    if isHtmxRequest
        then do
            setHeader ("HX-Reswap", "none")
            respondHtmlProfiled mempty
        else redirectToPath (rosterWeekUrl weekOffset rosterGroupId)

fetchRosterSlotCreateContext :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterDay -> Id RosterWeekSlotDefinition -> Int -> IO (RosterDay, RosterWeek, RosterWeekSlotDefinition)
fetchRosterSlotCreateContext rosterDayId rosterWeekSlotDefinitionId rowIndex = do
    rosterDay <- fetch rosterDayId
    let rosterWeekId = (coerce rosterDay.rosterWeekId :: Id RosterWeek)
    rosterWeek <- fetch rosterWeekId
    ensureRecordInCurrentVenue rosterWeek.venueId
    ensureRosterWeekIsDraftForEdit rosterWeek
    accessDeniedUnless (not rosterDay.isClosed)
    accessDeniedUnless (rowIndex >= 0)
    slotDefinition <- fetch rosterWeekSlotDefinitionId
    accessDeniedUnless (slotDefinition.rosterWeekId == unpackId rosterWeek.id)
    accessDeniedUnless (isNothing slotDefinition.deletedAt)
    pure (rosterDay, rosterWeek, slotDefinition)

fetchRosterSlotEditContext :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterSlot -> IO (RosterSlot, RosterDay, RosterWeek)
fetchRosterSlotEditContext rosterSlotId = do
    rosterSlot <- fetch rosterSlotId
    accessDeniedUnless (isNothing rosterSlot.deletedAt)
    let rosterDayId = (coerce rosterSlot.rosterDayId :: Id RosterDay)
    rosterDay <- fetch rosterDayId
    let rosterWeekId = (coerce rosterDay.rosterWeekId :: Id RosterWeek)
    rosterWeek <- fetch rosterWeekId
    ensureRecordInCurrentVenue rosterWeek.venueId
    ensureRosterWeekIsDraftForEdit rosterWeek
    accessDeniedUnless (not rosterDay.isClosed)
    pure (rosterSlot, rosterDay, rosterWeek)

renderRosterShiftDialogForCreate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterDay -> RosterWeek -> RosterWeekSlotDefinition -> Int -> RosterShiftDialogValues -> IO ()
renderRosterShiftDialogForCreate rosterDay rosterWeek slotDefinition rowIndex values = do
    dialog <- rosterShiftDialogForCreateHtml rosterDay rosterWeek slotDefinition rowIndex values
    respondHtmlProfiled dialog

respondWithRosterShiftCreateDialogOob :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterDay -> RosterWeek -> RosterWeekSlotDefinition -> Int -> RosterShiftDialogValues -> IO ()
respondWithRosterShiftCreateDialogOob rosterDay rosterWeek slotDefinition rowIndex values = do
    dialog <- rosterShiftDialogForCreateHtml rosterDay rosterWeek slotDefinition rowIndex values
    respondHtmlProfiled [hsx|
        <div id={dialogOverlayMountId} hx-swap-oob="innerHTML">
            {dialog}
        </div>
    |]

rosterShiftDialogForCreateHtml :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterDay -> RosterWeek -> RosterWeekSlotDefinition -> Int -> RosterShiftDialogValues -> IO Blaze.Html
rosterShiftDialogForCreateHtml rosterDay rosterWeek slotDefinition rowIndex values = do
    staffMembers <- fetchEligibleRosterGroupStaff (coerce rosterWeek.rosterGroupId)
    shiftTypes <- fetchCurrentVenueRosterShiftTypesForDialog
    venueConfig <- fetchVenueConfig
    let targetSlot =
            newRecord @RosterSlot
                |> set #rosterDayId (unpackId rosterDay.id)
                |> set #rosterWeekSlotDefinitionId (unpackId slotDefinition.id)
                |> set #slotSortOrder slotDefinition.sortOrder
                |> set #rowIndex rowIndex
    staffOptionStates <- buildRosterShiftDialogStaffOptionStates (coerce rosterWeek.rosterGroupId) rosterWeek targetSlot staffMembers
    pure $ renderRosterShiftDialog RosterShiftDialogData
        { rosterShiftDialogMode = NewRosterShiftDialog rosterDay.id slotDefinition.id rowIndex
        , rosterShiftDialogTitle = "Add shift"
        , rosterShiftDialogStaff = staffMembers
        , rosterShiftDialogStaffOptionStates = staffOptionStates
        , rosterShiftDialogShiftTypes = shiftTypes
        , rosterShiftDialogTimePickerStart = venueTimePickerStartTimeText venueConfig
        , rosterShiftDialogTimePickerEnd = venueTimePickerFinalSelectableTimeText venueConfig
        , rosterShiftDialogValues = values
        }

renderRosterShiftDialogForEdit :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterSlot -> RosterDay -> RosterWeek -> RosterShiftDialogValues -> IO ()
renderRosterShiftDialogForEdit rosterSlot _rosterDay rosterWeek values = do
    staffMembers <- fetchEligibleRosterGroupStaff (coerce rosterWeek.rosterGroupId)
    shiftTypes <- fetchCurrentVenueRosterShiftTypesForDialog
    venueConfig <- fetchVenueConfig
    staffOptionStates <- buildRosterShiftDialogStaffOptionStates (coerce rosterWeek.rosterGroupId) rosterWeek rosterSlot staffMembers
    respondHtmlProfiled $ renderRosterShiftDialog RosterShiftDialogData
        { rosterShiftDialogMode = EditRosterShiftDialog rosterSlot.id
        , rosterShiftDialogTitle = "Edit shift"
        , rosterShiftDialogStaff = staffMembers
        , rosterShiftDialogStaffOptionStates = staffOptionStates
        , rosterShiftDialogShiftTypes = shiftTypes
        , rosterShiftDialogTimePickerStart = venueTimePickerStartTimeText venueConfig
        , rosterShiftDialogTimePickerEnd = venueTimePickerFinalSelectableTimeText venueConfig
        , rosterShiftDialogValues = values
        }

defaultRosterShiftDialogValuesForVenue :: VenueConfig -> RosterShiftDialogValues
defaultRosterShiftDialogValuesForVenue venueConfig =
    let (defaultStart, defaultEnd) = defaultShiftTimesForVenueConfig venueConfig
     in emptyRosterShiftDialogValues
            { rosterShiftStartTime = timeOfDayToStorageValue defaultStart
            , rosterShiftEndTime = timeOfDayToStorageValue defaultEnd
            }

buildRosterShiftDialogStaffOptionStates :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> RosterSlot -> [Staff] -> IO (Map.Map UUID.UUID RosterAssignmentOptionState)
buildRosterShiftDialogStaffOptionStates rosterGroupId rosterWeek targetSlot staffMembers = do
    venueConfig <- fetchVenueConfig
    assignmentFilters <- fetchRosterAssignmentFilters
    let weekStartDate = venueWeekStartDate venueConfig rosterWeek.weekOffset
    rosterDays <- query @RosterDay
        |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
        |> fetch
    visibleSlots <-
        if null rosterDays
            then pure []
            else query @RosterSlot
                |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) rosterDays)
                |> filterWhere (#deletedAt, Nothing)
                |> fetch
    let targetSlotId = coerce targetSlot.id
    let slotsForOptions = targetSlot : filter (\slot -> coerce slot.id /= targetSlotId) visibleSlots
    optionStates <- buildRosterStaffOptionStates rosterGroupId assignmentFilters weekStartDate rosterDays slotsForOptions staffMembers
    pure $ Map.fromList
        [ (coerce staff.id, optionState)
        | staff <- staffMembers
        , Just optionState <- [Map.lookup (targetSlotId, coerce staff.id) optionStates]
        ]

fetchCurrentVenueRosterShiftTypesForDialog :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [ShiftType]
fetchCurrentVenueRosterShiftTypesForDialog =
    query @ShiftType
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#archivedAt, Nothing)
        |> orderByAsc #sortOrder
        |> orderByAsc #createdAt
        |> fetch

validateRosterShiftDialogSubmission :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> Maybe RosterSlot -> IO (Either RosterShiftDialogValues ValidatedRosterShift)
validateRosterShiftDialogSubmission rosterGroupId rosterWeek maybeExistingSlot = do
    let staffParam = paramOrNothing @Text "staffId"
    let startParam = paramOrNothing @Text "startTime"
    let endParam = paramOrNothing @Text "endTime"
    let shiftTypeParam = paramOrNothing @Text "shiftTypeId"
    let parsedStaffId = parseOptionalStaffId staffParam
    let parsedStartTime = parseOptionalTime startParam
    let parsedEndTime = parseOptionalTime endParam
    let parsedShiftTypeId = parseOptionalShiftTypeId shiftTypeParam
    staffInVenue <- maybe (pure False) staffIdIsInCurrentVenue parsedStaffId
    staffEligible <- maybe (pure False) (\staffId -> staffIsEligibleForRosterGroup (Id staffId) rosterGroupId) parsedStaffId
    shiftTypeInVenue <- maybe (pure False) shiftTypeIdIsInCurrentVenue parsedShiftTypeId
    let baseValues = emptyRosterShiftDialogValues
            { rosterShiftStaffId = parsedStaffId
            , rosterShiftStartTime = fromMaybe "" (normalizeOptionalText startParam)
            , rosterShiftEndTime = fromMaybe "" (normalizeOptionalText endParam)
            , rosterShiftTypeId = parsedShiftTypeId
            }
    let staffError
            | isNothing (normalizeOptionalText staffParam) = Just "Choose a staff member."
            | isNothing parsedStaffId || not staffInVenue = Just "Choose a staff member for this venue."
            | not staffEligible = Just "That staff member is not applicable to this roster group."
            | otherwise = Nothing
    let startError
            | isNothing (normalizeOptionalText startParam) = Just "Choose a start time."
            | isNothing parsedStartTime = Just "Choose a valid start time."
            | otherwise = Nothing
    let endError
            | isNothing (normalizeOptionalText endParam) = Just "Choose an end time."
            | isNothing parsedEndTime = Just "Choose a valid end time."
            | otherwise = Nothing
    let shiftTypeError
            | isNothing (normalizeOptionalText shiftTypeParam) = Just "Choose a shift type."
            | isNothing parsedShiftTypeId || not shiftTypeInVenue = Just "Choose a shift type for this venue."
            | otherwise = Nothing
    let timingError =
            case (parsedStartTime, parsedEndTime) of
                (Just startTime, Just endTime)
                    | not (isValidRosterShiftTimePair startTime endTime) -> Just invalidRosterSlotTimingMessage
                _ -> Nothing
    let valuesWithErrors = baseValues
            { rosterShiftFormError = timingError
            , rosterShiftStaffError = staffError
            , rosterShiftStartError = startError
            , rosterShiftEndError = endError <|> timingError
            , rosterShiftTypeError = shiftTypeError
            }
    case (staffError, startError, endError, shiftTypeError, timingError, parsedStaffId, parsedStartTime, parsedEndTime, parsedShiftTypeId) of
        (Nothing, Nothing, Nothing, Nothing, Nothing, Just staffId, Just startTime, Just endTime, Just shiftTypeId) ->
            pure (Right ValidatedRosterShift
                { validRosterShiftStaffId = staffId
                , validRosterShiftStartTime = startTime
                , validRosterShiftEndTime = Just endTime
                , validRosterShiftTypeId = shiftTypeId
                })
        _ -> pure (Left valuesWithErrors)

staffIdIsInCurrentVenue :: (?context :: ControllerContext, ?modelContext :: ModelContext) => UUID.UUID -> IO Bool
staffIdIsInCurrentVenue staffId =
    query @Staff
        |> filterWhere (#id, Id staffId)
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#isActive, True)
        |> filterWhere (#archivedAt, Nothing)
        |> fetchExists

shiftTypeIdIsInCurrentVenue :: (?context :: ControllerContext, ?modelContext :: ModelContext) => UUID.UUID -> IO Bool
shiftTypeIdIsInCurrentVenue shiftTypeId =
    query @ShiftType
        |> filterWhere (#id, Id shiftTypeId)
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#isActive, True)
        |> filterWhere (#archivedAt, Nothing)
        |> fetchExists

applyValidatedRosterShift :: ValidatedRosterShift -> RosterSlot -> RosterSlot
applyValidatedRosterShift valid slot =
    slot
        |> set #staffId (Just valid.validRosterShiftStaffId)
        |> set #startTime (Just valid.validRosterShiftStartTime)
        |> set #endTime valid.validRosterShiftEndTime
        |> set #shiftTypeId (Just valid.validRosterShiftTypeId)
        |> applyRosterSlotDuration

respondToRosterSlotMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> RosterDay -> Int -> LiveMutationResult RosterSlotMutationResult -> Text -> IO ()
respondToRosterSlotMutation rosterGroupId rosterWeek rosterDay rowIndex mutationResult successMessage = do
    layoutMode <- fetchCurrentRosterLayoutMode
    let mountedProjections =
            rosterGridInnerAndStaffPanelFragments
                <> case rosterLayoutModeValue layoutMode of
                    "day_columns" -> []
                    _ -> actorRosterRowFragments [(unpackId rosterDay.id, rowIndex)]
    if isHtmxRequest
        then
            respondWithRosterResourceInvalidation
                rosterGroupId
                rosterWeek.weekOffset
                mutationResult.liveMutationTouchedResources
                mountedProjections
                (clearDialogOverlayOob <> renderToastOob ToastBottomCenter (successToast successMessage))
        else do
            setSuccessMessage successMessage
            redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)

respondToRosterSlotMove :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> LiveMutationResult RosterSlotMutationResult -> [(UUID.UUID, Int)] -> Bool -> IO ()
respondToRosterSlotMove rosterGroupId rosterWeek mutationResult impactedRowKeys shouldWarnSourceTimesheetUnchanged = do
    layoutMode <- fetchCurrentRosterLayoutMode
    let mountedProjections =
            rosterGridInnerAndStaffPanelFragments
                <> case rosterLayoutModeValue layoutMode of
                    "day_columns" -> []
                    _             -> actorRosterRowFragments impactedRowKeys
    respondWithRosterResourceInvalidation
        rosterGroupId
        rosterWeek.weekOffset
        mutationResult.liveMutationTouchedResources
        mountedProjections
        (clearDialogOverlayOob <> renderToastOob ToastBottomCenter (successToast "Roster shift moved.") <> sourceTimesheetWarningToast shouldWarnSourceTimesheetUnchanged)

respondToRosterTimelineSlotMove :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> LiveMutationResult RosterSlotMutationResult -> Bool -> IO ()
respondToRosterTimelineSlotMove rosterGroupId rosterWeek mutationResult shouldWarnSourceTimesheetUnchanged =
    respondWithRosterResourceInvalidation
        rosterGroupId
        rosterWeek.weekOffset
        mutationResult.liveMutationTouchedResources
        [ RosterProjectionGridToolbar
        , RosterProjectionGridFrame
        , RosterProjectionStaffPanel
        ]
        (clearDialogOverlayOob <> renderToastOob ToastBottomCenter (successToast "Roster shift moved.") <> sourceTimesheetWarningToast shouldWarnSourceTimesheetUnchanged)

respondToRosterSlotUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> LiveMutationResult RosterSlotMutationResult -> [(UUID.UUID, Int)] -> Bool -> IO ()
respondToRosterSlotUpdate rosterGroupId rosterWeek mutationResult impactedRowKeys shouldWarnSourceTimesheetUnchanged = do
    layoutMode <- fetchCurrentRosterLayoutMode
    let mountedProjections =
            rosterGridInnerAndStaffPanelFragments
                <> case rosterLayoutModeValue layoutMode of
                    "day_columns" -> []
                    _             -> actorRosterRowFragments impactedRowKeys
    respondWithRosterResourceInvalidation
        rosterGroupId
        rosterWeek.weekOffset
        mutationResult.liveMutationTouchedResources
        mountedProjections
        (clearDialogOverlayOob <> sourceTimesheetWarningToast shouldWarnSourceTimesheetUnchanged)

sourceTimesheetWarningToast :: (?context :: ControllerContext, ?request :: Request) => Bool -> Blaze.Html
sourceTimesheetWarningToast shouldWarn =
    if shouldWarn
        then renderToastOob ToastBottomCenter (errorToast "A pending timesheet already exists for this roster slot, so the timesheet was not changed. Edit the timesheet entry directly.")
        else mempty

resolveRequestedRosterGroup :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO RosterGroup
resolveRequestedRosterGroup =
    fetchCurrentVenueRosterGroupOrDefault (paramOrNothing "rosterGroupId")

resolveRosterGroupIdForFragmentRosterDay :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Int -> Id RosterDay -> IO (Id RosterGroup)
resolveRosterGroupIdForFragmentRosterDay weekOffset rosterDayId = do
    rosterDay <- fetch rosterDayId
    rosterWeek <- fetch (Id rosterDay.rosterWeekId :: Id RosterWeek)
    ensureRecordInCurrentVenue rosterWeek.venueId
    accessDeniedUnless (rosterWeek.weekOffset == weekOffset)
    pure (coerce rosterWeek.rosterGroupId)

respondWithDeleteRosterSlotDropConfirmation :: (?context :: ControllerContext, ?request :: Request) => RosterSlot -> IO ()
respondWithDeleteRosterSlotDropConfirmation rosterSlot =
    respondHtmlProfiled [hsx|
        <div id={dialogOverlayMountId} hx-swap-oob="innerHTML">
            {renderAppShellActionForm
                (appShellActionByMarker @DeleteRosterSlotOverlay)
                (rosterDeleteSlotActionRoute (pathTo (DeleteRosterSlotAction rosterSlot.id)))
                    { appShellActionRouteExtraAttrs =
                        [ ("class", "d-none")
                        , appShellDialogAutoSubmitOnceAttr
                        ]
                    }
                mempty}
        </div>
    |]

rosterDeleteSlotActionRoute :: Text -> AppShellActionRoute
rosterDeleteSlotActionRoute actionUrl =
    AppShellActionRoute
        { appShellActionRouteUrl = actionUrl
        , appShellActionRouteFields = []
        , appShellActionRouteCustomHtmx = []
        , appShellActionRouteStandardUrl = Nothing
        , appShellActionRouteExtraAttrs = []
        }

respondWithRemoveRosterRowConfirmation :: (?context :: ControllerContext, ?request :: Request) => RosterDay -> RemoveRosterRowPackingPreview -> IO ()
respondWithRemoveRosterRowConfirmation rosterDay preview =
    if isHtmxRequest
        then respondHtmlProfiled [hsx|
            <div id={dialogOverlayMountId} hx-swap-oob="innerHTML">
                {confirmationDialog}
                {confirmForm}
            </div>
        |]
        else do
            setErrorMessage (overflowCopy <> " cannot be packed into another column and would be deleted. Confirm from the roster screen before deleting this row.")
            redirectToPath (pathTo RosterWeeksAction)
    where
        confirmFormId = "confirm-remove-roster-row-form" :: Text
        overflowCount = preview.removeRosterRowOverflowCount
        overflowCopy =
            if overflowCount == 1
                then "1 shift"
                else tshow overflowCount <> " shifts"
        confirmForm =
            renderAppShellActionForm
                (appShellActionByMarker @ConfirmRemoveRosterRowOverlay)
                AppShellActionRoute
                    { appShellActionRouteUrl = pathTo (RemoveRosterRowAction rosterDay.id)
                    , appShellActionRouteFields = []
                    , appShellActionRouteCustomHtmx = []
                    , appShellActionRouteStandardUrl = Nothing
                    , appShellActionRouteExtraAttrs =
                        [ ("id", confirmFormId)

                        ]
                    }
                [hsx|<input type="hidden" name="confirmDeletePopulatedRow" value="true" />|]
        confirmationDialog =
            renderDialogOverlay DialogOverlayConfig
                { dialogOverlayTitle = "Delete roster row?"
                , dialogOverlayBody = [hsx|
                    <p class="mb-2">
                        {overflowCopy} cannot be packed into another column and will be deleted.
                    </p>
                    <p class="mb-0 app-muted">
                        Shifts that fit will be moved into the bottom of the remaining columns from left to right.
                    </p>
                |]
                , dialogOverlayStartButtons = []
                , dialogOverlayButtons =
                    [ OverlayButton
                        { overlayButtonLabel = "Cancel"
                        , overlayButtonClass = "btn btn-outline-secondary"
                        , overlayButtonAction = OverlayCloseAction
                        }
                    , OverlayButton
                        { overlayButtonLabel = "Delete row"
                        , overlayButtonClass = "btn btn-danger"
                        , overlayButtonAction = OverlaySubmitFormAction confirmFormId
                        }
                    ]
                , dialogOverlayDialogClass = ""
                }

clearDialogOverlayOob :: Blaze.Html
clearDialogOverlayOob = [hsx|<div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>|]

currentRosterGridViewMode :: (?request :: Request) => RosterGridViewMode
currentRosterGridViewMode =
    case (paramOrNothing @Text "rosterView", paramOrNothing @Int "dayOffset") of
        (Just "timeline", Just dayOffset) -> RosterDayTimelineGridView (max 0 (min 6 dayOffset))
        _ -> RosterWeekGridView

currentRosterTimelineDayOffset :: (?request :: Request) => Maybe Int
currentRosterTimelineDayOffset = case currentRosterGridViewMode of
    RosterDayTimelineGridView dayOffset -> Just dayOffset
    RosterWeekGridView                  -> Nothing

buildRosterTimelineTodayUrl :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> IO Text
buildRosterTimelineTodayUrl rosterGroupId = do
    venueConfig <- fetchVenueConfig
    today <- utctDay <$> getCurrentTime
    let currentWeekOffset = venueWeekOffsetForDay venueConfig today
        todayDayOffset = fromInteger (Calendar.diffDays today (venueWeekStartDate venueConfig currentWeekOffset))
    pure (rosterDayTimelineUrl currentWeekOffset rosterGroupId (max 0 (min 6 todayDayOffset)))

renderRosterWeekPage :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => Int -> Id RosterGroup -> IO ()
renderRosterWeekPage weekOffset requestedRosterGroupId =
    profileActionSpan "roster.page.render" do
        venueConfig <- profileActionSpan "roster.page.fetch_venue_config" fetchVenueConfig
        let weekStartDate = venueWeekStartDate venueConfig weekOffset
        let weekEndDate = Calendar.addDays 6 weekStartDate
        setTitle "Roster"
        rosterGroups <- profileActionSpan "roster.page.fetch_roster_groups" fetchCurrentVenueRosterGroups
        currentRosterGroup <- profileActionSpan "roster.page.resolve_current_group" (fetchCurrentVenueRosterGroupOrDefault (Just requestedRosterGroupId))
        _ <- profileActionSpan "roster.page.ensure_week_exists" (ensureRosterWeekExists currentRosterGroup.id weekOffset)
        rosterDataOrNothing <- profileActionSpan "roster.page.fetch_read_model" (fetchVisibleRosterReadModel currentRosterGroup.id weekOffset)
        passkeySetupPrompt <- profileActionSpan "roster.page.passkey_prompt" passkeySetupPromptFromSession
        timelineTodayUrl <- profileActionSpan "roster.page.timeline_today_url" (buildRosterTimelineTodayUrl currentRosterGroup.id)

        case rosterDataOrNothing of
            Just RosterRenderData { rosterWeek, rosterDays, assignmentFilters, staffMembers, panelStaff, staffSelfServicePanel, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled, rosterTimePickerStartMinute, rosterTimePickerFinalSelectableMinute, rosterWagePrediction, showWageEstimates, showRosterWarnings, rosterPublicHolidays } ->
                let visibleRosterWeek =
                        if rosterWeek.isLive || hasRole ManagerRole'
                            then Just rosterWeek
                            else Nothing
                 in profileActionSpan "roster.page.respond" $
                        respondWithRosterWeekView
                            ShowView
                                { rosterWeek = visibleRosterWeek
                                , rosterDays
                                , weekOffset
                                , rosterGroups
                                , currentRosterGroup
                                , weekStartDate
                                , weekEndDate
                                , assignmentFilters
                                , staffMembers
                                , panelStaff
                                , staffSelfServicePanel
                                , slotNames = orderedSlotNames
                                , shiftTypes
                                , allSlots
                                , slotConflicts
                                , renderIndexes
                                , viewCapabilities = buildRosterViewCapabilities visibleRosterWeek
                                , rosterLayoutMode
                                , rosterEndTimesEnabled
                                , rosterTimePickerStartMinute
                                , rosterTimePickerFinalSelectableMinute
                                , rosterWagePrediction
                                , showWageEstimates
                                , showRosterWarnings
                                , publicHolidays = rosterPublicHolidays
                                , passkeySetupPrompt
                                , rosterGridViewMode = currentRosterGridViewMode
                                , rosterTimelineTodayUrl = Just timelineTodayUrl
                                }
            Nothing ->
                error "Roster week should exist after ensureRosterWeekExists"

respondWithRosterWeekView :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => ShowView -> IO ()
respondWithRosterWeekView showView =
    profileActionSpan "roster.page.render_response" do
        if isHtmxRequest
            then respondHtmlProfiled (renderRosterWeekShell showView)
            else renderProfiled showView

passkeySetupPromptFromSession :: (?request :: Request) => IO (Maybe PasskeySetupPromptMode)
passkeySetupPromptFromSession =
    fmap promptModeFromText (getSessionAndClear @Text passkeySetupPromptSessionKey)
  where
    promptModeFromText = \case
        Just "first-passkey"     -> Just FirstPasskeyPrompt
        Just "additional-device" -> Just AdditionalDevicePasskeyPrompt
        _                        -> Nothing

renderRosterWeekOverviewFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> Id RosterGroup -> IO Blaze.Html
renderRosterWeekOverviewFragment weekOffset rosterGroupId = do
    venueConfig <- fetchVenueConfig
    todayDate <- utctDay <$> getCurrentTime
    let weekStartDate = venueWeekStartDate venueConfig weekOffset
    let focusDate = initialOverviewFocusDate weekStartDate todayDate
    weekOverviewDays <- profileActionSpan "roster.build_month_overview" (buildRosterMonthOverviewDays venueConfig rosterGroupId focusDate)
    pure (renderWeekOverviewPanelFragment weekOffset rosterGroupId weekStartDate todayDate weekOverviewDays (buildRosterViewCapabilities Nothing))

fetchRelatedSlotsForStaffIdsInRosterWeek :: (?modelContext :: ModelContext) => RosterWeek -> [UUID.UUID] -> IO [RosterSlot]
fetchRelatedSlotsForStaffIdsInRosterWeek rosterWeek staffIds =
    if null staffIds
        then pure []
        else do
            rosterDays <- query @RosterDay
                |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
                |> fetch
            if null rosterDays
                then pure []
                else query @RosterSlot
                    |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) rosterDays)
                    |> filterWhereIn (#staffId, map Just (nub staffIds))
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetch

respondToRosterSlotDefinitionError :: (?context :: ControllerContext, ?request :: Request) => RosterWeek -> Text -> IO ()
respondToRosterSlotDefinitionError rosterWeek errorMessage =
    if isHtmxRequest
        then respondWithRosterToast errorMessage "app-toast-error"
        else do
            setErrorMessage errorMessage
            redirectToPath (rosterWeekUrl rosterWeek.weekOffset (coerce rosterWeek.rosterGroupId :: Id RosterGroup))

respondToRosterSlotDefinitionSuccess :: (?context :: ControllerContext, ?request :: Request) => RosterWeek -> LiveMutationResult value -> Text -> IO ()
respondToRosterSlotDefinitionSuccess rosterWeek mutationResult successMessage =
    if isHtmxRequest
        then
            respondWithRosterResourceInvalidation
                rosterGroupId
                rosterWeek.weekOffset
                mutationResult.liveMutationTouchedResources
                rosterGridFrameAndStaffPanelFragments
                mempty
        else do
            setSuccessMessage successMessage
            redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)
    where
        rosterGroupId = coerce rosterWeek.rosterGroupId
