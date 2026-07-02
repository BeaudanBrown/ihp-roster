{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.Timesheets.Projection
    ( TimesheetFragmentRenderMode (..)
    , TimesheetProjectionFragment (..)
    , TimesheetProjectionRequest (..)
    , TimesheetWeekProjection (..)
    , currentTimesheetWeekOffset
    , fetchShiftTypesForForm
    , fetchStaffForForm
    , fetchTimesheetWeekProjection
    , fetchTimesheetWeekProjectionCached
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
    , weekOffsetFromParamOrCurrent
    , weekOffsetFromParamOrEntry
    ) where

import Application.Helper.Profiling
import Application.Helper.VenueScopedQueries (fetchLinkedActiveVenueStaff)
import Application.Helper.View.Oob (OobSwapAttr)
import Data.Time.Calendar (Day, addDays, diffDays)
import Data.Time.Clock (getCurrentTime, utctDay)
import qualified Data.UUID as UUID
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.Timesheets.FrontendSurface (TimesheetWeekScopeValue (..),
                                       TimesheetsMountStateValue (..),
                                       timesheetsLegacyLiveSurfaceConfig,
                                       timesheetsSurfaceImpl)
import Web.View.Timesheets.Index

data TimesheetWeekProjection = TimesheetWeekProjection
    { timesheetEntries              :: [TimesheetEntry]
    , timesheetStaffMembers         :: [Staff]
    , timesheetShiftTypes           :: [ShiftType]
    , timesheetToday                :: Day
    , timesheetEditWindowDays       :: Int
    , timesheetWeekOffset           :: Int
    , timesheetWeekStartDate        :: Day
    , timesheetWeekEndDate          :: Day
    , timesheetShowApproved         :: Bool
    , timesheetShowAllStaff         :: Bool
    , timesheetStaffFilterId        :: Maybe UUID.UUID
    , timesheetCurrentViewerStaffId :: Maybe UUID.UUID
    }

data TimesheetProjectionRequest = TimesheetProjectionRequest
    { projectionWeekOffset    :: !Int
    , projectionShowApproved  :: !Bool
    , projectionShowAllStaff  :: !Bool
    , projectionStaffFilterId :: !(Maybe UUID.UUID)
    }
    deriving (Eq, Show)

data TimesheetProjectionFragment
    = TimesheetProjectionToolbar
    | TimesheetProjectionDayColumns
    | TimesheetProjectionDaySection !Int
    deriving (Eq, Show)

data TimesheetFragmentRenderMode
    = TimesheetFragmentPlain
    | TimesheetFragmentOob !OobSwapAttr
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
fetchTimesheetWeekProjection TimesheetProjectionRequest { projectionWeekOffset = weekOffset, projectionShowApproved = showApproved, projectionShowAllStaff = showAllStaff, projectionStaffFilterId = staffFilterId } = do
    venueConfig <- fetchVenueConfig
    let weekStartDate = venueWeekStartDate venueConfig weekOffset
    let weekEndDate = addDays 6 weekStartDate

    (entries, staffMembers, validStaffFilterId, currentViewerStaffId) <- profileActionSpan "timesheets.fetch_week_data" (fetchTimesheetDataForWeek weekStartDate weekEndDate showApproved showAllStaff staffFilterId)
    shiftTypes <- profileActionSpan "timesheets.fetch_shift_types" fetchShiftTypesForForm
    today <- utctDay <$> getCurrentTime
    let editWindowDays = venueConfig.staffTimesheetEditWindowDays

    pure
        TimesheetWeekProjection
            { timesheetEntries = entries
            , timesheetStaffMembers = staffMembers
            , timesheetShiftTypes = shiftTypes
            , timesheetToday = today
            , timesheetEditWindowDays = editWindowDays
            , timesheetWeekOffset = weekOffset
            , timesheetWeekStartDate = weekStartDate
            , timesheetWeekEndDate = weekEndDate
            , timesheetShowApproved = showApproved
            , timesheetShowAllStaff = showAllStaff
            , timesheetStaffFilterId = validStaffFilterId
            , timesheetCurrentViewerStaffId = currentViewerStaffId
            }

fetchTimesheetWeekProjectionCached :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetProjectionRequest -> IO TimesheetWeekProjection
fetchTimesheetWeekProjectionCached requestKey =
    profileActionSpan "timesheets.projection.load" (fetchTimesheetWeekProjection requestKey)

renderTimesheetProjectionFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetProjectionRequest -> TimesheetProjectionFragment -> IO (Maybe Blaze.Html)
renderTimesheetProjectionFragment requestKey fragment =
    profileActionSpan "timesheets.projection.render_fragment" do
        projection <- fetchTimesheetWeekProjectionCached requestKey
        pure (renderTimesheetWeekProjectionFragment projection fragment)

renderTimesheetWeekProjectionFragment :: (?context :: ControllerContext, ?request :: Request) => TimesheetWeekProjection -> TimesheetProjectionFragment -> Maybe Blaze.Html
renderTimesheetWeekProjectionFragment =
    renderTimesheetProjectionFragmentFromProjection TimesheetFragmentPlain

renderTimesheetProjectionFragmentFromProjection :: (?context :: ControllerContext, ?request :: Request) => TimesheetFragmentRenderMode -> TimesheetWeekProjection -> TimesheetProjectionFragment -> Maybe Blaze.Html
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
            TimesheetFragmentPlain        -> renderTimesheetWeekToolbar
            TimesheetFragmentOob swapAttr -> renderTimesheetWeekToolbarWithSwap swapAttr
        columnsRenderer = case renderMode of
            TimesheetFragmentPlain        -> renderTimesheetDayColumns
            TimesheetFragmentOob swapAttr -> renderTimesheetDayColumnsWithSwap swapAttr
        dayRenderer = case renderMode of
            TimesheetFragmentPlain        -> renderDaySection
            TimesheetFragmentOob swapAttr -> renderDaySectionWithSwap swapAttr

timesheetDayRenderModelFromProjection :: TimesheetWeekProjection -> Int -> TimesheetDayRenderModel
timesheetDayRenderModelFromProjection projection dayOffset =
    TimesheetDayRenderModel
        { dayEntries = projection.timesheetEntries
        , dayStaffMembers = projection.timesheetStaffMembers
        , dayShiftTypes = projection.timesheetShiftTypes
        , dayToday = projection.timesheetToday
        , dayEditWindowDays = projection.timesheetEditWindowDays
        , dayWeekOffset = projection.timesheetWeekOffset
        , dayWeekStartDate = projection.timesheetWeekStartDate
        , dayShowApproved = projection.timesheetShowApproved
        , dayShowAllStaff = projection.timesheetShowAllStaff
        , dayStaffFilterId = projection.timesheetStaffFilterId
        , dayOffset
        }

timesheetIndexView :: (?context :: ControllerContext) => TimesheetWeekProjection -> IndexView
timesheetIndexView TimesheetWeekProjection { timesheetEntries, timesheetStaffMembers, timesheetShiftTypes, timesheetToday, timesheetEditWindowDays, timesheetWeekOffset, timesheetWeekStartDate, timesheetWeekEndDate, timesheetShowApproved, timesheetShowAllStaff, timesheetStaffFilterId, timesheetCurrentViewerStaffId } =
    IndexView
        { entries = timesheetEntries
        , staffMembers = timesheetStaffMembers
        , shiftTypes = timesheetShiftTypes
        , today = timesheetToday
        , editWindowDays = timesheetEditWindowDays
        , weekOffset = timesheetWeekOffset
        , weekStartDate = timesheetWeekStartDate
        , weekEndDate = timesheetWeekEndDate
        , showApproved = timesheetShowApproved
        , showAllStaff = timesheetShowAllStaff
        , selectedStaffFilterId = timesheetStaffFilterId
        , currentViewerStaffId = timesheetCurrentViewerStaffId
        , liveUpdateSurface = Just (timesheetsLegacyLiveSurfaceConfig surfaceImpl scopeValue)
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

timesheetViewFiltersFromRequest :: (?request :: Request) => (Bool, Bool, Maybe UUID.UUID)
timesheetViewFiltersFromRequest =
    ( paramOrDefault @Bool False "showApproved"
    , paramOrDefault @Bool True "showAllStaff"
    , parseUUIDText =<< paramOrNothing @Text "staffFilterId"
    )
