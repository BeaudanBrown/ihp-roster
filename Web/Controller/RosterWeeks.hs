{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Web.Controller.RosterWeeks where

import Application.Helper.Controller
import Application.Helper.LiveSurface (serveTypedLiveFragment,
                                       setTypedLiveSurfaceActorRefresh,
                                       typedLiveSurfaceAffectedFragments)
import Application.Helper.LiveUpdate (LiveUpdateScope (..))
import Application.Helper.Profiling
import Application.Helper.RosterGroups
import Application.Helper.UserPreferences
import Application.Helper.View (DialogOverlayConfig (..), OverlayButton (..),
                                OverlayButtonAction (..),
                                ToastOverlayPosition (ToastBottomCenter),
                                dialogOverlayMountId, errorToast,
                                renderDialogOverlay, renderToastOob)
import Application.Helper.LiveResource (LiveMutationResult (..), LiveResource)
import Data.Coerce (coerce)
import Data.List (nub)
import qualified Data.Set as Set
import Data.Maybe (catMaybes, fromMaybe, isJust, mapMaybe)
import qualified Data.Text as Text
import Data.Time (getCurrentTime, utctDay)
import qualified Data.Time.Calendar as Calendar
import qualified Data.UUID as UUID
import qualified Text.Blaze.Html as Blaze
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
                                  respondWithRosterToast)
import Web.RosterWeeks.Rows
import Web.RosterWeeks.Service
import Web.RosterWeeks.Types
import Web.View.RosterWeeks.Overview (renderWeekOverviewPanelFragment)
import Web.View.RosterWeeks.Show (renderRosterWeekShell)
import Web.View.RosterWeeks.StaffPanel (renderRosterStaffPanelFragment,
                                        renderRosterStaffPanelFragmentOob)

