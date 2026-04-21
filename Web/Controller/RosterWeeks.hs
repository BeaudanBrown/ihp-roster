{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Web.Controller.RosterWeeks where

import Application.Helper.Controller
import Application.Helper.LiveUpdate (LiveFragmentRef,
                                      LiveUpdateScope (..))
import Application.Helper.Profiling
import Application.Helper.RosterGroups
import Application.Helper.View (appendQueryParams)
import qualified Data.Aeson as Aeson
import Data.Coerce (coerce)
import Data.List (nub)
import Data.Maybe (catMaybes, fromMaybe, isJust, mapMaybe)
import Data.Time (getCurrentTime, utctDay)
import qualified Data.Time.Calendar as Calendar
import qualified Data.UUID as UUID
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.RosterWeeks.Capabilities (buildRosterViewCapabilities)
import Web.RosterWeeks.Dom
import Web.RosterWeeks.Filters
import Web.RosterWeeks.LiveUpdates (broadcastRosterWeekInvalidation)
import Web.RosterWeeks.Overview
import Web.RosterWeeks.Projection
import Web.RosterWeeks.RenderData
import Web.RosterWeeks.Responses (respondWithRosterContent,
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
        ensureCurrentVenue
        ensureProfileCompleted

    action RosterWeeksAction = do
        -- Redirect to the current week's offset based on today's date
        currentWeekOffset <- fetchCurrentRosterWeekOffset
        currentRosterGroup <- resolveRequestedRosterGroup
        let currentWeekPath = buildRosterWeekPath currentWeekOffset currentRosterGroup.id

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
                let selectedWeekOffset = weekOffsetForDay venueConfig.weekOffsetEpoch weekDate
                let targetPath = buildRosterWeekPath selectedWeekOffset rosterGroup.id
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
        rosterGroup <- resolveRequestedRosterGroup
        daySectionHtml <- fetchVisibleRosterDaySectionFragment rosterGroup.id weekOffset rosterDayId
        respondHtmlProfiled (fromMaybe mempty daySectionHtml)

    action ShowRosterWeekRowFragmentAction { weekOffset, rosterDayId, rowIndex } = do
        rosterGroup <- resolveRequestedRosterGroup
        rowHtml <- fetchVisibleRosterRowFragment rosterGroup.id weekOffset rosterDayId rowIndex
        respondHtmlProfiled (fromMaybe mempty rowHtml)

    action UpdateRosterAssignmentFiltersAction { weekOffset } = do
        ensureManagerRole
        rosterGroup <- resolveRequestedRosterGroup
        setRosterAssignmentFiltersSession (rosterAssignmentFiltersFromParams)
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
        let targetPath = buildRosterWeekPath rosterWeek.weekOffset rosterGroup.id
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
                        redirectToPath (buildRosterWeekPath targetWeekOffset rosterGroup.id)
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
                                redirectToPath (buildRosterWeekPath targetWeekOffset rosterGroup.id)
                    Just sourceWeek -> do
                        withTransaction do
                            existingTarget <- query @RosterWeek
                                |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
                                |> filterWhere (#weekOffset, targetWeekOffset)
                                |> fetchOneOrNothing
                            forM_ existingTarget deleteRecord
                            copyRosterWeek sourceWeek targetWeekOffset

                        broadcastRosterWeekInvalidation
                            rosterGroup.id
                            targetWeekOffset
                            [buildRosterContentFragmentRef rosterGroup.id targetWeekOffset]
                        let successMessage = "Roster week copied from the previous week."
                        let targetPath = buildRosterWeekPath targetWeekOffset rosterGroup.id
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
        rosterWeek
            |> set #isLive nextLiveStatus
            |> updateRecord

        let rosterGroupId = coerce rosterWeek.rosterGroupId
        broadcastRosterWeekInvalidation
            rosterGroupId
            rosterWeek.weekOffset
            [buildRosterContentFragmentRef rosterGroupId rosterWeek.weekOffset]
        let successMessage =
                if nextLiveStatus
                    then "Roster week is now live."
                    else "Roster week moved back to draft."
        let targetPath = buildRosterWeekPath rosterWeek.weekOffset rosterGroupId
        if isHtmxRequest
            then do
                setHtmxPushUrl targetPath
                respondWithRosterContentUpdate rosterGroupId rosterWeek.weekOffset successMessage
            else do
                setSuccessMessage successMessage
                redirectToPath targetPath

    action SyncRosterWeekSlotStructureAction { rosterWeekId } = do
        ensureManagerRole
        rosterWeek <- fetch rosterWeekId
        ensureRecordInCurrentVenue rosterWeek.venueId
        ensureRosterWeekIsDraftForEdit rosterWeek

        let rosterGroupId = coerce rosterWeek.rosterGroupId

        withTransaction do
            syncRosterWeekSlotStructure rosterWeek

        broadcastRosterWeekInvalidation
            rosterGroupId
            rosterWeek.weekOffset
            [ buildRosterContentFragmentRef rosterGroupId rosterWeek.weekOffset
            , buildRosterStaffPanelFragmentRef rosterGroupId rosterWeek.weekOffset
            ]

        if isHtmxRequest
            then respondWithRosterContentUpdate rosterGroupId rosterWeek.weekOffset "Slot structure synced."
            else do
                setSuccessMessage "Slot structure synced."
                redirectToPath (buildRosterWeekPath rosterWeek.weekOffset rosterGroupId)

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
        let targetPath = buildRosterWeekPath rosterWeek.weekOffset rosterGroupId
        if isHtmxRequest
            then do
                setHtmxPushUrl targetPath
                respondWithRosterContentUpdate rosterGroupId rosterWeek.weekOffset successMessage
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
            let errorMessage = "Closed days stay locked at three blank rows until reopened."
            if isHtmxRequest
                then respondWithRosterToast errorMessage "app-toast-error"
                else do
                    setErrorMessage errorMessage
                    redirectToPath (buildRosterWeekPath rosterWeek.weekOffset rosterGroupId)

        -- Find the current max row index for this day
        existingSlots <- query @RosterSlot |> filterWhere (#rosterDayId, coerce rosterDayId) |> fetch
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
                        redirectToPath (buildRosterWeekPath rosterWeek.weekOffset rosterGroupId)
            else do
                forM_ slotTemplate \(slotName, slotSortOrder) -> do
                    newRecord @RosterSlot
                        |> set #rosterDayId (coerce rosterDayId)
                        |> set #slotNameId (coerce (get #id slotName))
                        |> set #slotSortOrder slotSortOrder
                        |> set #rowIndex nextRowIndex
                        |> createRecord

                broadcastRosterWeekInvalidation
                    rosterGroupId
                    rosterWeek.weekOffset
                    [ buildRosterDaySectionFragmentRef rosterGroupId rosterWeek.weekOffset (coerce rosterDay.id)
                    , buildRosterStaffPanelFragmentRef rosterGroupId rosterWeek.weekOffset
                    ]
                respondWithRosterContent rosterGroupId rosterWeek.weekOffset

    action RemoveRosterRowAction { rosterDayId } = do
        ensureManagerRole

        rosterDay <- fetch rosterDayId
        let rosterWeekId = (coerce rosterDay.rosterWeekId :: Id RosterWeek)
        rosterWeek <- fetch rosterWeekId
        ensureRecordInCurrentVenue rosterWeek.venueId
        ensureRosterWeekIsDraftForEdit rosterWeek

        when rosterDay.isClosed do
            let rosterGroupId = coerce rosterWeek.rosterGroupId
            let errorMessage = "Closed days stay locked at three blank rows until reopened."
            if isHtmxRequest
                then respondWithRosterToast errorMessage "app-toast-error"
                else do
                    setErrorMessage errorMessage
                    redirectToPath (buildRosterWeekPath rosterWeek.weekOffset rosterGroupId)

        existingSlots <- query @RosterSlot
            |> filterWhere (#rosterDayId, coerce rosterDayId)
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
                    redirectToPath (buildRosterWeekPath rosterWeek.weekOffset rosterGroupId)

        slotsToDelete <-
            case maybeLastRowIndex of
                Nothing -> pure []
                Just lastRowIndex ->
                    query @RosterSlot
                        |> filterWhere (#rosterDayId, coerce rosterDayId)
                        |> filterWhere (#rowIndex, lastRowIndex)
                        |> fetch

        deleteRecords slotsToDelete

        let rosterGroupId = coerce rosterWeek.rosterGroupId
        broadcastRosterWeekInvalidation
            rosterGroupId
            rosterWeek.weekOffset
            [ buildRosterDaySectionFragmentRef rosterGroupId rosterWeek.weekOffset (coerce rosterDay.id)
            , buildRosterStaffPanelFragmentRef rosterGroupId rosterWeek.weekOffset
            ]
        respondWithRosterContent rosterGroupId rosterWeek.weekOffset

    action UpdateRosterSlotAction { rosterSlotId } = do
        ensureManagerRole

        rosterSlot <- fetch rosterSlotId
        let previousStaffId = rosterSlot.staffId
        let rosterDayId = (coerce rosterSlot.rosterDayId :: Id RosterDay)
        rosterDay <- fetch rosterDayId
        let rosterWeekId = (coerce rosterDay.rosterWeekId :: Id RosterWeek)
        rosterWeek <- fetch rosterWeekId
        ensureRecordInCurrentVenue rosterWeek.venueId
        ensureRosterWeekIsDraftForEdit rosterWeek

        let maybeStaffParam = paramOrNothing @Text "staffId"
        let maybeStartTimeParam = paramOrNothing @Text "startTime"
        let maybeFlagParam = paramOrNothing @Text "note"

        let rosterGroupId = coerce rosterWeek.rosterGroupId
        case normalizeOptionalSlotFlag maybeFlagParam of
            Left errorMessage ->
                if isHtmxRequest
                    then respondWithRosterToast errorMessage "app-toast-error"
                    else do
                        setErrorMessage errorMessage
                        redirectToPath (buildRosterWeekPath rosterWeek.weekOffset rosterGroupId)
            Right normalizedFlag -> do
                let updatedSlot =
                        rosterSlot
                            |> applyOptionalField #staffId (parseOptionalStaffId maybeStaffParam) maybeStaffParam
                            |> applyOptionalField #startTime (parseOptionalTime maybeStartTimeParam) maybeStartTimeParam
                            |> applyOptionalField #note normalizedFlag maybeFlagParam

                ensureOptionalStaffInCurrentVenue updatedSlot.staffId
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
                                redirectToPath (buildRosterWeekPath rosterWeek.weekOffset rosterGroupId)
                    else do
                        _ <- updatedSlot |> updateRecord

                        relatedSlots <- fetchRelatedSlotsForStaffIds (catMaybes [previousStaffId, updatedSlot.staffId])
                        let impactedRowKeys = impactedRowKeysForSlotUpdate previousStaffId updatedSlot relatedSlots
                        let actorFragments =
                                buildActorRosterRowFragmentRefs maybeStaffParam rosterGroupId rosterWeek.weekOffset impactedRowKeys
                                    <> buildAssignmentRefreshFragmentRefs maybeStaffParam rosterGroupId rosterWeek.weekOffset
                                    <> [buildRosterStaffPanelFragmentRef rosterGroupId rosterWeek.weekOffset]
                        broadcastRosterWeekInvalidation
                            rosterGroupId
                            rosterWeek.weekOffset
                            actorFragments
                        respondWithActorRosterFragmentRefresh actorFragments

resolveRequestedRosterGroup :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO RosterGroup
resolveRequestedRosterGroup =
    fetchCurrentVenueRosterGroupOrDefault (paramOrNothing "rosterGroupId")

buildRosterWeekPath :: (?context :: ControllerContext) => Int -> Id RosterGroup -> Text
buildRosterWeekPath weekOffset rosterGroupId =
    appendQueryParams (pathTo ShowRosterWeekAction { weekOffset }) [("rosterGroupId", tshow rosterGroupId)]

respondWithRosterRows :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> [(UUID.UUID, Int)] -> IO ()
respondWithRosterRows rosterGroupId weekOffset requestedRowKeys =
    respondWithRosterPatches rosterGroupId weekOffset requestedRowKeys False

respondWithActorRosterFragmentRefresh :: (?context :: ControllerContext, ?request :: Request) => [LiveFragmentRef] -> IO ()
respondWithActorRosterFragmentRefresh fragments = do
    setHeader ("HX-Trigger", cs (Aeson.encode payload))
    respondHtmlProfiled [hsx||]
    where
        payload =
            Aeson.object
                [ "app-roster-fragments-refresh" Aeson..=
                    Aeson.object
                        [ "fragments" Aeson..= fragments
                        ]
                ]

respondWithRosterDaySectionPatch :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Id RosterDay -> Bool -> IO ()
respondWithRosterDaySectionPatch rosterGroupId weekOffset rosterDayId shouldRefreshStaffPanel = do
    rosterData <- fetchVisibleRosterRenderDataCached rosterGroupId weekOffset
    case rosterData of
        Nothing -> respondHtmlProfiled [hsx||]
        Just RosterRenderData { rosterDays, weekStartDate, assignmentFilters, staffMembers, staffOptionStates, panelStaff, orderedSlotNames, allSlots, slotConflicts, renderIndexes } -> do
            let renderedDaySection =
                    mapMaybe
                        (renderRequestedDaySection weekStartDate orderedSlotNames assignmentFilters staffMembers staffOptionStates allSlots slotConflicts renderIndexes)
                        [unpackId rosterDayId]
            let renderedStaffPanel = [renderRosterStaffPanelFragmentOob weekOffset rosterGroupId panelStaff | shouldRefreshStaffPanel]
            respondHtmlProfiled (mconcat (renderedDaySection <> renderedStaffPanel))

respondWithRosterPatches :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> [(UUID.UUID, Int)] -> Bool -> IO ()
respondWithRosterPatches rosterGroupId weekOffset requestedRowKeys shouldRefreshStaffPanel = do
    rosterData <- fetchVisibleRosterRenderDataCached rosterGroupId weekOffset
    case rosterData of
        Nothing -> respondHtmlProfiled [hsx||]
        Just RosterRenderData { rosterDays, weekStartDate, assignmentFilters, staffMembers, staffOptionStates, panelStaff, orderedSlotNames, allSlots, slotConflicts, renderIndexes } -> do
            let uniqueRowKeys = nub requestedRowKeys
            let renderedRows = mapMaybe (renderRequestedRow weekStartDate orderedSlotNames assignmentFilters staffMembers staffOptionStates renderIndexes) uniqueRowKeys
            let renderedStaffPanel = [renderRosterStaffPanelFragmentOob weekOffset rosterGroupId panelStaff | shouldRefreshStaffPanel]
            respondHtmlProfiled (mconcat (renderedRows <> renderedStaffPanel))

renderRosterWeekPage :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => Int -> Id RosterGroup -> IO ()
renderRosterWeekPage weekOffset requestedRosterGroupId = do
    venueConfig <- fetchVenueConfig
    let epoch = venueConfig.weekOffsetEpoch
    let weekStartDate = Calendar.addDays (toInteger (weekOffset * 7)) epoch
    let weekEndDate = Calendar.addDays 6 weekStartDate
    setTitle "Roster"
    rosterGroups <- fetchCurrentVenueRosterGroups
    currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (Just requestedRosterGroupId)
    _ <- ensureRosterWeekExists currentRosterGroup.id weekOffset
    keepCurrentRosterWeekProjectionHot currentRosterGroup.id weekOffset
    rosterDataOrNothing <- fetchVisibleRosterRenderDataCached currentRosterGroup.id weekOffset

    case rosterDataOrNothing of
        Just RosterRenderData { rosterWeek, rosterDays, assignmentFilters, staffMembers, staffOptionStates, panelStaff, orderedSlotNames, allSlots, slotConflicts, renderIndexes } ->
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
                        , allSlots
                        , slotConflicts
                        , renderIndexes
                        , liveUpdateScope = Just (RosterWeekScope { venueId = unpackId currentVenueId, rosterGroupId = unpackId currentRosterGroup.id, weekOffset })
                        , viewCapabilities = buildRosterViewCapabilities visibleRosterWeek
                        }
        Nothing ->
            error "Roster week should exist after ensureRosterWeekExists"

respondWithRosterWeekView :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => ShowView -> IO ()
respondWithRosterWeekView showView =
    if isHtmxRequest
        then respondHtmlProfiled (renderRosterWeekShell showView)
        else renderProfiled showView

renderRosterWeekOverviewFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> Id RosterGroup -> IO Blaze.Html
renderRosterWeekOverviewFragment weekOffset rosterGroupId = do
    venueConfig <- fetchVenueConfig
    todayDate <- utctDay <$> getCurrentTime
    let weekStartDate = Calendar.addDays (toInteger (weekOffset * 7)) venueConfig.weekOffsetEpoch
    let focusDate = initialOverviewFocusDate weekStartDate todayDate
    weekOverviewDays <- profileActionSpan "roster.build_month_overview" (buildRosterMonthOverviewDays venueConfig.weekOffsetEpoch rosterGroupId focusDate)
    pure (renderWeekOverviewPanelFragment weekOffset rosterGroupId weekStartDate todayDate weekOverviewDays (buildRosterViewCapabilities Nothing))

fetchRelatedSlotsForStaffIds :: (?modelContext :: ModelContext) => [UUID.UUID] -> IO [RosterSlot]
fetchRelatedSlotsForStaffIds staffIds =
    if null staffIds
        then pure []
        else query @RosterSlot
            |> filterWhereIn (#staffId, map Just (nub staffIds))
            |> fetch

ensureRosterWeekIsDraftForEdit :: (?context :: ControllerContext, ?request :: Request) => RosterWeek -> IO ()
ensureRosterWeekIsDraftForEdit rosterWeek =
    when rosterWeek.isLive do
        let rosterGroupId = coerce rosterWeek.rosterGroupId
        let targetPath = buildRosterWeekPath rosterWeek.weekOffset rosterGroupId
        let errorMessage = "Live roster weeks are read-only. Move it back to draft to make changes."
        if isHtmxRequest
            then respondWithRosterToast errorMessage "app-toast-error"
            else do
                setErrorMessage errorMessage
                redirectToPath targetPath
