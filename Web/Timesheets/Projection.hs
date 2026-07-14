{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.Timesheets.Projection
    ( TimesheetProjectionFragment (..)
    , TimesheetProjectionRequest (..)
    , TimesheetSuggestion (..)
    , TimesheetWeekProjection (..)
    , currentTimesheetWeekOffset
    , fetchShiftTypesForForm
    , fetchStaffForForm
    , fetchTimesheetSuggestionForRosterSlot
    , fetchTimesheetWeekProjection
    , renderTimesheetProjectionFragment
    , renderTimesheetProjectionFragmentFromProjection
    , renderTimesheetWeekProjectionFragment
    , timesheetDayOffset
    , timesheetDayRenderModelFromProjection
    , timesheetDayColumnsFragment
    , timesheetDaySectionFragment
    , timesheetIndexView
    , timesheetToolbarFragment
    , timesheetViewFiltersFromRequest
    , viewerHasTimesheetSuggestionOnDay
    , weekOffsetFromParamOrCurrent
    , weekOffsetFromParamOrEntry
    ) where

import Application.Helper.Controller (automaticMealBreakForShift,
                                      validRosterShiftDurationMinutes)
import Application.Helper.FrontendContract.Surface.FragmentRender (FragmentRenderMode (..))
import Application.Helper.Profiling
import Application.Helper.VenueScopedQueries (fetchLinkedActiveVenueStaff)
import Control.Monad (guard)
import qualified Data.Set as Set
import Data.Time.Calendar (Day, addDays, diffDays)
import Data.Time.Clock (getCurrentTime, utctDay)
import qualified Data.UUID as UUID
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.Timesheets.FrontendSurface (TimesheetWeekScopeValue (..),
                                       TimesheetsMountStateValue (..),
                                       timesheetsSurfaceImpl)
import Web.Timesheets.Suggestion
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
    , timesheetShowAllStaff         :: Bool
    , timesheetShowSuggestions      :: Bool
    , timesheetStaffFilterId        :: Maybe UUID.UUID
    , timesheetCurrentViewerStaffId :: Maybe UUID.UUID
    }

data TimesheetProjectionRequest = TimesheetProjectionRequest
    { projectionWeekOffset      :: !Int
    , projectionShowApproved    :: !Bool
    , projectionShowAllStaff    :: !Bool
    , projectionShowSuggestions :: !Bool
    , projectionStaffFilterId   :: !(Maybe UUID.UUID)
    }
    deriving (Eq, Show)

data TimesheetProjectionFragment
    = TimesheetProjectionToolbar
    | TimesheetProjectionDayColumns
    | TimesheetProjectionDaySection !Int
    deriving (Eq, Show)