instance Controller RosterWeeksController where
    beforeAction = do
        ensureIsUser
        ensureCurrentVenueOrSupportRedirect
        ensureProfileCompleted

    action RosterWeeksAction = do
        -- Redirect to the current week's offset based on today's date
        currentWeekOffset <- fetchCurrentRosterWeekOffset
        currentRosterGroup <- resolveRequestedRosterGroup
        let currentWeekPath = rosterWeekUrl currentWeekOffset currentRosterGroup.id

        if isHtmxRequest
            then do
                setHtmxPushUrl currentWeekPath
                renderRosterWeekPage currentWeekOffset currentRosterGroup.id
            else redirectToPath currentWeekPath

    action ShowRosterWeekAction { weekOffset } = do
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

    action ShowRosterWeekOverviewFragmentAction { weekOffset } = do
        rosterGroup <- resolveRequestedRosterGroup
        respondHtmlProfiled =<< renderRosterWeekOverviewFragment weekOffset rosterGroup.id

    action ShowRosterWeekContentFragmentAction { weekOffset } = do
        rosterGroup <- resolveRequestedRosterGroup
        serveTypedLiveFragment rosterLiveSurfaceDefinition (buildRosterProjectionScope rosterGroup.id weekOffset) RosterProjectionContent \_ ->
            respondWithRosterContent rosterGroup.id weekOffset

    action ShowRosterWeekStaffPanelFragmentAction { weekOffset } = do
        rosterGroup <- resolveRequestedRosterGroup
        let panelScope = rosterStaffPanelScopeFromParams
        serveTypedLiveFragment rosterLiveSurfaceDefinition (buildRosterProjectionScope rosterGroup.id weekOffset) RosterProjectionStaffPanel \_ -> do
            panelStaff <- fetchVisibleRosterStaffPanelEntries panelScope rosterGroup.id weekOffset
            respondHtmlProfiled $
                maybe mempty (renderRosterStaffPanelFragment weekOffset rosterGroup.id panelScope) panelStaff

    action ShowRosterWeekDaySectionFragmentAction { weekOffset, rosterDayId } = do
        rosterGroupId <- resolveRosterGroupIdForFragmentRosterDay weekOffset rosterDayId
        serveTypedLiveFragment rosterLiveSurfaceDefinition (buildRosterProjectionScope rosterGroupId weekOffset) (RosterProjectionDaySection (coerce rosterDayId)) \_ -> do
            daySectionHtml <- fetchVisibleRosterDaySectionFragment rosterGroupId weekOffset rosterDayId
            respondHtmlProfiled (fromMaybe mempty daySectionHtml)

    action ShowRosterWeekRowFragmentAction { weekOffset, rosterDayId, rowIndex } = do
        rosterGroupId <- resolveRosterGroupIdForFragmentRosterDay weekOffset rosterDayId
        serveTypedLiveFragment rosterLiveSurfaceDefinition (buildRosterProjectionScope rosterGroupId weekOffset) (RosterProjectionRow (coerce rosterDayId) rowIndex) \_ -> do
            rowHtml <- fetchVisibleRosterRowFragment rosterGroupId weekOffset rosterDayId rowIndex
            respondHtmlProfiled (fromMaybe mempty rowHtml)

    action UpdateRosterAssignmentFiltersAction { weekOffset } = do
        ensureManagerRole
        rosterGroup <- resolveRequestedRosterGroup
        setRosterAssignmentFiltersSession rosterAssignmentFiltersFromParams
        respondWithRosterContent rosterGroup.id weekOffset

    action CreateRosterWeekAction { weekOffset } = do
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

    action CopyRosterWeekAction { sourceWeekOffset, targetWeekOffset } = do
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

    action ToggleRosterWeekLiveStatusAction { rosterWeekId } = do
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

    action CreateRosterWeekSlotDefinitionAction { rosterWeekId } = do
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

    action UpdateRosterWeekSlotDefinitionAction { rosterWeekSlotDefinitionId } = do
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

    action DeleteRosterWeekSlotDefinitionAction { rosterWeekSlotDefinitionId } = do
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

    action SortRosterWeekAction { rosterWeekId } = do
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
                    rosterContentAndStaffPanelFragments
            else do
                setSuccessMessage "Roster sorted."
                redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)

    action ToggleRosterDayClosedAction { rosterDayId } = do
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
                    rosterContentAndStaffPanelFragments
            else do
                setSuccessMessage successMessage
                redirectToPath targetPath

    action AddRosterRowAction { rosterDayId } = do
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
                            rosterContentAndStaffPanelFragments
                    else do
                        setSuccessMessage "Roster row added."
                        redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)

    action RemoveRosterRowAction { rosterDayId } = do
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
                            rosterContentAndStaffPanelFragments
                    else do
                        setSuccessMessage "Roster row removed."
                        redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)

    action UpdateRosterLayoutPreferenceAction { weekOffset } = do
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
                    then respondWithRosterContent rosterGroup.id weekOffset
                    else do
                        setSuccessMessage "Roster layout preference saved."
                        redirectToPath (rosterWeekUrl weekOffset rosterGroup.id)

    action UpdateRosterWageEstimatePreferenceAction { weekOffset } = do
        accessDeniedUnless (hasRole VenueAdminRole)
        rosterGroup <- resolveRequestedRosterGroup
        venueConfig <- fetchVenueConfig
        if venueConfig.rosterEndTimesEnabled
            then do
                let showWageEstimates = paramOrDefault @Text "false" "showWageEstimates" == "true"
                _ <- upsertCurrentUserShowWageEstimates showWageEstimates
                if isHtmxRequest
                    then respondWithRosterContent rosterGroup.id weekOffset
                    else do
                        setSuccessMessage "Roster wage estimate preference saved."
                        redirectToPath (rosterWeekUrl weekOffset rosterGroup.id)
            else
                if isHtmxRequest
                    then respondWithRosterContent rosterGroup.id weekOffset
                    else do
                        setErrorMessage "Enable roster end times before showing wage estimates."
                        redirectToPath (rosterWeekUrl weekOffset rosterGroup.id)

    action CreateRosterSlotAction { rosterDayId, rosterWeekSlotDefinitionId, rowIndex } = do
        ensureManagerRole
        ensureVenueWritable

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

        let maybeStaffParam = paramOrNothing @Text "staffId"
        let maybeStartTimeParam = paramOrNothing @Text "startTime"
        let maybeEndTimeParam = paramOrNothing @Text "endTime"
        let maybeShiftTypeParam = paramOrNothing @Text "shiftTypeId"
        let rosterGroupId = coerce rosterWeek.rosterGroupId
        existingSlot <- query @RosterSlot
            |> filterWhere (#rosterDayId, unpackId rosterDay.id)
            |> filterWhere (#rosterWeekSlotDefinitionId, unpackId slotDefinition.id)
            |> filterWhere (#rowIndex, rowIndex)
            |> filterWhere (#deletedAt, Nothing)
            |> fetchOneOrNothing
        let baseSlot =
                fromMaybe
                    ( newRecord @RosterSlot
                    |> set #rosterDayId (unpackId rosterDay.id)
                    |> set #rosterWeekSlotDefinitionId (unpackId slotDefinition.id)
                    |> set #slotSortOrder slotDefinition.sortOrder
                    |> set #rowIndex rowIndex
                    )
                    existingSlot
        let newSlot =
                baseSlot
                    |> applyOptionalField #staffId (parseOptionalStaffId maybeStaffParam) maybeStaffParam
                    |> applyOptionalField #startTime (parseOptionalTime maybeStartTimeParam) maybeStartTimeParam
                    |> applyOptionalField #endTime (parseOptionalTime maybeEndTimeParam) maybeEndTimeParam
                    |> applyOptionalField #shiftTypeId (parseOptionalShiftTypeId maybeShiftTypeParam) maybeShiftTypeParam
                    |> applyRosterSlotDuration

        ensureOptionalStaffInCurrentVenue newSlot.staffId
        ensureOptionalShiftTypeInCurrentVenue newSlot.shiftTypeId
        isEligibleForAssignment <-
            case newSlot.staffId of
                Nothing -> pure True
                Just staffId -> staffIsEligibleForRosterGroup (Id staffId) rosterGroupId

        if not isEligibleForAssignment
            then do
                let errorMessage = "That staff member is not applicable to this roster group."
                if isHtmxRequest
                    then respondWithRosterToast errorMessage "app-toast-error"
                    else do
                        setErrorMessage errorMessage
                        redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)
            else do
                mutationResult <- saveRosterSlotMutation rosterGroupId rosterWeek rosterDay existingSlot newSlot
                let RosterSlotMutationResult { rosterSlotMutationSlot = createdSlot } = mutationResult.liveMutationValue
                layoutMode <- fetchCurrentRosterLayoutMode
                let actorFragmentCandidates =
                        case rosterLayoutModeValue layoutMode of
                            "day_columns" ->
                                rosterContentAndStaffPanelFragments
                            _ ->
                                rosterContentAndStaffPanelFragments
                                    <> maybe
                                        [rosterRowFragment (unpackId rosterDay.id) rowIndex]
                                        (\slot ->
                                            actorRosterRowFragments maybeStaffParam [(slot.rosterDayId, slot.rowIndex)]
                                                <> assignmentRefreshFragments maybeStaffParam
                                        )
                                        createdSlot
                let actorFragments =
                        rosterActorFragmentsForTouchedResources
                            rosterGroupId
                            rosterWeek.weekOffset
                            mutationResult.liveMutationTouchedResources
                            actorFragmentCandidates
                if isHtmxRequest
                    then respondWithRosterActorRefresh rosterGroupId rosterWeek.weekOffset actorFragments
                    else do
                        setSuccessMessage "Roster slot updated."
                        redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)

    action UpdateRosterSlotAction { rosterSlotId } = do
        ensureManagerRole
        ensureVenueWritable

        rosterSlot <- fetch rosterSlotId
        accessDeniedUnless (isNothing rosterSlot.deletedAt)
        let rosterDayId = (coerce rosterSlot.rosterDayId :: Id RosterDay)
        rosterDay <- fetch rosterDayId
        let rosterWeekId = (coerce rosterDay.rosterWeekId :: Id RosterWeek)
        rosterWeek <- fetch rosterWeekId
        ensureRecordInCurrentVenue rosterWeek.venueId
        ensureRosterWeekIsDraftForEdit rosterWeek

        let maybeStaffParam = paramOrNothing @Text "staffId"
        let maybeStartTimeParam = paramOrNothing @Text "startTime"
        let maybeEndTimeParam = paramOrNothing @Text "endTime"
        let maybeShiftTypeParam = paramOrNothing @Text "shiftTypeId"
        let rosterGroupId = coerce rosterWeek.rosterGroupId
        let updatedSlot =
                rosterSlot
                    |> applyOptionalField #staffId (parseOptionalStaffId maybeStaffParam) maybeStaffParam
                    |> applyOptionalField #startTime (parseOptionalTime maybeStartTimeParam) maybeStartTimeParam
                    |> applyOptionalField #endTime (parseOptionalTime maybeEndTimeParam) maybeEndTimeParam
                    |> applyOptionalField #shiftTypeId (parseOptionalShiftTypeId maybeShiftTypeParam) maybeShiftTypeParam
                    |> applyRosterSlotDuration

        ensureOptionalStaffInCurrentVenue updatedSlot.staffId
        ensureOptionalShiftTypeInCurrentVenue updatedSlot.shiftTypeId
        isEligibleForAssignment <-
            case updatedSlot.staffId of
                Nothing -> pure True
                Just staffId -> staffIsEligibleForRosterGroup (Id staffId) rosterGroupId

        if not isEligibleForAssignment
            then do
                let errorMessage = "That staff member is not applicable to this roster group."
                if isHtmxRequest
                    then respondWithRosterToast errorMessage "app-toast-error"
                    else do
                        setErrorMessage errorMessage
                        redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)
            else do
                mutationResult <- updateRosterSlotMutation rosterGroupId rosterWeek rosterDay rosterSlot updatedSlot
                let RosterSlotMutationResult { rosterSlotMutationPreviousStaffId = previousStaffId, rosterSlotMutationShouldWarnSourceTimesheetUnchanged = shouldWarnSourceTimesheetUnchanged } = mutationResult.liveMutationValue

                relatedSlots <- fetchRelatedSlotsForStaffIdsInRosterWeek rosterWeek (catMaybes [previousStaffId, updatedSlot.staffId])
                let impactedRowKeys = impactedRowKeysForSlotUpdate previousStaffId updatedSlot relatedSlots
                layoutMode <- fetchCurrentRosterLayoutMode
                let actorFragmentCandidates =
                        case rosterLayoutModeValue layoutMode of
                            "day_columns" ->
                                rosterContentAndStaffPanelFragments
                            _ ->
                                rosterContentAndStaffPanelFragments
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
rosterActorFragmentsForTouchedResources rosterGroupId weekOffset touchedResources =
    typedLiveSurfaceAffectedFragments
        rosterLiveSurfaceDefinition
        (buildRosterProjectionScope rosterGroupId weekOffset)
        touchedResources

respondWithRosterActorRefresh :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> [RosterProjectionFragment] -> IO ()
respondWithRosterActorRefresh rosterGroupId weekOffset fragments =
    respondWithRosterActorRefreshWithToast rosterGroupId weekOffset fragments Nothing

respondWithRosterActorRefreshWithToast :: (?context :: ControllerContext, ?request :: Request) => Id RosterGroup -> Int -> [RosterProjectionFragment] -> Maybe Text -> IO ()
respondWithRosterActorRefreshWithToast rosterGroupId weekOffset fragments maybeWarningMessage = do
    setTypedLiveSurfaceActorRefresh rosterLiveSurfaceDefinition (buildRosterProjectionScope rosterGroupId weekOffset) fragments
    respondHtmlProfiled $
        maybe mempty (renderToastOob ToastBottomCenter . errorToast) maybeWarningMessage

respondWithActorRosterFragmentRefresh :: (?context :: ControllerContext, ?request :: Request) => Id RosterGroup -> Int -> [RosterProjectionFragment] -> IO ()
respondWithActorRosterFragmentRefresh rosterGroupId weekOffset fragments = do
    setTypedLiveSurfaceActorRefresh rosterLiveSurfaceDefinition (buildRosterProjectionScope rosterGroupId weekOffset) fragments
    respondHtmlProfiled mempty

respondWithRosterPatches :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> [(UUID.UUID, Int)] -> Bool -> IO ()
respondWithRosterPatches rosterGroupId weekOffset requestedRowKeys shouldRefreshStaffPanel = do
    rosterData <- fetchVisibleRosterReadModel rosterGroupId weekOffset
    case rosterData of
        Nothing -> respondHtmlProfiled [hsx||]
        Just RosterRenderData { rosterDays, weekStartDate, assignmentFilters, staffMembers, staffOptionStates, panelStaff, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled } -> do
            let uniqueRowKeys = nub requestedRowKeys
            let renderedRows = mapMaybe (renderRequestedRow weekStartDate orderedSlotNames assignmentFilters staffMembers staffOptionStates shiftTypes renderIndexes rosterLayoutMode rosterEndTimesEnabled) uniqueRowKeys
            let renderedStaffPanel = [renderRosterStaffPanelFragmentOob weekOffset rosterGroupId RosterStaffPanelCurrentGroup panelStaff | shouldRefreshStaffPanel]
            respondHtmlProfiled (mconcat (renderedRows <> renderedStaffPanel))

renderRosterWeekPage :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => Int -> Id RosterGroup -> IO ()
renderRosterWeekPage weekOffset requestedRosterGroupId = do
    venueConfig <- fetchVenueConfig
    let weekStartDate = venueWeekStartDate venueConfig weekOffset
    let weekEndDate = Calendar.addDays 6 weekStartDate
    setTitle "Roster"
    rosterGroups <- fetchCurrentVenueRosterGroups
    currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (Just requestedRosterGroupId)
    _ <- ensureRosterWeekExists currentRosterGroup.id weekOffset
    keepCurrentRosterWeekProjectionHot currentRosterGroup.id weekOffset
    rosterDataOrNothing <- fetchVisibleRosterReadModel currentRosterGroup.id weekOffset
    passkeySetupPrompt <- passkeySetupPromptFromSession

    case rosterDataOrNothing of
        Just RosterRenderData { rosterWeek, rosterDays, assignmentFilters, staffMembers, staffOptionStates, panelStaff, staffSelfServicePanel, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled, rosterWagePrediction, showWageEstimates } ->
            let visibleRosterWeek =
                    if rosterWeek.isLive || hasRole ManagerRole'
                        then Just rosterWeek
                        else Nothing
             in respondWithRosterWeekView
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
                        , staffOptionStates
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
                        , passkeySetupPrompt
                        }
        Nothing ->
            error "Roster week should exist after ensureRosterWeekExists"

