{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Web.Controller.RosterWeeks where

import Application.Helper.Conflict
import Application.Helper.Controller
import Application.Helper.LiveUpdate
import Application.Helper.RosterGroups
import Application.Helper.View (ToastOverlayConfig (..),
                                ToastOverlayPosition (ToastBottomCenter),
                                appendQueryParams,
                                linkedActiveStaffForRosterPanel,
                                renderToastOverlayHostOob)
import qualified Data.Aeson as Aeson
import Data.Coerce (coerce)
import Data.List (find, nub)
import Data.Maybe (catMaybes, mapMaybe)
import qualified Data.Text as Text
import Data.Time (diffDays, getCurrentTime, utctDay)
import qualified Data.Time.Calendar as Calendar
import Data.Time.Format (defaultTimeLocale, parseTimeM)
import Data.Time.LocalTime (TimeOfDay)
import qualified Data.UUID as UUID
import Web.Controller.Prelude
import Web.View.RosterWeeks.Show (RosterStaffPanelEntry (..), ShowView (..),
                                  lastRowIndexForRows,
                                  renderRosterContentFragment,
                                  renderRosterContentFragmentOob,
                                  renderRosterDaySectionFragment,
                                  renderRosterDaySectionFragmentOob,
                                  renderRosterStaffPanelFragment,
                                  renderRosterStaffPanelFragmentOob,
                                  renderRosterWeekShell, renderRowFragment,
                                  renderRowOob, rosterContentFragmentId,
                                  rosterDaySectionDomId, rosterRowDomIdText,
                                  rosterStaffPanelFragmentId, rowsForDay)

instance Controller RosterWeeksController where
    beforeAction = do
        ensureIsUser
        ensureCurrentVenue
        ensureProfileCompleted

    action RosterWeeksAction = do
        -- Redirect to the current week's offset based on today's date
        now <- liftIO getCurrentTime
        venueConfig <- fetchVenueConfig

        let today = utctDay now
        let epoch = venueConfig.weekOffsetEpoch
        let daysSinceEpoch = diffDays today epoch
        let currentWeekOffset = fromIntegral (daysSinceEpoch `div` 7)
        currentRosterGroup <- resolveRequestedRosterGroup
        let currentWeekPath = buildRosterWeekPath currentWeekOffset currentRosterGroup.id

        if isHtmxRequest
            then do
                setHtmxPushUrl currentWeekPath
                renderRosterWeekPage currentWeekOffset currentRosterGroup.id
            else redirectToPath currentWeekPath

    action ShowRosterWeekAction { weekOffset } = do
        rosterGroup <- resolveRequestedRosterGroup
        renderRosterWeekPage weekOffset rosterGroup.id

    action ShowRosterWeekContentFragmentAction { weekOffset } = do
        rosterGroup <- resolveRequestedRosterGroup
        respondWithRosterContent rosterGroup.id weekOffset

    action ShowRosterWeekStaffPanelFragmentAction { weekOffset } = do
        rosterGroup <- resolveRequestedRosterGroup
        panelStaff <- fetchVisibleRosterStaffPanelEntries rosterGroup.id weekOffset
        respondHtml $
            maybe mempty (renderRosterStaffPanelFragment weekOffset rosterGroup.id) panelStaff

    action ShowRosterWeekDaySectionFragmentAction { weekOffset, rosterDayId } = do
        rosterGroup <- resolveRequestedRosterGroup
        daySectionHtml <- fetchVisibleRosterDaySectionFragment rosterGroup.id weekOffset rosterDayId
        respondHtml (fromMaybe mempty daySectionHtml)

    action ShowRosterWeekRowFragmentAction { weekOffset, rosterDayId, rowIndex } = do
        rosterGroup <- resolveRequestedRosterGroup
        rowHtml <- fetchVisibleRosterRowFragment rosterGroup.id weekOffset rosterDayId rowIndex
        respondHtml (fromMaybe mempty rowHtml)

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
        orderedSlotNames <- fetchActiveRosterGroupSlotNames rosterGroupId

        if null orderedSlotNames
            then do
                let errorMessage = "Add at least one active slot to the selected roster group before adding roster rows."
                if isHtmxRequest
                    then respondWithRosterToast errorMessage "app-toast-error"
                    else do
                        setErrorMessage errorMessage
                        redirectToPath (buildRosterWeekPath rosterWeek.weekOffset rosterGroupId)
            else do
                forM_ orderedSlotNames \slotName -> do
                    newRecord @RosterSlot
                        |> set #rosterDayId (coerce rosterDayId)
                        |> set #slotNameId (coerce (get #id slotName))
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
        let maybeNoteParam = paramOrNothing @Text "note"

        let updatedSlot =
                rosterSlot
                    |> applyOptionalField #staffId (parseOptionalStaffId maybeStaffParam) maybeStaffParam
                    |> applyOptionalField #startTime (parseOptionalTime maybeStartTimeParam) maybeStartTimeParam
                    |> applyOptionalField #note (normalizeOptionalText maybeNoteParam) maybeNoteParam

        let rosterGroupId = coerce rosterWeek.rosterGroupId
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
                        buildRosterRowFragmentRefs rosterGroupId rosterWeek.weekOffset impactedRowKeys
                            <> [buildRosterStaffPanelFragmentRef rosterGroupId rosterWeek.weekOffset]
                broadcastRosterWeekInvalidation
                    rosterGroupId
                    rosterWeek.weekOffset
                    actorFragments
                respondWithActorRosterFragmentRefresh actorFragments

minimumOpenRosterRows :: Int
minimumOpenRosterRows = 2

closedRosterDayRows :: Int
closedRosterDayRows = 3

resolveRequestedRosterGroup :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO RosterGroup
resolveRequestedRosterGroup =
    fetchCurrentVenueRosterGroupOrDefault (paramOrNothing "rosterGroupId")

buildRosterWeekPath :: (?context :: ControllerContext) => Int -> Id RosterGroup -> Text
buildRosterWeekPath weekOffset rosterGroupId =
    appendQueryParams (pathTo ShowRosterWeekAction { weekOffset }) [("rosterGroupId", tshow rosterGroupId)]

parseOptionalStaffId :: Maybe Text -> Maybe UUID.UUID
parseOptionalStaffId value = UUID.fromText =<< normalizeOptionalText value

parseOptionalTime :: Maybe Text -> Maybe TimeOfDay
parseOptionalTime value =
    case normalizeOptionalText value of
        Nothing -> Nothing
        Just valueText -> parseTimeM True defaultTimeLocale "%H:%M" (cs valueText)

normalizeOptionalText :: Maybe Text -> Maybe Text
normalizeOptionalText = \case
    Nothing -> Nothing
    Just value ->
        let trimmed = Text.strip value
         in if Text.null trimmed then Nothing else Just trimmed

buildSlotConflicts :: (?modelContext :: ModelContext) => Id RosterGroup -> Int -> Calendar.Day -> [RosterDay] -> [RosterSlot] -> [Staff] -> IO [(Id RosterSlot, [RosterConflict])]
buildSlotConflicts rosterGroupId lateToEarlyMinStartGapMinutes weekStartDate rosterDays allSlots staffMembers = do
    let assignedStaffIds = nub $ mapMaybe (.staffId) allSlots
    if null assignedStaffIds
        then pure []
        else do
            leaveRequests <- query @LeaveRequest
                |> filterWhereIn (#staffId, assignedStaffIds)
                |> fetch

            availabilities <- query @StaffAvailability
                |> filterWhereIn (#staffId, assignedStaffIds)
                |> fetch

            shiftPreferences <- query @StaffShiftPreference
                |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
                |> filterWhereIn (#staffId, assignedStaffIds)
                |> fetch

            let dayById = map (\day -> (coerce (get #id day), day)) rosterDays
            let conflictsBySlot = mapMaybe (conflictsForSlot dayById leaveRequests availabilities shiftPreferences) allSlots
            pure conflictsBySlot
    where
        conflictsForSlot dayById leaveRequests availabilities shiftPreferences slot = do
            staffUuid <- slot.staffId
            day <- lookup slot.rosterDayId dayById
            let weekSlotsForStaff = filter (\candidate -> candidate.staffId == Just staffUuid) allSlots
            let daySlotsForStaff = filter (\candidate -> candidate.rosterDayId == slot.rosterDayId && candidate.staffId == Just staffUuid) allSlots
            let staffIdealShifts = (.idealShiftsPerWeek) <$> find (\staff -> coerce (get #id staff) == staffUuid) staffMembers
            let leaveRequestsForStaff = filter (\leaveRequest -> leaveRequest.staffId == staffUuid) leaveRequests
            let availabilitiesForStaff = filter (\availability -> availability.staffId == staffUuid) availabilities
            let shiftPreferencesForStaff = filter (\preference -> preference.staffId == staffUuid) shiftPreferences
            let rosterDayDate = Calendar.addDays (toInteger day.dayOffset) weekStartDate
            let conflicts = evaluateConflicts ConflictContext
                    { slot
                    , rosterGroupId = unpackId rosterGroupId
                    , weekSlots = weekSlotsForStaff
                    , daySlots = daySlotsForStaff
                    , weekRosterDays = rosterDays
                    , leaveRequests = leaveRequestsForStaff
                    , availabilities = availabilitiesForStaff
                    , shiftPreferences = shiftPreferencesForStaff
                    , rosterDayDate
                    , lateToEarlyMinStartGapMinutes
                    , staffIdealShifts
                    }
            if null conflicts
                then Nothing
                else Just (get #id slot, conflicts)

respondWithRosterContent :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> IO ()
respondWithRosterContent rosterGroupId weekOffset = do
    rosterGroups <- fetchCurrentVenueRosterGroups
    currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (Just rosterGroupId)
    rosterData <- fetchVisibleRosterRenderData rosterGroupId weekOffset
    case rosterData of
        Nothing -> respondHtml [hsx|<div id="roster-content"></div>|]
        Just RosterRenderData { rosterWeek, rosterDays, weekStartDate, staffMembers, panelStaff, orderedSlotNames, allSlots, slotConflicts } ->
            respondHtml $
                renderRosterContentFragment
                    (Just rosterWeek)
                    rosterDays
                    weekOffset
                    rosterGroups
                    currentRosterGroup
                    staffMembers
                    panelStaff
                    orderedSlotNames
                    weekStartDate
                    allSlots
                    slotConflicts

respondWithRosterContentOob :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> IO ()
respondWithRosterContentOob rosterGroupId weekOffset = do
    rosterGroups <- fetchCurrentVenueRosterGroups
    currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (Just rosterGroupId)
    rosterData <- fetchVisibleRosterRenderData rosterGroupId weekOffset
    case rosterData of
        Nothing -> respondHtml [hsx|<div id="roster-content" hx-swap-oob="outerHTML"></div>|]
        Just RosterRenderData { rosterWeek, rosterDays, weekStartDate, staffMembers, panelStaff, orderedSlotNames, allSlots, slotConflicts } ->
            respondHtml $
                renderRosterContentFragmentOob
                    (Just rosterWeek)
                    rosterDays
                    weekOffset
                    rosterGroups
                    currentRosterGroup
                    staffMembers
                    panelStaff
                    orderedSlotNames
                    weekStartDate
                    allSlots
                    slotConflicts

respondWithRosterContentUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> Text -> IO ()
respondWithRosterContentUpdate rosterGroupId weekOffset successMessage = do
    rosterGroups <- fetchCurrentVenueRosterGroups
    currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (Just rosterGroupId)
    rosterData <- fetchVisibleRosterRenderData rosterGroupId weekOffset
    respondHtml $
        mconcat
            [ case rosterData of
                Nothing -> [hsx|<div id="roster-content"></div>|]
                Just RosterRenderData { rosterWeek, rosterDays, weekStartDate, staffMembers, panelStaff, orderedSlotNames, allSlots, slotConflicts } ->
                    renderRosterContentFragment
                        (Just rosterWeek)
                        rosterDays
                        weekOffset
                        rosterGroups
                        currentRosterGroup
                        staffMembers
                        panelStaff
                        orderedSlotNames
                        weekStartDate
                        allSlots
                        slotConflicts
            , renderToastOverlayHostOob ToastBottomCenter
                [ ToastOverlayConfig
                    { toastOverlayTitle = Just "Success"
                    , toastOverlayMessage = successMessage
                    , toastOverlayClass = "app-toast-success"
                    , toastOverlayAutoHideMs = 3200
                    }
                ]
            ]

respondWithRosterToast :: (?context :: ControllerContext) => Text -> Text -> IO ()
respondWithRosterToast message toastClass =
    respondHtml $
        renderToastOverlayHostOob ToastBottomCenter
            [ ToastOverlayConfig
                { toastOverlayTitle = Just (if toastClass == "app-toast-error" then "Error" else "Success")
                , toastOverlayMessage = message
                , toastOverlayClass = toastClass
                , toastOverlayAutoHideMs = if toastClass == "app-toast-error" then 4200 else 3200
                }
            ]

respondWithRosterRows :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> [(UUID.UUID, Int)] -> IO ()
respondWithRosterRows rosterGroupId weekOffset requestedRowKeys =
    respondWithRosterPatches rosterGroupId weekOffset requestedRowKeys False

respondWithActorRosterFragmentRefresh :: (?context :: ControllerContext) => [LiveFragmentRef] -> IO ()
respondWithActorRosterFragmentRefresh fragments = do
    setHeader ("HX-Trigger", cs (Aeson.encode payload))
    respondHtml [hsx||]
    where
        payload =
            Aeson.object
                [ "app-roster-fragments-refresh" Aeson..=
                    Aeson.object
                        [ "fragments" Aeson..= fragments
                        ]
                ]

respondWithRosterDaySectionPatch :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> Id RosterDay -> Bool -> IO ()
respondWithRosterDaySectionPatch rosterGroupId weekOffset rosterDayId shouldRefreshStaffPanel = do
    rosterData <- fetchVisibleRosterRenderData rosterGroupId weekOffset
    case rosterData of
        Nothing -> respondHtml [hsx||]
        Just RosterRenderData { rosterDays, weekStartDate, staffMembers, panelStaff, orderedSlotNames, allSlots, slotConflicts } -> do
            let renderedDaySection =
                    mapMaybe
                        (renderRequestedDaySection rosterDays weekStartDate orderedSlotNames staffMembers allSlots slotConflicts)
                        [unpackId rosterDayId]
            let renderedStaffPanel = [renderRosterStaffPanelFragmentOob weekOffset rosterGroupId panelStaff | shouldRefreshStaffPanel]
            respondHtml (mconcat (renderedDaySection <> renderedStaffPanel))

respondWithRosterPatches :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> [(UUID.UUID, Int)] -> Bool -> IO ()
respondWithRosterPatches rosterGroupId weekOffset requestedRowKeys shouldRefreshStaffPanel = do
    rosterData <- fetchVisibleRosterRenderData rosterGroupId weekOffset
    case rosterData of
        Nothing -> respondHtml [hsx||]
        Just RosterRenderData { rosterDays, weekStartDate, staffMembers, panelStaff, orderedSlotNames, allSlots, slotConflicts } -> do
            let uniqueRowKeys = nub requestedRowKeys
            let renderedRows = mapMaybe (renderRequestedRow rosterDays weekStartDate orderedSlotNames staffMembers allSlots slotConflicts) uniqueRowKeys
            let renderedStaffPanel = [renderRosterStaffPanelFragmentOob weekOffset rosterGroupId panelStaff | shouldRefreshStaffPanel]
            respondHtml (mconcat (renderedRows <> renderedStaffPanel))

renderRosterWeekPage :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Int -> Id RosterGroup -> IO ()
renderRosterWeekPage weekOffset requestedRosterGroupId = do
    venueConfig <- fetchVenueConfig
    let epoch = venueConfig.weekOffsetEpoch
    let weekStartDate = Calendar.addDays (toInteger (weekOffset * 7)) epoch
    let weekEndDate = Calendar.addDays 6 weekStartDate
    rosterGroups <- fetchCurrentVenueRosterGroups
    currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (Just requestedRosterGroupId)
    _ <- ensureRosterWeekExists currentRosterGroup.id weekOffset

    visibleRosterWeek <- fetchVisibleRosterWeek currentRosterGroup.id weekOffset

    case visibleRosterWeek of
        Just _ -> do
            rosterDataOrNothing <- fetchRosterRenderData currentRosterGroup.id weekOffset
            case rosterDataOrNothing of
                Just RosterRenderData { rosterWeek, rosterDays, staffMembers, panelStaff, orderedSlotNames, allSlots, slotConflicts } ->
                    respondWithRosterWeekView
                        ShowView
                            { rosterWeek = Just rosterWeek
                            , rosterDays
                            , weekOffset
                            , rosterGroups
                            , currentRosterGroup
                            , weekStartDate
                            , weekEndDate
                            , staffMembers
                            , panelStaff
                            , slotNames = orderedSlotNames
                            , allSlots
                            , slotConflicts
                            , liveUpdateScope = Just (RosterWeekScope { venueId = unpackId currentVenueId, rosterGroupId = unpackId currentRosterGroup.id, weekOffset })
                            }
                Nothing ->
                    error "Visible roster week should exist after ensureRosterWeekExists"
        Nothing -> do
            (_, rosterDays, _, orderedSlotNames, maskedSlots) <- fetchHiddenRosterRenderData currentRosterGroup.id weekOffset
            respondWithRosterWeekView
                ShowView
                    { rosterWeek = Nothing
                    , rosterDays
                    , weekOffset
                    , rosterGroups
                    , currentRosterGroup
                    , weekStartDate
                    , weekEndDate
                    , staffMembers = []
                    , panelStaff = []
                    , slotNames = orderedSlotNames
                    , allSlots = maskedSlots
                    , slotConflicts = []
                    , liveUpdateScope = Just (RosterWeekScope { venueId = unpackId currentVenueId, rosterGroupId = unpackId currentRosterGroup.id, weekOffset })
                    }

respondWithRosterWeekView :: (?context :: ControllerContext) => ShowView -> IO ()
respondWithRosterWeekView showView =
    if isHtmxRequest
        then respondHtml (renderRosterWeekShell showView)
        else render showView

fetchRelatedSlotsForStaffIds :: (?modelContext :: ModelContext) => [UUID.UUID] -> IO [RosterSlot]
fetchRelatedSlotsForStaffIds staffIds =
    if null staffIds
        then pure []
        else query @RosterSlot
            |> filterWhereIn (#staffId, map Just (nub staffIds))
            |> fetch

data RosterRenderData = RosterRenderData
    { rosterWeek       :: RosterWeek
    , rosterDays       :: [RosterDay]
    , weekStartDate    :: Calendar.Day
    , staffMembers     :: [Staff]
    , panelStaff       :: [RosterStaffPanelEntry]
    , orderedSlotNames :: [SlotName]
    , allSlots         :: [RosterSlot]
    , slotConflicts    :: [(Id RosterSlot, [RosterConflict])]
    }

fetchRosterRenderData :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> IO (Maybe RosterRenderData)
fetchRosterRenderData rosterGroupId weekOffset = do
    _ <- ensureRosterWeekExists rosterGroupId weekOffset
    venueConfig <- fetchVenueConfig
    let epoch = venueConfig.weekOffsetEpoch
    let weekStartDate = Calendar.addDays (toInteger (weekOffset * 7)) epoch

    rosterWeekOrNothing <- query @RosterWeek
        |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
        |> filterWhere (#weekOffset, weekOffset)
        |> fetchOneOrNothing

    case rosterWeekOrNothing of
        Nothing -> pure Nothing
        Just rosterWeek -> do
            rosterDays <- query @RosterDay
                |> filterWhere (#rosterWeekId, coerce (get #id rosterWeek))
                |> orderBy #dayOffset
                |> fetch

            allSlots <- query @RosterSlot
                |> filterWhereIn (#rosterDayId, map (coerce . (.id)) rosterDays)
                |> fetch

            let visibleSlots = filterVisibleRosterSlots rosterDays allSlots
            eligibleStaffMembers <- fetchEligibleRosterGroupStaff rosterGroupId
            assignedStaffMembers <- fetchAssignedRosterWeekStaff visibleSlots
            let staffMembers = nubBy (\left right -> left.id == right.id) (eligibleStaffMembers <> assignedStaffMembers)
            panelStaff <- fetchRosterStaffPanelEntries eligibleStaffMembers visibleSlots

            orderedSlotNames <- fetchActiveRosterGroupSlotNames rosterGroupId
            slotConflicts <- buildSlotConflicts rosterGroupId venueConfig.lateToEarlyMinStartGapMinutes weekStartDate rosterDays visibleSlots staffMembers
            pure (Just RosterRenderData { rosterWeek, rosterDays, weekStartDate, staffMembers, panelStaff, orderedSlotNames, allSlots, slotConflicts })

fetchVisibleRosterRenderData :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> IO (Maybe RosterRenderData)
fetchVisibleRosterRenderData rosterGroupId weekOffset = do
    visibleRosterWeek <- fetchVisibleRosterWeek rosterGroupId weekOffset
    case visibleRosterWeek of
        Nothing -> do
            (backingRosterWeek, rosterDays, weekStartDate, orderedSlotNames, maskedSlots) <- fetchHiddenRosterRenderData rosterGroupId weekOffset
            pure $
                Just
                    RosterRenderData
                        { rosterWeek = backingRosterWeek
                        , rosterDays
                        , weekStartDate
                        , staffMembers = []
                        , panelStaff = []
                        , orderedSlotNames
                        , allSlots = maskedSlots
                        , slotConflicts = []
                        }
        Just _  -> fetchRosterRenderData rosterGroupId weekOffset

fetchVisibleRosterWeek :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> IO (Maybe RosterWeek)
fetchVisibleRosterWeek rosterGroupId weekOffset = do
    _ <- ensureRosterWeekExists rosterGroupId weekOffset
    rosterWeekOrNothing <-
        query @RosterWeek
            |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
            |> filterWhere (#weekOffset, weekOffset)
            |> fetchOneOrNothing

    pure $
        case rosterWeekOrNothing of
            Just rosterWeek | get #isLive rosterWeek || hasRole ManagerRole' -> Just rosterWeek
            _ -> Nothing

fetchVisibleRosterStaffPanelEntries :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> IO (Maybe [RosterStaffPanelEntry])
fetchVisibleRosterStaffPanelEntries rosterGroupId weekOffset = do
    rosterData <- fetchVisibleRosterRenderData rosterGroupId weekOffset
    pure ((\RosterRenderData { panelStaff } -> panelStaff) <$> rosterData)

fetchVisibleRosterRowFragment rosterGroupId weekOffset rosterDayId rowIndex = do
    rosterData <- fetchVisibleRosterRenderData rosterGroupId weekOffset
    pure do
        RosterRenderData { rosterWeek, rosterDays, weekStartDate, staffMembers, orderedSlotNames, allSlots, slotConflicts } <- rosterData
        renderRequestedRowFragment (hasRole ManagerRole' && not rosterWeek.isLive) rosterDays weekStartDate orderedSlotNames staffMembers allSlots slotConflicts (unpackId rosterDayId, rowIndex)

fetchVisibleRosterDaySectionFragment rosterGroupId weekOffset rosterDayId = do
    rosterData <- fetchVisibleRosterRenderData rosterGroupId weekOffset
    pure do
        RosterRenderData { rosterWeek, rosterDays, weekStartDate, staffMembers, orderedSlotNames, allSlots, slotConflicts } <- rosterData
        renderRequestedDaySectionFragment (hasRole ManagerRole' && not rosterWeek.isLive) rosterDays weekStartDate orderedSlotNames staffMembers allSlots slotConflicts (unpackId rosterDayId)

buildRosterWeekScope :: (?context :: ControllerContext) => Id RosterGroup -> Int -> LiveUpdateScope
buildRosterWeekScope rosterGroupId weekOffset =
    RosterWeekScope
        { venueId = unpackId currentVenueId
        , rosterGroupId = unpackId rosterGroupId
        , weekOffset
        }

buildRosterContentFragmentRef :: (?context :: ControllerContext) => Id RosterGroup -> Int -> LiveFragmentRef
buildRosterContentFragmentRef rosterGroupId weekOffset =
    LiveFragmentRef
        { fragmentKey = RosterContentFragment
        , targetId = rosterContentFragmentId
        , url = appendQueryParams (pathTo ShowRosterWeekContentFragmentAction { weekOffset }) [("rosterGroupId", tshow rosterGroupId)]
        , deferUntilBlur = False
        }

buildRosterStaffPanelFragmentRef :: (?context :: ControllerContext) => Id RosterGroup -> Int -> LiveFragmentRef
buildRosterStaffPanelFragmentRef rosterGroupId weekOffset =
    LiveFragmentRef
        { fragmentKey = RosterStaffPanelFragment
        , targetId = rosterStaffPanelFragmentId
        , url = appendQueryParams (pathTo ShowRosterWeekStaffPanelFragmentAction { weekOffset }) [("rosterGroupId", tshow rosterGroupId)]
        , deferUntilBlur = False
        }

buildRosterDaySectionFragmentRef :: (?context :: ControllerContext) => Id RosterGroup -> Int -> UUID.UUID -> LiveFragmentRef
buildRosterDaySectionFragmentRef rosterGroupId weekOffset rosterDayId =
    LiveFragmentRef
        { fragmentKey = RosterDaySectionFragment { rosterDayId }
        , targetId = rosterDaySectionDomId (coerce rosterDayId)
        , url = appendQueryParams (pathTo ShowRosterWeekDaySectionFragmentAction { weekOffset, rosterDayId = coerce rosterDayId }) [("rosterGroupId", tshow rosterGroupId)]
        , deferUntilBlur = True
        }

buildRosterRowFragmentRefs :: (?context :: ControllerContext) => Id RosterGroup -> Int -> [(UUID.UUID, Int)] -> [LiveFragmentRef]
buildRosterRowFragmentRefs rosterGroupId weekOffset =
    map (uncurry (buildRosterRowFragmentRef rosterGroupId weekOffset)) . nub

buildRosterRowFragmentRef :: (?context :: ControllerContext) => Id RosterGroup -> Int -> UUID.UUID -> Int -> LiveFragmentRef
buildRosterRowFragmentRef rosterGroupId weekOffset rosterDayId rowIndex =
    LiveFragmentRef
        { fragmentKey = RosterRowFragment { rosterDayId, rowIndex }
        , targetId = rosterRowDomIdText (coerce rosterDayId) rowIndex
        , url = appendQueryParams (pathTo ShowRosterWeekRowFragmentAction { weekOffset, rosterDayId = coerce rosterDayId, rowIndex }) [("rosterGroupId", tshow rosterGroupId)]
        , deferUntilBlur = True
        }

broadcastRosterWeekInvalidation ::
    (?context :: ControllerContext) =>
    Id RosterGroup ->
    Int ->
    [LiveFragmentRef] ->
    IO ()
broadcastRosterWeekInvalidation rosterGroupId weekOffset fragments =
    unless (null fragments) do
        liftIO $
            broadcastLiveInvalidation
                (buildRosterWeekScope rosterGroupId weekOffset)
                (cs <$> getHeader "X-Live-Update-Client-Id")
                fragments

fetchRosterStaffPanelEntries :: (?context :: ControllerContext, ?modelContext :: ModelContext) => [Staff] -> [RosterSlot] -> IO [RosterStaffPanelEntry]
fetchRosterStaffPanelEntries staffMembers allSlots = do
    let linkedStaff = linkedActiveStaffForRosterPanel staffMembers
    let linkedUserIds = mapMaybe (.userId) linkedStaff

    memberships <-
        if null linkedUserIds
            then pure []
            else query @VenueMembership
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhereIn (#userId, linkedUserIds)
                |> filterWhere (#isActive, True)
                |> fetch

    pure (map (buildPanelEntry memberships) linkedStaff)
    where
        buildPanelEntry memberships staff =
            let assignedShiftCount = length (filter (\slot -> slot.staffId == Just (coerce (get #id staff))) allSlots)
                roleText = case staff.userId >>= \userId -> find (\membership -> membership.userId == userId) memberships of
                    Just membership -> inputValue membership.venueRole
                    Nothing         -> venueRoleToText WorkerRole
             in RosterStaffPanelEntry
                    { staff
                    , assignedShiftCount
                    , userRole = roleText
                    }

fetchAssignedRosterWeekStaff :: (?context :: ControllerContext, ?modelContext :: ModelContext) => [RosterSlot] -> IO [Staff]
fetchAssignedRosterWeekStaff allSlots = do
    let assignedStaffIds = nub (mapMaybe (.staffId) allSlots)
    if null assignedStaffIds
        then pure []
        else
            query @Staff
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhereIn (#id, map Id assignedStaffIds)
                |> orderBy #lastName
                |> fetch

ensureRosterWeekExists :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> IO (RosterWeek, Bool)
ensureRosterWeekExists rosterGroupId weekOffset = do
    existing <- query @RosterWeek
        |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
        |> filterWhere (#weekOffset, weekOffset)
        |> fetchOneOrNothing
    case existing of
        Just rosterWeek -> pure (rosterWeek, False)
        Nothing -> do
            rosterWeek <- createEmptyRosterWeek rosterGroupId weekOffset
            pure (rosterWeek, True)

createEmptyRosterWeek :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> IO RosterWeek
createEmptyRosterWeek rosterGroupId weekOffset = do
    orderedSlotNames <- fetchActiveRosterGroupSlotNames rosterGroupId

    rosterWeek <- newRecord @RosterWeek
        |> set #venueId (unpackId currentVenueId)
        |> set #rosterGroupId (unpackId rosterGroupId)
        |> set #weekOffset weekOffset
        |> set #isLive False
        |> createRecord

    forM_ [0 .. 6] \dayOffset -> do
        rosterDay <- newRecord @RosterDay
            |> set #rosterWeekId (coerce (get #id rosterWeek))
            |> set #dayOffset dayOffset
            |> set #isClosed False
            |> createRecord

        forM_ [0 .. 3] \rowIndex ->
            forM_ orderedSlotNames \slotName -> do
                newRecord @RosterSlot
                    |> set #rosterDayId (coerce (get #id rosterDay))
                    |> set #slotNameId (coerce (get #id slotName))
                    |> set #rowIndex rowIndex
                    |> createRecord

    pure rosterWeek

copyRosterWeek :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterWeek -> Int -> IO RosterWeek
copyRosterWeek sourceWeek targetWeekOffset = do
    targetWeek <- newRecord @RosterWeek
        |> set #venueId (unpackId currentVenueId)
        |> set #rosterGroupId sourceWeek.rosterGroupId
        |> set #weekOffset targetWeekOffset
        |> set #isLive False
        |> createRecord

    sourceDays <- query @RosterDay
        |> filterWhere (Proxy @"rosterWeekId", coerce (get #id sourceWeek))
        |> fetch

    forM_ [0 .. 6] \dayOffset -> do
        let maybeSourceDay = find (\day -> get #dayOffset day == dayOffset) sourceDays
        targetDay <- newRecord @RosterDay
            |> set #rosterWeekId (coerce (get #id targetWeek))
            |> set #dayOffset dayOffset
            |> set #isClosed (maybe False (.isClosed) maybeSourceDay)
            |> createRecord

        case maybeSourceDay of
            Just sourceDay -> do
                sourceSlots <- query @RosterSlot
                    |> filterWhere (#rosterDayId, coerce (get #id sourceDay))
                    |> fetch
                forM_ sourceSlots \slot -> do
                    newRecord @RosterSlot
                        |> set #rosterDayId (coerce (get #id targetDay))
                        |> set #staffId slot.staffId
                        |> set #slotNameId slot.slotNameId
                        |> set #rowIndex slot.rowIndex
                        |> set #startTime slot.startTime
                        |> set #durationMinutes slot.durationMinutes
                        |> set #note slot.note
                        |> createRecord
                    pure ()
            Nothing -> pure ()

    pure targetWeek

fetchHiddenRosterRenderData :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> IO (RosterWeek, [RosterDay], Calendar.Day, [SlotName], [RosterSlot])
fetchHiddenRosterRenderData rosterGroupId weekOffset = do
    rosterDataOrNothing <- fetchRosterRenderData rosterGroupId weekOffset
    case rosterDataOrNothing of
        Just RosterRenderData { rosterWeek, rosterDays, weekStartDate, orderedSlotNames, allSlots } ->
            pure (rosterWeek, rosterDays, weekStartDate, orderedSlotNames, maskRosterSlots rosterWeek allSlots)
        Nothing -> error "Roster week should exist after ensureRosterWeekExists"

fetchHiddenRosterWeekSkeleton :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> IO (RosterWeek, [RosterDay], [SlotName], [RosterSlot])
fetchHiddenRosterWeekSkeleton rosterGroupId weekOffset = do
    (rosterWeek, rosterDays, _, orderedSlotNames, maskedSlots) <- fetchHiddenRosterRenderData rosterGroupId weekOffset
    pure (rosterWeek, rosterDays, orderedSlotNames, maskedSlots)

maskRosterSlots :: (?context :: ControllerContext) => RosterWeek -> [RosterSlot] -> [RosterSlot]
maskRosterSlots rosterWeek slots =
    if get #isLive rosterWeek || hasRole ManagerRole'
        then slots
        else map maskSlot slots
    where
        maskSlot slot =
            slot
                |> set #staffId Nothing
                |> set #startTime Nothing
                |> set #durationMinutes Nothing
                |> set #note Nothing


renderRequestedRow rosterDays weekStartDate orderedSlotNames staffMembers allSlots slotConflicts (rosterDayUuid, targetRowIndex) = do
    rosterDay <- find (\day -> coerce (get #id day) == rosterDayUuid) rosterDays
    let daySlots = filter (\slot -> slot.rosterDayId == rosterDayUuid) allSlots
    let dayRows = rowsForDay rosterDay daySlots
    let rowCount = length dayRows
    let lastRowIndex = lastRowIndexForRows dayRows
    let indexedRows = zip [0 :: Int ..] dayRows
    (rowPosition, (_, rowSlots)) <- find (\(_, (rowIndex, _)) -> rowIndex == targetRowIndex) indexedRows
    let date = Calendar.addDays (toInteger (get #dayOffset rosterDay)) weekStartDate
    pure (renderRowOob True orderedSlotNames staffMembers date rosterDay rowCount lastRowIndex slotConflicts (rowPosition, (targetRowIndex, rowSlots)))

renderRequestedRowFragment isEditable rosterDays weekStartDate orderedSlotNames staffMembers allSlots slotConflicts (rosterDayUuid, targetRowIndex) = do
    rosterDay <- find (\day -> coerce (get #id day) == rosterDayUuid) rosterDays
    let daySlots = filter (\slot -> slot.rosterDayId == rosterDayUuid) allSlots
    let dayRows = rowsForDay rosterDay daySlots
    let rowCount = length dayRows
    let lastRowIndex = lastRowIndexForRows dayRows
    let indexedRows = zip [0 :: Int ..] dayRows
    (rowPosition, (_, rowSlots)) <- find (\(_, (rowIndex, _)) -> rowIndex == targetRowIndex) indexedRows
    let date = Calendar.addDays (toInteger (get #dayOffset rosterDay)) weekStartDate
    pure (renderRowFragment isEditable orderedSlotNames staffMembers date rosterDay rowCount lastRowIndex slotConflicts (rowPosition, (targetRowIndex, rowSlots)))

renderRequestedDaySection rosterDays weekStartDate orderedSlotNames staffMembers allSlots slotConflicts rosterDayUuid = do
    rosterDay <- find (\day -> coerce (get #id day) == rosterDayUuid) rosterDays
    pure (renderRosterDaySectionFragment True orderedSlotNames staffMembers weekStartDate allSlots slotConflicts rosterDay)

renderRequestedDaySectionFragment isEditable rosterDays weekStartDate orderedSlotNames staffMembers allSlots slotConflicts rosterDayUuid = do
    rosterDay <- find (\day -> coerce (get #id day) == rosterDayUuid) rosterDays
    pure (renderRosterDaySectionFragment isEditable orderedSlotNames staffMembers weekStartDate allSlots slotConflicts rosterDay)

ensureRosterWeekIsDraftForEdit :: (?context :: ControllerContext) => RosterWeek -> IO ()
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

impactedRowKeysForSlotUpdate :: Maybe UUID.UUID -> RosterSlot -> [RosterSlot] -> [(UUID.UUID, Int)]
impactedRowKeysForSlotUpdate previousStaffId updatedSlot relatedSlots =
    nub $
        (updatedSlot.rosterDayId, updatedSlot.rowIndex)
            : map (\slot -> (slot.rosterDayId, slot.rowIndex)) affectedSlots
    where
        impactedStaffIds = catMaybes [previousStaffId, updatedSlot.staffId]
        affectedSlots = filter (\slot -> slot.staffId `elem` map Just impactedStaffIds) relatedSlots

filterVisibleRosterSlots :: [RosterDay] -> [RosterSlot] -> [RosterSlot]
filterVisibleRosterSlots rosterDays allSlots =
    let openRosterDayIds = map (coerce . (.id)) (filter (not . (.isClosed)) rosterDays)
     in filter (\slot -> slot.rosterDayId `elem` openRosterDayIds) allSlots

ensureRosterDayHasMinimumRows :: (?modelContext :: ModelContext) => RosterDay -> Id RosterGroup -> Int -> IO ()
ensureRosterDayHasMinimumRows rosterDay rosterGroupId minimumRowCount = do
    existingSlots <- query @RosterSlot
        |> filterWhere (#rosterDayId, unpackId rosterDay.id)
        |> fetch

    orderedSlotNames <- fetchActiveRosterGroupSlotNames rosterGroupId

    forM_ [0 .. minimumRowCount - 1] \rowIndex ->
        forM_ orderedSlotNames \slotName ->
            when (isNothing (find (\slot -> slot.rowIndex == rowIndex && slot.slotNameId == unpackId slotName.id) existingSlots)) do
                _ <- newRecord @RosterSlot
                    |> set #rosterDayId (unpackId rosterDay.id)
                    |> set #slotNameId (unpackId slotName.id)
                    |> set #rowIndex rowIndex
                    |> createRecord
                pure ()

applyOptionalField :: forall field model value. (SetField field model value) => Proxy field -> value -> Maybe Text -> model -> model
applyOptionalField _ parsedValue rawParam model =
    case rawParam of
        Nothing -> model
        Just _  -> setField @field parsedValue model
