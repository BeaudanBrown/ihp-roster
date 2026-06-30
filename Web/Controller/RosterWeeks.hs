{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Web.Controller.RosterWeeks where

import Application.Helper.Controller
import Application.Helper.LiveResource (LiveMutationResult (..), LiveResource)
import Application.Helper.LiveSurface (respondWithTypedLiveSurfaceFragments,
                                       serveTypedLiveFragment,
                                       typedLiveSurfaceAffectedFragments)
import Application.Helper.LiveUpdate (LiveUpdateScope (..))
import Application.Helper.Profiling
import Application.Helper.RosterGroups
import Application.Helper.UserPreferences
import Application.Helper.View (DialogOverlayConfig (..), OverlayButton (..),
                                OverlayButtonAction (..),
                                ToastOverlayPosition (ToastBottomCenter),
                                dialogOverlayMountId, errorToast,
                                renderDialogOverlay, renderToastOob,
                                successToast)
import Control.Monad (guard)
import Data.Coerce (coerce)
import Data.List (nub)
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
import Web.Controller.Sessions (passkeySetupPromptSessionKey)
import Web.RosterWeeks.Capabilities (buildRosterViewCapabilities)
import Web.RosterWeeks.Dom
import Web.RosterWeeks.Filters
import Web.RosterWeeks.LiveSurface (rosterLiveSurfaceDefinition)
import Web.RosterWeeks.Mutations
import Web.RosterWeeks.Overview
import Web.RosterWeeks.Paths (rosterWeekUrl)
import Web.RosterWeeks.Projection
import Web.RosterWeeks.RenderData
import Web.RosterWeeks.Responses (respondWithRosterContent,
                                  respondWithRosterContentError,
                                  respondWithRosterContentUpdate,
                                  respondWithRosterFragmentsUpdate,
                                  respondWithRosterToast)
import Web.RosterWeeks.Rows
import Web.RosterWeeks.Service
import Web.RosterWeeks.StaffOptions (buildRosterStaffOptionStates)
import Web.RosterWeeks.Types
import Web.View.RosterWeeks.Overview (renderWeekOverviewPanelFragment)
import Web.View.RosterWeeks.ShiftDialog
import Web.View.RosterWeeks.Show (renderRosterWeekShell)
import Web.View.RosterWeeks.StaffPanel (renderRosterStaffPanelFragment,
                                        renderRosterStaffPanelFragmentOob)

rosterWarningPreferenceMutationSpec :: BepisMutationSpec
rosterWarningPreferenceMutationSpec = BepisMutationSpec
    { auditPolicy = BepisAuditNotRequired
    , realtimePolicy = BepisRealtimeNotApplicable
    , scopePolicy = BepisCurrentUserScope
    }

rosterWeekMutationSpec :: BepisMutationSpec
rosterWeekMutationSpec = BepisMutationSpec
    { auditPolicy = BepisAuditNotRequired
    , realtimePolicy = BepisEmitsRealtimeInvalidation
    , scopePolicy = BepisVenueRosterWeekScope
    }

rosterPreferenceMutationSpec :: BepisMutationSpec
rosterPreferenceMutationSpec = BepisMutationSpec
    { auditPolicy = BepisAuditNotRequired
    , realtimePolicy = BepisEmitsRealtimeInvalidation
    , scopePolicy = BepisVenueRosterWeekScope
    }

instance Controller RosterWeeksController where
    beforeAction = bepisBeforeAction BepisAuthenticatedVenueController do
        annotateTelemetryAction
        ensureIsUser
        ensureCurrentVenueOrSupportRedirect
        ensureProfileCompleted

    action RosterWeeksAction = bepisPageAction "RosterWeeksAction" do
        -- Redirect to the current week's offset based on today's date
        currentWeekOffset <- fetchCurrentRosterWeekOffset
        currentRosterGroup <- resolveRequestedRosterGroup
        let currentWeekPath = rosterWeekUrl currentWeekOffset currentRosterGroup.id

        if isHtmxRequest
            then do
                setHtmxPushUrl currentWeekPath
                renderRosterWeekPage currentWeekOffset currentRosterGroup.id
            else redirectToPath currentWeekPath

    action ShowRosterWeekAction { weekOffset } = bepisPageAction "ShowRosterWeekAction" do
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

    action ShowRosterWeekOverviewFragmentAction { weekOffset } = bepisFragmentAction "ShowRosterWeekOverviewFragmentAction" do
        rosterGroup <- resolveRequestedRosterGroup
        respondHtmlProfiled =<< renderRosterWeekOverviewFragment weekOffset rosterGroup.id

    action ShowRosterWeekContentFragmentAction { weekOffset } = bepisFragmentAction "ShowRosterWeekContentFragmentAction" do
        rosterGroup <- resolveRequestedRosterGroup
        serveTypedLiveFragment rosterLiveSurfaceDefinition (buildRosterProjectionScope rosterGroup.id weekOffset) RosterProjectionContent \_ ->
            respondWithRosterContent rosterGroup.id weekOffset

    action ShowRosterWeekGridToolbarFragmentAction { weekOffset } = bepisFragmentAction "ShowRosterWeekGridToolbarFragmentAction" do
        rosterGroup <- resolveRequestedRosterGroup
        serveTypedLiveFragment rosterLiveSurfaceDefinition (buildRosterProjectionScope rosterGroup.id weekOffset) RosterProjectionGridToolbar \_ -> do
            toolbarHtml <- renderVisibleRosterReadModelFragment rosterGroup.id weekOffset RosterProjectionGridToolbar
            respondHtmlProfiled (fromMaybe mempty toolbarHtml)

    action ShowRosterWeekGridFrameFragmentAction { weekOffset } = bepisFragmentAction "ShowRosterWeekGridFrameFragmentAction" do
        rosterGroup <- resolveRequestedRosterGroup
        serveTypedLiveFragment rosterLiveSurfaceDefinition (buildRosterProjectionScope rosterGroup.id weekOffset) RosterProjectionGridFrame \_ -> do
            frameHtml <- renderVisibleRosterReadModelFragment rosterGroup.id weekOffset RosterProjectionGridFrame
            respondHtmlProfiled (fromMaybe mempty frameHtml)

    action ShowRosterWeekDayColumnsFragmentAction { weekOffset } = bepisFragmentAction "ShowRosterWeekDayColumnsFragmentAction" do
        rosterGroup <- resolveRequestedRosterGroup
        serveTypedLiveFragment rosterLiveSurfaceDefinition (buildRosterProjectionScope rosterGroup.id weekOffset) RosterProjectionDayColumns \_ -> do
            fragmentHtml <- renderVisibleRosterReadModelFragment rosterGroup.id weekOffset RosterProjectionDayColumns
            respondHtmlProfiled (fromMaybe mempty fragmentHtml)

    action ShowRosterWeekDayRailFragmentAction { weekOffset } = bepisFragmentAction "ShowRosterWeekDayRailFragmentAction" do
        rosterGroup <- resolveRequestedRosterGroup
        serveTypedLiveFragment rosterLiveSurfaceDefinition (buildRosterProjectionScope rosterGroup.id weekOffset) RosterProjectionDayRail \_ -> do
            fragmentHtml <- renderVisibleRosterReadModelFragment rosterGroup.id weekOffset RosterProjectionDayRail
            respondHtmlProfiled (fromMaybe mempty fragmentHtml)

    action ShowRosterWeekWageRailFragmentAction { weekOffset } = bepisFragmentAction "ShowRosterWeekWageRailFragmentAction" do
        rosterGroup <- resolveRequestedRosterGroup
        serveTypedLiveFragment rosterLiveSurfaceDefinition (buildRosterProjectionScope rosterGroup.id weekOffset) RosterProjectionWageRail \_ -> do
            fragmentHtml <- renderVisibleRosterReadModelFragment rosterGroup.id weekOffset RosterProjectionWageRail
            respondHtmlProfiled (fromMaybe mempty fragmentHtml)

    action ShowRosterWeekSlotsGridFragmentAction { weekOffset } = bepisFragmentAction "ShowRosterWeekSlotsGridFragmentAction" do
        rosterGroup <- resolveRequestedRosterGroup
        serveTypedLiveFragment rosterLiveSurfaceDefinition (buildRosterProjectionScope rosterGroup.id weekOffset) RosterProjectionSlotsGrid \_ -> do
            fragmentHtml <- renderVisibleRosterReadModelFragment rosterGroup.id weekOffset RosterProjectionSlotsGrid
            respondHtmlProfiled (fromMaybe mempty fragmentHtml)

    action ShowRosterWeekStaffPanelFragmentAction { weekOffset } = bepisFragmentAction "ShowRosterWeekStaffPanelFragmentAction" do
        rosterGroup <- resolveRequestedRosterGroup
        let panelScope = rosterStaffPanelScopeFromParams
        serveTypedLiveFragment rosterLiveSurfaceDefinition (buildRosterProjectionScope rosterGroup.id weekOffset) RosterProjectionStaffPanel \_ -> do
            rosterGroups <- fetchCurrentVenueRosterGroups
            panelStaff <- fetchVisibleRosterStaffPanelEntries panelScope rosterGroup.id weekOffset
            respondHtmlProfiled $
                maybe mempty (renderRosterStaffPanelFragment weekOffset rosterGroup.id (length rosterGroups > 1) panelScope) panelStaff

    action ShowRosterWeekDaySectionFragmentAction { weekOffset, rosterDayId } = bepisFragmentAction "ShowRosterWeekDaySectionFragmentAction" do
        rosterGroupId <- resolveRosterGroupIdForFragmentRosterDay weekOffset rosterDayId
        serveTypedLiveFragment rosterLiveSurfaceDefinition (buildRosterProjectionScope rosterGroupId weekOffset) (RosterProjectionDaySection (coerce rosterDayId)) \_ -> do
            daySectionHtml <- fetchVisibleRosterDaySectionFragment rosterGroupId weekOffset rosterDayId
            respondHtmlProfiled (fromMaybe mempty daySectionHtml)

    action ShowRosterWeekRowFragmentAction { weekOffset, rosterDayId, rowIndex } = bepisFragmentAction "ShowRosterWeekRowFragmentAction" do
        rosterGroupId <- resolveRosterGroupIdForFragmentRosterDay weekOffset rosterDayId
        serveTypedLiveFragment rosterLiveSurfaceDefinition (buildRosterProjectionScope rosterGroupId weekOffset) (RosterProjectionRow (coerce rosterDayId) rowIndex) \_ -> do
            rowHtml <- fetchVisibleRosterRowFragment rosterGroupId weekOffset rosterDayId rowIndex
            respondHtmlProfiled (fromMaybe mempty rowHtml)

    action UpdateRosterAssignmentFiltersAction { weekOffset = _ } = bepisPreferenceAction "UpdateRosterAssignmentFiltersAction" rosterPreferenceMutationSpec do
        ensureManagerRole
        _ <- resolveRequestedRosterGroup
        setRosterAssignmentFiltersSession rosterAssignmentFiltersFromParams
        respondHtmlProfiled mempty

    action CreateRosterWeekAction { weekOffset } = bepisMutationAction "CreateRosterWeekAction" rosterWeekMutationSpec do
        ensureManagerRole
        ensureVenueWritable
        rosterGroup <- resolveRequestedRosterGroup
        LiveMutationResult { liveMutationValue = (rosterWeek, wasCreated) } <- ensureRosterWeekExistsMutation rosterGroup.id weekOffset

        let successMessage =
                if wasCreated
                    then "Roster week created successfully"
                    else "Roster week already exists."
        let targetPath = rosterWeekUrl rosterWeek.weekOffset rosterGroup.id
        if isHtmxRequest
            then do
                setHtmxPushUrl targetPath
                respondWithRosterContentUpdate rosterGroup.id rosterWeek.weekOffset successMessage
            else do
                setSuccessMessage successMessage
                redirectToPath targetPath

    action CopyRosterWeekAction { sourceWeekOffset, targetWeekOffset } = bepisMutationAction "CopyRosterWeekAction" rosterWeekMutationSpec do
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
                        _ <- copyRosterWeekFromSourceMutation rosterGroup.id sourceWeek targetWeekOffset
                        let successMessage = "Roster week copied from the previous week."
                        let targetPath = rosterWeekUrl targetWeekOffset rosterGroup.id
                        if isHtmxRequest
                            then do
                                setHtmxPushUrl targetPath
                                respondWithRosterContentUpdate rosterGroup.id targetWeekOffset successMessage
                            else do
                                setSuccessMessage successMessage
                                redirectToPath targetPath

    action ToggleRosterWeekLiveStatusAction { rosterWeekId } = bepisMutationAction "ToggleRosterWeekLiveStatusAction" rosterWeekMutationSpec do
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
                LiveMutationResult { liveMutationValue = (updatedRosterWeek, queuedTimesheetJobCount) } <- toggleRosterWeekLiveStatusMutation rosterGroupId rosterWeek nextLiveStatus
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
                        respondWithRosterContentUpdate rosterGroupId rosterWeek.weekOffset successMessage
                    else do
                        setSuccessMessage successMessage
                        redirectToPath targetPath

    action CreateRosterWeekSlotDefinitionAction { rosterWeekId } = bepisMutationAction "CreateRosterWeekSlotDefinitionAction" rosterWeekMutationSpec do
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
                duplicate <- activeRosterWeekSlotDefinitionWithName rosterWeek slotName Nothing
                case duplicate of
                    Just _ -> respondToRosterSlotDefinitionError rosterWeek "A column with that name already exists for this week."
                    Nothing -> do
                        _ <- appendRosterWeekSlotDefinitionMutation rosterGroupId rosterWeek slotName
                        respondToRosterSlotDefinitionSuccess rosterWeek "Roster column added."

    action UpdateRosterWeekSlotDefinitionAction { rosterWeekSlotDefinitionId } = bepisMutationAction "UpdateRosterWeekSlotDefinitionAction" rosterWeekMutationSpec do
        ensureManagerRole
        ensureVenueWritable
        slotDefinition <- fetch rosterWeekSlotDefinitionId
        rosterWeek <- fetch (Id slotDefinition.rosterWeekId :: Id RosterWeek)
        ensureRecordInCurrentVenue rosterWeek.venueId
        ensureRosterWeekIsDraftForEdit rosterWeek

        let rosterGroupId = coerce rosterWeek.rosterGroupId
        case normalizeRosterSlotDefinitionName (paramOrDefault @Text "" "name") of
            Left errorMessage -> respondToRosterSlotDefinitionError rosterWeek errorMessage
            Right slotName -> do
                duplicate <- activeRosterWeekSlotDefinitionWithName rosterWeek slotName (Just slotDefinition.id)
                case duplicate of
                    Just _ -> respondToRosterSlotDefinitionError rosterWeek "A column with that name already exists for this week."
                    Nothing -> do
                        _ <- renameRosterWeekSlotDefinitionMutation rosterGroupId rosterWeek slotDefinition slotName
                        respondToRosterSlotDefinitionSuccess rosterWeek "Roster column renamed."

    action DeleteRosterWeekSlotDefinitionAction { rosterWeekSlotDefinitionId } = bepisMutationAction "DeleteRosterWeekSlotDefinitionAction" rosterWeekMutationSpec do
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
                _ <- removeRosterWeekSlotDefinitionMutation rosterGroupId rosterWeek slotDefinition
                respondToRosterSlotDefinitionSuccess rosterWeek "Roster column removed."

    action SortRosterWeekAction { rosterWeekId } = bepisMutationAction "SortRosterWeekAction" rosterWeekMutationSpec do
        ensureManagerRole
        ensureVenueWritable
        rosterWeek <- fetch rosterWeekId
        ensureRecordInCurrentVenue rosterWeek.venueId
        ensureRosterWeekIsDraftForEdit rosterWeek

        let rosterGroupId = coerce rosterWeek.rosterGroupId
        _ <- repackRosterWeekMutation rosterWeek

        if isHtmxRequest
            then
                respondWithRosterActorRefresh
                    rosterGroupId
                    rosterWeek.weekOffset
                    rosterGridInnerAndStaffPanelFragments
            else do
                setSuccessMessage "Roster sorted."
                redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)

    action ToggleRosterDayClosedAction { rosterDayId } = bepisMutationAction "ToggleRosterDayClosedAction" rosterWeekMutationSpec do
        ensureManagerRole
        ensureVenueWritable

        rosterDay <- fetch rosterDayId
        let rosterWeekId = (coerce rosterDay.rosterWeekId :: Id RosterWeek)
        rosterWeek <- fetch rosterWeekId
        ensureRecordInCurrentVenue rosterWeek.venueId
        ensureRosterWeekIsDraftForEdit rosterWeek

        let rosterGroupId = coerce rosterWeek.rosterGroupId
        let nextClosedState = not rosterDay.isClosed

        _ <- toggleRosterDayClosedMutation rosterGroupId rosterWeek rosterDay nextClosedState closedRosterDayRows

        let successMessage =
                if nextClosedState
                    then "Roster day marked closed."
                    else "Roster day reopened."
        let targetPath = rosterWeekUrl rosterWeek.weekOffset rosterGroupId
        if isHtmxRequest
            then do
                setHtmxPushUrl targetPath
                respondWithRosterActorRefresh
                    rosterGroupId
                    rosterWeek.weekOffset
                    rosterGridInnerAndStaffPanelFragments
            else do
                setSuccessMessage successMessage
                redirectToPath targetPath

    action AddRosterRowAction { rosterDayId } = bepisMutationAction "AddRosterRowAction" rosterWeekMutationSpec do
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
                _ <- addRosterDayRowMutation rosterGroupId rosterWeek rosterDay

                if isHtmxRequest
                    then
                        respondWithRosterActorRefresh
                            rosterGroupId
                            rosterWeek.weekOffset
                            rosterGridInnerAndStaffPanelFragments
                    else do
                        setSuccessMessage "Roster row added."
                        redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)

    action RemoveRosterRowAction { rosterDayId } = bepisMutationAction "RemoveRosterRowAction" rosterWeekMutationSpec do
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
                _ <- removeRosterDayRowMutation rosterGroupId rosterWeek rosterDay activeDefinitions

                if isHtmxRequest
                    then
                        respondWithRosterActorRefresh
                            rosterGroupId
                            rosterWeek.weekOffset
                            rosterGridInnerAndStaffPanelFragments
                    else do
                        setSuccessMessage "Roster row removed."
                        redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)

    action UpdateRosterLayoutPreferenceAction { weekOffset } = bepisPreferenceAction "UpdateRosterLayoutPreferenceAction" rosterPreferenceMutationSpec do
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

    action MoveRosterShiftToSlotAction { weekOffset } = bepisMutationAction "MoveRosterShiftToSlotAction" rosterWeekMutationSpec do
        ensureManagerRole
        ensureVenueWritable
        rosterGroup <- resolveRequestedRosterGroup
        result <- validateMoveRosterShiftIntent rosterGroup.id weekOffset
        case result of
            Left message -> respondWithMoveRosterShiftFailure rosterGroup.id weekOffset message
            Right MoveRosterShiftIntent { sourceSlot, sourceRosterDay, targetRosterDay, targetSlotDefinition, targetRowIndex } -> do
                let updatedSlot = sourceSlot
                        |> set #rosterDayId (unpackId targetRosterDay.id)
                        |> set #rosterWeekSlotDefinitionId (unpackId targetSlotDefinition.id)
                        |> set #slotSortOrder targetSlotDefinition.sortOrder
                        |> set #rowIndex targetRowIndex
                rosterWeek <- fetch (Id targetRosterDay.rosterWeekId :: Id RosterWeek)
                mutationResult <- moveRosterSlotMutation rosterGroup.id rosterWeek sourceRosterDay targetRosterDay sourceSlot updatedSlot
                let RosterSlotMutationResult { rosterSlotMutationPreviousStaffId = previousStaffId, rosterSlotMutationShouldWarnSourceTimesheetUnchanged = shouldWarnSourceTimesheetUnchanged } = mutationResult.liveMutationValue
                let impactedRows = nub [(sourceSlot.rosterDayId, sourceSlot.rowIndex), (unpackId targetRosterDay.id, targetRowIndex)]
                respondToRosterSlotMove rosterGroup.id rosterWeek mutationResult previousStaffId impactedRows shouldWarnSourceTimesheetUnchanged

    action UpdateRosterWarningPreferenceAction { weekOffset } =
        bepisMutationAction "UpdateRosterWarningPreferenceAction" rosterWarningPreferenceMutationSpec do
            ensureManagerRole
            rosterGroup <- resolveRequestedRosterGroup
            let showRosterWarnings = paramOrDefault @Text "false" "showRosterWarnings" == "true"
            _ <- upsertCurrentUserShowRosterWarnings showRosterWarnings
            if isHtmxRequest
                then respondWithRosterFragmentsUpdate rosterGroup.id weekOffset [RosterProjectionGridToolbar, RosterProjectionGridFrame] (successToast "Roster warning preference saved.")
                else do
                    setSuccessMessage "Roster warning preference saved."
                    redirectToPath (rosterWeekUrl weekOffset rosterGroup.id)

    action UpdateRosterWageEstimatePreferenceAction { weekOffset } = bepisPreferenceAction "UpdateRosterWageEstimatePreferenceAction" rosterPreferenceMutationSpec do
        accessDeniedUnless (hasRole VenueAdminRole)
        rosterGroup <- resolveRequestedRosterGroup
        let showWageEstimates = paramOrDefault @Text "false" "showWageEstimates" == "true"
        _ <- upsertCurrentUserShowWageEstimates showWageEstimates
        if isHtmxRequest
            then respondWithRosterFragmentsUpdate rosterGroup.id weekOffset rosterGridStructuralFragments (successToast "Roster wage estimate preference saved.")
            else do
                setSuccessMessage "Roster wage estimate preference saved."
                redirectToPath (rosterWeekUrl weekOffset rosterGroup.id)

    action NewRosterSlotDialogAction { rosterDayId, rosterWeekSlotDefinitionId, rowIndex } = bepisDialogAction "NewRosterSlotDialogAction" do
        ensureManagerRole
        ensureVenueWritable
        (rosterDay, rosterWeek, slotDefinition) <- fetchRosterSlotCreateContext rosterDayId rosterWeekSlotDefinitionId rowIndex
        renderRosterShiftDialogForCreate rosterDay rosterWeek slotDefinition rowIndex emptyRosterShiftDialogValues

    action EditRosterSlotDialogAction { rosterSlotId } = bepisDialogAction "EditRosterSlotDialogAction" do
        ensureManagerRole
        ensureVenueWritable
        (rosterSlot, rosterDay, rosterWeek) <- fetchRosterSlotEditContext rosterSlotId
        renderRosterShiftDialogForEdit rosterSlot rosterDay rosterWeek (rosterShiftDialogValuesFromSlot rosterSlot)

    action CreateRosterSlotAction { rosterDayId, rosterWeekSlotDefinitionId, rowIndex } = bepisMutationAction "CreateRosterSlotAction" rosterWeekMutationSpec do
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
                respondToRosterSlotMutation rosterGroupId rosterWeek rosterDay rowIndex mutationResult (Just valid.validRosterShiftStaffId) "Roster shift saved."

    action UpdateRosterSlotAction { rosterSlotId } = bepisMutationAction "UpdateRosterSlotAction" rosterWeekMutationSpec do
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
                respondToRosterSlotUpdate rosterGroupId rosterWeek mutationResult (Just valid.validRosterShiftStaffId) impactedRowKeys shouldWarnSourceTimesheetUnchanged

    action DeleteRosterSlotAction { rosterSlotId } = bepisMutationAction "DeleteRosterSlotAction" rosterWeekMutationSpec do
        ensureManagerRole
        ensureVenueWritable
        (rosterSlot, rosterDay, rosterWeek) <- fetchRosterSlotEditContext rosterSlotId
        let rosterGroupId = coerce rosterWeek.rosterGroupId
        mutationResult <- deleteRosterSlotMutation rosterGroupId rosterWeek rosterDay rosterSlot
        let RosterSlotMutationResult { rosterSlotMutationPreviousStaffId = previousStaffId } = mutationResult.liveMutationValue
        respondToRosterSlotUpdate rosterGroupId rosterWeek mutationResult previousStaffId [(rosterSlot.rosterDayId, rosterSlot.rowIndex)] False

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
    }