respondWithRosterWeekView :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => ShowView -> IO ()
respondWithRosterWeekView showView =
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
    venueConfig <- fetchVenueConfig
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
    let blockingSlots = filter (rosterSlotBlocksPublish venueConfig.rosterEndTimesEnabled) rosterSlots
    pure
        if null blockingSlots
            then Nothing
            else Just (publishRequiredFieldsMessage venueConfig.rosterEndTimesEnabled)

publishRequiredFieldsMessage :: Bool -> Text
publishRequiredFieldsMessage True = "Roster week cannot go live until every staffed shift has a start time, end time, and shift type."
publishRequiredFieldsMessage False = "Roster week cannot go live until every staffed shift has a start time and shift type."

rosterSlotBlocksPublish :: Bool -> RosterSlot -> Bool
rosterSlotBlocksPublish endTimesEnabled slot =
    isJust slot.staffId
        && ( isNothing slot.startTime
             || isNothing slot.shiftTypeId
             || ( endTimesEnabled
                    && (isNothing slot.endTime || maybe True (<= 0) slot.durationMinutes)
                )
           )

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
            slot |> set #durationMinutes (Just (shiftDurationMinutes startTime endTime))
        _ ->
            slot

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

respondToRosterSlotDefinitionSuccess :: (?context :: ControllerContext, ?request :: Request) => RosterWeek -> Text -> IO ()
respondToRosterSlotDefinitionSuccess rosterWeek successMessage =
    if isHtmxRequest
        then
            respondWithActorRosterFragmentRefresh
                rosterGroupId
                rosterWeek.weekOffset
                rosterContentAndStaffPanelFragments
        else do
            setSuccessMessage successMessage
            redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)
    where
        rosterGroupId = coerce rosterWeek.rosterGroupId
