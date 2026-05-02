{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Web.Controller.RosterWeeks where

import Application.Helper.Controller
import Application.Helper.LiveUpdate (LiveFragmentRef, LiveUpdateScope (..),
                                      liveFragmentsRefreshTriggerPayload)
import Application.Helper.Profiling
import Application.Helper.RosterGroups
import Application.Helper.UserPreferences
import Application.Helper.View (ToastOverlayPosition (ToastBottomCenter),
                                errorToast, renderToastOob)
import Application.RosterTimesheets.Automation (enqueueRosterTimesheetCreationJobsForWeek,
                                                rosterSlotHasGeneratedTimesheet)
import qualified Data.Aeson as Aeson
import Data.Coerce (coerce)
import Data.List (nub)
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
import Web.RosterWeeks.LiveUpdates (broadcastRosterWeekInvalidation)
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
        respondWithRosterContent rosterGroup.id weekOffset

    action ShowRosterWeekStaffPanelFragmentAction { weekOffset } = do
        rosterGroup <- resolveRequestedRosterGroup
        panelStaff <- fetchVisibleRosterStaffPanelEntries rosterGroup.id weekOffset
        respondHtmlProfiled $
            maybe mempty (renderRosterStaffPanelFragment weekOffset rosterGroup.id) panelStaff

    action ShowRosterWeekDaySectionFragmentAction { weekOffset, rosterDayId } = do
        rosterGroupId <- resolveRosterGroupIdForFragmentRosterDay weekOffset rosterDayId
        daySectionHtml <- fetchVisibleRosterDaySectionFragment rosterGroupId weekOffset rosterDayId
        respondHtmlProfiled (fromMaybe mempty daySectionHtml)

    action ShowRosterWeekRowFragmentAction { weekOffset, rosterDayId, rowIndex } = do
        rosterGroupId <- resolveRosterGroupIdForFragmentRosterDay weekOffset rosterDayId
        rowHtml <- fetchVisibleRosterRowFragment rosterGroupId weekOffset rosterDayId rowIndex
        respondHtmlProfiled (fromMaybe mempty rowHtml)

    action UpdateRosterAssignmentFiltersAction { weekOffset } = do
        ensureManagerRole
        rosterGroup <- resolveRequestedRosterGroup
        setRosterAssignmentFiltersSession rosterAssignmentFiltersFromParams
        respondWithRosterContent rosterGroup.id weekOffset

    action CreateRosterWeekAction { weekOffset } = do
        ensureManagerRole
        rosterGroup <- resolveRequestedRosterGroup
        (rosterWeek, wasCreated) <- ensureRosterWeekExists rosterGroup.id weekOffset

        when wasCreated do
            broadcastRosterWeekInvalidation
                rosterGroup.id
                weekOffset
                [buildRosterContentFragmentRef rosterGroup.id weekOffset]

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
                        withTransaction do
                            existingTarget <- query @RosterWeek
                                |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
                                |> filterWhere (#weekOffset, targetWeekOffset)
                                |> fetchOneOrNothing
                            case existingTarget of
                                Just targetWeek -> replaceRosterWeekFromSource sourceWeek targetWeek
                                Nothing -> copyRosterWeek sourceWeek targetWeekOffset

                        broadcastRosterWeekInvalidation
                            rosterGroup.id
                            targetWeekOffset
                            [buildRosterContentFragmentRef rosterGroup.id targetWeekOffset]
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
                updatedRosterWeek <- rosterWeek
                    |> set #isLive nextLiveStatus
                    |> updateRecord
                queuedTimesheetJobs <-
                    if nextLiveStatus
                        then enqueueRosterTimesheetCreationJobsForWeek (Just currentUser.id) updatedRosterWeek
                        else pure []

                broadcastRosterWeekInvalidation
                    rosterGroupId
                    rosterWeek.weekOffset
                    [buildRosterContentFragmentRef rosterGroupId rosterWeek.weekOffset]
                let successMessage =
                        if nextLiveStatus
                            then
                                if null queuedTimesheetJobs
                                    then "Roster week is now live."
                                    else "Roster week is now live. Pending timesheet jobs queued for " <> tshow (length queuedTimesheetJobs) <> " shifts."
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
                        withTransaction do
                            _ <- appendRosterWeekSlotDefinition rosterWeek slotName
                            pure ()
                        broadcastRosterWeekInvalidation
                            rosterGroupId
                            rosterWeek.weekOffset
                            [ buildRosterContentFragmentRef rosterGroupId rosterWeek.weekOffset
                            , buildRosterStaffPanelFragmentRef rosterGroupId rosterWeek.weekOffset
                            ]
                        respondToRosterSlotDefinitionSuccess rosterWeek "Roster column added."

    action UpdateRosterWeekSlotDefinitionAction { rosterWeekSlotDefinitionId } = do
        ensureManagerRole
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
                        _ <- slotDefinition
                            |> set #name slotName
                            |> updateRecord
                        broadcastRosterWeekInvalidation
                            rosterGroupId
                            rosterWeek.weekOffset
                            [buildRosterContentFragmentRef rosterGroupId rosterWeek.weekOffset]
                        respondToRosterSlotDefinitionSuccess rosterWeek "Roster column renamed."

    action DeleteRosterWeekSlotDefinitionAction { rosterWeekSlotDefinitionId } = do
        ensureManagerRole
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
                withTransaction do
                    deleteRosterWeekSlotDefinition slotDefinition
                broadcastRosterWeekInvalidation
                    rosterGroupId
                    rosterWeek.weekOffset
                    [ buildRosterContentFragmentRef rosterGroupId rosterWeek.weekOffset
                    , buildRosterStaffPanelFragmentRef rosterGroupId rosterWeek.weekOffset
                    ]
                respondToRosterSlotDefinitionSuccess rosterWeek "Roster column removed."

    action ToggleRosterDayClosedAction { rosterDayId } = do
        ensureManagerRole

        rosterDay <- fetch rosterDayId
        let rosterWeekId = (coerce rosterDay.rosterWeekId :: Id RosterWeek)
        rosterWeek <- fetch rosterWeekId
        ensureRecordInCurrentVenue rosterWeek.venueId
        ensureRosterWeekIsDraftForEdit rosterWeek

        let rosterGroupId = coerce rosterWeek.rosterGroupId
        let nextClosedState = not rosterDay.isClosed

        when nextClosedState do
            ensureRosterDayHasMinimumRows rosterDay rosterGroupId closedRosterDayRows

        _ <- rosterDay |> set #isClosed nextClosedState |> updateRecord

        broadcastRosterWeekInvalidation
            rosterGroupId
            rosterWeek.weekOffset
            [ buildRosterContentFragmentRef rosterGroupId rosterWeek.weekOffset
            , buildRosterStaffPanelFragmentRef rosterGroupId rosterWeek.weekOffset
            ]

        let successMessage =
                if nextClosedState
                    then "Roster day marked closed."
                    else "Roster day reopened."
        let targetPath = rosterWeekUrl rosterWeek.weekOffset rosterGroupId
        if isHtmxRequest
            then do
                setHtmxPushUrl targetPath
                respondWithActorRosterFragmentRefresh
                    [ buildRosterContentFragmentRef rosterGroupId rosterWeek.weekOffset
                    , buildRosterStaffPanelFragmentRef rosterGroupId rosterWeek.weekOffset
                    ]
            else do
                setSuccessMessage successMessage
                redirectToPath targetPath

    action AddRosterRowAction { rosterDayId } = do
        ensureManagerRole

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

        -- Find the current max row index for this day
        existingSlots <-
            query @RosterSlot
                |> filterWhere (#rosterDayId, coerce rosterDayId)
                |> filterWhere (#deletedAt, Nothing)
                |> fetch
        let nextRowIndex = if null existingSlots then 0 else maximum (map (.rowIndex) existingSlots) + 1

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
                forM_ slotTemplate \(slotDefinition, slotSortOrder) -> do
                    newRecord @RosterSlot
                        |> set #rosterDayId (coerce rosterDayId)
                        |> set #rosterWeekSlotDefinitionId (coerce (get #id slotDefinition))
                        |> set #slotSortOrder slotSortOrder
                        |> set #rowIndex nextRowIndex
                        |> createRecord

                broadcastRosterWeekInvalidation
                    rosterGroupId
                    rosterWeek.weekOffset
                    [ buildRosterContentFragmentRef rosterGroupId rosterWeek.weekOffset
                    , buildRosterStaffPanelFragmentRef rosterGroupId rosterWeek.weekOffset
                    ]
                if isHtmxRequest
                    then
                        respondWithActorRosterFragmentRefresh
                            [ buildRosterContentFragmentRef rosterGroupId rosterWeek.weekOffset
                            , buildRosterStaffPanelFragmentRef rosterGroupId rosterWeek.weekOffset
                            ]
                    else do
                        setSuccessMessage "Roster row added."
                        redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)

    action RemoveRosterRowAction { rosterDayId } = do
        ensureManagerRole

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

        existingSlots <- query @RosterSlot
            |> filterWhere (#rosterDayId, coerce rosterDayId)
            |> filterWhere (#deletedAt, Nothing)
            |> fetch

        let rowIndices = existingSlots |> map (.rowIndex) |> nub |> sort
        let rowCount = length rowIndices
        let maybeLastRowIndex =
                rowIndices |> last

        when (rowCount <= minimumOpenRosterRows) do
            let rosterGroupId = coerce rosterWeek.rosterGroupId
            let errorMessage = "Roster days must keep at least two rows."
            if isHtmxRequest
                then respondWithRosterToast errorMessage "app-toast-error"
                else do
                    setErrorMessage errorMessage
                    redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)

        slotsToDelete <-
            case maybeLastRowIndex of
                Nothing -> pure []
                Just lastRowIndex ->
                    query @RosterSlot
                        |> filterWhere (#rosterDayId, coerce rosterDayId)
                        |> filterWhere (#rowIndex, lastRowIndex)
                        |> filterWhere (#deletedAt, Nothing)
                        |> fetch

        now <- getCurrentTime
        forM_ slotsToDelete \slot -> do
            _ <- slot
                |> set #deletedAt (Just now)
                |> set #deletedByUserId (Just (unpackId currentUser.id))
                |> set #deleteReason (Just "roster_row_removed")
                |> updateRecord
            pure ()

        let rosterGroupId = coerce rosterWeek.rosterGroupId
        broadcastRosterWeekInvalidation
            rosterGroupId
            rosterWeek.weekOffset
            [ buildRosterContentFragmentRef rosterGroupId rosterWeek.weekOffset
            , buildRosterStaffPanelFragmentRef rosterGroupId rosterWeek.weekOffset
            ]
        if isHtmxRequest
            then
                respondWithActorRosterFragmentRefresh
                    [ buildRosterContentFragmentRef rosterGroupId rosterWeek.weekOffset
                    , buildRosterStaffPanelFragmentRef rosterGroupId rosterWeek.weekOffset
                    ]
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

    action UpdateRosterSlotAction { rosterSlotId } = do
        ensureManagerRole

        rosterSlot <- fetch rosterSlotId
        accessDeniedUnless (isNothing rosterSlot.deletedAt)
        let previousStaffId = rosterSlot.staffId
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
        let maybeFlagParam = paramOrNothing @Text "note"
        sourceTimesheetExists <- rosterSlotHasGeneratedTimesheet rosterSlot

        let rosterGroupId = coerce rosterWeek.rosterGroupId
        case normalizeOptionalSlotFlag maybeFlagParam of
            Left errorMessage ->
                if isHtmxRequest
                    then respondWithRosterToast errorMessage "app-toast-error"
                    else do
                        setErrorMessage errorMessage
                        redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)
            Right normalizedFlag -> do
                let updatedSlot =
                        rosterSlot
                            |> applyOptionalField #staffId (parseOptionalStaffId maybeStaffParam) maybeStaffParam
                            |> applyOptionalField #startTime (parseOptionalTime maybeStartTimeParam) maybeStartTimeParam
                            |> applyOptionalField #endTime (parseOptionalTime maybeEndTimeParam) maybeEndTimeParam
                            |> applyOptionalField #shiftTypeId (parseOptionalShiftTypeId maybeShiftTypeParam) maybeShiftTypeParam
                            |> applyOptionalField #note normalizedFlag maybeFlagParam
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
                        _ <- updatedSlot |> updateRecord
                        let shouldWarnSourceTimesheetUnchanged =
                                sourceTimesheetExists && rosterSlotTimesheetSourceChanged rosterSlot updatedSlot

                        relatedSlots <- fetchRelatedSlotsForStaffIdsInRosterWeek rosterWeek (catMaybes [previousStaffId, updatedSlot.staffId])
                        let impactedRowKeys = impactedRowKeysForSlotUpdate previousStaffId updatedSlot relatedSlots
                        let actorFragments =
                                buildActorRosterRowFragmentRefs maybeStaffParam rosterGroupId rosterWeek.weekOffset impactedRowKeys
                                    <> buildAssignmentRefreshFragmentRefs maybeStaffParam rosterGroupId rosterWeek.weekOffset
                                    <> [buildRosterStaffPanelFragmentRef rosterGroupId rosterWeek.weekOffset]
                        broadcastRosterWeekInvalidation
                            rosterGroupId
                            rosterWeek.weekOffset
                            actorFragments
                        respondWithActorRosterFragmentRefreshWithToast
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

respondWithRosterRows :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> [(UUID.UUID, Int)] -> IO ()
respondWithRosterRows rosterGroupId weekOffset requestedRowKeys =
    respondWithRosterPatches rosterGroupId weekOffset requestedRowKeys False

respondWithActorRosterFragmentRefresh :: (?context :: ControllerContext, ?request :: Request) => [LiveFragmentRef] -> IO ()
respondWithActorRosterFragmentRefresh fragments =
    respondWithActorRosterFragmentRefreshWithToast fragments Nothing

respondWithActorRosterFragmentRefreshWithToast :: (?context :: ControllerContext, ?request :: Request) => [LiveFragmentRef] -> Maybe Text -> IO ()
respondWithActorRosterFragmentRefreshWithToast fragments maybeWarningMessage = do
    setHeader ("HX-Trigger", cs (Aeson.encode payload))
    respondHtmlProfiled $
        maybe mempty (renderToastOob ToastBottomCenter . errorToast) maybeWarningMessage
    where
        payload =
            liveFragmentsRefreshTriggerPayload fragments

respondWithRosterPatches :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> [(UUID.UUID, Int)] -> Bool -> IO ()
respondWithRosterPatches rosterGroupId weekOffset requestedRowKeys shouldRefreshStaffPanel = do
    rosterData <- fetchVisibleRosterRenderDataCached rosterGroupId weekOffset
    case rosterData of
        Nothing -> respondHtmlProfiled [hsx||]
        Just RosterRenderData { rosterDays, weekStartDate, assignmentFilters, staffMembers, staffOptionStates, panelStaff, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled } -> do
            let uniqueRowKeys = nub requestedRowKeys
            let renderedRows = mapMaybe (renderRequestedRow weekStartDate orderedSlotNames assignmentFilters staffMembers staffOptionStates shiftTypes renderIndexes rosterLayoutMode rosterEndTimesEnabled) uniqueRowKeys
            let renderedStaffPanel = [renderRosterStaffPanelFragmentOob weekOffset rosterGroupId panelStaff | shouldRefreshStaffPanel]
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
    rosterDataOrNothing <- fetchVisibleRosterRenderDataCached currentRosterGroup.id weekOffset
    passkeySetupPrompt <- passkeySetupPromptFromSession

    case rosterDataOrNothing of
        Just RosterRenderData { rosterWeek, rosterDays, assignmentFilters, staffMembers, staffOptionStates, panelStaff, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled, rosterWagePrediction } ->
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
    if not venueConfig.rosterEndTimesEnabled
        then pure Nothing
        else do
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
                    else Just "Roster week cannot go live until every staffed shift has a start time, end time, and shift type."

rosterSlotBlocksPublish :: RosterSlot -> Bool
rosterSlotBlocksPublish slot =
    isJust slot.staffId
        && ( isNothing slot.startTime
             || isNothing slot.endTime
             || isNothing slot.shiftTypeId
             || maybe True (<= 0) slot.durationMinutes
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
                [ buildRosterContentFragmentRef rosterGroupId rosterWeek.weekOffset
                , buildRosterStaffPanelFragmentRef rosterGroupId rosterWeek.weekOffset
                ]
        else do
            setSuccessMessage successMessage
            redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)
    where
        rosterGroupId = coerce rosterWeek.rosterGroupId
