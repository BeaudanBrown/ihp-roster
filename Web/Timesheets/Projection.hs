{-# LANGUAGE FlexibleContexts #-}
{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.Timesheets.Projection
    ( TimesheetProjectionFragment (..)
    , TimesheetProjectionRequest (..)
    , TimesheetSuggestion (..)
    , TimesheetSurfaceRequestState (..)
    , TimesheetWeekProjection (..)
    , currentTimesheetWeekOffset
    , fetchShiftTypesForForm
    , fetchShiftTypesForFormIncluding
    , fetchStaffForForm
    , fetchStaffForFormIncluding
    , fetchTimesheetSuggestionForRosterSlot
    , fetchTimesheetWeekProjection
    , renderTimesheetProjectionFragment
    , renderTimesheetProjectionFragmentFromProjection
    , renderTimesheetWeekProjectionFragment
    , timesheetDayOffset
    , timesheetDayRenderModelFromProjection
    , timesheetIndexView
    , parseApproveTimesheetEntryState
    , parseCreateTimesheetEntryFromSuggestionState
    , parseUnapproveTimesheetEntryState
    , canonicalTimesheetFilters
    , timesheetFiltersFromRequest
    , viewerHasTimesheetSuggestionOnDay
    , weekOffsetFromParamOrCurrent
    , weekOffsetFromParamOrEntry
    ) where

import Application.Helper.Controller (venueRoleToText)
import Application.Helper.FrontendContract.Surface.FragmentRender (FragmentRenderMode (..))
import Application.Helper.FrontendContract.Surface.Request (SurfaceRequestFieldError)
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Surface
import qualified Application.Helper.FrontendContract.Surface.Timesheets.Action as TimesheetsAction
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.Profiling
import Application.Helper.Staff (sortStaffForDisplay)
import Application.Helper.RosterTimesheetBoundaries (projectRosterSlotTimesheetBoundaries)
import Application.Helper.UserPreferences (fetchCurrentUserTimesheetPreferences,
                                           userTimesheetShowApproved,
                                           userTimesheetShowSuggestions,
                                           userTimesheetShowWageEstimates)
import Application.Helper.VenueScopedQueries (fetchActiveVenueShiftTypes,
                                               fetchLinkedActiveVenueStaff,
                                               sortShiftTypesForDisplay)
import Application.Helper.WeekBoundaries (venueWeekOffsetForDay)
import Application.PayAssignment (ShiftPayAssignment (..),
                                  StaffPayAssignment (..),
                                  shiftAssignmentAllowsTimesheets,
                                  staffAssignmentAllowsTimesheets)
import Application.RosterShiftAssignment (RosterShiftAssignment (StaffAssignment),
                                          rosterShiftAssignment)
import Application.VenueTime.Model
import Control.Monad (guard)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Time.Calendar (Day, addDays, diffDays)
import Data.Time.Clock (getCurrentTime, utctDay)
import qualified Data.UUID as UUID
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.Timesheets.Filters
import Web.Timesheets.FrontendSurface (TimesheetWeekScopeValue (..),
                                       TimesheetsMountStateValue (..),
                                       timesheetsSurfaceImpl)
import Web.Timesheets.Suggestion
import Web.Timesheets.WageEstimates
import Web.View.Timesheets.Index

data TimesheetWeekProjection = TimesheetWeekProjection
    { timesheetEntries              :: [TimesheetEntry]
    , timesheetSuggestions          :: [TimesheetSuggestion]
    , timesheetStaffMembers         :: [Staff]
    , timesheetShiftTypes           :: [ShiftType]
    , timesheetToday                :: Day
    , timesheetEditWindowDays       :: Int
    , timesheetWeekOffset           :: Int
    , timesheetWeekStartDate        :: Day
    , timesheetWeekEndDate          :: Day
    , timesheetShowApproved         :: Bool
    , timesheetSuggestionsVisible   :: Bool
    , timesheetShowWageEstimates    :: Bool
    , timesheetWageEstimates        :: !(Maybe TimesheetWageEstimates)
    , timesheetRosterGroups         :: [RosterGroup]
    , timesheetFilters              :: TimesheetViewFilters
    , timesheetCurrentViewerStaffId :: Maybe UUID.UUID
    , timesheetStaffPanelEntries    :: [TimesheetStaffPanelEntry]
    }

data TimesheetProjectionRequest = TimesheetProjectionRequest
    { projectionWeekOffset :: !Int
    , projectionFilters    :: !TimesheetViewFilters
    }
    deriving (Eq, Show)

data TimesheetProjectionFragment
    = TimesheetProjectionToolbar
    | TimesheetProjectionDayColumns
    | TimesheetProjectionSidePanel
    | TimesheetProjectionDaySection !Int
    deriving (Eq, Show)

canonicalTimesheetFilters :: (?modelContext :: ModelContext, ?context :: ControllerContext) => TimesheetViewFilters -> IO TimesheetViewFilters
canonicalTimesheetFilters requestedFilters
    | not (hasRole Manager) = pure emptyTimesheetViewFilters
    | otherwise = do
        staffMembers <- fetchLinkedActiveVenueStaff currentVenueId
        rosterGroups <- fetchActiveTimesheetRosterGroups
        pure (canonicalTimesheetFiltersFor staffMembers rosterGroups requestedFilters)

canonicalTimesheetFiltersFor :: [Staff] -> [RosterGroup] -> TimesheetViewFilters -> TimesheetViewFilters
canonicalTimesheetFiltersFor staffMembers rosterGroups requestedFilters =
    TimesheetViewFilters
        { filterStaffId = do
            staffFilterId <- requestedFilters.filterStaffId
            guard (any (\staff -> staffCanProduceTimesheets staff && unpackId (get #id staff) == staffFilterId) staffMembers)
            pure staffFilterId
        , filterRosterGroupId = do
            guard (length rosterGroups > 1)
            rosterGroupFilterId <- requestedFilters.filterRosterGroupId
            guard (any ((== rosterGroupFilterId) . unpackId . (.id)) rosterGroups)
            pure rosterGroupFilterId
        }

fetchActiveTimesheetRosterGroups :: (?modelContext :: ModelContext, ?context :: ControllerContext) => IO [RosterGroup]
fetchActiveTimesheetRosterGroups =
    query @RosterGroup
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#isActive, True)
        |> filterWhere (#archivedAt, Nothing)
        |> orderByAsc #sortOrder
        |> fetch

fetchTimesheetDataForWeek :: (?modelContext :: ModelContext, ?context :: ControllerContext) => Day -> Day -> Bool -> [Staff] -> TimesheetViewFilters -> IO ([TimesheetEntry], Maybe UUID.UUID, [TimesheetStaffPanelEntry])
fetchTimesheetDataForWeek weekStartDate weekEndDate showApproved staffMembers validFilters = do
    maybeCurrentViewerStaff <- fetchCurrentUserStaff

    let (weekStartsAt, weekEndsAt) = requireMelbourneDateRangeUTC weekStartDate weekEndDate
    let baseQuery =
            query @TimesheetEntry
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhereGreaterThanOrEqualTo (#startsAt, weekStartsAt)
                |> filterWhereLessThan (#startsAt, weekEndsAt)
                |> filterWhere (#deletedAt, Nothing)

    allManagerEntries <-
        if hasRole Manager
            then baseQuery |> orderByAsc #startsAt |> fetch
            else pure []
    workerEntries <-
        if hasRole Manager
            then pure []
            else case maybeCurrentViewerStaff of
                Nothing -> pure []
                Just staff ->
                    baseQuery
                        |> filterWhere (#staffId, unpackId (get #id staff))
                        |> orderByAsc #startsAt
                        |> fetch
    let authorizedEntries = if hasRole Manager then allManagerEntries else workerEntries
    rosterGroupEntries <- filterTimesheetEntriesByRosterGroup validFilters.filterRosterGroupId authorizedEntries
    let entries = rosterGroupEntries
            |> filter (\entry -> showApproved || not entry.isApproved)
            |> filter (\entry -> maybe True (== entry.staffId) validFilters.filterStaffId)
    staffPanelEntries <-
        if hasRole Manager
            then buildTimesheetStaffPanelEntries staffMembers rosterGroupEntries
            else pure []

    pure (entries, unpackId . get #id <$> maybeCurrentViewerStaff, staffPanelEntries)

filterTimesheetEntriesByRosterGroup :: (?modelContext :: ModelContext) => Maybe UUID.UUID -> [TimesheetEntry] -> IO [TimesheetEntry]
filterTimesheetEntriesByRosterGroup Nothing entries = pure entries
filterTimesheetEntriesByRosterGroup (Just rosterGroupId) entries = do
    let sourceSlotIds = Set.toList (Set.fromList (mapMaybe (.sourceRosterSlotId) entries))
    rosterSlots <-
        if null sourceSlotIds
            then pure []
            else query @RosterSlot
                |> filterWhereIn (#id, map Id sourceSlotIds)
                |> fetch
    let rosterDayIds = Set.toList (Set.fromList (map (.rosterDayId) rosterSlots))
    rosterDays <-
        if null rosterDayIds
            then pure []
            else query @RosterDay
                |> filterWhereIn (#id, map Id rosterDayIds)
                |> fetch
    let rosterWeekIds = Set.toList (Set.fromList (map (.rosterWeekId) rosterDays))
    matchingRosterWeeks <-
        if null rosterWeekIds
            then pure []
            else query @RosterWeek
                |> filterWhereIn (#id, map Id rosterWeekIds)
                |> filterWhere (#rosterGroupId, rosterGroupId)
                |> fetch
    let matchingRosterWeekIds = Set.fromList (map (unpackId . (.id)) matchingRosterWeeks)
    let matchingRosterDayIds = Set.fromList [unpackId day.id | day <- rosterDays, Set.member day.rosterWeekId matchingRosterWeekIds]
    let matchingRosterSlotIds = Set.fromList [unpackId slot.id | slot <- rosterSlots, Set.member slot.rosterDayId matchingRosterDayIds]
    pure (filter (maybe False (`Set.member` matchingRosterSlotIds) . (.sourceRosterSlotId)) entries)

buildTimesheetStaffPanelEntries :: (?modelContext :: ModelContext, ?context :: ControllerContext) => [Staff] -> [TimesheetEntry] -> IO [TimesheetStaffPanelEntry]
buildTimesheetStaffPanelEntries staffMembers entries = do
    let eligibleStaff = filter staffCanProduceTimesheets staffMembers
    let linkedUserIds = mapMaybe (.userId) eligibleStaff
    memberships <-
        if null linkedUserIds
            then pure []
            else query @VenueMembership
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhereIn (#userId, linkedUserIds)
                |> filterWhere (#isActive, True)
                |> fetch
    let membershipsByUserId = Map.fromList [(membership.userId, membership) | membership <- memberships]
    let entryCountByStaffId = Map.fromListWith (+) [(entry.staffId, 1 :: Int) | entry <- entries]
    let approvedCountByStaffId = Map.fromListWith (+) [(entry.staffId, 1 :: Int) | entry <- entries, entry.isApproved]
    pure
        [ TimesheetStaffPanelEntry
            { panelStaff = staff
            , panelStaffRole = maybe (venueRoleToText Worker) (venueRoleToText . (.venueRole)) (staff.userId >>= (`Map.lookup` membershipsByUserId))
            , panelEntryCount = Map.findWithDefault 0 (unpackId staff.id) entryCountByStaffId
            , panelApprovedCount = Map.findWithDefault 0 (unpackId staff.id) approvedCountByStaffId
            }
        | staff <- eligibleStaff
        ]

fetchTimesheetSuggestionsForWeek :: (?modelContext :: ModelContext, ?context :: ControllerContext) => VenueConfig -> Int -> TimesheetViewFilters -> [RosterGroup] -> [Staff] -> Maybe UUID.UUID -> IO [TimesheetSuggestion]
fetchTimesheetSuggestionsForWeek venueConfig weekOffset filters activeRosterGroups staffMembers currentViewerStaffId = do
    let activeRosterGroupIds =
            activeRosterGroups
                |> map (unpackId . (.id))
                |> filter (\rosterGroupId -> maybe True (== rosterGroupId) filters.filterRosterGroupId)
    liveRosterWeeks <-
        if null activeRosterGroupIds
            then pure []
            else
                query @RosterWeek
                    |> filterWhere (#venueId, unpackId currentVenueId)
                    |> filterWhereIn (#weekOffset, [weekOffset - 1, weekOffset])
                    |> filterWhere (#isLive, True)
                    |> filterWhere (#archivedAt, Nothing)
                    |> filterWhereIn (#rosterGroupId, activeRosterGroupIds)
                    |> fetch
    let liveRosterWeekIds = map (unpackId . (.id)) liveRosterWeeks
    rosterDays <-
        if null liveRosterWeekIds
            then pure []
            else
                query @RosterDay
                    |> filterWhereIn (#rosterWeekId, liveRosterWeekIds)
                    |> fetch
    let rosterDayIds = map (unpackId . (.id)) rosterDays
    rosterSlots <-
        if null rosterDayIds
            then pure []
            else
                query @RosterSlot
                    |> filterWhereIn (#rosterDayId, rosterDayIds)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetch
    activeLinkedEntries <-
        if null rosterSlots
            then pure []
            else
                query @TimesheetEntry
                    |> filterWhere (#venueId, unpackId currentVenueId)
                    |> filterWhere (#deletedAt, Nothing)
                    |> filterWhereIn (#sourceRosterSlotId, map (Just . unpackId . (.id)) rosterSlots)
                    |> fetch

    let linkedRosterSlotIds = Set.fromList (mapMaybe (.sourceRosterSlotId) activeLinkedEntries)
    let linkedActiveStaffIds = Set.fromList (map (unpackId . (.id)) (filter staffCanProduceTimesheets staffMembers))
    let visibleStaffIds =
            if hasRole Manager
                then maybe linkedActiveStaffIds Set.singleton filters.filterStaffId
                else maybe Set.empty Set.singleton currentViewerStaffId
    shiftTypes <- fetchShiftTypesForForm
    let activeShiftTypeIds = Set.fromList (map (unpackId . (.id)) shiftTypes)
    let rosterDaysById = map (\rosterDay -> (unpackId rosterDay.id, rosterDay)) rosterDays
    let weekStartDate = venueWeekStartDate venueConfig weekOffset
    let weekEndDate = addDays 6 weekStartDate

    pure
        ( rosterSlots
            |> mapMaybe (suggestionForSlot rosterDaysById linkedRosterSlotIds visibleStaffIds linkedActiveStaffIds activeShiftTypeIds)
            |> filter (\suggestion -> timesheetSuggestionWorkedOn suggestion >= weekStartDate && timesheetSuggestionWorkedOn suggestion <= weekEndDate)
            |> sortOn (\suggestion -> (timesheetSuggestionWorkedOn suggestion, timesheetSuggestionStartTime suggestion, suggestion.suggestionStaffId))
        )
  where
    suggestionForSlot rosterDaysById linkedRosterSlotIds visibleStaffIds linkedActiveStaffIds activeShiftTypeIds rosterSlot = do
        guard (Set.notMember (unpackId rosterSlot.id) linkedRosterSlotIds)
        _ <- lookup rosterSlot.rosterDayId rosterDaysById
        StaffAssignment (Id staffId) <- eitherToMaybe (rosterShiftAssignment rosterSlot)
        shiftTypeId <- rosterSlot.shiftTypeId
        guard (Set.member staffId linkedActiveStaffIds)
        guard (Set.member staffId visibleStaffIds)
        guard (Set.member shiftTypeId activeShiftTypeIds)
        suggestionBoundaries <- eitherToMaybe (projectRosterSlotTimesheetBoundaries rosterSlot)
        pure TimesheetSuggestion
            { suggestionRosterSlotId = rosterSlot.id
            , suggestionStaffId = staffId
            , suggestionShiftTypeId = shiftTypeId
            , suggestionBoundaries
            }

    eitherToMaybe = either (const Nothing) Just

fetchStaffForForm :: (?modelContext :: ModelContext, ?context :: ControllerContext) => IO [Staff]
fetchStaffForForm = do
    staffMembers <-
        if hasRole Manager
            then fetchLinkedActiveVenueStaff currentVenueId
            else filter (isJust . (.userId)) . maybeToList <$> fetchCurrentUserStaff
    pure (filter staffCanProduceTimesheets staffMembers)

fetchStaffForFormIncluding :: (?modelContext :: ModelContext, ?context :: ControllerContext) => UUID.UUID -> IO [Staff]
fetchStaffForFormIncluding staffId = do
    eligible <- fetchStaffForForm
    if any ((== staffId) . unpackId . (.id)) eligible
        then pure eligible
        else do
            retained <-
                query @Staff
                    |> filterWhere (#venueId, unpackId currentVenueId)
                    |> filterWhere (#id, Id staffId)
                    |> filterWhere (#isActive, True)
                    |> filterWhere (#archivedAt, Nothing)
                    |> fetchOneOrNothing
            pure (sortStaffForDisplay (maybe eligible (: eligible) retained))

fetchShiftTypesForForm :: (?modelContext :: ModelContext, ?context :: ControllerContext) => IO [ShiftType]
fetchShiftTypesForForm =
    filter shiftTypeCanProduceTimesheets <$> fetchActiveVenueShiftTypes currentVenueId

fetchShiftTypesForFormIncluding :: (?modelContext :: ModelContext, ?context :: ControllerContext) => UUID.UUID -> IO [ShiftType]
fetchShiftTypesForFormIncluding shiftTypeId = do
    eligible <- fetchShiftTypesForForm
    if any ((== shiftTypeId) . unpackId . (.id)) eligible
        then pure eligible
        else do
            retained <-
                query @ShiftType
                    |> filterWhere (#venueId, unpackId currentVenueId)
                    |> filterWhere (#id, Id shiftTypeId)
                    |> filterWhere (#isActive, True)
                    |> filterWhere (#archivedAt, Nothing)
                    |> fetchOneOrNothing
            pure (sortShiftTypesForDisplay (maybe eligible (: eligible) retained))

staffCanProduceTimesheets :: Staff -> Bool
staffCanProduceTimesheets = staffAssignmentAllowsTimesheets . staffPayAssignment

shiftTypeCanProduceTimesheets :: ShiftType -> Bool
shiftTypeCanProduceTimesheets = shiftAssignmentAllowsTimesheets . shiftPayAssignment

staffPayAssignment :: Staff -> StaffPayAssignment
staffPayAssignment staff =
    StaffPayAssignment staff.payAssignmentMode staff.defaultAwardLevelId staff.importedXeroPayItemId

shiftPayAssignment :: ShiftType -> ShiftPayAssignment
shiftPayAssignment shiftType =
    ShiftPayAssignment shiftType.payAssignmentMode shiftType.overrideAwardLevelId shiftType.importedXeroPayItemId

fetchShiftTypesForProjection :: (?modelContext :: ModelContext, ?context :: ControllerContext) => IO [ShiftType]
fetchShiftTypesForProjection =
    fetchActiveVenueShiftTypes currentVenueId

fetchTimesheetWeekProjection :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetProjectionRequest -> IO TimesheetWeekProjection
fetchTimesheetWeekProjection TimesheetProjectionRequest { projectionWeekOffset = weekOffset, projectionFilters = requestedFilters } = do
    venueConfig <- fetchVenueConfig
    preferences <- fetchCurrentUserTimesheetPreferences
    let showApproved = preferences.userTimesheetShowApproved
    let showTimesheetSuggestions = preferences.userTimesheetShowSuggestions
    let showWageEstimates = canViewTimesheetWageEstimates && preferences.userTimesheetShowWageEstimates
    let weekStartDate = venueWeekStartDate venueConfig weekOffset
    let weekEndDate = addDays 6 weekStartDate

    staffMembers <- fetchLinkedActiveVenueStaff currentVenueId
    activeRosterGroups <- fetchActiveTimesheetRosterGroups
    let validFilters =
            if hasRole Manager
                then canonicalTimesheetFiltersFor staffMembers activeRosterGroups requestedFilters
                else emptyTimesheetViewFilters
    (entries, currentViewerStaffId, staffPanelEntries) <- profileActionSpan "timesheets.fetch_week_data" (fetchTimesheetDataForWeek weekStartDate weekEndDate showApproved staffMembers validFilters)
    suggestions <-
        if showTimesheetSuggestions
            then profileActionSpan "timesheets.fetch_suggestions" (fetchTimesheetSuggestionsForWeek venueConfig weekOffset validFilters activeRosterGroups staffMembers currentViewerStaffId)
            else pure []
    shiftTypes <- profileActionSpan "timesheets.fetch_shift_types" fetchShiftTypesForProjection
    wageEstimates <-
        if showWageEstimates
            then Just <$> profileActionSpan "timesheets.calculate_wage_estimates" (evaluateTimesheetWageEstimates entries suggestions)
            else pure Nothing
    today <- utctDay <$> getCurrentTime
    let editWindowDays = venueConfig.staffTimesheetEditWindowDays

    pure
        TimesheetWeekProjection
            { timesheetEntries = entries
            , timesheetSuggestions = suggestions
            , timesheetStaffMembers = staffMembers
            , timesheetShiftTypes = shiftTypes
            , timesheetToday = today
            , timesheetEditWindowDays = editWindowDays
            , timesheetWeekOffset = weekOffset
            , timesheetWeekStartDate = weekStartDate
            , timesheetWeekEndDate = weekEndDate
            , timesheetShowApproved = showApproved
            , timesheetSuggestionsVisible = showTimesheetSuggestions
            , timesheetShowWageEstimates = showWageEstimates
            , timesheetWageEstimates = wageEstimates
            , timesheetRosterGroups = if hasRole Manager then activeRosterGroups else []
            , timesheetFilters = validFilters
            , timesheetCurrentViewerStaffId = currentViewerStaffId
            , timesheetStaffPanelEntries = staffPanelEntries
            }

-- Action authority is evaluated against the viewer's full Timesheets scope.
-- URL filters control the rendered list; they do not revoke manager authority.
fetchTimesheetSuggestionForRosterSlot :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterSlot -> IO (Maybe TimesheetSuggestion)
fetchTimesheetSuggestionForRosterSlot rosterSlotId = do
    maybeRosterSlot <-
        query @RosterSlot
            |> filterWhere (#id, rosterSlotId)
            |> fetchOneOrNothing
    case maybeRosterSlot of
        Nothing -> pure Nothing
        Just rosterSlot -> do
            maybeRosterDay <-
                query @RosterDay
                    |> filterWhere (#id, Id rosterSlot.rosterDayId)
                    |> fetchOneOrNothing
            case maybeRosterDay of
                Nothing -> pure Nothing
                Just rosterDay -> do
                    maybeRosterWeek <-
                        query @RosterWeek
                            |> filterWhere (#id, Id rosterDay.rosterWeekId)
                            |> filterWhere (#venueId, unpackId currentVenueId)
                            |> fetchOneOrNothing
                    case maybeRosterWeek of
                        Nothing -> pure Nothing
                        Just _rosterWeek ->
                            case rosterSlot.startsAt of
                                Nothing -> pure Nothing
                                Just startsAt -> do
                                    venueConfig <- fetchVenueConfig
                                    let workedOn = (storedInstantLocalTime rosterSlot.timezone startsAt).localDay
                                    let suggestionWeekOffset = venueWeekOffsetForDay venueConfig workedOn
                                    suggestions <- fetchAuthorizedTimesheetSuggestionsForWeek suggestionWeekOffset emptyTimesheetViewFilters
                                    pure (find (\suggestion -> suggestion.suggestionRosterSlotId == rosterSlotId) suggestions)

-- Presentation preferences never constrain suggestion authority. This path is
-- used by form and mutation checks even when suggestion cards are hidden.
fetchAuthorizedTimesheetSuggestionsForWeek :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Int -> TimesheetViewFilters -> IO [TimesheetSuggestion]
fetchAuthorizedTimesheetSuggestionsForWeek weekOffset filters = do
    venueConfig <- fetchVenueConfig
    let weekStartDate = venueWeekStartDate venueConfig weekOffset
    let weekEndDate = addDays 6 weekStartDate
    staffMembers <- fetchLinkedActiveVenueStaff currentVenueId
    activeRosterGroups <- fetchActiveTimesheetRosterGroups
    let validFilters =
            if hasRole Manager
                then canonicalTimesheetFiltersFor staffMembers activeRosterGroups filters
                else emptyTimesheetViewFilters
    (_, currentViewerStaffId, _) <- fetchTimesheetDataForWeek weekStartDate weekEndDate False staffMembers validFilters
    fetchTimesheetSuggestionsForWeek venueConfig weekOffset validFilters activeRosterGroups staffMembers currentViewerStaffId

-- Ad-hoc creation stays suggestion-aware even when cards are hidden, so the
-- user is told that the new entry is deliberately separate.
viewerHasTimesheetSuggestionOnDay :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Int -> TimesheetViewFilters -> Day -> IO Bool
viewerHasTimesheetSuggestionOnDay weekOffset filters workedOn = do
    suggestions <- fetchAuthorizedTimesheetSuggestionsForWeek weekOffset filters
    pure (any ((== workedOn) . timesheetSuggestionWorkedOn) suggestions)

renderTimesheetProjectionFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetProjectionRequest -> TimesheetProjectionFragment -> IO (Maybe Blaze.Html)
renderTimesheetProjectionFragment requestKey fragment =
    profileActionSpan "timesheets.read_model.render_fragment" do
        projection <- fetchTimesheetWeekProjection requestKey
        pure (renderTimesheetWeekProjectionFragment projection fragment)

renderTimesheetWeekProjectionFragment :: (?context :: ControllerContext, ?request :: Request) => TimesheetWeekProjection -> TimesheetProjectionFragment -> Maybe Blaze.Html
renderTimesheetWeekProjectionFragment =
    renderTimesheetProjectionFragmentFromProjection FragmentPlain

renderTimesheetProjectionFragmentFromProjection :: (?context :: ControllerContext, ?request :: Request) => FragmentRenderMode -> TimesheetWeekProjection -> TimesheetProjectionFragment -> Maybe Blaze.Html
renderTimesheetProjectionFragmentFromProjection renderMode projection fragment =
    case fragment of
        TimesheetProjectionToolbar ->
            Just (toolbarRenderer (timesheetIndexView projection))
        TimesheetProjectionDayColumns ->
            Just (columnsRenderer (timesheetIndexView projection))
        TimesheetProjectionSidePanel ->
            Just (sidePanelRenderer (timesheetIndexView projection))
        TimesheetProjectionDaySection dayOffset ->
            Just (dayRenderer (timesheetDayRenderModelFromProjection projection dayOffset))
    where
        toolbarRenderer = case renderMode of
            FragmentPlain        -> renderTimesheetWeekToolbar
            FragmentOob swapAttr -> renderTimesheetWeekToolbarWithSwap swapAttr
        columnsRenderer = case renderMode of
            FragmentPlain        -> renderTimesheetDayColumns
            FragmentOob swapAttr -> renderTimesheetDayColumnsWithSwap swapAttr
        sidePanelRenderer = case renderMode of
            FragmentPlain        -> renderTimesheetSidePanel
            FragmentOob swapAttr -> renderTimesheetSidePanelWithSwap swapAttr
        dayRenderer = case renderMode of
            FragmentPlain        -> renderDaySection
            FragmentOob swapAttr -> renderDaySectionWithSwap swapAttr

timesheetDayRenderModelFromProjection :: TimesheetWeekProjection -> Int -> TimesheetDayRenderModel
timesheetDayRenderModelFromProjection projection dayOffset =
    TimesheetDayRenderModel
        { dayEntries = projection.timesheetEntries
        , daySuggestions = projection.timesheetSuggestions
        , dayStaffMembers = projection.timesheetStaffMembers
        , dayShiftTypes = projection.timesheetShiftTypes
        , dayWageEstimates = projection.timesheetWageEstimates
        , dayToday = projection.timesheetToday
        , dayEditWindowDays = projection.timesheetEditWindowDays
        , dayWeekOffset = projection.timesheetWeekOffset
        , dayWeekStartDate = projection.timesheetWeekStartDate
        , dayFilters = projection.timesheetFilters
        , dayOffset
        }

timesheetIndexView :: (?context :: ControllerContext) => TimesheetWeekProjection -> IndexView
timesheetIndexView TimesheetWeekProjection { timesheetEntries, timesheetSuggestions, timesheetStaffMembers, timesheetShiftTypes, timesheetToday, timesheetEditWindowDays, timesheetWeekOffset, timesheetWeekStartDate, timesheetWeekEndDate, timesheetShowApproved, timesheetSuggestionsVisible, timesheetShowWageEstimates, timesheetWageEstimates, timesheetRosterGroups, timesheetFilters, timesheetCurrentViewerStaffId, timesheetStaffPanelEntries } =
    IndexView
        { entries = timesheetEntries
        , suggestions = timesheetSuggestions
        , staffMembers = timesheetStaffMembers
        , shiftTypes = timesheetShiftTypes
        , today = timesheetToday
        , editWindowDays = timesheetEditWindowDays
        , weekOffset = timesheetWeekOffset
        , weekStartDate = timesheetWeekStartDate
        , weekEndDate = timesheetWeekEndDate
        , showApproved = timesheetShowApproved
        , showTimesheetSuggestions = timesheetSuggestionsVisible
        , showTimesheetWageEstimates = timesheetShowWageEstimates
        , wageEstimates = timesheetWageEstimates
        , rosterGroups = timesheetRosterGroups
        , viewFilters = timesheetFilters
        , currentViewerStaffId = timesheetCurrentViewerStaffId
        , staffPanelEntries = timesheetStaffPanelEntries
        , frontendSurfaceImpl = Just surfaceImpl
        }
    where
        scopeValue = TimesheetWeekScopeValue
            { timesheetWeekVenueId = unpackId currentVenueId
            , timesheetWeekWeekOffset = timesheetWeekOffset
            }
        mountStateValue = TimesheetsMountStateValue
            { timesheetsMountStaffFilterId = timesheetFilters.filterStaffId
            , timesheetsMountRosterGroupFilterId = timesheetFilters.filterRosterGroupId
            }
        surfaceImpl = timesheetsSurfaceImpl scopeValue mountStateValue

data TimesheetSurfaceRequestState = TimesheetSurfaceRequestState
    { surfaceRequestWeekOffset :: !Int
    , surfaceRequestFilters    :: !TimesheetViewFilters
    }

parseCreateTimesheetEntryFromSuggestionState :: (?request :: Request) => Either [SurfaceRequestFieldError] TimesheetSurfaceRequestState
parseCreateTimesheetEntryFromSuggestionState =
    timesheetSurfaceRequestState
        <$> TimesheetsAction.parseCreateTimesheetEntryFromSuggestionActionParams

parseApproveTimesheetEntryState :: (?request :: Request) => Either [SurfaceRequestFieldError] TimesheetSurfaceRequestState
parseApproveTimesheetEntryState =
    timesheetSurfaceRequestState
        <$> TimesheetsAction.parseApproveTimesheetEntryActionParams

parseUnapproveTimesheetEntryState :: (?request :: Request) => Either [SurfaceRequestFieldError] TimesheetSurfaceRequestState
parseUnapproveTimesheetEntryState =
    timesheetSurfaceRequestState
        <$> TimesheetsAction.parseUnapproveTimesheetEntryActionParams

timesheetSurfaceRequestState :: SurfaceFieldBundleOf (ActionFieldSpecs TimesheetsAction.UpdateTimesheetFiltersActionOperation) fields => fields -> TimesheetSurfaceRequestState
timesheetSurfaceRequestState fields =
    TimesheetSurfaceRequestState
        { surfaceRequestWeekOffset = surfaceFieldValue @Surface.WeekOffset fields
        , surfaceRequestFilters = TimesheetViewFilters
            { filterStaffId = surfaceFieldValue @Surface.StaffFilterId fields
            , filterRosterGroupId = surfaceFieldValue @Surface.RosterGroupFilterId fields
            }
        }

weekOffsetFromParamOrCurrent :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO Int
weekOffsetFromParamOrCurrent = do
    currentOffset <- currentTimesheetWeekOffset
    pure (paramOrDefault currentOffset (cs (surfaceFieldNameFrom @Surface.WeekOffset timesheetRequestFieldWitness)))

weekOffsetFromParamOrEntry :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Day -> IO Int
weekOffsetFromParamOrEntry workedOnDate = do
    venueConfig <- fetchVenueConfig
    let entryOffset = venueWeekOffsetForDay venueConfig workedOnDate
    pure (paramOrDefault entryOffset (cs (surfaceFieldNameFrom @Surface.WeekOffset timesheetRequestFieldWitness)))

currentTimesheetWeekOffset :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO Int
currentTimesheetWeekOffset = do
    venueConfig <- fetchVenueConfig
    today <- utctDay <$> getCurrentTime
    pure (venueWeekOffsetForDay venueConfig today)

timesheetDayOffset :: Day -> Day -> Int
timesheetDayOffset weekStartDate workedOn = fromInteger (diffDays workedOn weekStartDate)




timesheetFiltersFromRequest :: (?request :: Request) => TimesheetViewFilters
timesheetFiltersFromRequest =
    TimesheetViewFilters
        { filterStaffId = parseUUIDText =<< paramOrNothing @Text (cs (surfaceFieldNameFrom @Surface.StaffFilterId timesheetRequestFieldWitness))
        , filterRosterGroupId = parseUUIDText =<< paramOrNothing @Text (cs (surfaceFieldNameFrom @Surface.RosterGroupFilterId timesheetRequestFieldWitness))
        }

timesheetRequestFieldWitness :: ActionFields TimesheetsAction.NavigateTimesheetWeekActionOperation
timesheetRequestFieldWitness =
    TimesheetsAction.navigateTimesheetWeekActionFields 0 Nothing Nothing
