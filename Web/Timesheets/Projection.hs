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
    , timesheetDayColumnsFragment
    , timesheetDaySectionFragment
    , timesheetIndexView
    , timesheetToolbarFragment
    , parseApproveTimesheetEntryState
    , parseCreateTimesheetEntryFromSuggestionState
    , parseNavigateTimesheetWeekState
    , parseUnapproveTimesheetEntryState
    , canonicalTimesheetStaffFilter
    , parseUpdateTimesheetFiltersState
    , timesheetStaffFilterFromRequest
    , viewerHasTimesheetSuggestionOnDay
    , weekOffsetFromParamOrCurrent
    , weekOffsetFromParamOrEntry
    ) where

import Application.Helper.FrontendContract.Surface.FragmentRender (FragmentRenderMode (..))
import Application.Helper.FrontendContract.Surface.Request (SurfaceRequestFieldError)
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Surface
import qualified Application.Helper.FrontendContract.Surface.Timesheets.Action as TimesheetsAction
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.Profiling
import Application.Helper.RosterTimesheetBoundaries (projectRosterSlotTimesheetBoundaries)
import Application.Helper.UserPreferences (fetchCurrentUserTimesheetPreferences,
                                           userTimesheetHideApproved,
                                           userTimesheetShowSuggestions)
import Application.Helper.VenueScopedQueries (fetchLinkedActiveVenueStaff)
import Application.Helper.WeekBoundaries (venueWeekOffsetForDay)
import Application.PayAssignment (ShiftPayAssignment (..),
                                  StaffPayAssignment (..),
                                  shiftAssignmentAllowsTimesheets,
                                  staffAssignmentAllowsTimesheets)
import Application.RosterShiftAssignment (RosterShiftAssignment (StaffAssignment),
                                          rosterShiftAssignment)
import Application.VenueTime.Model
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
    , timesheetHideApproved         :: Bool
    , timesheetSuggestionsVisible   :: Bool
    , timesheetStaffFilterId        :: Maybe UUID.UUID
    , timesheetCurrentViewerStaffId :: Maybe UUID.UUID
    }

data TimesheetProjectionRequest = TimesheetProjectionRequest
    { projectionWeekOffset    :: !Int
    , projectionStaffFilterId :: !(Maybe UUID.UUID)
    }
    deriving (Eq, Show)

data TimesheetProjectionFragment
    = TimesheetProjectionToolbar
    | TimesheetProjectionDayColumns
    | TimesheetProjectionDaySection !Int
    deriving (Eq, Show)

