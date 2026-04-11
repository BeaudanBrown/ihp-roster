{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Web.Controller.RosterWeeks where

import Application.Helper.Conflict
import Application.Helper.Controller
import Application.Helper.LiveUpdate
import Application.Helper.Profiling
import Application.Helper.RosterGroups
import Application.Helper.SurfaceProjection
import Application.Helper.View (ToastOverlayConfig (..),
                                ToastOverlayPosition (ToastBottomCenter),
                                appendQueryParams,
                                linkedActiveStaffForRosterPanel,
                                renderToastOverlayHostOob)
import qualified Data.Aeson as Aeson
import Data.Coerce (coerce)
import Data.List (find, nub, nubBy, sortOn)
import qualified Data.Map.Strict as Map
import Data.Maybe (catMaybes, fromMaybe, isJust, mapMaybe)
import qualified Data.Text as Text
import Data.Time (diffDays, getCurrentTime, utctDay)
import qualified Data.Time.Calendar as Calendar
import Data.Time.Calendar.WeekDate (toWeekDate)
import Data.Time.Format (defaultTimeLocale, parseTimeM)
import Data.Time.LocalTime (TimeOfDay)
import qualified Data.UUID as UUID
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.RosterWeeks.Capabilities (buildRosterViewCapabilities)
import Web.RosterWeeks.Dom
import Web.RosterWeeks.Types
import Web.View.RosterWeeks.Grid (lastRowIndexForRows,
                                  renderRosterContentFragment,
                                  renderRosterContentFragmentOob,
                                  renderRosterDaySectionFragment,
                                  renderRosterDaySectionFragmentOob,
                                  renderRowFragment, renderRowOob,
                                  rowsForDay)
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

normalizeOptionalSlotFlag :: Maybe Text -> Either Text (Maybe Text)
normalizeOptionalSlotFlag value =
    case Text.toUpper <$> normalizeOptionalText value of
        Just normalized | Text.length normalized > 2 ->
            Left "Flags can only be 1 or 2 characters."
        normalized -> Right normalized

rosterAssignmentFiltersSessionKey :: ByteString
rosterAssignmentFiltersSessionKey = "rosterAssignmentFilters"

defaultRosterAssignmentFilters :: RosterAssignmentFilters
defaultRosterAssignmentFilters =
    RosterAssignmentFilters
        { hideStaffAtIdealShifts = False
        , hideStaffUnavailable = False
        , hideStaffOnApprovedLeave = False
        , hideStaffAlreadyAssignedToday = False
        }

encodeRosterAssignmentFilters :: RosterAssignmentFilters -> Text
encodeRosterAssignmentFilters filters =
    Text.pack
        [ encodeFlag filters.hideStaffAtIdealShifts
        , encodeFlag filters.hideStaffUnavailable
        , encodeFlag filters.hideStaffOnApprovedLeave
        , encodeFlag filters.hideStaffAlreadyAssignedToday
        ]
    where
        encodeFlag True  = '1'
        encodeFlag False = '0'

decodeRosterAssignmentFilters :: Text -> RosterAssignmentFilters
decodeRosterAssignmentFilters encoded =
    case Text.unpack encoded of
        [idealFlag, unavailableFlag, leaveFlag, assignedFlag] ->
            RosterAssignmentFilters
                { hideStaffAtIdealShifts = decodeFlag idealFlag
                , hideStaffUnavailable = decodeFlag unavailableFlag
                , hideStaffOnApprovedLeave = decodeFlag leaveFlag
                , hideStaffAlreadyAssignedToday = decodeFlag assignedFlag
                }
        _ -> defaultRosterAssignmentFilters
    where
        decodeFlag '1' = True
        decodeFlag _   = False

rosterAssignmentFiltersFromParams :: (?context :: ControllerContext, ?request :: Request) => RosterAssignmentFilters
rosterAssignmentFiltersFromParams =
    RosterAssignmentFilters
        { hideStaffAtIdealShifts = isJust (paramOrNothing @Text "hideStaffAtIdealShifts")
        , hideStaffUnavailable = isJust (paramOrNothing @Text "hideStaffUnavailable")
        , hideStaffOnApprovedLeave = isJust (paramOrNothing @Text "hideStaffOnApprovedLeave")
        , hideStaffAlreadyAssignedToday = isJust (paramOrNothing @Text "hideStaffAlreadyAssignedToday")
        }

fetchRosterAssignmentFilters :: (?context :: ControllerContext, ?request :: Request) => IO RosterAssignmentFilters
fetchRosterAssignmentFilters = do
    encoded <- getSession @Text rosterAssignmentFiltersSessionKey
    pure (maybe defaultRosterAssignmentFilters decodeRosterAssignmentFilters encoded)

setRosterAssignmentFiltersSession :: (?context :: ControllerContext, ?request :: Request) => RosterAssignmentFilters -> IO ()
setRosterAssignmentFiltersSession filters =
    setSession rosterAssignmentFiltersSessionKey (encodeRosterAssignmentFilters filters)

buildSlotConflicts :: (?modelContext :: ModelContext) => Id RosterGroup -> Int -> Calendar.Day -> [RosterDay] -> [RosterSlot] -> [Staff] -> IO [(Id RosterSlot, [RosterConflict])]
buildSlotConflicts rosterGroupId lateToEarlyMinStartGapMinutes weekStartDate rosterDays allSlots staffMembers = do
    let assignedStaffIds = nub $ mapMaybe (.staffId) allSlots
    if null assignedStaffIds
        then pure []
        else do
            leaveRequests <- query @LeaveRequest
                |> filterWhereIn (#staffId, assignedStaffIds)
                |> fetch

            shiftPreferences <- query @StaffShiftPreference
                |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
                |> filterWhereIn (#staffId, assignedStaffIds)
                |> fetch

            let dayById = map (\day -> (coerce (get #id day), day)) rosterDays
            let conflictsBySlot = mapMaybe (conflictsForSlot dayById leaveRequests shiftPreferences) allSlots
            pure conflictsBySlot
    where
        conflictsForSlot dayById leaveRequests shiftPreferences slot = do
            staffUuid <- slot.staffId
            day <- lookup slot.rosterDayId dayById
            let weekSlotsForStaff = filter (\candidate -> candidate.staffId == Just staffUuid) allSlots
            let daySlotsForStaff = filter (\candidate -> candidate.rosterDayId == slot.rosterDayId && candidate.staffId == Just staffUuid) allSlots
            let staffIdealShifts = (.idealShiftsPerWeek) <$> find (\staff -> coerce (get #id staff) == staffUuid) staffMembers
            let leaveRequestsForStaff = filter (\leaveRequest -> leaveRequest.staffId == staffUuid) leaveRequests
            let shiftPreferencesForStaff = filter (\preference -> preference.staffId == staffUuid) shiftPreferences
            let rosterDayDate = Calendar.addDays (toInteger day.dayOffset) weekStartDate
            let conflicts = evaluateConflicts ConflictContext
                    { slot
                    , rosterGroupId = unpackId rosterGroupId
                    , weekSlots = weekSlotsForStaff
                    , daySlots = daySlotsForStaff
                    , weekRosterDays = rosterDays
                    , leaveRequests = leaveRequestsForStaff
                    , shiftPreferences = shiftPreferencesForStaff
                    , rosterDayDate
                    , lateToEarlyMinStartGapMinutes
                    , staffIdealShifts
                    }
            if null conflicts
                then Nothing
                else Just (get #id slot, conflicts)

respondWithRosterContent :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO ()
respondWithRosterContent rosterGroupId weekOffset =
    respondHtmlProfiled . fromMaybe mempty =<< renderVisibleRosterProjectionFragment rosterGroupId weekOffset RosterProjectionContent

respondWithRosterContentOob :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO ()
respondWithRosterContentOob rosterGroupId weekOffset = do
    rosterGroups <- fetchCurrentVenueRosterGroups
    currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (Just rosterGroupId)
    rosterData <- fetchVisibleRosterRenderDataCached rosterGroupId weekOffset
    case rosterData of
        Nothing -> respondHtmlProfiled [hsx|<div id="roster-content" hx-swap-oob="outerHTML"></div>|]
        Just RosterRenderData { rosterWeek, rosterDays, weekStartDate, assignmentFilters, staffMembers, staffOptionStates, panelStaff, orderedSlotNames, allSlots, slotConflicts, renderIndexes } ->
            let viewCapabilities = buildRosterViewCapabilities (Just rosterWeek)
             in respondHtmlProfiled $
                    renderRosterContentFragmentOob
                        (Just rosterWeek)
                        rosterDays
                        weekOffset
                        rosterGroups
                        currentRosterGroup
                        assignmentFilters
                        staffMembers
                        staffOptionStates
                        panelStaff
                        orderedSlotNames
                        weekStartDate
                        allSlots
                        slotConflicts
                        renderIndexes
                        viewCapabilities

respondWithRosterContentUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Text -> IO ()
respondWithRosterContentUpdate rosterGroupId weekOffset successMessage = do
    rosterGroups <- fetchCurrentVenueRosterGroups
    currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (Just rosterGroupId)
    rosterData <- fetchVisibleRosterRenderDataCached rosterGroupId weekOffset
    respondHtmlProfiled $
        mconcat
            [ case rosterData of
                Nothing -> [hsx|<div id="roster-content"></div>|]
                Just RosterRenderData { rosterWeek, rosterDays, weekStartDate, assignmentFilters, staffMembers, staffOptionStates, panelStaff, orderedSlotNames, allSlots, slotConflicts, renderIndexes } ->
                    let viewCapabilities = buildRosterViewCapabilities (Just rosterWeek)
                     in renderRosterContentFragment
                            (Just rosterWeek)
                            rosterDays
                            weekOffset
                            rosterGroups
                            currentRosterGroup
                            assignmentFilters
                            staffMembers
                            staffOptionStates
                            panelStaff
                            orderedSlotNames
                            weekStartDate
                            allSlots
                            slotConflicts
                            renderIndexes
                            viewCapabilities
            , renderToastOverlayHostOob ToastBottomCenter
                [ ToastOverlayConfig
                    { toastOverlayTitle = Just "Success"
                    , toastOverlayMessage = successMessage
                    , toastOverlayClass = "app-toast-success"
                    , toastOverlayAutoHideMs = 3200
                    }
                ]
            ]

respondWithRosterToast :: (?context :: ControllerContext, ?request :: Request) => Text -> Text -> IO ()
respondWithRosterToast message toastClass =
    respondHtmlProfiled $
        renderToastOverlayHostOob ToastBottomCenter
            [ ToastOverlayConfig
                { toastOverlayTitle = Just (if toastClass == "app-toast-error" then "Error" else "Success")
                , toastOverlayMessage = message
                , toastOverlayClass = toastClass
                , toastOverlayAutoHideMs = if toastClass == "app-toast-error" then 4200 else 3200
                }
            ]

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

buildRosterProjectionScope :: Id RosterGroup -> Int -> RosterProjectionScope
buildRosterProjectionScope rosterGroupId weekOffset =
    RosterProjectionScope
        { rosterProjectionGroupId = rosterGroupId
        , rosterProjectionWeekOffset = weekOffset
        }

rosterProjectionDefinition :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => SurfaceProjectionDefinition RosterProjectionScope (Maybe RosterRenderData) RosterProjectionFragment
rosterProjectionDefinition =
    SurfaceProjectionDefinition
        { surfaceName = "roster-week"
        , cachePolicy = defaultSurfaceProjectionCachePolicy
        , scopeKey = \scope -> tshow scope.rosterProjectionGroupId <> ":" <> tshow scope.rosterProjectionWeekOffset
        , viewerKey = do
            filters <- fetchRosterAssignmentFilters
            pure (tshow currentUser.id <> ":" <> encodeRosterAssignmentFilters filters)
        , currentVersion = \scope -> currentLiveUpdateVersion (buildRosterWeekScope scope.rosterProjectionGroupId scope.rosterProjectionWeekOffset)
        , loadProjection = \scope -> fetchVisibleRosterRenderData scope.rosterProjectionGroupId scope.rosterProjectionWeekOffset
        , renderFragment = renderRosterProjectionFragment
        , buildFragmentRef = \scope fragment ->
            case fragment of
                RosterProjectionContent ->
                    buildRosterContentFragmentRef scope.rosterProjectionGroupId scope.rosterProjectionWeekOffset
                RosterProjectionStaffPanel ->
                    buildRosterStaffPanelFragmentRef scope.rosterProjectionGroupId scope.rosterProjectionWeekOffset
                RosterProjectionDaySection rosterDayId ->
                    buildRosterDaySectionFragmentRef scope.rosterProjectionGroupId scope.rosterProjectionWeekOffset rosterDayId
                RosterProjectionRow rosterDayId rowIndex ->
                    buildRosterRowFragmentRef scope.rosterProjectionGroupId scope.rosterProjectionWeekOffset rosterDayId rowIndex
        }

fetchVisibleRosterRenderDataCached :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (Maybe RosterRenderData)
fetchVisibleRosterRenderDataCached rosterGroupId weekOffset =
    profileActionSpanWithDetail "roster.projection.load" do
        let scope = buildRosterProjectionScope rosterGroupId weekOffset
        before <- readSurfaceProjectionCacheStats
        projection <- loadSurfaceProjection rosterProjectionDefinition scope
        after <- readSurfaceProjectionCacheStats
        pure (projection, surfaceProjectionCacheDeltaDetail before after)

renderVisibleRosterProjectionFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> RosterProjectionFragment -> IO (Maybe Blaze.Html)
renderVisibleRosterProjectionFragment rosterGroupId weekOffset fragment =
    case fragment of
        RosterProjectionContent -> do
            rosterGroups <- fetchCurrentVenueRosterGroups
            currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (Just rosterGroupId)
            rosterData <- fetchVisibleRosterRenderDataCached rosterGroupId weekOffset
            pure (Just (renderRosterContentFromProjection rosterGroups currentRosterGroup rosterData))
        _ ->
            profileActionSpanWithDetail "roster.projection.render_fragment" do
                let scope = buildRosterProjectionScope rosterGroupId weekOffset
                before <- readSurfaceProjectionCacheStats
                html <- renderSurfaceProjectionFragment rosterProjectionDefinition scope fragment
                after <- readSurfaceProjectionCacheStats
                pure (html, surfaceProjectionCacheDeltaDetail before after)

renderRosterProjectionFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Maybe RosterRenderData -> RosterProjectionFragment -> Maybe Blaze.Html
renderRosterProjectionFragment rosterData fragment =
    case fragment of
        RosterProjectionContent ->
            Nothing
        RosterProjectionStaffPanel ->
            Just (renderRosterStaffPanelFromProjection rosterData)
        RosterProjectionDaySection rosterDayId ->
            rosterData >>= \projection -> renderRequestedDaySectionFragmentFromProjection projection rosterDayId
        RosterProjectionRow rosterDayId rowIndex ->
            rosterData >>= \projection -> renderRequestedRowFragmentFromProjection projection rosterDayId rowIndex

renderRosterContentFromProjection :: (?context :: ControllerContext, ?request :: Request) => [RosterGroup] -> RosterGroup -> Maybe RosterRenderData -> Blaze.Html
renderRosterContentFromProjection rosterGroups currentRosterGroup rosterData =
    case rosterData of
        Nothing -> [hsx|<div id="roster-content"></div>|]
        Just RosterRenderData { rosterWeek, rosterDays, weekStartDate, assignmentFilters, staffMembers, staffOptionStates, panelStaff, orderedSlotNames, allSlots, slotConflicts, renderIndexes } ->
            let viewCapabilities = buildRosterViewCapabilities (Just rosterWeek)
             in renderRosterContentFragment
                    (Just rosterWeek)
                    rosterDays
                    rosterWeek.weekOffset
                    rosterGroups
                    currentRosterGroup
                    assignmentFilters
                    staffMembers
                    staffOptionStates
                    panelStaff
                    orderedSlotNames
                    weekStartDate
                    allSlots
                    slotConflicts
                    renderIndexes
                    viewCapabilities

renderRosterStaffPanelFromProjection :: (?context :: ControllerContext, ?request :: Request) => Maybe RosterRenderData -> Blaze.Html
renderRosterStaffPanelFromProjection rosterData =
    case rosterData of
        Nothing -> mempty
        Just RosterRenderData { rosterWeek, panelStaff } ->
            renderRosterStaffPanelFragment rosterWeek.weekOffset (coerce rosterWeek.rosterGroupId) panelStaff

renderRequestedRowFragmentFromProjection :: (?context :: ControllerContext, ?request :: Request) => RosterRenderData -> UUID.UUID -> Int -> Maybe Blaze.Html
renderRequestedRowFragmentFromProjection RosterRenderData { rosterWeek, weekStartDate, assignmentFilters, staffMembers, staffOptionStates, orderedSlotNames, renderIndexes } rosterDayId rowIndex =
    renderRequestedRowFragment (hasRole ManagerRole' && not rosterWeek.isLive) weekStartDate orderedSlotNames assignmentFilters staffMembers staffOptionStates renderIndexes (rosterDayId, rowIndex)

renderRequestedDaySectionFragmentFromProjection :: (?context :: ControllerContext, ?request :: Request) => RosterRenderData -> UUID.UUID -> Maybe Blaze.Html
renderRequestedDaySectionFragmentFromProjection RosterRenderData { rosterWeek, weekStartDate, assignmentFilters, staffMembers, staffOptionStates, orderedSlotNames, allSlots, slotConflicts, renderIndexes } rosterDayId =
    renderRequestedDaySectionFragment (hasRole ManagerRole' && not rosterWeek.isLive) weekStartDate orderedSlotNames assignmentFilters staffMembers staffOptionStates allSlots slotConflicts renderIndexes rosterDayId

fetchRosterRenderData :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (Maybe RosterRenderData)
fetchRosterRenderData rosterGroupId weekOffset = do
    _ <- profileActionSpan "roster.ensure_week_exists" (ensureRosterWeekExists rosterGroupId weekOffset)
    venueConfig <- fetchVenueConfig
    assignmentFilters <- fetchRosterAssignmentFilters
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
            eligibleStaffMembers <- profileActionSpan "roster.fetch_eligible_staff" (fetchEligibleRosterGroupStaff rosterGroupId)
            assignedStaffMembers <- profileActionSpan "roster.fetch_assigned_staff" (fetchAssignedRosterWeekStaff visibleSlots)
            let staffMembers = nubBy (\left right -> left.id == right.id) (eligibleStaffMembers <> assignedStaffMembers)
            panelStaff <- profileActionSpan "roster.build_staff_panel" (fetchRosterStaffPanelEntries eligibleStaffMembers visibleSlots)
            staffOptionStates <- profileActionSpan "roster.build_staff_option_states" (buildRosterStaffOptionStates assignmentFilters weekStartDate rosterDays visibleSlots staffMembers)
            orderedSlotNames <- profileActionSpan "roster.fetch_ordered_slot_names" (fetchRosterWeekOrderedSlotNamesFromSlots allSlots)
            slotConflicts <-
                if rosterWeek.isLive
                    then pure []
                    else profileActionSpan "roster.build_slot_conflicts" (buildSlotConflicts rosterGroupId venueConfig.lateToEarlyMinStartGapMinutes weekStartDate rosterDays visibleSlots staffMembers)
            let renderIndexes = buildRosterRenderIndexes rosterDays visibleSlots staffMembers slotConflicts
            pure (Just RosterRenderData { rosterWeek, rosterDays, weekStartDate, assignmentFilters, staffMembers, staffOptionStates, panelStaff, orderedSlotNames, allSlots, slotConflicts, renderIndexes })

fetchVisibleRosterRenderData :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (Maybe RosterRenderData)
fetchVisibleRosterRenderData rosterGroupId weekOffset = do
    visibleRosterWeek <- fetchVisibleRosterWeek rosterGroupId weekOffset
    case visibleRosterWeek of
        Nothing -> do
            (backingRosterWeek, rosterDays, weekStartDate, orderedSlotNames, maskedSlots) <- fetchHiddenRosterRenderData rosterGroupId weekOffset
            let renderIndexes = buildRosterRenderIndexes rosterDays (filterVisibleRosterSlots rosterDays maskedSlots) [] []
            pure $
                Just
                    RosterRenderData
                        { rosterWeek = backingRosterWeek
                        , rosterDays
                        , weekStartDate
                        , assignmentFilters = defaultRosterAssignmentFilters
                        , staffMembers = []
                        , staffOptionStates = Map.empty
                        , panelStaff = []
                        , orderedSlotNames
                        , allSlots = maskedSlots
                        , slotConflicts = []
                        , renderIndexes
                        }
        Just _  -> fetchRosterRenderData rosterGroupId weekOffset

fetchVisibleRosterWeek :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (Maybe RosterWeek)
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

buildRosterRenderIndexes :: [RosterDay] -> [RosterSlot] -> [Staff] -> [(Id RosterSlot, [RosterConflict])] -> RosterRenderIndexes
buildRosterRenderIndexes rosterDays visibleSlots staffMembers slotConflicts =
    RosterRenderIndexes
        { rosterDayById = Map.fromList [(coerce (get #id rosterDay), rosterDay) | rosterDay <- rosterDays]
        , rosterDayRowsByDayId =
            Map.fromList
                [ (coerce (get #id rosterDay), rowsForDay rosterDay daySlots)
                | rosterDay <- rosterDays
                , let daySlots = filter (\slot -> slot.rosterDayId == coerce (get #id rosterDay)) visibleSlots
                ]
        , rosterSlotByDayRowSlotName =
            Map.fromList
                [ ((slot.rosterDayId, slot.rowIndex, slot.slotNameId), slot)
                | slot <- visibleSlots
                ]
        , rosterStaffById = Map.fromList [(coerce (get #id staff), staff) | staff <- staffMembers]
        , rosterConflictsBySlotId = Map.fromList [(coerce slotId, conflicts) | (slotId, conflicts) <- slotConflicts]
        }

buildRosterMonthOverviewDays :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Calendar.Day -> Id RosterGroup -> Calendar.Day -> IO [RosterWeekOverviewDay]
buildRosterMonthOverviewDays epoch rosterGroupId focusDate = do
    let (monthStartDate, monthEndDate) = monthBounds focusDate
    let firstWeekOffset = weekOffsetForDay epoch (startOfWeek monthStartDate)
    let lastWeekOffset = weekOffsetForDay epoch (startOfWeek monthEndDate)
    let monthWeekOffsets = [firstWeekOffset .. lastWeekOffset]

    rosterWeeks <-
        if null monthWeekOffsets
            then pure []
            else
                (query @RosterWeek
                    |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
                    |> filterWhereIn (#weekOffset, monthWeekOffsets)
                    |> applyVisibleRosterWeekScope
                )
                    |> fetch

    let rosterWeekIds = map (coerce . (.id)) rosterWeeks
    rosterDays <-
        if null rosterWeekIds
            then pure []
            else query @RosterDay
                |> filterWhereIn (#rosterWeekId, rosterWeekIds)
                |> fetch

    let rosterDayIds = map (coerce . (.id)) rosterDays
    allSlots <-
        if null rosterDayIds
            then pure []
            else query @RosterSlot
                |> filterWhereIn (#rosterDayId, rosterDayIds)
                |> fetch

    eligibleStaffMembers <- fetchEligibleRosterGroupStaff rosterGroupId
    assignedStaffMembers <- fetchAssignedRosterWeekStaff allSlots
    let overviewStaffIds = nub (map (coerce . (.id)) (eligibleStaffMembers <> assignedStaffMembers))
    leaveRequests <-
        if null overviewStaffIds
            then pure []
            else query @LeaveRequest
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhereIn (#staffId, overviewStaffIds)
                |> fetch

    let rosterWeekStartDates = Map.fromList
            [ (coerce rosterWeek.id, Calendar.addDays (toInteger (rosterWeek.weekOffset * 7)) epoch)
            | rosterWeek <- rosterWeeks
            ]
    let rosterDaysByDate = Map.fromList
            [ (overviewDate, rosterDay)
            | rosterDay <- rosterDays
            , Just weekStartDate <- [Map.lookup rosterDay.rosterWeekId rosterWeekStartDates]
            , let overviewDate = Calendar.addDays (toInteger rosterDay.dayOffset) weekStartDate
            , overviewDate >= monthStartDate
            , overviewDate <= monthEndDate
            ]
    let slotsByRosterDayId = Map.fromListWith (++) [ (slot.rosterDayId, [slot]) | slot <- allSlots ]

    pure [ buildDaySummary overviewDate (Map.lookup overviewDate rosterDaysByDate) (maybe [] (\rosterDay -> Map.findWithDefault [] (coerce rosterDay.id) slotsByRosterDayId) (Map.lookup overviewDate rosterDaysByDate)) leaveRequests
         | overviewDate <- [monthStartDate .. monthEndDate]
         ]
    where
        applyVisibleRosterWeekScope queryBuilder =
            if hasRole ManagerRole'
                then queryBuilder
                else queryBuilder |> filterWhere (#isLive, True)

        buildDaySummary overviewDate maybeRosterDay daySlots leaveRequests =
            let
                assignedShiftCount =
                    length
                        [ ()
                        | slot <- daySlots
                        , isJust slot.staffId
                        ]
                scheduledMinutes =
                    sum
                        [ fromMaybe 0 slot.durationMinutes
                        | slot <- daySlots
                        , isJust slot.staffId
                        ]
                leaveRequestCount =
                    length
                        [ leaveRequest
                        | leaveRequest <- leaveRequests
                        , parseLeaveRequestStatus leaveRequest.status `elem` [Just LeavePending, Just LeaveApproved]
                        , overviewDate >= leaveRequest.startDate
                        , overviewDate < leaveRequest.endDate
                        ]
             in
                RosterWeekOverviewDay
                    { overviewDate
                    , leaveRequestCount
                    , overviewAssignedShiftCount = assignedShiftCount
                    , scheduledMinutes
                    , overviewIsClosed = maybe False (.isClosed) maybeRosterDay
                    }

initialOverviewFocusDate :: Calendar.Day -> Calendar.Day -> Calendar.Day
initialOverviewFocusDate weekStartDate todayDate =
    if todayDate >= weekStartDate && todayDate <= Calendar.addDays 6 weekStartDate
        then todayDate
        else weekStartDate

monthBounds :: Calendar.Day -> (Calendar.Day, Calendar.Day)
monthBounds focusDate =
    let
        (year, month, _) = Calendar.toGregorian focusDate
        monthStartDate = Calendar.fromGregorian year month 1
        monthEndDate = Calendar.fromGregorian year month (Calendar.gregorianMonthLength year month)
     in
        (monthStartDate, monthEndDate)

startOfWeek :: Calendar.Day -> Calendar.Day
startOfWeek day =
    let (_, _, weekdayNumber) = toWeekDate day
     in Calendar.addDays (toInteger (1 - weekdayNumber)) day

fetchVisibleRosterStaffPanelEntries :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (Maybe [RosterStaffPanelEntry])
fetchVisibleRosterStaffPanelEntries rosterGroupId weekOffset = do
    rosterData <- fetchVisibleRosterRenderDataCached rosterGroupId weekOffset
    pure ((\RosterRenderData { panelStaff } -> panelStaff) <$> rosterData)

buildRosterStaffOptionStates :: (?modelContext :: ModelContext) => RosterAssignmentFilters -> Calendar.Day -> [RosterDay] -> [RosterSlot] -> [Staff] -> IO (Map.Map (UUID.UUID, UUID.UUID) RosterAssignmentOptionState)
buildRosterStaffOptionStates assignmentFilters weekStartDate rosterDays visibleSlots staffMembers = do
    let staffIds = map (coerce . (.id)) staffMembers
    if null staffIds
        then pure Map.empty
        else do
            leaveRequests <- query @LeaveRequest
                |> filterWhereIn (#staffId, staffIds)
                |> fetch
            shiftPreferences <- query @StaffShiftPreference
                |> filterWhereIn (#staffId, staffIds)
                |> fetch

            let dayById = Map.fromList (map (\day -> (coerce (get #id day), day)) rosterDays)
            pure $
                Map.fromList
                    [ ((coerce (get #id slot), coerce (get #id staff)), rosterAssignmentOptionStateFor assignmentFilters weekStartDate dayById visibleSlots leaveRequests shiftPreferences slot staff)
                    | slot <- visibleSlots
                    , staff <- staffMembers
                    ]

rosterAssignmentOptionStateFor :: RosterAssignmentFilters -> Calendar.Day -> Map.Map UUID.UUID RosterDay -> [RosterSlot] -> [LeaveRequest] -> [StaffShiftPreference] -> RosterSlot -> Staff -> RosterAssignmentOptionState
rosterAssignmentOptionStateFor assignmentFilters weekStartDate dayById visibleSlots leaveRequests shiftPreferences slot staff =
    let staffId = coerce (get #id staff)
        visibleSlotNameIds = nub (map (.slotNameId) visibleSlots)
        rosterDayDate =
            case Map.lookup slot.rosterDayId dayById of
                Just rosterDay -> Calendar.addDays (toInteger rosterDay.dayOffset) weekStartDate
                Nothing -> weekStartDate
        assignedShiftCount = length (filter (\candidate -> candidate.staffId == Just staffId) visibleSlots)
        assignedToday = any (\candidate -> candidate.rosterDayId == slot.rosterDayId && candidate.staffId == Just staffId && get #id candidate /= get #id slot) visibleSlots
        unavailable = hasNoPreferredShiftsOnDay staffId visibleSlotNameIds rosterDayDate shiftPreferences
        onApprovedLeave = any (isApprovedLeaveOn rosterDayDate staffId) leaveRequests
        hiddenByIdeal = assignmentFilters.hideStaffAtIdealShifts && assignedShiftCount >= staff.idealShiftsPerWeek
        hiddenByUnavailable = assignmentFilters.hideStaffUnavailable && unavailable
        hiddenByLeave = assignmentFilters.hideStaffOnApprovedLeave && onApprovedLeave
        hiddenByAssignedToday = assignmentFilters.hideStaffAlreadyAssignedToday && assignedToday
    in RosterAssignmentOptionState
        { optionHidden = hiddenByIdeal || hiddenByUnavailable || hiddenByLeave || hiddenByAssignedToday
        , optionAssignedShiftCount = assignedShiftCount
        , optionHiddenByIdeal = hiddenByIdeal
        , optionHiddenByUnavailable = hiddenByUnavailable
        , optionHiddenByLeave = hiddenByLeave
        , optionHiddenByAssignedToday = hiddenByAssignedToday
        }

isApprovedLeaveOn :: Calendar.Day -> UUID.UUID -> LeaveRequest -> Bool
isApprovedLeaveOn rosterDayDate staffId leaveRequest =
    leaveRequest.staffId == staffId
        && parseLeaveRequestStatus leaveRequest.status == Just LeaveApproved
        && rosterDayDate >= leaveRequest.startDate
        && rosterDayDate < leaveRequest.endDate

hasNoPreferredShiftsOnDay :: UUID.UUID -> [UUID.UUID] -> Calendar.Day -> [StaffShiftPreference] -> Bool
hasNoPreferredShiftsOnDay staffId visibleSlotNameIds rosterDayDate shiftPreferences =
    null
        [ preference
        | preference <- shiftPreferences
        , preference.staffId == staffId
        , preference.slotNameId `elem` visibleSlotNameIds
        , preference.weekdayIndex == weekdayIndexForDay rosterDayDate
        ]

fetchVisibleRosterRowFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Id RosterDay -> Int -> IO (Maybe Blaze.Html)
fetchVisibleRosterRowFragment rosterGroupId weekOffset rosterDayId rowIndex = do
    renderVisibleRosterProjectionFragment rosterGroupId weekOffset (RosterProjectionRow (unpackId rosterDayId) rowIndex)

fetchVisibleRosterDaySectionFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Id RosterDay -> IO (Maybe Blaze.Html)
fetchVisibleRosterDaySectionFragment rosterGroupId weekOffset rosterDayId = do
    renderVisibleRosterProjectionFragment rosterGroupId weekOffset (RosterProjectionDaySection (unpackId rosterDayId))

fetchCurrentRosterWeekOffset :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO Int
fetchCurrentRosterWeekOffset = do
    venueConfig <- fetchVenueConfig
    today <- utctDay <$> getCurrentTime
    pure (weekOffsetForDay venueConfig.weekOffsetEpoch today)

weekOffsetForDay :: Calendar.Day -> Calendar.Day -> Int
weekOffsetForDay epoch day =
    fromInteger (diffDays day epoch `div` 7)

keepCurrentRosterWeekProjectionHot :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO ()
keepCurrentRosterWeekProjectionHot rosterGroupId weekOffset = do
    currentWeekOffset <- fetchCurrentRosterWeekOffset
    when (weekOffset == currentWeekOffset) $
        warmSurfaceProjection rosterProjectionDefinition (buildRosterProjectionScope rosterGroupId weekOffset)

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

buildDeferredRosterContentFragmentRef :: (?context :: ControllerContext) => Id RosterGroup -> Int -> LiveFragmentRef
buildDeferredRosterContentFragmentRef rosterGroupId weekOffset =
    (buildRosterContentFragmentRef rosterGroupId weekOffset) { deferUntilBlur = True }

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

buildActorRosterRowFragmentRefs :: (?context :: ControllerContext) => Maybe Text -> Id RosterGroup -> Int -> [(UUID.UUID, Int)] -> [LiveFragmentRef]
buildActorRosterRowFragmentRefs maybeStaffParam rosterGroupId weekOffset rowKeys =
    let refs = buildRosterRowFragmentRefs rosterGroupId weekOffset rowKeys
     in if isJust maybeStaffParam
            then map disableFragmentBlurDeferral refs
            else refs

buildAssignmentRefreshFragmentRefs :: (?context :: ControllerContext) => Maybe Text -> Id RosterGroup -> Int -> [LiveFragmentRef]
buildAssignmentRefreshFragmentRefs maybeStaffParam rosterGroupId weekOffset =
    if isJust maybeStaffParam
        then [buildDeferredRosterContentFragmentRef rosterGroupId weekOffset]
        else []

buildRosterRowFragmentRef :: (?context :: ControllerContext) => Id RosterGroup -> Int -> UUID.UUID -> Int -> LiveFragmentRef
buildRosterRowFragmentRef rosterGroupId weekOffset rosterDayId rowIndex =
    LiveFragmentRef
        { fragmentKey = RosterRowFragment { rosterDayId, rowIndex }
        , targetId = rosterRowDomIdText (coerce rosterDayId) rowIndex
        , url = appendQueryParams (pathTo ShowRosterWeekRowFragmentAction { weekOffset, rosterDayId = coerce rosterDayId, rowIndex }) [("rosterGroupId", tshow rosterGroupId)]
        , deferUntilBlur = True
        }

disableFragmentBlurDeferral :: LiveFragmentRef -> LiveFragmentRef
disableFragmentBlurDeferral fragment = fragment { deferUntilBlur = False }

broadcastRosterWeekInvalidation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
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
        keepCurrentRosterWeekProjectionHot rosterGroupId weekOffset

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

type RosterWeekSlotTemplate = (SlotName, Int)

fetchRosterWeekSlotTemplate :: (?modelContext :: ModelContext) => RosterWeek -> IO [RosterWeekSlotTemplate]
fetchRosterWeekSlotTemplate rosterWeek = do
    rosterDays <-
        query @RosterDay
            |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
            |> fetch
    if null rosterDays
        then pure []
        else do
            allSlots <-
                query @RosterSlot
                    |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) rosterDays)
                    |> fetch
            fetchRosterWeekSlotTemplateFromSlots allSlots

fetchRosterWeekSlotTemplateFromSlots :: (?modelContext :: ModelContext) => [RosterSlot] -> IO [RosterWeekSlotTemplate]
fetchRosterWeekSlotTemplateFromSlots allSlots = do
    let orderedSlotPairs =
            allSlots
                |> map (\slot -> (slot.slotNameId, slot.slotSortOrder))
                |> Map.fromListWith min
                |> Map.toList
                |> sortOn snd
    let orderedSlotIds = map fst orderedSlotPairs
    if null orderedSlotIds
        then pure []
        else do
            slotNames <-
                query @SlotName
                    |> filterWhereIn (#id, map Id orderedSlotIds)
                    |> fetch
            let slotNameById = Map.fromList (map (\slotName -> (unpackId slotName.id, slotName)) slotNames)
            pure
                [ (slotName, slotSortOrder)
                | (slotNameId, slotSortOrder) <- orderedSlotPairs
                , Just slotName <- [Map.lookup slotNameId slotNameById]
                ]

fetchRosterWeekOrderedSlotNames :: (?modelContext :: ModelContext) => RosterWeek -> IO [SlotName]
fetchRosterWeekOrderedSlotNames rosterWeek =
    map fst <$> fetchRosterWeekSlotTemplate rosterWeek

fetchRosterWeekOrderedSlotNamesFromSlots :: (?modelContext :: ModelContext) => [RosterSlot] -> IO [SlotName]
fetchRosterWeekOrderedSlotNamesFromSlots allSlots =
    map fst <$> fetchRosterWeekSlotTemplateFromSlots allSlots

syncRosterWeekSlotStructure :: (?modelContext :: ModelContext) => RosterWeek -> IO ()
syncRosterWeekSlotStructure rosterWeek = do
    currentSlotTemplate <- fetchActiveRosterGroupSlotNames (Id rosterWeek.rosterGroupId :: Id RosterGroup)
    rosterDays <-
        query @RosterDay
            |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
            |> fetch

    let currentSlotIds = map (unpackId . (.id)) currentSlotTemplate
    let sortOrderBySlotId = Map.fromList (map (\slotName -> (unpackId slotName.id, slotName.sortOrder)) currentSlotTemplate)

    forM_ rosterDays \rosterDay -> do
        existingSlots <-
            query @RosterSlot
                |> filterWhere (#rosterDayId, unpackId rosterDay.id)
                |> fetch

        let existingRowIndexes = nub (map (.rowIndex) existingSlots)
        let obsoleteSlots = filter (\slot -> slot.slotNameId `notElem` currentSlotIds) existingSlots
        unless (null obsoleteSlots) do
            deleteRecords obsoleteSlots

        forM_ existingSlots \slot ->
            case Map.lookup slot.slotNameId sortOrderBySlotId of
                Just slotSortOrder | slot.slotSortOrder /= slotSortOrder -> do
                    _ <- slot |> set #slotSortOrder slotSortOrder |> updateRecord
                    pure ()
                _ -> pure ()

        let retainedSlotPairs =
                [ (rowIndex, slotName)
                | rowIndex <- existingRowIndexes
                , slotName <- currentSlotTemplate
                ]

        forM_ retainedSlotPairs \(rowIndex, slotName) ->
            when (isNothing (find (\slot -> slot.rowIndex == rowIndex && slot.slotNameId == unpackId slotName.id) existingSlots)) do
                _ <-
                    newRecord @RosterSlot
                        |> set #rosterDayId (unpackId rosterDay.id)
                        |> set #slotNameId (unpackId slotName.id)
                        |> set #slotSortOrder slotName.sortOrder
                        |> set #rowIndex rowIndex
                        |> createRecord
                pure ()

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
                    |> set #slotSortOrder slotName.sortOrder
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
                        |> set #slotSortOrder slot.slotSortOrder
                        |> set #rowIndex slot.rowIndex
                        |> set #startTime slot.startTime
                        |> set #durationMinutes slot.durationMinutes
                        |> set #note slot.note
                        |> createRecord
                    pure ()
            Nothing -> pure ()

    pure targetWeek

fetchHiddenRosterRenderData :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (RosterWeek, [RosterDay], Calendar.Day, [SlotName], [RosterSlot])
fetchHiddenRosterRenderData rosterGroupId weekOffset = do
    rosterDataOrNothing <- fetchRosterRenderData rosterGroupId weekOffset
    case rosterDataOrNothing of
        Just RosterRenderData { rosterWeek, rosterDays, weekStartDate, orderedSlotNames, allSlots } ->
            pure (rosterWeek, rosterDays, weekStartDate, orderedSlotNames, maskRosterSlots rosterWeek allSlots)
        Nothing -> error "Roster week should exist after ensureRosterWeekExists"

fetchHiddenRosterWeekSkeleton :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (RosterWeek, [RosterDay], [SlotName], [RosterSlot])
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


renderRequestedRow weekStartDate orderedSlotNames assignmentFilters staffMembers staffOptionStates renderIndexes (rosterDayUuid, targetRowIndex) = do
    rosterDay <- Map.lookup rosterDayUuid renderIndexes.rosterDayById
    dayRows <- Map.lookup rosterDayUuid renderIndexes.rosterDayRowsByDayId
    let rowCount = length dayRows
    let lastRowIndex = lastRowIndexForRows dayRows
    let indexedRows = zip [0 :: Int ..] dayRows
    (rowPosition, (_, rowSlots)) <- find (\(_, (rowIndex, _)) -> rowIndex == targetRowIndex) indexedRows
    let date = Calendar.addDays (toInteger (get #dayOffset rosterDay)) weekStartDate
    pure (renderRowOob True orderedSlotNames assignmentFilters staffMembers staffOptionStates date rosterDay rowCount lastRowIndex renderIndexes (rowPosition, (targetRowIndex, rowSlots)))

renderRequestedRowFragment isEditable weekStartDate orderedSlotNames assignmentFilters staffMembers staffOptionStates renderIndexes (rosterDayUuid, targetRowIndex) = do
    rosterDay <- Map.lookup rosterDayUuid renderIndexes.rosterDayById
    dayRows <- Map.lookup rosterDayUuid renderIndexes.rosterDayRowsByDayId
    let rowCount = length dayRows
    let lastRowIndex = lastRowIndexForRows dayRows
    let indexedRows = zip [0 :: Int ..] dayRows
    (rowPosition, (_, rowSlots)) <- find (\(_, (rowIndex, _)) -> rowIndex == targetRowIndex) indexedRows
    let date = Calendar.addDays (toInteger (get #dayOffset rosterDay)) weekStartDate
    pure (renderRowFragment isEditable orderedSlotNames assignmentFilters staffMembers staffOptionStates date rosterDay rowCount lastRowIndex renderIndexes (rowPosition, (targetRowIndex, rowSlots)))

renderRequestedDaySection weekStartDate orderedSlotNames assignmentFilters staffMembers staffOptionStates allSlots slotConflicts renderIndexes rosterDayUuid = do
    rosterDay <- Map.lookup rosterDayUuid renderIndexes.rosterDayById
    pure (renderRosterDaySectionFragment True orderedSlotNames assignmentFilters staffMembers staffOptionStates weekStartDate allSlots slotConflicts renderIndexes rosterDay)

renderRequestedDaySectionFragment isEditable weekStartDate orderedSlotNames assignmentFilters staffMembers staffOptionStates allSlots slotConflicts renderIndexes rosterDayUuid = do
    rosterDay <- Map.lookup rosterDayUuid renderIndexes.rosterDayById
    pure (renderRosterDaySectionFragment isEditable orderedSlotNames assignmentFilters staffMembers staffOptionStates weekStartDate allSlots slotConflicts renderIndexes rosterDay)

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
    rosterWeek <- fetch (Id rosterDay.rosterWeekId :: Id RosterWeek)
    existingSlots <- query @RosterSlot
        |> filterWhere (#rosterDayId, unpackId rosterDay.id)
        |> fetch

    slotTemplate <- fetchRosterWeekSlotTemplate rosterWeek

    forM_ [0 .. minimumRowCount - 1] \rowIndex ->
        forM_ slotTemplate \(slotName, slotSortOrder) ->
            when (isNothing (find (\slot -> slot.rowIndex == rowIndex && slot.slotNameId == unpackId slotName.id) existingSlots)) do
                _ <- newRecord @RosterSlot
                    |> set #rosterDayId (unpackId rosterDay.id)
                    |> set #slotNameId (unpackId slotName.id)
                    |> set #slotSortOrder slotSortOrder
                    |> set #rowIndex rowIndex
                    |> createRecord
                pure ()

applyOptionalField :: forall field model value. (SetField field model value) => Proxy field -> value -> Maybe Text -> model -> model
applyOptionalField _ parsedValue rawParam model =
    case rawParam of
        Nothing -> model
        Just _  -> setField @field parsedValue model