fetchTimesheetDataForWeek :: (?modelContext :: ModelContext, ?context :: ControllerContext) => Day -> Day -> Bool -> Bool -> Maybe UUID.UUID -> IO ([TimesheetEntry], [Staff], Maybe UUID.UUID, Maybe UUID.UUID)
fetchTimesheetDataForWeek weekStartDate weekEndDate showApproved showAllStaff requestedStaffFilterId = do
    staffMembers <- fetchLinkedActiveVenueStaff currentVenueId

    let weekDays = [weekStartDate .. weekEndDate]
    maybeCurrentViewerStaff <- fetchCurrentUserStaff
    let validStaffFilterId =
            if hasRole ManagerRole'
                then requestedStaffFilterId >>= \staffFilterId ->
                    if any (\staff -> unpackId (get #id staff) == staffFilterId) staffMembers
                        then Just staffFilterId
                        else Nothing
                else Nothing

    let applyApprovedFilter queryBuilder =
            if showApproved
                then queryBuilder
                else queryBuilder |> filterWhere (#isApproved, False)

    entries <-
        if hasRole ManagerRole'
            then do
                let baseQuery =
                        query @TimesheetEntry
                            |> filterWhere (#venueId, unpackId currentVenueId)
                            |> filterWhereIn (#workedOn, weekDays)
                            |> filterWhere (#deletedAt, Nothing)
                case (validStaffFilterId, showAllStaff, maybeCurrentViewerStaff) of
                    (Just staffFilterId, _, _) ->
                        applyApprovedFilter
                            (baseQuery |> filterWhere (#staffId, staffFilterId))
                            |> orderByAsc #workedOn
                            |> orderByAsc #startTime
                            |> fetch
                    (Nothing, False, Just staff) ->
                        applyApprovedFilter
                            (baseQuery |> filterWhere (#staffId, unpackId (get #id staff)))
                            |> orderByAsc #workedOn
                            |> orderByAsc #startTime
                            |> fetch
                    (Nothing, False, Nothing) ->
                        pure []
                    (Nothing, True, _) ->
                        applyApprovedFilter baseQuery
                            |> orderByAsc #workedOn
                            |> orderByAsc #startTime
                            |> fetch
            else do
                case maybeCurrentViewerStaff of
                    Nothing -> pure []
                    Just staff ->
                        applyApprovedFilter
                                ( query @TimesheetEntry
                                    |> filterWhere (#venueId, unpackId currentVenueId)
                                    |> filterWhere (#staffId, unpackId (get #id staff))
                                    |> filterWhereIn (#workedOn, weekDays)
                                    |> filterWhere (#deletedAt, Nothing)
                                )
                                |> orderByAsc #workedOn
                                |> orderByAsc #startTime
                                |> fetch

    pure (entries, staffMembers, validStaffFilterId, unpackId . get #id <$> maybeCurrentViewerStaff)

fetchTimesheetSuggestionsForWeek :: (?modelContext :: ModelContext, ?context :: ControllerContext) => VenueConfig -> Int -> Bool -> Maybe UUID.UUID -> [Staff] -> Maybe UUID.UUID -> IO [TimesheetSuggestion]
fetchTimesheetSuggestionsForWeek venueConfig weekOffset showAllStaff validStaffFilterId staffMembers currentViewerStaffId = do
    activeRosterGroups <-
        query @RosterGroup
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#isActive, True)
            |> filterWhere (#archivedAt, Nothing)
            |> fetch
    let activeRosterGroupIds = map (unpackId . (.id)) activeRosterGroups
    liveRosterWeeks <-
        if null activeRosterGroupIds
            then pure []
            else
                query @RosterWeek
                    |> filterWhere (#venueId, unpackId currentVenueId)
                    |> filterWhere (#weekOffset, weekOffset)
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
    let linkedActiveStaffIds = Set.fromList (map (unpackId . (.id)) staffMembers)
    let visibleStaffIds =
            if hasRole ManagerRole'
                then case (validStaffFilterId, showAllStaff, currentViewerStaffId) of
                    (Just staffFilterId, _, _) -> Set.singleton staffFilterId
                    (Nothing, False, Just viewerStaffId) -> Set.singleton viewerStaffId
                    (Nothing, False, Nothing) -> Set.empty
                    (Nothing, True, _) -> linkedActiveStaffIds
                else maybe Set.empty Set.singleton currentViewerStaffId
    shiftTypes <- fetchShiftTypesForForm
    let activeShiftTypeIds = Set.fromList (map (unpackId . (.id)) shiftTypes)
    let rosterDaysById = map (\rosterDay -> (unpackId rosterDay.id, rosterDay)) rosterDays
    let weekStartDate = venueWeekStartDate venueConfig weekOffset

    pure
        ( rosterSlots
            |> mapMaybe (suggestionForSlot rosterDaysById weekStartDate linkedRosterSlotIds visibleStaffIds linkedActiveStaffIds activeShiftTypeIds)
            |> sortOn (\suggestion -> (suggestion.suggestionWorkedOn, suggestion.suggestionStartTime, suggestion.suggestionStaffId))
        )
  where
    suggestionForSlot rosterDaysById weekStartDate linkedRosterSlotIds visibleStaffIds linkedActiveStaffIds activeShiftTypeIds rosterSlot = do
        guard (Set.notMember (unpackId rosterSlot.id) linkedRosterSlotIds)
        rosterDay <- lookup rosterSlot.rosterDayId rosterDaysById
        staffId <- rosterSlot.staffId
        startTime <- rosterSlot.startTime
        endTime <- rosterSlot.endTime
        shiftTypeId <- rosterSlot.shiftTypeId
        _ <- validRosterShiftDurationMinutes startTime endTime
        guard (Set.member staffId linkedActiveStaffIds)
        guard (Set.member staffId visibleStaffIds)
        guard (Set.member shiftTypeId activeShiftTypeIds)
        let (hadBreak, breakStart, breakEnd, breakMinutes) =
                case automaticMealBreakForShift startTime endTime of
                    Nothing -> (False, Nothing, Nothing, 0)
                    Just (automaticBreakStart, automaticBreakEnd, automaticBreakMinutes) ->
                        (True, Just automaticBreakStart, Just automaticBreakEnd, automaticBreakMinutes)
        pure
            TimesheetSuggestion
                { suggestionRosterSlotId = rosterSlot.id
                , suggestionStaffId = staffId
                , suggestionShiftTypeId = shiftTypeId
                , suggestionWorkedOn = addDays (toInteger rosterDay.dayOffset) weekStartDate
                , suggestionStartTime = startTime
                , suggestionEndTime = endTime
                , suggestionHadBreak = hadBreak
                , suggestionBreakStart = breakStart
                , suggestionBreakEnd = breakEnd
                , suggestionBreakMinutes = breakMinutes
                }

fetchStaffForForm :: (?modelContext :: ModelContext, ?context :: ControllerContext) => IO [Staff]
fetchStaffForForm =
    if hasRole ManagerRole'
        then fetchLinkedActiveVenueStaff currentVenueId
        else filter (isJust . (.userId)) . maybeToList <$> fetchCurrentUserStaff

fetchShiftTypesForForm :: (?modelContext :: ModelContext, ?context :: ControllerContext) => IO [ShiftType]
fetchShiftTypesForForm =
    query @ShiftType
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#isActive, True)
        |> orderByAsc #createdAt
        |> fetch

fetchTimesheetWeekProjection :: (?context :: ControllerContext, ?modelContext :: ModelContext) => TimesheetProjectionRequest -> IO TimesheetWeekProjection
fetchTimesheetWeekProjection TimesheetProjectionRequest { projectionWeekOffset = weekOffset, projectionShowApproved = showApproved, projectionShowAllStaff = showAllStaff, projectionShowSuggestions = showSuggestions, projectionStaffFilterId = staffFilterId } = do
    venueConfig <- fetchVenueConfig
    let weekStartDate = venueWeekStartDate venueConfig weekOffset
    let weekEndDate = addDays 6 weekStartDate

    (entries, staffMembers, validStaffFilterId, currentViewerStaffId) <- profileActionSpan "timesheets.fetch_week_data" (fetchTimesheetDataForWeek weekStartDate weekEndDate showApproved showAllStaff staffFilterId)
    suggestions <-
        if showSuggestions
            then profileActionSpan "timesheets.fetch_suggestions" (fetchTimesheetSuggestionsForWeek venueConfig weekOffset showAllStaff validStaffFilterId staffMembers currentViewerStaffId)
            else pure []
    shiftTypes <- profileActionSpan "timesheets.fetch_shift_types" fetchShiftTypesForForm
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
            , timesheetShowAllStaff = showAllStaff
            , timesheetShowSuggestions = showSuggestions
            , timesheetStaffFilterId = validStaffFilterId
            , timesheetCurrentViewerStaffId = currentViewerStaffId
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
                        Just rosterWeek -> do
                            projection <-
                                fetchTimesheetWeekProjection
                                    TimesheetProjectionRequest
                                        { projectionWeekOffset = rosterWeek.weekOffset
                                        , projectionShowApproved = True
                                        , projectionShowAllStaff = True
                                        , projectionShowSuggestions = True
                                        , projectionStaffFilterId = Nothing
                                        }
                            pure (find (\suggestion -> suggestion.suggestionRosterSlotId == rosterSlotId) projection.timesheetSuggestions)

-- Ad-hoc creation stays suggestion-aware even when cards are hidden, so the
-- user is told that the new entry is deliberately separate.
viewerHasTimesheetSuggestionOnDay :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Int -> Bool -> Maybe UUID.UUID -> Day -> IO Bool
viewerHasTimesheetSuggestionOnDay weekOffset showAllStaff staffFilterId workedOn = do
    projection <-
        fetchTimesheetWeekProjection
            TimesheetProjectionRequest
                { projectionWeekOffset = weekOffset
                , projectionShowApproved = True
                , projectionShowAllStaff = showAllStaff
                , projectionShowSuggestions = True
                , projectionStaffFilterId = staffFilterId
                }
    pure (any (\suggestion -> suggestion.suggestionWorkedOn == workedOn) projection.timesheetSuggestions)

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
        TimesheetProjectionDaySection dayOffset ->
            Just (dayRenderer (timesheetDayRenderModelFromProjection projection dayOffset))
    where
        toolbarRenderer = case renderMode of
            FragmentPlain        -> renderTimesheetWeekToolbar
            FragmentOob swapAttr -> renderTimesheetWeekToolbarWithSwap swapAttr
        columnsRenderer = case renderMode of
            FragmentPlain        -> renderTimesheetDayColumns
            FragmentOob swapAttr -> renderTimesheetDayColumnsWithSwap swapAttr
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
        , dayToday = projection.timesheetToday
        , dayEditWindowDays = projection.timesheetEditWindowDays
        , dayWeekOffset = projection.timesheetWeekOffset
        , dayWeekStartDate = projection.timesheetWeekStartDate
        , dayShowApproved = projection.timesheetShowApproved
        , dayShowAllStaff = projection.timesheetShowAllStaff
        , dayShowSuggestions = projection.timesheetShowSuggestions
        , dayStaffFilterId = projection.timesheetStaffFilterId
        , dayOffset
        }

timesheetIndexView :: (?context :: ControllerContext) => TimesheetWeekProjection -> IndexView
timesheetIndexView TimesheetWeekProjection { timesheetEntries, timesheetSuggestions, timesheetStaffMembers, timesheetShiftTypes, timesheetToday, timesheetEditWindowDays, timesheetWeekOffset, timesheetWeekStartDate, timesheetWeekEndDate, timesheetShowApproved, timesheetShowAllStaff, timesheetShowSuggestions, timesheetStaffFilterId, timesheetCurrentViewerStaffId } =
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
        , showAllStaff = timesheetShowAllStaff
        , showSuggestions = timesheetShowSuggestions
        , selectedStaffFilterId = timesheetStaffFilterId
        , currentViewerStaffId = timesheetCurrentViewerStaffId
        , frontendSurfaceImpl = Just surfaceImpl
        }
    where
        scopeValue = TimesheetWeekScopeValue
            { timesheetWeekVenueId = unpackId currentVenueId
            , timesheetWeekWeekOffset = timesheetWeekOffset
            }
        mountStateValue = TimesheetsMountStateValue
            { timesheetsMountShowApproved = timesheetShowApproved
            , timesheetsMountShowAllStaff = timesheetShowAllStaff
            , timesheetsMountShowSuggestions = timesheetShowSuggestions
            , timesheetsMountStaffFilterId = timesheetStaffFilterId
            }
        surfaceImpl = timesheetsSurfaceImpl scopeValue mountStateValue

weekOffsetFromParamOrCurrent :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO Int
weekOffsetFromParamOrCurrent = do
    currentOffset <- currentTimesheetWeekOffset
    pure (paramOrDefault currentOffset "weekOffset")

weekOffsetFromParamOrEntry :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Day -> IO Int
weekOffsetFromParamOrEntry workedOnDate = do
    venueConfig <- fetchVenueConfig
    let entryOffset = venueWeekOffsetForDay venueConfig workedOnDate
    pure (paramOrDefault entryOffset "weekOffset")

currentTimesheetWeekOffset :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO Int
currentTimesheetWeekOffset = do
    venueConfig <- fetchVenueConfig
    today <- utctDay <$> getCurrentTime
    pure (venueWeekOffsetForDay venueConfig today)

timesheetDayOffset :: Day -> Day -> Int
timesheetDayOffset weekStartDate workedOn = fromInteger (diffDays workedOn weekStartDate)

timesheetToolbarFragment :: TimesheetProjectionFragment
timesheetToolbarFragment =
    TimesheetProjectionToolbar

timesheetDayColumnsFragment :: TimesheetProjectionFragment
timesheetDayColumnsFragment =
    TimesheetProjectionDayColumns

timesheetDaySectionFragment :: Int -> TimesheetProjectionFragment
timesheetDaySectionFragment =
    TimesheetProjectionDaySection

timesheetViewFiltersFromRequest :: (?request :: Request) => (Bool, Bool, Bool, Maybe UUID.UUID)
timesheetViewFiltersFromRequest =
    ( paramOrDefault @Bool False "showApproved"
    , paramOrDefault @Bool True "showAllStaff"
    , paramOrDefault @Bool True "showSuggestions"
    , parseUUIDText =<< paramOrNothing @Text "staffFilterId"
    )
