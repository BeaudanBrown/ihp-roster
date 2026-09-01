{-# LANGUAGE FlexibleContexts #-}
{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.Timesheets.Projection
    ( TimesheetProjectionFragment (..)
    , TimesheetProjectionRequest (..)
    , TimesheetFormContext (..)
    , TimesheetFormReferences (..)
    , TimesheetSuggestion (..)
    , TimesheetSurfaceRequestState (..)
    , TimesheetWeekProjection (..)
    , currentTimesheetWindowStart
    , fetchShiftTypesForForm
    , fetchTimesheetFormContext
    , noReferencedTimesheetOptions
    , fetchTimesheetSuggestionForRosterSlot
    , fetchTimesheetWeekProjection
    , renderTimesheetProjectionFragment
    , renderTimesheetProjectionFragmentFromProjection
    , renderTimesheetWeekProjectionFragment
    , timesheetDayRenderModelFromProjection
    , timesheetFormInputsFor
    , timesheetFormReferencesFor
    , timesheetIndexView
    , parseApproveTimesheetEntryState
    , parseCreateTimesheetEntryFromSuggestionState
    , parseUnapproveTimesheetEntryState
    , canonicalTimesheetFilters
    , timesheetFiltersFromRequest
    , viewerHasTimesheetSuggestionOnDay
    , windowStartFromParamOrCurrent
    ) where

import Application.Helper.Controller (venueRoleToText)
import Application.Helper.FrontendContract.Surface.FragmentRender (FragmentRenderMode (..))
import Application.Helper.FrontendContract.Surface.Request (SurfaceRequestFieldError)
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Surface
import qualified Application.Helper.FrontendContract.Surface.Timesheets.Action as TimesheetsAction
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.Profiling
import Application.Helper.RosterTimesheetBoundaries (projectRosterSlotTimesheetBoundaries)
import Application.Helper.TimeRules (venueShiftTimeIntervalMinutes,
                                     venueTimePickerFinalSelectableTimeText,
                                     venueTimePickerStartTimeText)
import Application.Helper.UserPreferences (fetchCurrentUserTimesheetPreferences,
                                           userTimesheetShowApproved,
                                           userTimesheetShowSuggestions,
                                           userTimesheetShowWageEstimates)
import Application.Helper.VenueScopedQueries (fetchActiveVenueMembershipsByUserIds,
                                              fetchLinkedActiveVenueStaff)
import Application.Helper.View.Timesheets (TimesheetFormInputs (..))
import Application.Helper.WeekBoundaries (startOfWeekFor)
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
import Data.Time.Calendar (Day, addDays)
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

data TimesheetFormReferences = TimesheetFormReferences
    { referencedStaffId     :: Maybe (Id Staff)
    , referencedShiftTypeId :: Maybe (Id ShiftType)
    }

noReferencedTimesheetOptions :: TimesheetFormReferences
noReferencedTimesheetOptions = TimesheetFormReferences { referencedStaffId = Nothing, referencedShiftTypeId = Nothing }

timesheetFormReferencesFor :: TimesheetEntry -> TimesheetFormReferences
timesheetFormReferencesFor entry =
    TimesheetFormReferences
        { referencedStaffId = Just (Id entry.staffId)
        , referencedShiftTypeId = Just (Id entry.shiftTypeId)
        }

data TimesheetFormContext = TimesheetFormContext
    { formVenueConfig           :: VenueConfig
    , formStaffMembers          :: [Staff]
    , formShiftTypes            :: [ShiftType]
    , formCurrentViewerStaffId  :: Maybe UUID.UUID
    , formSelectedStaffFilterId :: Maybe UUID.UUID
    , formViewerIsManager       :: Bool
    }

data TimesheetWeekProjection = TimesheetWeekProjection
    { timesheetEntries              :: [TimesheetEntry]
    , timesheetTimingByEntryId      :: !(Map.Map UUID.UUID (Either TimesheetIntegrityError ValidatedTimesheetTiming))
    , timesheetSuggestions          :: [TimesheetSuggestion]
    , timesheetStaffMembers         :: [Staff]
    , timesheetShiftTypes           :: [ShiftType]
    , timesheetToday                :: Day
    , timesheetEditWindowDays       :: Int
    , timesheetWeekStartDate        :: Day
    , timesheetWeekEndDate          :: Day
    , timesheetCalendarRevision     :: Int
    , timesheetHideApproved         :: Bool
    , timesheetSuggestionsVisible   :: Bool
    , timesheetShowWageEstimates    :: Bool
    , timesheetWageEstimates        :: !(Maybe TimesheetWageEstimates)
    , timesheetRosterGroups         :: [RosterGroup]
    , timesheetFilters              :: TimesheetViewFilters
    , timesheetStaffFilterId        :: Maybe UUID.UUID
    , timesheetCurrentViewerStaffId :: Maybe UUID.UUID
    , timesheetStaffPanelEntries    :: [TimesheetStaffPanelEntry]
    }

data TimesheetProjectionRequest = TimesheetProjectionRequest
    { projectionWindowStart         :: !Day
    , projectionWindowEnd           :: !Day
    , projectionStaffFilterId       :: !(Maybe UUID.UUID)
    , projectionRosterGroupFilterId :: !(Maybe UUID.UUID)
    }
    deriving (Eq, Show)

data TimesheetProjectionFragment
    = TimesheetProjectionToolbar
    | TimesheetProjectionDayColumns
    | TimesheetProjectionSidePanel
    | TimesheetProjectionDaySection !Int
    deriving (Eq, Show)

canonicalTimesheetFilters :: (?modelContext :: ModelContext, ?context :: ControllerContext) => TimesheetViewFilters -> IO TimesheetViewFilters
canonicalTimesheetFilters requested
    | not (hasRole Manager) = pure emptyTimesheetViewFilters
    | otherwise = do
        staffMembers <- fetchLinkedActiveVenueStaff currentVenueId
        rosterGroups <- fetchActiveTimesheetRosterGroups
        pure TimesheetViewFilters
            { filterStaffId = requested.filterStaffId >>= \staffId -> guard (any (\staff -> staffCanProduceTimesheets staff && unpackId staff.id == staffId) staffMembers) >> pure staffId
            , filterRosterGroupId = requested.filterRosterGroupId >>= \groupId -> guard (length rosterGroups > 1 && any ((== groupId) . unpackId . (.id)) rosterGroups) >> pure groupId
            }

fetchActiveTimesheetRosterGroups :: (?modelContext :: ModelContext, ?context :: ControllerContext) => IO [RosterGroup]
fetchActiveTimesheetRosterGroups =
    query @RosterGroup
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#isActive, True)
        |> filterWhere (#archivedAt, Nothing)
        |> orderByAsc #sortOrder
        |> fetch

fetchTimesheetDataForWeek :: (?modelContext :: ModelContext, ?context :: ControllerContext) => Day -> Day -> Bool -> TimesheetViewFilters -> IO ([TimesheetEntry], [Staff], Maybe UUID.UUID, Maybe UUID.UUID, [TimesheetStaffPanelEntry])
fetchTimesheetDataForWeek weekStartDate weekEndDate hideApproved filters = do
    staffMembers <- fetchLinkedActiveVenueStaff currentVenueId

    maybeCurrentViewerStaff <- fetchCurrentUserStaff
    let validStaffFilterId =
            if hasRole Manager
                then filters.filterStaffId >>= \staffFilterId ->
                    if any (\staff -> staffCanProduceTimesheets staff && unpackId (get #id staff) == staffFilterId) staffMembers
                        then Just staffFilterId
                        else Nothing
                else Nothing

    let baseQuery =
            query @TimesheetEntry
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhereGreaterThanOrEqualTo (#operationalDate, weekStartDate)
                |> filterWhereLessThan (#operationalDate, weekEndDate)
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
    rosterGroupEntries <- filterTimesheetEntriesByRosterGroup filters.filterRosterGroupId authorizedEntries
    let entries = rosterGroupEntries
            |> filter (not . (hideApproved &&) . (.isApproved))
            |> filter (\entry -> maybe True (== entry.staffId) validStaffFilterId)
    staffPanelEntries <-
        if hasRole Manager
            then buildTimesheetStaffPanelEntries staffMembers rosterGroupEntries
            else pure []

    pure (entries, staffMembers, validStaffFilterId, unpackId . get #id <$> maybeCurrentViewerStaff, staffPanelEntries)

filterTimesheetEntriesByRosterGroup :: (?modelContext :: ModelContext) => Maybe UUID.UUID -> [TimesheetEntry] -> IO [TimesheetEntry]
filterTimesheetEntriesByRosterGroup Nothing entries = pure entries
filterTimesheetEntriesByRosterGroup (Just rosterGroupId) entries = do
    let sourceSlotIds = Set.toList (Set.fromList (mapMaybe (.sourceRosterSlotId) entries))
    slots <- if null sourceSlotIds then pure [] else query @RosterSlot |> filterWhereIn (#id, map Id sourceSlotIds) |> fetch
    let dayIds = nub (map (.rosterDayId) slots)
    days <- if null dayIds then pure [] else query @RosterDay |> filterWhereIn (#id, map Id dayIds) |> filterWhere (#rosterGroupId, rosterGroupId) |> fetch
    let matchingDayIds = Set.fromList (map (unpackId . (.id)) days)
    let matchingSlotIds = Set.fromList [unpackId slot.id | slot <- slots, Set.member slot.rosterDayId matchingDayIds]
    pure (filter (maybe False (`Set.member` matchingSlotIds) . (.sourceRosterSlotId)) entries)

buildTimesheetStaffPanelEntries :: (?modelContext :: ModelContext, ?context :: ControllerContext) => [Staff] -> [TimesheetEntry] -> IO [TimesheetStaffPanelEntry]
buildTimesheetStaffPanelEntries staffMembers entries = do
    let eligibleStaff = filter staffCanProduceTimesheets staffMembers
    let linkedUserIds = mapMaybe (.userId) eligibleStaff
    memberships <- fetchActiveVenueMembershipsByUserIds currentVenueId linkedUserIds
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

fetchTimesheetSuggestionsForWindow :: (?modelContext :: ModelContext, ?context :: ControllerContext) => Day -> Day -> TimesheetViewFilters -> [Staff] -> Maybe UUID.UUID -> IO [TimesheetSuggestion]
fetchTimesheetSuggestionsForWindow windowStart windowEnd filters staffMembers currentViewerStaffId = do
    activeRosterGroups <-
        query @RosterGroup
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#isActive, True)
            |> filterWhere (#archivedAt, Nothing)
            |> fetch
    let activeRosterGroupIds = map (unpackId . (.id)) activeRosterGroups
            |> filter (\groupId -> maybe True (== groupId) filters.filterRosterGroupId)
    rosterDays <-
        if null activeRosterGroupIds
            then pure []
            else
                query @RosterDay
                    |> filterWhere (#venueId, unpackId currentVenueId)
                    |> filterWhereIn (#rosterGroupId, activeRosterGroupIds)
                    |> filterWhere (#publicationState, Published)
                    |> filterWhereGreaterThanOrEqualTo (#operationalDate, windowStart)
                    |> filterWhereLessThan (#operationalDate, windowEnd)
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
    pure
        ( rosterSlots
            |> mapMaybe (suggestionForSlot rosterDaysById linkedRosterSlotIds visibleStaffIds linkedActiveStaffIds activeShiftTypeIds)
            |> filter (\suggestion -> timesheetSuggestionOperationalDate suggestion >= windowStart && timesheetSuggestionOperationalDate suggestion < windowEnd)
            |> sortOn (\suggestion -> (timesheetSuggestionOperationalDate suggestion, timesheetSuggestionStartTime suggestion, suggestion.suggestionStaffId))
        )
  where
    suggestionForSlot rosterDaysById linkedRosterSlotIds visibleStaffIds linkedActiveStaffIds activeShiftTypeIds rosterSlot = do
        guard (Set.notMember (unpackId rosterSlot.id) linkedRosterSlotIds)
        rosterDay <- lookup rosterSlot.rosterDayId rosterDaysById
        StaffAssignment (Id staffId) <- eitherToMaybe (rosterShiftAssignment rosterSlot)
        shiftTypeId <- rosterSlot.shiftTypeId
        guard (Set.member staffId linkedActiveStaffIds)
        guard (Set.member staffId visibleStaffIds)
        guard (Set.member shiftTypeId activeShiftTypeIds)
        suggestionBoundaries <- eitherToMaybe (projectRosterSlotTimesheetBoundaries rosterSlot)
        pure TimesheetSuggestion
            { suggestionRosterSlotId = rosterSlot.id
            , suggestionOperationalDate = rosterDay.operationalDate
            , suggestionStaffId = staffId
            , suggestionShiftTypeId = shiftTypeId
            , suggestionBoundaries
            }

    eitherToMaybe = either (const Nothing) Just

fetchTimesheetFormContext ::
    (?modelContext :: ModelContext, ?context :: ControllerContext) =>
    TimesheetFormReferences ->
    Maybe UUID.UUID ->
    IO TimesheetFormContext
fetchTimesheetFormContext TimesheetFormReferences { .. } formSelectedStaffFilterId = do
    formStaffMembers <- maybe fetchStaffForForm (fetchStaffForFormIncluding . unpackId) referencedStaffId
    formShiftTypes <- maybe fetchShiftTypesForForm (fetchShiftTypesForFormIncluding . unpackId) referencedShiftTypeId
    currentUserStaff <- fetchCurrentUserStaff
    let formCurrentViewerStaffId = unpackId . (.id) <$> currentUserStaff
    formVenueConfig <- fetchVenueConfig
    let formViewerIsManager = hasRole Manager
    pure TimesheetFormContext { .. }

timesheetFormInputsFor :: TimesheetFormContext -> TimesheetEntry -> TimesheetFormInputs
timesheetFormInputsFor context timesheetEntry =
    TimesheetFormInputs
        { timesheetEntry
        , staffMembers = context.formStaffMembers
        , shiftTypes = context.formShiftTypes
        , calendarRevision = context.formVenueConfig.rosterCalendarRevision
        , selectedStaffFilterId = context.formSelectedStaffFilterId
        , currentViewerStaffId = context.formCurrentViewerStaffId
        , pickerStart = venueTimePickerStartTimeText context.formVenueConfig
        , pickerEnd = venueTimePickerFinalSelectableTimeText context.formVenueConfig
        , pickerStep = venueShiftTimeIntervalMinutes context.formVenueConfig
        , viewerIsManager = context.formViewerIsManager
        }

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
fetchTimesheetWeekProjection TimesheetProjectionRequest { projectionWindowStart = weekStartDate, projectionWindowEnd = weekEndExclusive, projectionStaffFilterId = staffFilterId, projectionRosterGroupFilterId = rosterGroupFilterId } = do
    venueConfig <- fetchVenueConfig
    preferences <- fetchCurrentUserTimesheetPreferences
    let hideApproved = not preferences.userTimesheetShowApproved
    let showTimesheetSuggestions = preferences.userTimesheetShowSuggestions
    let showWageEstimates = canViewTimesheetWageEstimates && preferences.userTimesheetShowWageEstimates
    let weekEndDate = addDays (-1) weekEndExclusive
    rosterGroups <- fetchActiveTimesheetRosterGroups
    filters <- canonicalTimesheetFilters (TimesheetViewFilters staffFilterId rosterGroupFilterId)

    (entries, staffMembers, validStaffFilterId, currentViewerStaffId, staffPanelEntries) <- profileActionSpan "timesheets.fetch_week_data" (fetchTimesheetDataForWeek weekStartDate weekEndExclusive hideApproved filters)
    suggestions <-
        if showTimesheetSuggestions
            then profileActionSpan "timesheets.fetch_suggestions" (fetchTimesheetSuggestionsForWindow weekStartDate weekEndExclusive filters { filterStaffId = validStaffFilterId } staffMembers currentViewerStaffId)
            else pure []
    shiftTypes <- profileActionSpan "timesheets.fetch_shift_types" fetchShiftTypesForProjection
    wageEstimates <- if showWageEstimates then Just <$> profileActionSpan "timesheets.calculate_wage_estimates" (evaluateTimesheetWageEstimates entries suggestions) else pure Nothing
    today <- currentOperationalDayForVenue venueConfig
    let editWindowDays = venueConfig.staffTimesheetEditWindowDays

    pure
        TimesheetWeekProjection
            { timesheetEntries = entries
            , timesheetTimingByEntryId = Map.fromList [(unpackId entry.id, decodeTimesheetTiming entry) | entry <- entries]
            , timesheetSuggestions = suggestions
            , timesheetStaffMembers = staffMembers
            , timesheetShiftTypes = shiftTypes
            , timesheetToday = today
            , timesheetEditWindowDays = editWindowDays
            , timesheetWeekStartDate = weekStartDate
            , timesheetWeekEndDate = weekEndDate
            , timesheetCalendarRevision = venueConfig.rosterCalendarRevision
            , timesheetHideApproved = hideApproved
            , timesheetSuggestionsVisible = showTimesheetSuggestions
            , timesheetShowWageEstimates = showWageEstimates
            , timesheetWageEstimates = wageEstimates
            , timesheetRosterGroups = if hasRole Manager then rosterGroups else []
            , timesheetFilters = filters { filterStaffId = validStaffFilterId }
            , timesheetStaffFilterId = validStaffFilterId
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
                    |> filterWhere (#venueId, unpackId currentVenueId)
                    |> filterWhere (#publicationState, Published)
                    |> fetchOneOrNothing
            case maybeRosterDay of
                Nothing -> pure Nothing
                Just rosterDay -> do
                    suggestions <- fetchAuthorizedTimesheetSuggestionsForWindow rosterDay.operationalDate (addDays 1 rosterDay.operationalDate) Nothing
                    pure (find (\suggestion -> suggestion.suggestionRosterSlotId == rosterSlotId) suggestions)

-- Presentation preferences never constrain suggestion authority. This path is
-- used by form and mutation checks even when suggestion cards are hidden.
fetchAuthorizedTimesheetSuggestionsForWindow :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Day -> Day -> Maybe UUID.UUID -> IO [TimesheetSuggestion]
fetchAuthorizedTimesheetSuggestionsForWindow windowStart windowEnd staffFilterId = do
    let filters = TimesheetViewFilters staffFilterId Nothing
    (_, staffMembers, validStaffFilterId, currentViewerStaffId, _) <- fetchTimesheetDataForWeek windowStart windowEnd False filters
    fetchTimesheetSuggestionsForWindow windowStart windowEnd filters { filterStaffId = validStaffFilterId } staffMembers currentViewerStaffId

-- Ad-hoc creation stays suggestion-aware even when cards are hidden, so the
-- user is told that the new entry is deliberately separate.
viewerHasTimesheetSuggestionOnDay :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe UUID.UUID -> Day -> IO Bool
viewerHasTimesheetSuggestionOnDay staffFilterId operationalDate = do
    suggestions <- fetchAuthorizedTimesheetSuggestionsForWindow operationalDate (addDays 1 operationalDate) staffFilterId
    pure (any ((== operationalDate) . timesheetSuggestionOperationalDate) suggestions)

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
        , dayTimingByEntryId = projection.timesheetTimingByEntryId
        , daySuggestions = projection.timesheetSuggestions
        , dayStaffMembers = projection.timesheetStaffMembers
        , dayShiftTypes = projection.timesheetShiftTypes
        , dayToday = projection.timesheetToday
        , dayEditWindowDays = projection.timesheetEditWindowDays
        , dayWeekStartDate = projection.timesheetWeekStartDate
        , dayCalendarRevision = projection.timesheetCalendarRevision
        , dayStaffFilterId = projection.timesheetStaffFilterId
        , dayRosterGroupFilterId = projection.timesheetFilters.filterRosterGroupId
        , dayWageEstimates = projection.timesheetWageEstimates
        , dayOffset
        }

timesheetIndexView :: (?context :: ControllerContext) => TimesheetWeekProjection -> IndexView
timesheetIndexView TimesheetWeekProjection { timesheetEntries, timesheetTimingByEntryId, timesheetSuggestions, timesheetStaffMembers, timesheetShiftTypes, timesheetToday, timesheetEditWindowDays, timesheetWeekStartDate, timesheetWeekEndDate, timesheetCalendarRevision, timesheetHideApproved, timesheetSuggestionsVisible, timesheetShowWageEstimates, timesheetWageEstimates, timesheetRosterGroups, timesheetFilters, timesheetStaffFilterId, timesheetCurrentViewerStaffId, timesheetStaffPanelEntries } =
    IndexView
        { entries = timesheetEntries
        , timingByEntryId = timesheetTimingByEntryId
        , suggestions = timesheetSuggestions
        , staffMembers = timesheetStaffMembers
        , shiftTypes = timesheetShiftTypes
        , today = timesheetToday
        , editWindowDays = timesheetEditWindowDays
        , weekStartDate = timesheetWeekStartDate
        , weekEndDate = timesheetWeekEndDate
        , calendarRevision = timesheetCalendarRevision
        , hideApproved = timesheetHideApproved
        , showTimesheetSuggestions = timesheetSuggestionsVisible
        , showTimesheetWageEstimates = timesheetShowWageEstimates
        , wageEstimates = timesheetWageEstimates
        , rosterGroups = timesheetRosterGroups
        , viewFilters = timesheetFilters
        , selectedStaffFilterId = timesheetStaffFilterId
        , currentViewerStaffId = timesheetCurrentViewerStaffId
        , staffPanelEntries = timesheetStaffPanelEntries
        , frontendSurfaceImpl = Just surfaceImpl
        }
    where
        scopeValue = TimesheetWeekScopeValue
            { timesheetWeekVenueId = unpackId currentVenueId
            , timesheetWindowStart = timesheetWeekStartDate
            , timesheetWindowEnd = addDays 1 timesheetWeekEndDate
            , timesheetCalendarRevision
            }
        mountStateValue = TimesheetsMountStateValue
            { timesheetsMountStaffFilterId = timesheetStaffFilterId
            , timesheetsMountRosterGroupFilterId = timesheetFilters.filterRosterGroupId
            }
        surfaceImpl = timesheetsSurfaceImpl scopeValue mountStateValue

data TimesheetSurfaceRequestState = TimesheetSurfaceRequestState
    { surfaceRequestAnchorDate          :: !Day
    , surfaceRequestCalendarRevision    :: !Int
    , surfaceRequestStaffFilterId       :: !(Maybe UUID.UUID)
    , surfaceRequestRosterGroupFilterId :: !(Maybe UUID.UUID)
    }

parseCreateTimesheetEntryFromSuggestionState :: (?request :: Request) => Either [SurfaceRequestFieldError] TimesheetSurfaceRequestState
parseCreateTimesheetEntryFromSuggestionState = do
    fields <- TimesheetsAction.parseCreateTimesheetEntryFromSuggestionActionParams
    pure (timesheetMutationSurfaceRequestState fields)

parseApproveTimesheetEntryState :: (?request :: Request) => Either [SurfaceRequestFieldError] TimesheetSurfaceRequestState
parseApproveTimesheetEntryState = do
    fields <- TimesheetsAction.parseApproveTimesheetEntryActionParams
    pure (timesheetMutationSurfaceRequestState fields)

parseUnapproveTimesheetEntryState :: (?request :: Request) => Either [SurfaceRequestFieldError] TimesheetSurfaceRequestState
parseUnapproveTimesheetEntryState = do
    fields <- TimesheetsAction.parseUnapproveTimesheetEntryActionParams
    pure (timesheetMutationSurfaceRequestState fields)

timesheetMutationSurfaceRequestState fields =
    TimesheetSurfaceRequestState
        { surfaceRequestAnchorDate = surfaceFieldValue @Surface.AnchorDate fields
        , surfaceRequestCalendarRevision = surfaceFieldValue @Surface.RosterCalendarRevision fields
        , surfaceRequestStaffFilterId = surfaceFieldValue @Surface.StaffFilterId fields
        , surfaceRequestRosterGroupFilterId = Nothing
        }

windowStartFromParamOrCurrent :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO Day
windowStartFromParamOrCurrent = do
    currentWindowStart <- currentTimesheetWindowStart
    case paramOrNothing @Day (cs (surfaceFieldNameFrom @Surface.AnchorDate timesheetRequestFieldWitness)) of
        Nothing -> pure currentWindowStart
        Just anchorDate -> do
            venueConfig <- fetchVenueConfig
            pure (startOfWeekFor venueConfig.rosterWeekStartsOn anchorDate)

currentTimesheetWindowStart :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO Day
currentTimesheetWindowStart = do
    venueConfig <- fetchVenueConfig
    today <- currentOperationalDayForVenue venueConfig
    pure (startOfWeekFor venueConfig.rosterWeekStartsOn today)


timesheetFiltersFromRequest :: (?request :: Request) => TimesheetViewFilters
timesheetFiltersFromRequest = TimesheetViewFilters
    { filterStaffId = parseUUIDText =<< paramOrNothing @Text (cs (surfaceFieldNameFrom @Surface.StaffFilterId timesheetRequestFieldWitness))
    , filterRosterGroupId = parseUUIDText =<< paramOrNothing @Text (cs (surfaceFieldNameFrom @Surface.RosterGroupFilterId timesheetRequestFieldWitness))
    }

timesheetRequestFieldWitness :: ActionFields TimesheetsAction.NavigateTimesheetWeekActionOperation
timesheetRequestFieldWitness =
    TimesheetsAction.navigateTimesheetWeekActionFields (ModifiedJulianDay 0) Nothing Nothing
