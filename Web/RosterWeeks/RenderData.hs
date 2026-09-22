{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Web.RosterWeeks.RenderData
    ( currentRosterGridViewMode
    , currentRosterTimelineDate
    , fetchVisibleRosterReadModel
    , fetchVisibleRosterReadModelForAuthorizedScope
    , fetchVisibleRosterStaffPanelRenderModel
    , fetchVisibleRosterStaffPanelRenderModelForAuthorizedScope
    , renderRosterProjectionFragmentWithMode
    , renderVisibleRosterReadModelFragment
    , renderVisibleRosterReadModelFragmentForAuthorizedScope
    , rosterGridRenderModelFromProjection
    )
where

import Application.Error.Runtime (ExternalRuntimeCategory (AuthorizedFrameworkInvariant),
                                  externalRuntimeInvariantFailure)
import Application.Helper.Conflict
import Application.Helper.Controller
import Application.Helper.FrontendContract.Surface.FragmentRender (FragmentRenderMode (..))
import Application.Helper.ProfileLeave (defaultLeaveRequestForOperationalDay)
import Application.Helper.Profiling
import Application.Helper.RosterGroups
import Application.Helper.RosterWagePrediction
import Application.Helper.UserPreferences
import Application.Helper.View.Staff (normalizedStaffDisplayBaseName,
                                      renderStaffLastInitial,
                                      staffDisplayBaseName)
import Application.Helper.VenueScopedQueries (fetchVenueShiftTypes)
import qualified Application.RosterNotification as Notification
import Application.RosterPublication (rosterDaysArePublished)
import Application.RosterTemplates (RosterTemplateLibrary,
                                    currentRosterTemplateActor)
import Application.VenueTime.Model (decodeRosterShiftTiming,
                                    decodeTimesheetTiming)
import Data.Coerce (coerce)
import qualified Data.Map.Strict as Map
import qualified Data.Time.Calendar as Calendar
import qualified Data.UUID as UUID
import qualified IHP.HSX.Markup as Markup
import Web.Controller.Prelude
import Web.RosterWeeks.AuthorizedScope
import Web.RosterWeeks.Capabilities
import Web.RosterWeeks.DateRange (RosterWindowLane, RosterWindowScope (..))
import Web.RosterWeeks.DirectReadModel
import Web.RosterWeeks.Filters
import Web.RosterWeeks.StaffOptions
import Web.RosterWeeks.Types
import Web.RosterWeeks.WageFilter (filterRosterWageSlots,
                                   pinnedRosterWageStaffId)
import Web.View.RosterWeeks.Grid
import Web.View.RosterWeeks.StaffPanel

-- Request-local authority and core facts for one roster window. The constructor
-- remains private so downstream projections cannot accidentally skip scope,
-- calendar, group-visibility, or current-venue checks.
data AuthorizedRosterSnapshot = AuthorizedRosterSnapshot
    { snapshotAuthorizedScope   :: !AuthorizedRosterScope
    , snapshotScope             :: !RosterWindowScope
    , snapshotVenueConfig       :: !VenueConfig
    , snapshotRosterGroups      :: ![RosterGroup]
    , snapshotRosterGroup       :: !RosterGroup
    , snapshotCurrentStaff      :: !(Maybe Staff)
    , snapshotRosterPreferences :: !UserRosterPreferences
    , snapshotWindowFacts       :: !RosterWindowFacts
    }

fetchAuthorizedRosterSnapshot :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> IO AuthorizedRosterSnapshot
fetchAuthorizedRosterSnapshot requestedScope = do
    authorizedScope <- authorizeRosterScope requestedScope
    fetchAuthorizedRosterSnapshotForAuthorizedScope authorizedScope

fetchAuthorizedRosterSnapshotForAuthorizedScope :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => AuthorizedRosterScope -> IO AuthorizedRosterSnapshot
fetchAuthorizedRosterSnapshotForAuthorizedScope authorizedScope =
    profileActionSpan "roster.snapshot.fetch_authorized" do
        let snapshotAuthorizedScope = authorizedScope
        let snapshotScope = authorizedScope.authorizedRosterWindowScope
        let snapshotVenueConfig = authorizedScope.authorizedVenueConfig
        let snapshotRosterGroups = authorizedScope.authorizedRosterGroups
        let snapshotRosterGroup = authorizedScope.authorizedRosterGroup
        let snapshotCurrentStaff = authorizedScope.authorizedCurrentStaff
        snapshotRosterPreferences <- profileActionSpan "roster.snapshot.fetch_user_preferences" fetchCurrentUserRosterPreferences
        snapshotWindowFacts <- fetchRosterWindowFactsForAuthorizedScopeDirect authorizedScope
        pure AuthorizedRosterSnapshot { .. }

shouldShowRosterWageEstimates :: (?context :: ControllerContext) => Bool -> Bool
shouldShowRosterWageEstimates userShowWageEstimates =
    hasRole VenueAdmin && userShowWageEstimates

fetchRosterPublicHolidayMap :: (?modelContext :: ModelContext) => VenueConfig -> Calendar.Day -> IO (Map.Map Calendar.Day Text)
fetchRosterPublicHolidayMap venueConfig weekStartDate = do
    holidays <-
        query @PublicHoliday
            |> filterWhere (#jurisdiction, venueConfig.publicHolidayJurisdiction)
            |> filterWhere (#isRegional, False)
            |> filterWhereGreaterThanOrEqualTo (#holidayDate, weekStartDate)
            |> filterWhereLessThanOrEqualTo (#holidayDate, Calendar.addDays 6 weekStartDate)
            |> orderByAsc #holidayDate
            |> orderByAsc #name
            |> fetch
    pure $
        Map.fromListWith
            (\newName existingName -> existingName <> ", " <> newName)
            [ (holiday.holidayDate, holiday.name)
            | holiday <- holidays
            ]

renderVisibleRosterReadModelFragment :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> RosterProjectionFragment -> IO (Maybe Markup.Html)
renderVisibleRosterReadModelFragment scope fragment = do
    authorizedScope <- authorizeRosterScope scope
    renderVisibleRosterReadModelFragmentForAuthorizedScope authorizedScope fragment

renderVisibleRosterReadModelFragmentForAuthorizedScope :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => AuthorizedRosterScope -> RosterProjectionFragment -> IO (Maybe Markup.Html)
renderVisibleRosterReadModelFragmentForAuthorizedScope authorizedScope fragment =
    profileActionSpan "roster.read_model.render_fragment" do
        snapshot <- fetchAuthorizedRosterSnapshotForAuthorizedScope authorizedScope
        case fragment of
            RosterProjectionContent -> do
                rosterData <- fetchVisibleRosterReadModelFromSnapshot snapshot
                Just <$> renderRosterContentFromProjection snapshot.snapshotRosterGroups snapshot.snapshotRosterGroup rosterData
            _ -> renderVisibleRosterFragment snapshot fragment

renderRosterProjectionFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Maybe RosterRenderData -> RosterProjectionFragment -> Maybe Markup.Html
renderRosterProjectionFragment =
    renderRosterProjectionFragmentWithMode FragmentPlain

renderRosterProjectionFragmentWithMode :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => FragmentRenderMode -> Maybe RosterRenderData -> RosterProjectionFragment -> Maybe Markup.Html
renderRosterProjectionFragmentWithMode renderMode rosterData fragment =
    case fragment of
        RosterProjectionContent ->
            Nothing
        RosterProjectionGridToolbar -> do
            projection <- rosterData
            let toolbarModel = rosterToolbarRenderModelFromProjection projection
            pure $ case renderMode of
                FragmentPlain        -> renderrosterGridToolbarLiveFragment toolbarModel
                FragmentOob swapAttr -> renderrosterGridToolbarLiveFragmentWithSwap swapAttr toolbarModel
        RosterProjectionGridFrame ->
            renderGridFragment renderrosterGridFrameLiveFragment renderrosterGridFrameLiveFragmentWithSwap rosterData
        RosterProjectionDayColumns ->
            renderDayColumnsFragment rosterData
        RosterProjectionDayRail ->
            renderDayRailFragment rosterData
        RosterProjectionWageRail ->
            renderWageRailFragment rosterData
        RosterProjectionSlotsGrid ->
            renderSlotsGridFragment rosterData
        RosterProjectionStaffPanel ->
            Just (renderRosterStaffPanelFromProjectionWithMode renderMode rosterData)
        RosterProjectionDaySection rosterDayId ->
            rosterData >>= \projection ->
                if isHiddenDraftForCurrentUser projection.rosterWeek
                    then Nothing
                    else renderRequestedDaySectionFragmentFromProjectionWithMode renderMode projection rosterDayId
        RosterProjectionRow rosterDayId rowIndex ->
            rosterData >>= \projection ->
                if isHiddenDraftForCurrentUser projection.rosterWeek
                    then Nothing
                    else renderRequestedRowFragmentFromProjectionWithMode renderMode projection rosterDayId rowIndex
    where
        renderGridFragment plainRenderer swapRenderer maybeRosterData = do
            projection <- maybeRosterData
            let gridModel = rosterGridRenderModelFromProjection projection
            pure $ case renderMode of
                FragmentPlain        -> plainRenderer gridModel
                FragmentOob swapAttr -> swapRenderer swapAttr gridModel
        renderDayColumnsFragment maybeRosterData = do
            projection <- maybeRosterData
            let dayModel = rosterDayRenderModelFromProjection projection
            if isHiddenDraftForCurrentUser projection.rosterWeek
                then Nothing
                else pure $ case renderMode of
                    FragmentPlain -> renderrosterDayColumnsLiveFragment dayModel projection.rosterDays
                    FragmentOob swapAttr -> renderrosterDayColumnsLiveFragmentWithSwap swapAttr dayModel projection.rosterDays
        renderDayRailFragment maybeRosterData = do
            projection <- maybeRosterData
            let visibleRosterWeek = visibleRosterWeekForCurrentUser projection.rosterWeek
            let viewCapabilities = buildRosterViewCapabilities visibleRosterWeek
            let dayModel = rosterDayRenderModelFromProjection projection
            pure $ case renderMode of
                FragmentPlain ->
                    if isNothing visibleRosterWeek
                        then renderHiddenDraftDayRailFragmentWithSwap Nothing dayModel projection.rosterDays
                        else renderrosterDayRailLiveFragment viewCapabilities.canManageRosterColumns dayModel projection.rosterDays
                FragmentOob swapAttr ->
                    if isNothing visibleRosterWeek
                        then renderHiddenDraftDayRailFragmentWithSwap swapAttr dayModel projection.rosterDays
                        else renderrosterDayRailLiveFragmentWithSwap swapAttr viewCapabilities.canManageRosterColumns dayModel projection.rosterDays
        renderWageRailFragment maybeRosterData = do
            projection <- maybeRosterData
            let dayModel = rosterDayRenderModelFromProjection projection
            pure $ case renderMode of
                FragmentPlain -> renderrosterWageRailLiveFragment dayModel projection.rosterDays
                FragmentOob swapAttr -> renderrosterWageRailLiveFragmentWithSwap swapAttr dayModel projection.rosterDays
        renderSlotsGridFragment maybeRosterData = do
            projection <- maybeRosterData
            let visibleRosterWeek = visibleRosterWeekForCurrentUser projection.rosterWeek
            let viewCapabilities = buildRosterViewCapabilities visibleRosterWeek
            let dayModel = rosterDayRenderModelFromProjection projection
            pure $ case renderMode of
                FragmentPlain ->
                    if isNothing visibleRosterWeek
                        then renderHiddenDraftSlotsGridFragmentWithSwap Nothing projection.rosterDays
                        else renderrosterSlotsGridLiveFragment projection.rosterEndTimesEnabled viewCapabilities.canManageRosterColumns visibleRosterWeek projection.orderedSlotNames dayModel projection.rosterDays
                FragmentOob swapAttr ->
                    if isNothing visibleRosterWeek
                        then renderHiddenDraftSlotsGridFragmentWithSwap swapAttr projection.rosterDays
                        else renderrosterSlotsGridLiveFragmentWithSwap swapAttr projection.rosterEndTimesEnabled viewCapabilities.canManageRosterColumns visibleRosterWeek projection.orderedSlotNames dayModel projection.rosterDays

renderRosterContentFromProjection :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => [RosterGroup] -> RosterGroup -> Maybe RosterRenderData -> IO Markup.Html
renderRosterContentFromProjection rosterGroups currentRosterGroup rosterData =
    case rosterData of
        Nothing -> pure [hsx|<div id="roster-content"></div>|]
        Just projection ->
            pure $
                renderrosterContentLiveFragment
                    (rosterGridRenderModelFromProjection projection)
                        { gridRosterGroups = rosterGroups
                        , gridCurrentRosterGroup = currentRosterGroup
                        , gridViewMode = RosterWeekGridView
                        }

rosterToolbarRenderModelFromProjection :: (?context :: ControllerContext, ?request :: Request) => RosterRenderData -> RosterToolbarRenderModel
rosterToolbarRenderModelFromProjection projection =
    let gridModel = rosterGridRenderModelFromProjection projection
     in RosterToolbarRenderModel
        { toolbarRosterWeek = gridModel.gridRosterWeek
        , toolbarCurrentRosterGroup = gridModel.gridCurrentRosterGroup
        , toolbarWeekStartDate = gridModel.gridWeekStartDate
        , toolbarCalendarRevision = gridModel.gridRosterCalendarRevision
        , toolbarViewCapabilities = gridModel.gridViewCapabilities
        , toolbarWagePrediction = gridModel.gridRosterWagePrediction
        , toolbarHasSidePanel = hasRole Manager || isJust gridModel.gridStaffSelfServicePanel
        , toolbarViewMode = gridModel.gridViewMode
        , toolbarTimelineTodayUrl = gridModel.gridTimelineTodayUrl
        }

rosterGridRenderModelFromProjection :: (?context :: ControllerContext, ?request :: Request) => RosterRenderData -> RosterGridRenderModel
rosterGridRenderModelFromProjection RosterRenderData { rosterWeek, rosterWindowScope, rosterGroups, currentRosterGroup, rosterDays, weekStartDate, rosterCalendarRevision, assignmentFilters, staffMembers, panelStaff, templateLibrary, rosterNotificationPanelData = notificationPanelData, staffSelfServicePanel, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled, rosterTimePickerStartMinute, rosterTimePickerFinalSelectableMinute, rosterWagePrediction, showWageEstimates, showRosterWarnings, highlightOwnLiveShifts, currentViewerStaffKey, rosterPublicHolidays } =
    let visibleRosterWeek = visibleRosterWeekForCurrentUser rosterWeek
     in RosterGridRenderModel
        { gridRosterWeek = visibleRosterWeek
        , gridRosterDays = rosterDays
        , gridWindowScope = rosterWindowScope
        , gridRosterGroups = rosterGroups
        , gridCurrentRosterGroup = currentRosterGroup
        , gridAssignmentFilters = assignmentFilters
        , gridStaffMembers = staffMembers
        , gridPanelStaff = panelStaff
        , gridTemplateLibrary = templateLibrary
        , gridNotificationPanelData = notificationPanelData
        , gridStaffSelfServicePanel = staffSelfServicePanel
        , gridSlotNames = orderedSlotNames
        , gridShiftTypes = shiftTypes
        , gridWeekStartDate = weekStartDate
        , gridRosterCalendarRevision = rosterCalendarRevision
        , gridAllSlots = allSlots
        , gridSlotConflicts = slotConflicts
        , gridRenderIndexes = renderIndexes
        , gridViewCapabilities = buildRosterViewCapabilities visibleRosterWeek
        , gridRosterLayoutMode = rosterLayoutMode
        , gridRosterEndTimesEnabled = rosterEndTimesEnabled
        , gridRosterTimePickerStartMinute = rosterTimePickerStartMinute
        , gridRosterTimePickerFinalSelectableMinute = rosterTimePickerFinalSelectableMinute
        , gridRosterWagePrediction = rosterWagePrediction
        , gridShowWageEstimates = showWageEstimates
        , gridShowRosterWarnings = showRosterWarnings
        , gridHighlightOwnLiveShifts = highlightOwnLiveShifts
        , gridCurrentViewerStaffKey = currentViewerStaffKey
        , gridPublicHolidays = rosterPublicHolidays
        , gridPublishAttempted = False
        , gridViewMode = currentRosterGridViewMode weekStartDate
        , gridTimelineTodayUrl = Nothing
        }

currentRosterGridViewMode :: (?request :: Request) => Calendar.Day -> RosterGridViewMode
currentRosterGridViewMode windowStart =
    case (paramOrNothing @Text "rosterView", paramOrNothing @Calendar.Day "dayDate", paramOrNothing @Int "dayOffset") of
        (Just "timeline", Just dayDate, _) -> RosterDayTimelineGridView (clampDayOffset (fromInteger (Calendar.diffDays dayDate windowStart)))
        (Just "timeline", Nothing, Just dayOffset) -> RosterDayTimelineGridView (clampDayOffset dayOffset)
        _ -> RosterWeekGridView
  where
    clampDayOffset = max 0 . min 6

currentRosterTimelineDate :: (?request :: Request) => Calendar.Day -> Maybe Calendar.Day
currentRosterTimelineDate windowStart = case currentRosterGridViewMode windowStart of
    RosterDayTimelineGridView dayOffset -> Just (Calendar.addDays (toInteger dayOffset) windowStart)
    RosterWeekGridView                  -> Nothing

visibleRosterWeekForCurrentUser :: (?context :: ControllerContext) => Maybe RosterWindowState -> Maybe RosterWindowState
visibleRosterWeekForCurrentUser (Just rosterWeek)
    | rosterWeek.windowIsPublished || hasRole Manager = Just rosterWeek
visibleRosterWeekForCurrentUser Nothing = Nothing
visibleRosterWeekForCurrentUser _ = Nothing

isHiddenDraftForCurrentUser :: (?context :: ControllerContext) => Maybe RosterWindowState -> Bool
isHiddenDraftForCurrentUser maybeRosterWeek =
    not (hasRole Manager) && maybe True (not . (.windowIsPublished)) maybeRosterWeek

rosterDayRenderModelFromProjection :: (?context :: ControllerContext) => RosterRenderData -> RosterDayRenderModel
rosterDayRenderModelFromProjection RosterRenderData { rosterWeek, weekStartDate, rosterCalendarRevision, assignmentFilters, staffMembers, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled, rosterWagePrediction, showWageEstimates, showRosterWarnings, rosterPublicHolidays } =
    RosterDayRenderModel
        { dayIsEditable = hasRole Manager && maybe False (not . (.windowIsPublished)) rosterWeek
        , daySlotNames = orderedSlotNames
        , dayAssignmentFilters = assignmentFilters
        , dayStaffMembers = staffMembers
        , dayShiftTypes = shiftTypes
        , dayWeekStartDate = weekStartDate
        , dayCalendarRevision = rosterCalendarRevision
        , dayAllSlots = allSlots
        , daySlotConflicts = slotConflicts
        , dayRenderIndexes = renderIndexes
        , dayRosterLayoutMode = rosterLayoutMode
        , dayRosterEndTimesEnabled = rosterEndTimesEnabled
        , dayRosterWagePrediction = rosterWagePrediction
        , dayShowWageEstimates = showWageEstimates
        , dayShowRosterWarnings = showRosterWarnings
        , dayPublicHolidays = rosterPublicHolidays
        , dayPublishAttempted = False
        }

renderRosterStaffPanelFromProjectionWithMode :: (?context :: ControllerContext, ?request :: Request) => FragmentRenderMode -> Maybe RosterRenderData -> Markup.Html
renderRosterStaffPanelFromProjectionWithMode renderMode rosterData =
    case rosterData of
        Nothing -> mempty
        Just projection ->
            let panelModel = rosterStaffPanelRenderModelFromProjection RosterStaffPanelCurrentGroup projection
             in case renderMode of
                    FragmentPlain -> renderrosterStaffPanelLiveFragment panelModel
                    FragmentOob swapAttr -> renderrosterStaffPanelLiveFragmentWithSwap swapAttr panelModel

rosterStaffPanelRenderModelFromProjection :: (?context :: ControllerContext, ?request :: Request) => RosterStaffPanelScope -> RosterRenderData -> RosterStaffPanelRenderModel
rosterStaffPanelRenderModelFromProjection panelScope RosterRenderData { rosterWeek, rosterGroups, currentRosterGroup, weekStartDate, rosterCalendarRevision, assignmentFilters, panelStaff, templateLibrary, rosterNotificationPanelData = notificationPanelData, rosterLayoutMode, showWageEstimates, showRosterWarnings, highlightOwnLiveShifts } =
    RosterStaffPanelRenderModel
        { staffPanelRosterWeek = visibleRosterWeekForCurrentUser rosterWeek
        , staffPanelWeekStartDate = weekStartDate
        , staffPanelCalendarRevision = rosterCalendarRevision
        , staffPanelRosterGroups = rosterGroups
        , staffPanelCurrentRosterGroup = currentRosterGroup
        , staffPanelAssignmentFilters = assignmentFilters
        , staffPanelViewCapabilities = buildRosterViewCapabilities (visibleRosterWeekForCurrentUser rosterWeek)
        , staffPanelRosterLayoutMode = rosterLayoutMode
        , staffPanelShowWageEstimates = showWageEstimates
        , staffPanelShowRosterWarnings = showRosterWarnings
        , staffPanelHighlightOwnLiveShifts = highlightOwnLiveShifts
        , staffPanelViewMode = currentRosterGridViewMode weekStartDate
        , staffPanelScope = panelScope
        , staffPanelEntries = panelStaff
        , staffPanelTemplateLibrary = templateLibrary
        , staffPanelNotificationPanelData = notificationPanelData
        }

renderRequestedRowFragmentFromProjectionWithMode :: (?context :: ControllerContext, ?request :: Request) => FragmentRenderMode -> RosterRenderData -> UUID.UUID -> Int -> Maybe Markup.Html
renderRequestedRowFragmentFromProjectionWithMode renderMode RosterRenderData { rosterWeek, weekStartDate, rosterCalendarRevision, assignmentFilters, staffMembers, orderedSlotNames, shiftTypes, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled } rosterDayId rowIndex =
    case renderMode of
        FragmentPlain -> renderRequestedRowFragment (hasRole Manager && maybe False (not . (.windowIsPublished)) rosterWeek) weekStartDate rosterCalendarRevision orderedSlotNames assignmentFilters staffMembers shiftTypes renderIndexes rosterLayoutMode rosterEndTimesEnabled (rosterDayId, rowIndex)
        FragmentOob _ -> renderRequestedRow weekStartDate rosterCalendarRevision orderedSlotNames assignmentFilters staffMembers shiftTypes renderIndexes rosterLayoutMode rosterEndTimesEnabled (rosterDayId, rowIndex)

renderRequestedDaySectionFragmentFromProjectionWithMode :: (?context :: ControllerContext, ?request :: Request) => FragmentRenderMode -> RosterRenderData -> UUID.UUID -> Maybe Markup.Html
renderRequestedDaySectionFragmentFromProjectionWithMode renderMode RosterRenderData { rosterWeek, weekStartDate, rosterCalendarRevision, assignmentFilters, staffMembers, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled, rosterWagePrediction, showWageEstimates, showRosterWarnings, rosterPublicHolidays } rosterDayId =
    case renderMode of
        FragmentPlain -> renderRequestedDaySectionFragment (hasRole Manager && maybe False (not . (.windowIsPublished)) rosterWeek) weekStartDate rosterCalendarRevision orderedSlotNames assignmentFilters staffMembers shiftTypes allSlots slotConflicts renderIndexes rosterLayoutMode rosterEndTimesEnabled rosterWagePrediction showWageEstimates showRosterWarnings rosterPublicHolidays rosterDayId
        FragmentOob _ -> renderRequestedDaySection weekStartDate rosterCalendarRevision orderedSlotNames assignmentFilters staffMembers shiftTypes allSlots slotConflicts renderIndexes rosterLayoutMode rosterEndTimesEnabled rosterWagePrediction showWageEstimates showRosterWarnings rosterPublicHolidays rosterDayId

fetchVisibleRosterReadModel :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> IO (Maybe RosterRenderData)
fetchVisibleRosterReadModel scope = do
    authorizedScope <- authorizeRosterScope scope
    fetchVisibleRosterReadModelForAuthorizedScope authorizedScope

fetchVisibleRosterReadModelForAuthorizedScope :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => AuthorizedRosterScope -> IO (Maybe RosterRenderData)
fetchVisibleRosterReadModelForAuthorizedScope authorizedScope =
    profileActionSpan "roster.read_model.fetch_visible" do
        snapshot <- fetchAuthorizedRosterSnapshotForAuthorizedScope authorizedScope
        fetchVisibleRosterReadModelFromSnapshot snapshot

fetchVisibleRosterReadModelFromSnapshot :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => AuthorizedRosterSnapshot -> IO (Maybe RosterRenderData)
fetchVisibleRosterReadModelFromSnapshot snapshot = do
    let visibleRosterWeek = visibleRosterWeekFromSnapshot snapshot
    rosterData <- fetchRosterRenderDataFromSnapshot snapshot
    pure $ case visibleRosterWeek of
        Nothing ->
            let hiddenRenderIndexes = buildRosterRenderIndexes rosterData.rosterDays [] [] [] []
             in Just
                    rosterData
                        { assignmentFilters = defaultRosterAssignmentFilters
                        , staffMembers = []
                        , panelStaff = []
                        , rosterNotificationPanelData = Nothing
                        , allSlots = []
                        , slotConflicts = []
                        , renderIndexes = hiddenRenderIndexes
                        , rosterWagePrediction = Nothing
                        , currentViewerStaffKey = Nothing
                        }
        Just _ -> Just rosterData

data RosterRenderPlan
    = CompleteRosterProjection
    | GridFrameProjection
    | DayColumnsProjection
    | DayRailProjection
    | WageRailProjection
    | SlotsGridProjection

renderPlanNeedsConflicts :: RosterRenderPlan -> Bool
renderPlanNeedsConflicts CompleteRosterProjection = True
renderPlanNeedsConflicts GridFrameProjection      = True
renderPlanNeedsConflicts DayColumnsProjection     = True
renderPlanNeedsConflicts SlotsGridProjection      = True
renderPlanNeedsConflicts DayRailProjection        = False
renderPlanNeedsConflicts WageRailProjection       = False

renderPlanNeedsPublicHolidays :: RosterRenderPlan -> Bool
renderPlanNeedsPublicHolidays CompleteRosterProjection = True
renderPlanNeedsPublicHolidays GridFrameProjection      = True
renderPlanNeedsPublicHolidays DayColumnsProjection     = True
renderPlanNeedsPublicHolidays DayRailProjection        = True
renderPlanNeedsPublicHolidays WageRailProjection       = False
renderPlanNeedsPublicHolidays SlotsGridProjection      = False

renderPlanNeedsWages :: RosterRenderPlan -> Bool
renderPlanNeedsWages CompleteRosterProjection = True
renderPlanNeedsWages GridFrameProjection      = True
renderPlanNeedsWages DayColumnsProjection     = True
renderPlanNeedsWages WageRailProjection       = True
renderPlanNeedsWages DayRailProjection        = False
renderPlanNeedsWages SlotsGridProjection      = False

fetchRosterRenderDataFromSnapshot :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => AuthorizedRosterSnapshot -> IO RosterRenderData
fetchRosterRenderDataFromSnapshot = fetchRosterRenderDataForPlan CompleteRosterProjection

fetchRosterRenderDataForPlan :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterRenderPlan -> AuthorizedRosterSnapshot -> IO RosterRenderData
fetchRosterRenderDataForPlan renderPlan snapshot = do
    baseFacts <- case renderPlan of
        CompleteRosterProjection -> fetchRosterBaseFactsForAuthorizedWindowDirect snapshot.snapshotAuthorizedScope snapshot.snapshotWindowFacts
        _ -> fetchRosterDisplayFactsForAuthorizedWindowDirect snapshot.snapshotAuthorizedScope snapshot.snapshotWindowFacts
    let scope = snapshot.snapshotScope
    let venueConfig = snapshot.snapshotVenueConfig
    let rosterGroups = snapshot.snapshotRosterGroups
    let currentRosterGroup = snapshot.snapshotRosterGroup
    assignmentFilters <- profileActionSpan "roster.direct.fetch_assignment_filters" fetchRosterAssignmentFilters
    let rosterLayoutMode = venueConfig.rosterLayoutMode
    let userShowWageEstimates = snapshot.snapshotRosterPreferences.userShowWageEstimates
    let showRosterWarnings = hasRole Manager && snapshot.snapshotRosterPreferences.userShowRosterWarnings
    let highlightOwnLiveShifts = snapshot.snapshotRosterPreferences.userHighlightOwnLiveShifts
    let maybeCurrentViewerStaff = snapshot.snapshotCurrentStaff
    let showWageEstimates = shouldShowRosterWageEstimates userShowWageEstimates
    let weekStartDate = scope.rosterWindowStart
    rosterPublicHolidays <-
        if renderPlanNeedsPublicHolidays renderPlan
            then profileActionSpan "roster.direct.fetch_public_holidays" (fetchRosterPublicHolidayMap venueConfig weekStartDate)
            else pure Map.empty

    let RosterBaseFacts { baseRosterWeek = rosterWeek, baseRosterDays = rosterDays, baseAllSlots = allSlots, baseVisibleSlots = visibleSlots, baseOrderedSlotDefinitions = orderedSlotNames, baseShiftTypes = shiftTypes, basePanelStaff = panelStaffMembers, basePanelPayConfigurationRequiredIds = panelPayConfigurationRequiredIds, baseStaffMembers = staffMembers } = baseFacts
    let currentViewerStaffKey =
            case maybeCurrentViewerStaff of
                Just staff
                    | staff.isActive
                    , isNothing staff.archivedAt
                    , any (\slot -> slot.staffId == Just (unpackId staff.id)) visibleSlots ->
                        Just ("staff:" <> tshow staff.id)
                _ -> Nothing
    (panelStaff, templateLibrary, notificationPanelData, staffSelfServicePanel) <-
        case renderPlan of
            CompleteRosterProjection -> do
                panelStaff <- profileActionSpan "roster.build_staff_panel" (fetchRosterStaffPanelEntriesWithPayState RosterStaffPanelCurrentGroup panelPayConfigurationRequiredIds panelStaffMembers visibleSlots)
                templateLibrary <- fetchRosterPanelTemplateLibrary currentRosterGroup
                notificationPanelData <- fetchRosterPanelNotificationData snapshot.snapshotAuthorizedScope weekStartDate rosterDays
                staffSelfServicePanel <- profileActionSpan "roster.build_staff_self_service_panel" (fetchRosterStaffSelfServicePanel venueConfig rosterGroups scope maybeCurrentViewerStaff highlightOwnLiveShifts)
                pure (panelStaff, templateLibrary, notificationPanelData, staffSelfServicePanel)
            _ -> pure ([], Nothing, Nothing, Nothing)
    slotConflicts <-
        if maybe False (.windowIsPublished) rosterWeek || not (renderPlanNeedsConflicts renderPlan)
            then pure []
            else profileActionSpan "roster.direct.build_slot_conflicts" (buildSlotConflictsDirect venueConfig.lateToEarlyMinStartGapMinutes visibleSlots)
    let renderIndexes = buildRosterRenderIndexes rosterDays visibleSlots staffMembers shiftTypes slotConflicts
    rosterWagePrediction <-
        if showWageEstimates && renderPlanNeedsWages renderPlan
            then do
                wageFilterStaff <- case renderPlan of
                    CompleteRosterProjection -> pure panelStaffMembers
                    _ -> fetchRosterWageFilterStaffForAuthorizedScopeDirect snapshot.snapshotAuthorizedScope
                let wageSlots = filterRosterWageSlots (pinnedRosterWageStaffId True wageFilterStaff) visibleSlots
                Just <$> profileActionSpan "roster.predict_wages" (fetchRosterWagePredictionForWindow venueConfig rosterDays wageSlots)
            else pure Nothing
    let rosterCalendarRevision = venueConfig.rosterCalendarRevision
    pure RosterRenderData { rosterWeek, rosterWindowScope = scope, rosterGroups, currentRosterGroup, rosterDays, weekStartDate, rosterCalendarRevision, assignmentFilters, staffMembers, panelStaff, templateLibrary, rosterNotificationPanelData = notificationPanelData, staffSelfServicePanel, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled = venueConfig.rosterEndTimesEnabled, rosterTimePickerStartMinute = venueConfig.timePickerStartMinuteOfDay, rosterTimePickerFinalSelectableMinute = venueConfig.timePickerFinalSelectableMinuteOfDay, rosterWagePrediction, showWageEstimates, showRosterWarnings, highlightOwnLiveShifts, currentViewerStaffKey, rosterPublicHolidays }

fetchRosterPanelNotificationData :: (?context :: ControllerContext, ?modelContext :: ModelContext) => AuthorizedRosterScope -> Day -> [RosterDay] -> IO (Maybe Notification.RosterNotificationPanelData)
fetchRosterPanelNotificationData authorizedScope windowStart rosterDays
    | hasRole Manager
    , map (.operationalDate) rosterDays == map (`Calendar.addDays` windowStart) [0 .. 6]
    , rosterDaysArePublished rosterDays =
        Just <$> profileActionSpan "roster.notification.fetch_panel_summary"
            (fetchRosterNotificationPanelDataDirect authorizedScope)
fetchRosterPanelNotificationData _ _ _ = pure Nothing

fetchRosterPanelTemplateLibrary :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterGroup -> IO (Maybe RosterTemplateLibrary)
fetchRosterPanelTemplateLibrary rosterGroup
    | not (hasRole Manager) = pure Nothing
    | otherwise = profileActionSpan "roster.template.fetch_library" (currentRosterTemplateActor >>= (`fetchRosterTemplateLibraryDirect` rosterGroup))

fetchRosterStaffSelfServicePanel :: (?context :: ControllerContext, ?modelContext :: ModelContext) => VenueConfig -> [RosterGroup] -> RosterWindowScope -> Maybe Staff -> Bool -> IO (Maybe RosterStaffSelfServicePanel)
fetchRosterStaffSelfServicePanel venueConfig rosterGroups scope maybeCurrentStaff highlightOwnLiveShifts
    | hasRole Manager = pure Nothing
    | currentUserIsUnimpersonatedSuperAdmin = pure Nothing
    | otherwise = do
        case maybeCurrentStaff of
            Nothing -> pure Nothing
            Just staff -> do
                operationalDay <- currentOperationalDayForVenue venueConfig
                let timesheetWeekStartDate = startOfWeekFor venueConfig.rosterWeekStartsOn operationalDay
                quickToolsTimesheetEntries <-
                    query @TimesheetEntry
                        |> filterWhere (#venueId, unpackId currentVenueId)
                        |> filterWhere (#staffId, unpackId staff.id)
                        |> filterWhere (#operationalDate, operationalDay)
                        |> filterWhere (#deletedAt, Nothing)
                        |> orderByAsc #startsAt
                        |> fetch
                quickToolsShiftTypes <- fetchCurrentVenueRosterShiftTypes
                let quickToolsLeaveRequest = defaultLeaveRequestForOperationalDay operationalDay
                pure $
                    Just
                        RosterStaffSelfServicePanel
                            { quickToolsLeaveRequest
                            , quickToolsVenueId = currentVenueId
                            , quickToolsRosterGroupId = scope.rosterWindowRosterGroupId
                            , quickToolsRosterGroups = rosterGroups
                            , quickToolsRosterWeekStartDate = scope.rosterWindowStart
                            , quickToolsTimesheetEntries
                            , quickToolsTimesheetTimingByEntryId = Map.fromList [(unpackId entry.id, decodeTimesheetTiming entry) | entry <- quickToolsTimesheetEntries]
                            , quickToolsStaffMembers = [staff]
                            , quickToolsShiftTypes
                            , quickToolsOperationalDay = operationalDay
                            , quickToolsTimesheetWeekStartDate = timesheetWeekStartDate
                            , quickToolsCalendarRevision = venueConfig.rosterCalendarRevision
                            , quickToolsTimesheetEditWindowDays = venueConfig.staffTimesheetEditWindowDays
                            , quickToolsHighlightOwnLiveShifts = highlightOwnLiveShifts
                            }

visibleRosterWeekFromSnapshot :: (?context :: ControllerContext) => AuthorizedRosterSnapshot -> Maybe RosterWindowState
visibleRosterWeekFromSnapshot snapshot =
    case snapshot.snapshotWindowFacts.windowFactsState of
        Just rosterWeek | rosterWeek.windowIsPublished || hasRole Manager -> Just rosterWeek
        _ -> Nothing

buildRosterRenderIndexes :: [RosterDay] -> [RosterSlot] -> [Staff] -> [ShiftType] -> [(Id RosterSlot, [RosterConflict])] -> RosterRenderIndexes
buildRosterRenderIndexes rosterDays visibleSlots staffMembers shiftTypes slotConflicts =
    let slotsByRosterDayId =
            Map.fromListWith
                (<>)
                [ (slot.rosterDayId, [slot])
                | slot <- visibleSlots
                ]
        normalizedStaffNameCounts =
            Map.fromListWith (+)
                [(normalizedStaffDisplayBaseName staff, 1 :: Int) | staff <- staffMembers]
        displayLabel staff =
            staffDisplayBaseName staff
                <> if Map.findWithDefault 0 (normalizedStaffDisplayBaseName staff) normalizedStaffNameCounts > 1
                    then renderStaffLastInitial staff
                    else ""
     in RosterRenderIndexes
        { rosterDayById = Map.fromList [(coerce (get #id rosterDay), rosterDay) | rosterDay <- rosterDays]
        , rosterDayRowsByDayId =
            Map.fromList
                [ (coerce (get #id rosterDay), rowsForDay rosterDay (Map.findWithDefault [] (coerce (get #id rosterDay)) slotsByRosterDayId))
                | rosterDay <- rosterDays
                ]
        , rosterSlotByDayRowSlotName =
            Map.fromList
                [ ((slot.rosterDayId, slot.rowIndex, slot.rosterLaneId), slot)
                | slot <- visibleSlots
                ]
        , rosterStaffLabelById = Map.fromList [(coerce (get #id staff), displayLabel staff) | staff <- staffMembers]
        , rosterShiftTypeById = Map.fromList [(coerce (get #id shiftType), shiftType) | shiftType <- shiftTypes]
        , rosterConflictsBySlotId = Map.fromList [(coerce slotId, conflicts) | (slotId, conflicts) <- slotConflicts]
        , rosterTimingBySlotId = Map.fromList [(unpackId slot.id, decodeRosterShiftTiming slot) | slot <- visibleSlots]
        }

renderVisibleRosterFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => AuthorizedRosterSnapshot -> RosterProjectionFragment -> IO (Maybe Markup.Html)
renderVisibleRosterFragment snapshot fragment = do
    let scope = snapshot.snapshotScope
    let visibleRosterWeek = visibleRosterWeekFromSnapshot snapshot
    case fragment of
        RosterProjectionGridToolbar -> do
            toolbarModel <- fetchRosterToolbarRenderModelFromSnapshot snapshot
            pure (Just (renderrosterGridToolbarLiveFragment toolbarModel))
        RosterProjectionGridFrame -> renderFullProjectionFragment snapshot fragment
        RosterProjectionDayColumns -> renderFullProjectionFragment snapshot fragment
        RosterProjectionDayRail -> renderFullProjectionFragment snapshot fragment
        RosterProjectionWageRail -> renderFullProjectionFragment snapshot fragment
        RosterProjectionSlotsGrid -> renderFullProjectionFragment snapshot fragment
        _ -> case visibleRosterWeek of
            Nothing -> do
                rosterData <- fetchVisibleRosterReadModelFromSnapshot snapshot
                pure (renderRosterProjectionFragment rosterData fragment)
            Just rosterWeek ->
              case fragment of
                RosterProjectionStaffPanel -> do
                    panelModel <- fetchVisibleRosterStaffPanelRenderModelFromSnapshot RosterStaffPanelCurrentGroup snapshot
                    pure (Just (renderrosterStaffPanelLiveFragment panelModel))
                RosterProjectionContent -> do
                    rosterData <- fetchVisibleRosterReadModelFromSnapshot snapshot
                    case rosterData of
                        Nothing -> pure Nothing
                        Just projection -> Just <$> renderRosterContentFromProjection projection.rosterGroups projection.currentRosterGroup rosterData
                RosterProjectionRow rosterDayUuid rowIndex -> do
                    facts@RosterBaseFacts { baseRosterDays = rosterDays, baseVisibleSlots = visibleSlots, baseStaffMembers = staffMembers } <-
                        if rosterWeek.windowIsPublished
                            then fetchPublishedRosterDayFactsForAuthorizedScopeDirect snapshot.snapshotAuthorizedScope snapshot.snapshotWindowFacts rosterDayUuid
                            else fetchRosterBaseFactsForAuthorizedWindowDirect snapshot.snapshotAuthorizedScope snapshot.snapshotWindowFacts
                    let venueConfig = snapshot.snapshotVenueConfig
                    assignmentFilters <- fetchRosterAssignmentFilters
                    let rosterLayoutMode = venueConfig.rosterLayoutMode
                    let weekStartDate = scope.rosterWindowStart
                    let targetSlots = filter (\slot -> slot.rosterDayId == rosterDayUuid && slot.rowIndex == rowIndex) visibleSlots
                    slotConflicts <-
                        if rosterWeek.windowIsPublished
                            then pure []
                            else profileActionSpan "roster.direct.build_slot_conflicts" (buildSlotConflictsForSlotsDirect venueConfig.lateToEarlyMinStartGapMinutes visibleSlots targetSlots)
                    let renderIndexes = buildRosterRenderIndexes rosterDays visibleSlots staffMembers facts.baseShiftTypes slotConflicts
                    pure (renderRequestedRowFragment (hasRole Manager && not rosterWeek.windowIsPublished) weekStartDate scope.rosterWindowCalendarRevision facts.baseOrderedSlotDefinitions assignmentFilters staffMembers facts.baseShiftTypes renderIndexes rosterLayoutMode venueConfig.rosterEndTimesEnabled (rosterDayUuid, rowIndex))
                RosterProjectionDaySection rosterDayUuid -> do
                    facts@RosterBaseFacts { baseRosterDays = rosterDays, baseVisibleSlots = visibleSlots, baseStaffMembers = staffMembers, basePanelStaff = panelStaffMembers } <-
                        if rosterWeek.windowIsPublished
                            then fetchPublishedRosterDayFactsForAuthorizedScopeDirect snapshot.snapshotAuthorizedScope snapshot.snapshotWindowFacts rosterDayUuid
                            else fetchRosterBaseFactsForAuthorizedWindowDirect snapshot.snapshotAuthorizedScope snapshot.snapshotWindowFacts
                    let venueConfig = snapshot.snapshotVenueConfig
                    assignmentFilters <- fetchRosterAssignmentFilters
                    let rosterLayoutMode = venueConfig.rosterLayoutMode
                    let userShowWageEstimates = snapshot.snapshotRosterPreferences.userShowWageEstimates
                    let showRosterWarnings = hasRole Manager && snapshot.snapshotRosterPreferences.userShowRosterWarnings
                    let showWageEstimates = shouldShowRosterWageEstimates userShowWageEstimates
                    let weekStartDate = scope.rosterWindowStart
                    rosterPublicHolidays <- fetchRosterPublicHolidayMap venueConfig weekStartDate
                    let targetSlots = filter (\slot -> slot.rosterDayId == rosterDayUuid) visibleSlots
                    slotConflicts <-
                        if rosterWeek.windowIsPublished
                            then pure []
                            else profileActionSpan "roster.direct.build_slot_conflicts" (buildSlotConflictsForSlotsDirect venueConfig.lateToEarlyMinStartGapMinutes visibleSlots targetSlots)
                    let renderIndexes = buildRosterRenderIndexes rosterDays visibleSlots staffMembers facts.baseShiftTypes slotConflicts
                    let wageSlots = filterRosterWageSlots (pinnedRosterWageStaffId showWageEstimates panelStaffMembers) visibleSlots
                    rosterWagePrediction <-
                        if showWageEstimates
                            then Just <$> profileActionSpan "roster.predict_wages" (fetchRosterWagePredictionForWindow venueConfig rosterDays wageSlots)
                            else pure Nothing
                    pure (renderRequestedDaySectionFragment (hasRole Manager && not rosterWeek.windowIsPublished) weekStartDate venueConfig.rosterCalendarRevision facts.baseOrderedSlotDefinitions assignmentFilters staffMembers facts.baseShiftTypes facts.baseAllSlots slotConflicts renderIndexes rosterLayoutMode venueConfig.rosterEndTimesEnabled rosterWagePrediction showWageEstimates showRosterWarnings rosterPublicHolidays rosterDayUuid)

fetchRosterToolbarRenderModelFromSnapshot :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => AuthorizedRosterSnapshot -> IO RosterToolbarRenderModel
fetchRosterToolbarRenderModelFromSnapshot snapshot = do
    let visibleRosterWeek = visibleRosterWeekFromSnapshot snapshot
    let venueConfig = snapshot.snapshotVenueConfig
    let showWageEstimates = shouldShowRosterWageEstimates snapshot.snapshotRosterPreferences.userShowWageEstimates
    toolbarWagePrediction <-
        if showWageEstimates && isJust visibleRosterWeek
            then do
                visibleSlots <- fetchRosterWageSlotsForAuthorizedWindowDirect snapshot.snapshotAuthorizedScope snapshot.snapshotWindowFacts
                wageFilterStaff <- fetchRosterWageFilterStaffForAuthorizedScopeDirect snapshot.snapshotAuthorizedScope
                let wageSlots = filterRosterWageSlots (pinnedRosterWageStaffId True wageFilterStaff) visibleSlots
                Just <$> profileActionSpan "roster.predict_wages" (fetchRosterWagePredictionForWindow venueConfig snapshot.snapshotWindowFacts.windowFactsDays wageSlots)
            else pure Nothing
    pure RosterToolbarRenderModel
        { toolbarRosterWeek = visibleRosterWeek
        , toolbarCurrentRosterGroup = snapshot.snapshotRosterGroup
        , toolbarWeekStartDate = snapshot.snapshotScope.rosterWindowStart
        , toolbarCalendarRevision = venueConfig.rosterCalendarRevision
        , toolbarViewCapabilities = buildRosterViewCapabilities visibleRosterWeek
        , toolbarWagePrediction
        , toolbarHasSidePanel = hasRole Manager || (not currentUserIsUnimpersonatedSuperAdmin && isJust snapshot.snapshotCurrentStaff)
        , toolbarViewMode = currentRosterGridViewMode snapshot.snapshotScope.rosterWindowStart
        , toolbarTimelineTodayUrl = Nothing
        }

renderFullProjectionFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => AuthorizedRosterSnapshot -> RosterProjectionFragment -> IO (Maybe Markup.Html)
renderFullProjectionFragment snapshot fragment = do
    let visibleRosterWeek = visibleRosterWeekFromSnapshot snapshot
    let renderPlan = case fragment of
            RosterProjectionGridFrame  -> GridFrameProjection
            RosterProjectionDayColumns -> DayColumnsProjection
            RosterProjectionDayRail    -> DayRailProjection
            RosterProjectionWageRail   -> WageRailProjection
            RosterProjectionSlotsGrid  -> SlotsGridProjection
            _ -> externalRuntimeInvariantFailure AuthorizedFrameworkInvariant "non-grid projection passed to grid projection loader"
    rosterData <- fetchRosterRenderDataForPlan renderPlan snapshot
    let visibleData = case visibleRosterWeek of
            Nothing ->
                rosterData
                    { assignmentFilters = defaultRosterAssignmentFilters
                    , staffMembers = []
                    , allSlots = []
                    , slotConflicts = []
                    , renderIndexes = buildRosterRenderIndexes rosterData.rosterDays [] [] [] []
                    , rosterWagePrediction = Nothing
                    , currentViewerStaffKey = Nothing
                    }
            Just _ -> rosterData
    pure (renderRosterProjectionFragment (Just visibleData) fragment)

fetchVisibleRosterStaffPanelRenderModel :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterStaffPanelScope -> RosterWindowScope -> IO RosterStaffPanelRenderModel
fetchVisibleRosterStaffPanelRenderModel panelScope scope = do
    authorizedScope <- authorizeRosterScope scope
    fetchVisibleRosterStaffPanelRenderModelForAuthorizedScope panelScope authorizedScope

fetchVisibleRosterStaffPanelRenderModelForAuthorizedScope :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterStaffPanelScope -> AuthorizedRosterScope -> IO RosterStaffPanelRenderModel
fetchVisibleRosterStaffPanelRenderModelForAuthorizedScope panelScope authorizedScope = do
    snapshot <- fetchAuthorizedRosterSnapshotForAuthorizedScope authorizedScope
    fetchVisibleRosterStaffPanelRenderModelFromSnapshot panelScope snapshot

fetchVisibleRosterStaffPanelRenderModelFromSnapshot :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterStaffPanelScope -> AuthorizedRosterSnapshot -> IO RosterStaffPanelRenderModel
fetchVisibleRosterStaffPanelRenderModelFromSnapshot panelScope snapshot = do
    let scope = snapshot.snapshotScope
    let visibleRosterWeek = visibleRosterWeekFromSnapshot snapshot
    let rosterGroups = snapshot.snapshotRosterGroups
    let currentRosterGroup = snapshot.snapshotRosterGroup
    let venueConfig = snapshot.snapshotVenueConfig
    (currentGroupStaff, currentGroupPayConfigurationRequiredIds, assignedShiftCounts) <- fetchRosterStaffPanelFactsForAuthorizedScopeDirect snapshot.snapshotAuthorizedScope
    assignmentFilters <- profileActionSpan "roster.fragment.fetch_assignment_filters" fetchRosterAssignmentFilters
    let rosterLayoutMode = venueConfig.rosterLayoutMode
    let userShowWageEstimates = snapshot.snapshotRosterPreferences.userShowWageEstimates
    let showRosterWarnings = hasRole Manager && snapshot.snapshotRosterPreferences.userShowRosterWarnings
    let highlightOwnLiveShifts = snapshot.snapshotRosterPreferences.userHighlightOwnLiveShifts
    let weekStartDate = scope.rosterWindowStart
    templateLibrary <- fetchRosterPanelTemplateLibrary currentRosterGroup
    panelStaff <- profileActionSpan "roster.build_staff_panel" $
        case panelScope of
            RosterStaffPanelCurrentGroup ->
                fetchRosterStaffPanelEntriesWithAssignedCounts panelScope currentGroupPayConfigurationRequiredIds assignedShiftCounts currentGroupStaff
            RosterStaffPanelAllVenue -> do
                allVenueStaff <- fetchCurrentVenueActiveStaff
                allVenuePayConfigurationRequiredIds <- fetchStaffPayConfigurationRequiredIds allVenueStaff
                fetchRosterStaffPanelEntriesWithAssignedCounts panelScope allVenuePayConfigurationRequiredIds assignedShiftCounts allVenueStaff
    notificationPanelData <- fetchRosterPanelNotificationData snapshot.snapshotAuthorizedScope weekStartDate snapshot.snapshotWindowFacts.windowFactsDays
    pure RosterStaffPanelRenderModel
        { staffPanelRosterWeek = visibleRosterWeek
        , staffPanelWeekStartDate = weekStartDate
        , staffPanelCalendarRevision = venueConfig.rosterCalendarRevision
        , staffPanelRosterGroups = rosterGroups
        , staffPanelCurrentRosterGroup = currentRosterGroup
        , staffPanelAssignmentFilters = assignmentFilters
        , staffPanelViewCapabilities = buildRosterViewCapabilities visibleRosterWeek
        , staffPanelRosterLayoutMode = rosterLayoutMode
        , staffPanelShowWageEstimates = shouldShowRosterWageEstimates userShowWageEstimates
        , staffPanelShowRosterWarnings = showRosterWarnings
        , staffPanelHighlightOwnLiveShifts = highlightOwnLiveShifts
        , staffPanelViewMode = currentRosterGridViewMode weekStartDate
        , staffPanelScope = panelScope
        , staffPanelEntries = panelStaff
        , staffPanelTemplateLibrary = templateLibrary
        , staffPanelNotificationPanelData = notificationPanelData
        }

renderRequestedRow :: (?context :: ControllerContext, ?request :: Request) => Calendar.Day -> Int -> [RosterWindowLane] -> RosterAssignmentFilters -> [Staff] -> [ShiftType] -> RosterRenderIndexes -> RosterLayoutModeEnum -> Bool -> (UUID.UUID, Int) -> Maybe Markup.Html
renderRequestedRow weekStartDate calendarRevision orderedSlotNames assignmentFilters staffMembers shiftTypes renderIndexes rosterLayoutMode rosterEndTimesEnabled (rosterDayUuid, targetRowIndex) = do
    rosterDay <- Map.lookup rosterDayUuid renderIndexes.rosterDayById
    dayRows <- Map.lookup rosterDayUuid renderIndexes.rosterDayRowsByDayId
    let rowCount = length dayRows
    let lastRowIndex = lastRowIndexForRows dayRows
    let indexedRows = zip [0 :: Int ..] dayRows
    (rowPosition, (_, rowSlots)) <- find (\(_, (rowIndex, _)) -> rowIndex == targetRowIndex) indexedRows
    let date = rosterDay.operationalDate
    pure (renderRowOob RosterRowRenderModel { rowIsEditable = True, rowSlotNames = orderedSlotNames, rowAssignmentFilters = assignmentFilters, rowStaffMembers = staffMembers, rowShiftTypes = shiftTypes, rowDate = date, rowDayIndex = fromInteger (Calendar.diffDays date weekStartDate), rowRosterDay = rosterDay, rowCalendarRevision = calendarRevision, rowCount, rowLastRowIndex = lastRowIndex, rowRenderIndexes = renderIndexes, rowRosterLayoutMode = rosterLayoutMode, rowRosterEndTimesEnabled = rosterEndTimesEnabled, rowPublishAttempted = False } (rowPosition, (targetRowIndex, rowSlots)))

renderRequestedRowFragment :: (?context :: ControllerContext, ?request :: Request) => Bool -> Calendar.Day -> Int -> [RosterWindowLane] -> RosterAssignmentFilters -> [Staff] -> [ShiftType] -> RosterRenderIndexes -> RosterLayoutModeEnum -> Bool -> (UUID.UUID, Int) -> Maybe Markup.Html
renderRequestedRowFragment isEditable weekStartDate calendarRevision orderedSlotNames assignmentFilters staffMembers shiftTypes renderIndexes rosterLayoutMode rosterEndTimesEnabled (rosterDayUuid, targetRowIndex) = do
    rosterDay <- Map.lookup rosterDayUuid renderIndexes.rosterDayById
    dayRows <- Map.lookup rosterDayUuid renderIndexes.rosterDayRowsByDayId
    let rowCount = length dayRows
    let lastRowIndex = lastRowIndexForRows dayRows
    let indexedRows = zip [0 :: Int ..] dayRows
    (rowPosition, (_, rowSlots)) <- find (\(_, (rowIndex, _)) -> rowIndex == targetRowIndex) indexedRows
    let date = rosterDay.operationalDate
    pure (renderRowFragment RosterRowRenderModel { rowIsEditable = isEditable, rowSlotNames = orderedSlotNames, rowAssignmentFilters = assignmentFilters, rowStaffMembers = staffMembers, rowShiftTypes = shiftTypes, rowDate = date, rowDayIndex = fromInteger (Calendar.diffDays date weekStartDate), rowRosterDay = rosterDay, rowCalendarRevision = calendarRevision, rowCount, rowLastRowIndex = lastRowIndex, rowRenderIndexes = renderIndexes, rowRosterLayoutMode = rosterLayoutMode, rowRosterEndTimesEnabled = rosterEndTimesEnabled, rowPublishAttempted = False } (rowPosition, (targetRowIndex, rowSlots)))

renderRequestedDaySection :: (?context :: ControllerContext, ?request :: Request) => Calendar.Day -> Int -> [RosterWindowLane] -> RosterAssignmentFilters -> [Staff] -> [ShiftType] -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterRenderIndexes -> RosterLayoutModeEnum -> Bool -> Maybe RosterWagePrediction -> Bool -> Bool -> Map.Map Calendar.Day Text -> UUID.UUID -> Maybe Markup.Html
renderRequestedDaySection weekStartDate calendarRevision orderedSlotNames assignmentFilters staffMembers shiftTypes allSlots slotConflicts renderIndexes rosterLayoutMode rosterEndTimesEnabled rosterWagePrediction showWageEstimates showRosterWarnings rosterPublicHolidays rosterDayUuid = do
    rosterDay <- Map.lookup rosterDayUuid renderIndexes.rosterDayById
    pure (renderRosterDaySectionFragment RosterDayRenderModel { dayIsEditable = True, daySlotNames = orderedSlotNames, dayAssignmentFilters = assignmentFilters, dayStaffMembers = staffMembers, dayShiftTypes = shiftTypes, dayWeekStartDate = weekStartDate, dayCalendarRevision = calendarRevision, dayAllSlots = allSlots, daySlotConflicts = slotConflicts, dayRenderIndexes = renderIndexes, dayRosterLayoutMode = rosterLayoutMode, dayRosterEndTimesEnabled = rosterEndTimesEnabled, dayRosterWagePrediction = rosterWagePrediction, dayShowWageEstimates = showWageEstimates, dayShowRosterWarnings = showRosterWarnings, dayPublicHolidays = rosterPublicHolidays, dayPublishAttempted = False } rosterDay)

renderRequestedDaySectionFragment :: (?context :: ControllerContext, ?request :: Request) => Bool -> Calendar.Day -> Int -> [RosterWindowLane] -> RosterAssignmentFilters -> [Staff] -> [ShiftType] -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterRenderIndexes -> RosterLayoutModeEnum -> Bool -> Maybe RosterWagePrediction -> Bool -> Bool -> Map.Map Calendar.Day Text -> UUID.UUID -> Maybe Markup.Html
renderRequestedDaySectionFragment isEditable weekStartDate calendarRevision orderedSlotNames assignmentFilters staffMembers shiftTypes allSlots slotConflicts renderIndexes rosterLayoutMode rosterEndTimesEnabled rosterWagePrediction showWageEstimates showRosterWarnings rosterPublicHolidays rosterDayUuid = do
    rosterDay <- Map.lookup rosterDayUuid renderIndexes.rosterDayById
    pure (renderRosterDaySectionFragment RosterDayRenderModel { dayIsEditable = isEditable, daySlotNames = orderedSlotNames, dayAssignmentFilters = assignmentFilters, dayStaffMembers = staffMembers, dayShiftTypes = shiftTypes, dayWeekStartDate = weekStartDate, dayCalendarRevision = calendarRevision, dayAllSlots = allSlots, daySlotConflicts = slotConflicts, dayRenderIndexes = renderIndexes, dayRosterLayoutMode = rosterLayoutMode, dayRosterEndTimesEnabled = rosterEndTimesEnabled, dayRosterWagePrediction = rosterWagePrediction, dayShowWageEstimates = showWageEstimates, dayShowRosterWarnings = showRosterWarnings, dayPublicHolidays = rosterPublicHolidays, dayPublishAttempted = False } rosterDay)

fetchCurrentVenueRosterShiftTypes :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [ShiftType]
fetchCurrentVenueRosterShiftTypes =
    fetchVenueShiftTypes currentVenueId