canonicalTimesheetStaffFilter :: (?modelContext :: ModelContext, ?context :: ControllerContext) => Maybe UUID.UUID -> IO (Maybe UUID.UUID)
canonicalTimesheetStaffFilter requestedStaffFilterId
    | not (hasRole Manager) = pure Nothing
    | otherwise = do
        staffMembers <- fetchLinkedActiveVenueStaff currentVenueId
        pure do
            staffFilterId <- requestedStaffFilterId
            guard (any (\staff -> staffCanProduceTimesheets staff && unpackId (get #id staff) == staffFilterId) staffMembers)
            pure staffFilterId

fetchTimesheetDataForWeek :: (?modelContext :: ModelContext, ?context :: ControllerContext) => Day -> Day -> Bool -> Maybe UUID.UUID -> IO ([TimesheetEntry], [Staff], Maybe UUID.UUID, Maybe UUID.UUID)
fetchTimesheetDataForWeek weekStartDate weekEndDate hideApproved requestedStaffFilterId = do
    staffMembers <- fetchLinkedActiveVenueStaff currentVenueId

    maybeCurrentViewerStaff <- fetchCurrentUserStaff
    let validStaffFilterId =
            if hasRole Manager
                then requestedStaffFilterId >>= \staffFilterId ->
                    if any (\staff -> staffCanProduceTimesheets staff && unpackId (get #id staff) == staffFilterId) staffMembers
                        then Just staffFilterId
                        else Nothing
                else Nothing

    let applyApprovedFilter queryBuilder =
            if hideApproved
                then queryBuilder |> filterWhere (#isApproved, False)
                else queryBuilder
    let (weekStartsAt, weekEndsAt) = requireMelbourneDateRangeUTC weekStartDate weekEndDate
    let baseQuery =
            query @TimesheetEntry
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhereGreaterThanOrEqualTo (#startsAt, weekStartsAt)
                |> filterWhereLessThan (#startsAt, weekEndsAt)
                |> filterWhere (#deletedAt, Nothing)

    entries <-
        if hasRole Manager
            then
                case validStaffFilterId of
                    Just staffFilterId ->
                        applyApprovedFilter
                            (baseQuery |> filterWhere (#staffId, staffFilterId))
                            |> orderByAsc #startsAt
                            |> fetch
                    Nothing ->
                        applyApprovedFilter baseQuery
                            |> orderByAsc #startsAt
                            |> fetch
            else
                case maybeCurrentViewerStaff of
                    Nothing -> pure []
                    Just staff ->
                        applyApprovedFilter
                            (baseQuery |> filterWhere (#staffId, unpackId (get #id staff)))
                            |> orderByAsc #startsAt
                            |> fetch

    pure (entries, staffMembers, validStaffFilterId, unpackId . get #id <$> maybeCurrentViewerStaff)

fetchTimesheetSuggestionsForWeek :: (?modelContext :: ModelContext, ?context :: ControllerContext) => VenueConfig -> Int -> Maybe UUID.UUID -> [Staff] -> Maybe UUID.UUID -> IO [TimesheetSuggestion]
fetchTimesheetSuggestionsForWeek venueConfig weekOffset validStaffFilterId staffMembers currentViewerStaffId = do
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
                then maybe linkedActiveStaffIds Set.singleton validStaffFilterId
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
            pure (maybe eligible (: eligible) retained)

fetchShiftTypesForForm :: (?modelContext :: ModelContext, ?context :: ControllerContext) => IO [ShiftType]
fetchShiftTypesForForm = do
    shiftTypes <-
        query @ShiftType
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#isActive, True)
            |> filterWhere (#archivedAt, Nothing)
            |> orderByAsc #createdAt
            |> fetch
    pure (filter shiftTypeCanProduceTimesheets shiftTypes)

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
            pure (maybe eligible (: eligible) retained)

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
    query @ShiftType
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#isActive, True)
        |> filterWhere (#archivedAt, Nothing)
        |> orderByAsc #createdAt
        |> fetch

fetchTimesheetWeekProjection :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetProjectionRequest -> IO TimesheetWeekProjection
fetchTimesheetWeekProjection TimesheetProjectionRequest { projectionWeekOffset = weekOffset, projectionStaffFilterId = staffFilterId } = do
    venueConfig <- fetchVenueConfig
    preferences <- fetchCurrentUserTimesheetPreferences
    let hideApproved = preferences.userTimesheetHideApproved
    let showTimesheetSuggestions = preferences.userTimesheetShowSuggestions
    let weekStartDate = venueWeekStartDate venueConfig weekOffset
    let weekEndDate = addDays 6 weekStartDate

    (entries, staffMembers, validStaffFilterId, currentViewerStaffId) <- profileActionSpan "timesheets.fetch_week_data" (fetchTimesheetDataForWeek weekStartDate weekEndDate hideApproved staffFilterId)
    suggestions <-
        if showTimesheetSuggestions
            then profileActionSpan "timesheets.fetch_suggestions" (fetchTimesheetSuggestionsForWeek venueConfig weekOffset validStaffFilterId staffMembers currentViewerStaffId)
            else pure []
    shiftTypes <- profileActionSpan "timesheets.fetch_shift_types" fetchShiftTypesForProjection
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
            , timesheetHideApproved = hideApproved
            , timesheetSuggestionsVisible = showTimesheetSuggestions
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
                        Just _rosterWeek ->
                            case rosterSlot.startsAt of
                                Nothing -> pure Nothing
                                Just startsAt -> do
                                    venueConfig <- fetchVenueConfig
                                    let workedOn = (storedInstantLocalTime rosterSlot.timezone startsAt).localDay
                                    let suggestionWeekOffset = venueWeekOffsetForDay venueConfig workedOn
                                    suggestions <- fetchAuthorizedTimesheetSuggestionsForWeek suggestionWeekOffset Nothing
                                    pure (find (\suggestion -> suggestion.suggestionRosterSlotId == rosterSlotId) suggestions)

-- Presentation preferences never constrain suggestion authority. This path is
-- used by form and mutation checks even when suggestion cards are hidden.
fetchAuthorizedTimesheetSuggestionsForWeek :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Int -> Maybe UUID.UUID -> IO [TimesheetSuggestion]
fetchAuthorizedTimesheetSuggestionsForWeek weekOffset staffFilterId = do
    venueConfig <- fetchVenueConfig
    let weekStartDate = venueWeekStartDate venueConfig weekOffset
    let weekEndDate = addDays 6 weekStartDate
    (_, staffMembers, validStaffFilterId, currentViewerStaffId) <- fetchTimesheetDataForWeek weekStartDate weekEndDate False staffFilterId
    fetchTimesheetSuggestionsForWeek venueConfig weekOffset validStaffFilterId staffMembers currentViewerStaffId

-- Ad-hoc creation stays suggestion-aware even when cards are hidden, so the
-- user is told that the new entry is deliberately separate.
viewerHasTimesheetSuggestionOnDay :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Int -> Maybe UUID.UUID -> Day -> IO Bool
viewerHasTimesheetSuggestionOnDay weekOffset staffFilterId workedOn = do
    suggestions <- fetchAuthorizedTimesheetSuggestionsForWeek weekOffset staffFilterId
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
        , dayStaffFilterId = projection.timesheetStaffFilterId
        , dayOffset
        }

timesheetIndexView :: (?context :: ControllerContext) => TimesheetWeekProjection -> IndexView
timesheetIndexView TimesheetWeekProjection { timesheetEntries, timesheetSuggestions, timesheetStaffMembers, timesheetShiftTypes, timesheetToday, timesheetEditWindowDays, timesheetWeekOffset, timesheetWeekStartDate, timesheetWeekEndDate, timesheetHideApproved, timesheetSuggestionsVisible, timesheetStaffFilterId, timesheetCurrentViewerStaffId } =
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
        , hideApproved = timesheetHideApproved
        , showTimesheetSuggestions = timesheetSuggestionsVisible
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
            { timesheetsMountStaffFilterId = timesheetStaffFilterId }
        surfaceImpl = timesheetsSurfaceImpl scopeValue mountStateValue

data TimesheetSurfaceRequestState = TimesheetSurfaceRequestState
    { surfaceRequestWeekOffset    :: !Int
    , surfaceRequestStaffFilterId :: !(Maybe UUID.UUID)
    }

parseNavigateTimesheetWeekState :: (?request :: Request) => Either [SurfaceRequestFieldError] TimesheetSurfaceRequestState
parseNavigateTimesheetWeekState =
    timesheetSurfaceRequestState
        <$> TimesheetsAction.parseNavigateTimesheetWeekActionParams

parseUpdateTimesheetFiltersState :: (?request :: Request) => Either [SurfaceRequestFieldError] TimesheetSurfaceRequestState
parseUpdateTimesheetFiltersState =
    timesheetSurfaceRequestState
        <$> TimesheetsAction.parseUpdateTimesheetFiltersActionParams

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

timesheetSurfaceRequestState :: SurfaceFieldBundleOf (SurfaceActionFieldSpecs Surface.TimesheetsSurface Surface.UpdateTimesheetFilters) fields => fields -> TimesheetSurfaceRequestState
timesheetSurfaceRequestState fields =
    TimesheetSurfaceRequestState
        { surfaceRequestWeekOffset = surfaceFieldValue @Surface.WeekOffset fields
        , surfaceRequestStaffFilterId = surfaceFieldValue @Surface.StaffFilterId fields
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

timesheetToolbarFragment :: TimesheetProjectionFragment
timesheetToolbarFragment =
    TimesheetProjectionToolbar

timesheetDayColumnsFragment :: TimesheetProjectionFragment
timesheetDayColumnsFragment =
    TimesheetProjectionDayColumns

timesheetDaySectionFragment :: Int -> TimesheetProjectionFragment
timesheetDaySectionFragment =
    TimesheetProjectionDaySection

timesheetStaffFilterFromRequest :: (?request :: Request) => Maybe UUID.UUID
timesheetStaffFilterFromRequest =
    parseUUIDText =<< paramOrNothing @Text (cs (surfaceFieldNameFrom @Surface.StaffFilterId timesheetRequestFieldWitness))

timesheetRequestFieldWitness :: SurfaceActionFields Surface.TimesheetsSurface Surface.NavigateTimesheetWeek
timesheetRequestFieldWitness =
    TimesheetsAction.navigateTimesheetWeekActionFields 0 Nothing