validateMoveRosterShiftIntent :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (Either Text MoveRosterShiftIntent)
validateMoveRosterShiftIntent rosterGroupId weekOffset = do
    let sourceToken = paramOrDefault @Text "" "sourceItemKey"
    let targetToken = paramOrDefault @Text "" "targetDropzoneKey"
    case (parseExistingSlotToken sourceToken, parseNewSlotToken targetToken) of
        (Just sourceSlotId, Just (targetRosterDayId, targetSlotDefinitionId, targetRowIndex)) -> do
            maybeResult <- validateMoveRosterShiftTarget rosterGroupId weekOffset sourceSlotId targetRosterDayId targetSlotDefinitionId targetRowIndex
            pure (maybe (Left "Choose an empty roster slot in this week.") Right maybeResult)
        _ -> pure (Left "Drag the shift onto an empty roster slot.")

validateMoveRosterShiftTarget :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> Id RosterSlot -> Id RosterDay -> Id RosterWeekSlotDefinition -> Int -> IO (Maybe MoveRosterShiftIntent)
validateMoveRosterShiftTarget rosterGroupId weekOffset sourceSlotId targetRosterDayId targetSlotDefinitionId targetRowIndex = do
    maybeSourceSlot <- fetchOneOrNothing (query @RosterSlot |> filterWhere (#id, sourceSlotId))
    maybeTargetRosterDay <- fetchOneOrNothing (query @RosterDay |> filterWhere (#id, targetRosterDayId))
    maybeTargetSlotDefinition <- fetchOneOrNothing (query @RosterWeekSlotDefinition |> filterWhere (#id, targetSlotDefinitionId))
    case (maybeSourceSlot, maybeTargetRosterDay, maybeTargetSlotDefinition) of
        (Just sourceSlot, Just targetRosterDay, Just targetSlotDefinition) -> do
            sourceRosterDay <- fetch (Id sourceSlot.rosterDayId :: Id RosterDay)
            sourceRosterWeek <- fetch (Id sourceRosterDay.rosterWeekId :: Id RosterWeek)
            targetRosterWeek <- fetch (Id targetRosterDay.rosterWeekId :: Id RosterWeek)
            targetExists <- query @RosterSlot
                |> filterWhere (#rosterDayId, unpackId targetRosterDay.id)
                |> filterWhere (#rosterWeekSlotDefinitionId, unpackId targetSlotDefinition.id)
                |> filterWhere (#rowIndex, targetRowIndex)
                |> filterWhere (#deletedAt, Nothing)
                |> fetchExists
            let sourceMatchesScope = sourceRosterWeek.rosterGroupId == unpackId rosterGroupId && sourceRosterWeek.weekOffset == weekOffset
            let targetMatchesScope = targetRosterWeek.rosterGroupId == unpackId rosterGroupId && targetRosterWeek.weekOffset == weekOffset
            let targetDefinitionMatchesWeek = targetSlotDefinition.rosterWeekId == unpackId targetRosterWeek.id
            let sourceIsStaffed = isJust sourceSlot.staffId
            let targetIsOpen = not targetRosterDay.isClosed && targetRowIndex >= 0 && targetRowIndex < targetRosterDay.rowCount
            pure do
                guard sourceMatchesScope
                guard targetMatchesScope
                guard targetDefinitionMatchesWeek
                guard sourceIsStaffed
                guard targetIsOpen
                guard (not targetExists)
                pure MoveRosterShiftIntent { sourceSlot, sourceRosterDay, targetRosterDay, targetSlotDefinition, targetRowIndex }
        _ -> pure Nothing

parseExistingSlotToken :: Text -> Maybe (Id RosterSlot)
parseExistingSlotToken token =
    case Text.splitOn ":" token of
        ["existing", rawSlotId] -> Id <$> parseUUIDText rawSlotId
        _                       -> Nothing

parseNewSlotToken :: Text -> Maybe (Id RosterDay, Id RosterWeekSlotDefinition, Int)
parseNewSlotToken token =
    case Text.splitOn ":" token of
        ["new", rawRosterDayId, rawSlotDefinitionId, rawRowIndex] -> do
            rosterDayId <- Id <$> parseUUIDText rawRosterDayId
            slotDefinitionId <- Id <$> parseUUIDText rawSlotDefinitionId
            rowIndex <- TextRead.readMaybe (cs rawRowIndex)
            pure (rosterDayId, slotDefinitionId, rowIndex)
        _ -> Nothing

respondWithMoveRosterShiftFailure :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Text -> IO ()
respondWithMoveRosterShiftFailure rosterGroupId weekOffset message =
    if isHtmxRequest
        then respondWithRosterActorRefreshWithToast rosterGroupId weekOffset [] (Just message)
        else do
            setErrorMessage message
            redirectToPath (rosterWeekUrl weekOffset rosterGroupId)

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
    staffMembers <- fetchEligibleRosterGroupStaff (coerce rosterWeek.rosterGroupId)
    shiftTypes <- fetchCurrentVenueRosterShiftTypesForDialog
    let targetSlot =
            newRecord @RosterSlot
                |> set #rosterDayId (unpackId rosterDay.id)
                |> set #rosterWeekSlotDefinitionId (unpackId slotDefinition.id)
                |> set #slotSortOrder slotDefinition.sortOrder
                |> set #rowIndex rowIndex
    staffOptionStates <- buildRosterShiftDialogStaffOptionStates (coerce rosterWeek.rosterGroupId) rosterWeek targetSlot staffMembers
    respondHtmlProfiled $ renderRosterShiftDialog RosterShiftDialogData
        { rosterShiftDialogMode = NewRosterShiftDialog rosterDay.id slotDefinition.id rowIndex
        , rosterShiftDialogTitle = "Add shift"
        , rosterShiftDialogStaff = staffMembers
        , rosterShiftDialogStaffOptionStates = staffOptionStates
        , rosterShiftDialogShiftTypes = shiftTypes
        , rosterShiftDialogValues = values
        }

renderRosterShiftDialogForEdit :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterSlot -> RosterDay -> RosterWeek -> RosterShiftDialogValues -> IO ()
renderRosterShiftDialogForEdit rosterSlot _rosterDay rosterWeek values = do
    staffMembers <- fetchEligibleRosterGroupStaff (coerce rosterWeek.rosterGroupId)
    shiftTypes <- fetchCurrentVenueRosterShiftTypesForDialog
    staffOptionStates <- buildRosterShiftDialogStaffOptionStates (coerce rosterWeek.rosterGroupId) rosterWeek rosterSlot staffMembers
    respondHtmlProfiled $ renderRosterShiftDialog RosterShiftDialogData
        { rosterShiftDialogMode = EditRosterShiftDialog rosterSlot.id
        , rosterShiftDialogTitle = "Edit shift"
        , rosterShiftDialogStaff = staffMembers
        , rosterShiftDialogStaffOptionStates = staffOptionStates
        , rosterShiftDialogShiftTypes = shiftTypes
        , rosterShiftDialogValues = values
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

respondToRosterSlotMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> RosterDay -> Int -> LiveMutationResult RosterSlotMutationResult -> Maybe UUID.UUID -> Text -> IO ()
respondToRosterSlotMutation rosterGroupId rosterWeek rosterDay rowIndex mutationResult maybeStaffId successMessage = do
    layoutMode <- fetchCurrentRosterLayoutMode
    let maybeStaffParam = tshow <$> maybeStaffId
    let actorFragmentCandidates =
            case rosterLayoutModeValue layoutMode of
                "day_columns" -> rosterGridInnerAndStaffPanelFragments
                _ -> rosterGridInnerAndStaffPanelFragments
                    <> actorRosterRowFragments maybeStaffParam [(unpackId rosterDay.id, rowIndex)]
                    <> assignmentRefreshFragments maybeStaffParam
    let actorFragments =
            rosterActorFragmentsForTouchedResources
                rosterGroupId
                rosterWeek.weekOffset
                mutationResult.liveMutationTouchedResources
                actorFragmentCandidates
    if isHtmxRequest
        then respondWithRosterActorRefreshWithSuccess rosterGroupId rosterWeek.weekOffset actorFragments successMessage
        else do
            setSuccessMessage successMessage
            redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)

respondToRosterSlotMove :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> LiveMutationResult RosterSlotMutationResult -> Maybe UUID.UUID -> [(UUID.UUID, Int)] -> Bool -> IO ()
respondToRosterSlotMove rosterGroupId rosterWeek mutationResult maybeStaffId impactedRowKeys shouldWarnSourceTimesheetUnchanged = do
    layoutMode <- fetchCurrentRosterLayoutMode
    let maybeStaffParam = tshow <$> maybeStaffId
    let actorFragmentCandidates =
            case rosterLayoutModeValue layoutMode of
                "day_columns" -> rosterGridInnerAndStaffPanelFragments
                _ -> rosterGridInnerAndStaffPanelFragments
                    <> actorRosterRowFragments maybeStaffParam impactedRowKeys
                    <> assignmentRefreshFragments maybeStaffParam
    let actorFragments =
            rosterActorFragmentsForTouchedResources
                rosterGroupId
                rosterWeek.weekOffset
                mutationResult.liveMutationTouchedResources
                actorFragmentCandidates
    let warningHtml =
            if shouldWarnSourceTimesheetUnchanged
                then renderToastOob ToastBottomCenter (errorToast "A pending timesheet already exists for this roster slot, so the timesheet was not changed. Edit the timesheet entry directly.")
                else mempty
    respondWithRosterActorFragments
        rosterGroupId
        rosterWeek.weekOffset
        actorFragments
        (clearDialogOverlayOob <> renderToastOob ToastBottomCenter (successToast "Roster shift moved.") <> warningHtml)

respondToRosterSlotUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> LiveMutationResult RosterSlotMutationResult -> Maybe UUID.UUID -> [(UUID.UUID, Int)] -> Bool -> IO ()
respondToRosterSlotUpdate rosterGroupId rosterWeek mutationResult maybeStaffId impactedRowKeys shouldWarnSourceTimesheetUnchanged = do
    layoutMode <- fetchCurrentRosterLayoutMode
    let maybeStaffParam = tshow <$> maybeStaffId
    let actorFragmentCandidates =
            case rosterLayoutModeValue layoutMode of
                "day_columns" -> rosterGridInnerAndStaffPanelFragments
                _ -> rosterGridInnerAndStaffPanelFragments
                    <> actorRosterRowFragments maybeStaffParam impactedRowKeys
                    <> assignmentRefreshFragments maybeStaffParam
    let actorFragments =
            rosterActorFragmentsForTouchedResources
                rosterGroupId
                rosterWeek.weekOffset
                mutationResult.liveMutationTouchedResources
                actorFragmentCandidates
    respondWithRosterActorRefreshWithToast
        rosterGroupId
        rosterWeek.weekOffset
        actorFragments
        ( if shouldWarnSourceTimesheetUnchanged
            then Just "A pending timesheet already exists for this roster slot, so the timesheet was not changed. Edit the timesheet entry directly."
            else Nothing
        )

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

respondWithRemoveRosterRowConfirmation :: (?context :: ControllerContext, ?request :: Request) => RosterDay -> RemoveRosterRowPackingPreview -> IO ()
respondWithRemoveRosterRowConfirmation rosterDay preview =
    if isHtmxRequest
        then respondHtmlProfiled [hsx|
            <div id={dialogOverlayMountId} hx-swap-oob="innerHTML">
                {confirmationDialog}
                <form id={confirmFormId}
                      method="POST"
                      action={RemoveRosterRowAction rosterDay.id}
                      data-disable-javascript-submission="true"
                      hx-post={RemoveRosterRowAction rosterDay.id}
                      hx-target={"#" <> dialogOverlayMountId}
                      hx-swap="innerHTML"
                      hx-push-url="false"
                      hx-sync={"#" <> rosterWeekShellId <> ":replace"}>
                    <input type="hidden" name="confirmDeletePopulatedRow" value="true" />
                </form>
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

respondWithRosterRows :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> [(UUID.UUID, Int)] -> IO ()
respondWithRosterRows rosterGroupId weekOffset requestedRowKeys =
    respondWithRosterPatches rosterGroupId weekOffset requestedRowKeys False

rosterActorFragmentsForTouchedResources :: (?context :: ControllerContext) => Id RosterGroup -> Int -> Set.Set LiveResource -> [RosterProjectionFragment] -> [RosterProjectionFragment]
rosterActorFragmentsForTouchedResources rosterGroupId weekOffset =
    typedLiveSurfaceAffectedFragments
        rosterLiveSurfaceDefinition
        (buildRosterProjectionScope rosterGroupId weekOffset)

respondWithRosterActorRefresh :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> [RosterProjectionFragment] -> IO ()
respondWithRosterActorRefresh rosterGroupId weekOffset fragments =
    respondWithRosterActorRefreshWithToast rosterGroupId weekOffset fragments Nothing

respondWithRosterActorRefreshWithToast :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> [RosterProjectionFragment] -> Maybe Text -> IO ()
respondWithRosterActorRefreshWithToast rosterGroupId weekOffset fragments maybeWarningMessage =
    respondWithRosterActorFragments
        rosterGroupId
        weekOffset
        fragments
        (clearDialogOverlayOob <> maybe mempty (renderToastOob ToastBottomCenter . errorToast) maybeWarningMessage)

respondWithRosterActorRefreshWithSuccess :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> [RosterProjectionFragment] -> Text -> IO ()
respondWithRosterActorRefreshWithSuccess rosterGroupId weekOffset fragments successMessage =
    respondWithRosterActorFragments
        rosterGroupId
        weekOffset
        fragments
        (clearDialogOverlayOob <> renderToastOob ToastBottomCenter (successToast successMessage))

respondWithRosterActorFragments :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> [RosterProjectionFragment] -> Blaze.Html -> IO ()
respondWithRosterActorFragments rosterGroupId weekOffset fragments extraHtml =
    respondWithTypedLiveSurfaceFragments
        rosterProjectionDefinition
        (buildRosterProjectionScope rosterGroupId weekOffset)
        fragments
        extraHtml
        renderRosterProjectionFragmentWithMode

clearDialogOverlayOob :: Blaze.Html
clearDialogOverlayOob = [hsx|<div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>|]

respondWithActorRosterFragmentRefresh :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> [RosterProjectionFragment] -> IO ()
respondWithActorRosterFragmentRefresh rosterGroupId weekOffset fragments =
    respondWithRosterActorFragments rosterGroupId weekOffset fragments mempty

respondWithRosterPatches :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> [(UUID.UUID, Int)] -> Bool -> IO ()
respondWithRosterPatches rosterGroupId weekOffset requestedRowKeys shouldRefreshStaffPanel = do
    rosterData <- fetchVisibleRosterReadModel rosterGroupId weekOffset
    case rosterData of
        Nothing -> respondHtmlProfiled [hsx||]
        Just RosterRenderData { rosterDays, weekStartDate, assignmentFilters, staffMembers, panelStaff, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled } -> do
            let uniqueRowKeys = nub requestedRowKeys
            let renderedRows = mapMaybe (renderRequestedRow weekStartDate orderedSlotNames assignmentFilters staffMembers shiftTypes renderIndexes rosterLayoutMode rosterEndTimesEnabled) uniqueRowKeys
            rosterGroups <- fetchCurrentVenueRosterGroups
            let renderedStaffPanel = [renderRosterStaffPanelFragmentOob weekOffset rosterGroupId (length rosterGroups > 1) RosterStaffPanelCurrentGroup panelStaff | shouldRefreshStaffPanel]
            respondHtmlProfiled (mconcat (renderedRows <> renderedStaffPanel))

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
        profileActionSpan "roster.page.keep_projection_hot" (keepCurrentRosterWeekProjectionHot currentRosterGroup.id weekOffset)
        rosterDataOrNothing <- profileActionSpan "roster.page.fetch_read_model" (fetchVisibleRosterReadModel currentRosterGroup.id weekOffset)
        passkeySetupPrompt <- profileActionSpan "roster.page.passkey_prompt" passkeySetupPromptFromSession

        case rosterDataOrNothing of
            Just RosterRenderData { rosterWeek, rosterDays, assignmentFilters, staffMembers, panelStaff, staffSelfServicePanel, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled, rosterWagePrediction, showWageEstimates, showRosterWarnings, rosterPublicHolidays } ->
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
                                , liveUpdateScope = Just (RosterWeekScope { venueId = unpackId currentVenueId, rosterGroupId = unpackId currentRosterGroup.id, weekOffset })
                                , viewCapabilities = buildRosterViewCapabilities visibleRosterWeek
                                , rosterLayoutMode
                                , rosterEndTimesEnabled
                                , rosterWagePrediction
                                , showWageEstimates
                                , showRosterWarnings
                                , publicHolidays = rosterPublicHolidays
                                , passkeySetupPrompt
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

validateRosterWeekCanGoLive :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterWeek -> Bool -> IO (Maybe Text)
validateRosterWeekCanGoLive _ False = pure Nothing
validateRosterWeekCanGoLive rosterWeek True = do
    rosterDays <- query @RosterDay
        |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
        |> fetch
    rosterSlots <-
        if null rosterDays
            then pure []
            else query @RosterSlot
                |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) rosterDays)
                |> filterWhere (#deletedAt, Nothing)
                |> fetch
    let blockingSlots = filter rosterSlotBlocksPublish rosterSlots
    pure
        if null blockingSlots
            then Nothing
            else Just publishRequiredFieldsMessage

publishRequiredFieldsMessage :: Text
publishRequiredFieldsMessage = "Roster week cannot go live until every staffed shift has a start time, valid end time, and shift type."

rosterSlotBlocksPublish :: RosterSlot -> Bool
rosterSlotBlocksPublish slot =
    isJust slot.staffId
        && ( isNothing slot.startTime
             || isNothing slot.shiftTypeId
             || not (rosterSlotHasValidStartEnd slot)
           )

rosterSlotHasValidStartEnd :: RosterSlot -> Bool
rosterSlotHasValidStartEnd slot =
    case (slot.startTime, slot.endTime) of
        (Just startTime, Just endTime) -> isValidRosterShiftTimePair startTime endTime
        _ -> False

ensureRosterSlotTimingValidForSave :: (?context :: ControllerContext, ?request :: Request) => RosterWeek -> RosterSlot -> IO ()
ensureRosterSlotTimingValidForSave rosterWeek slot =
    case (slot.startTime, slot.endTime) of
        (Just startTime, Just endTime)
            | not (isValidRosterShiftTimePair startTime endTime) ->
                let rosterGroupId = coerce rosterWeek.rosterGroupId
                    errorMessage = invalidRosterSlotTimingMessage
                 in if isHtmxRequest
                        then respondWithRosterToast errorMessage "app-toast-error"
                        else do
                            setErrorMessage errorMessage
                            redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)
        _ -> pure ()

invalidRosterSlotTimingMessage :: Text
invalidRosterSlotTimingMessage = "Choose an end time after the start time within the 6:00 AM to 5:45 AM roster day."

rosterSlotTimesheetSourceChanged :: RosterSlot -> RosterSlot -> Bool
rosterSlotTimesheetSourceChanged previous next =
    previous.staffId /= next.staffId
        || previous.startTime /= next.startTime
        || previous.endTime /= next.endTime
        || previous.shiftTypeId /= next.shiftTypeId

applyRosterSlotDuration :: RosterSlot -> RosterSlot
applyRosterSlotDuration slot =
    case (slot.startTime, slot.endTime) of
        (Just startTime, Just endTime) ->
            slot |> set #durationMinutes (validRosterShiftDurationMinutes startTime endTime)
        _ ->
            slot |> set #durationMinutes Nothing

ensureOptionalShiftTypeInCurrentVenue :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe UUID.UUID -> IO ()
ensureOptionalShiftTypeInCurrentVenue Nothing = pure ()
ensureOptionalShiftTypeInCurrentVenue (Just shiftTypeId) = do
    exists <-
        query @ShiftType
            |> filterWhere (#id, Id shiftTypeId)
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#archivedAt, Nothing)
            |> fetchExists
    accessDeniedUnless exists

ensureRosterWeekIsDraftForEdit :: (?context :: ControllerContext, ?request :: Request) => RosterWeek -> IO ()
ensureRosterWeekIsDraftForEdit rosterWeek =
    when rosterWeek.isLive do
        let rosterGroupId = coerce rosterWeek.rosterGroupId
        let targetPath = rosterWeekUrl rosterWeek.weekOffset rosterGroupId
        let errorMessage = "Live roster weeks are read-only. Move it back to draft to make changes."
        if isHtmxRequest
            then respondWithRosterToast errorMessage "app-toast-error"
            else do
                setErrorMessage errorMessage
                redirectToPath targetPath

rosterStaffPanelScopeFromParams :: (?request :: Request) => RosterStaffPanelScope
rosterStaffPanelScopeFromParams =
    case Text.toLower (paramOrDefault @Text "group" "staffScope") of
        "all" -> RosterStaffPanelAllVenue
        _     -> RosterStaffPanelCurrentGroup

normalizeRosterSlotDefinitionName :: Text -> Either Text Text
normalizeRosterSlotDefinitionName submittedName =
    let normalized = Text.strip submittedName
     in if Text.null normalized
            then Left "Roster column name is required."
            else
                if Text.length normalized > 120
                    then Left "Roster column name must be 120 characters or fewer."
                    else Right normalized

resolveRosterSlotDefinitionNameForCreate :: (?modelContext :: ModelContext, ?request :: Request) => RosterWeek -> IO (Either Text Text)
resolveRosterSlotDefinitionNameForCreate rosterWeek =
    case Text.strip (paramOrDefault @Text "" "name") of
        "" -> Right <$> nextDefaultRosterSlotDefinitionName rosterWeek
        submittedName -> pure (normalizeRosterSlotDefinitionName submittedName)

nextDefaultRosterSlotDefinitionName :: (?modelContext :: ModelContext) => RosterWeek -> IO Text
nextDefaultRosterSlotDefinitionName rosterWeek = do
    activeDefinitions <- query @RosterWeekSlotDefinition
        |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
        |> filterWhere (#deletedAt, Nothing)
        |> fetch
    let existingNames = map (.name) activeDefinitions
    pure (firstAvailableDefaultName existingNames)

firstAvailableDefaultName :: [Text] -> Text
firstAvailableDefaultName existingNames =
    fromMaybe "New column" (head (filter (`notElem` existingNames) candidateNames))
  where
    candidateNames =
        "New column" : map (\index -> "New column " <> tshow index) [2 :: Int ..]

activeRosterWeekSlotDefinitionWithName :: (?modelContext :: ModelContext) => RosterWeek -> Text -> Maybe (Id RosterWeekSlotDefinition) -> IO (Maybe RosterWeekSlotDefinition)
activeRosterWeekSlotDefinitionWithName rosterWeek slotName maybeExceptId = do
    matches <- query @RosterWeekSlotDefinition
        |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
        |> filterWhere (#name, slotName)
        |> filterWhere (#deletedAt, Nothing)
        |> fetch
    pure (find (\slotDefinition -> Just slotDefinition.id /= maybeExceptId) matches)

respondToRosterSlotDefinitionError :: (?context :: ControllerContext, ?request :: Request) => RosterWeek -> Text -> IO ()
respondToRosterSlotDefinitionError rosterWeek errorMessage =
    if isHtmxRequest
        then respondWithRosterToast errorMessage "app-toast-error"
        else do
            setErrorMessage errorMessage
            redirectToPath (rosterWeekUrl rosterWeek.weekOffset (coerce rosterWeek.rosterGroupId :: Id RosterGroup))

respondToRosterSlotDefinitionSuccess :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWeek -> Text -> IO ()
respondToRosterSlotDefinitionSuccess rosterWeek successMessage =
    if isHtmxRequest
        then
            respondWithActorRosterFragmentRefresh
                rosterGroupId
                rosterWeek.weekOffset
                rosterGridFrameAndStaffPanelFragments
        else do
            setSuccessMessage successMessage
            redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)
    where
        rosterGroupId = coerce rosterWeek.rosterGroupId
