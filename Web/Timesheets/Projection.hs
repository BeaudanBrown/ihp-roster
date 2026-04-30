module Web.Timesheets.Projection
    ( TimesheetProjectionFragment (..)
    , TimesheetProjectionRequest (..)
    , TimesheetWeekProjection (..)
    , buildTimesheetDaySectionFragmentRef
    , buildTimesheetWeekPageFragmentRef
    , buildTimesheetWeekScope
    , broadcastTimesheetDayInvalidation
    , broadcastTimesheetEntryMoveInvalidation
    , currentTimesheetWeekOffset
    , fetchShiftTypesForForm
    , fetchStaffForForm
    , fetchTimesheetWeekProjection
    , fetchTimesheetWeekProjectionCached
    , renderTimesheetProjectionFragment
    , renderTimesheetWeekProjectionFragment
    , timesheetDayOffset
    , timesheetDayRenderModelFromProjection
    , timesheetIndexView
    , timesheetLiveSurfaceDefinition
    , timesheetProjectionDefinition
    , timesheetViewFiltersFromRequest
    , weekOffsetFromParamOrCurrent
    , weekOffsetFromParamOrEntry
    ) where

import Application.Helper.LiveSurface
import Application.Helper.LiveUpdate (LiveFragmentKey (..),
                                      LiveFragmentRef (..),
                                      LiveUpdateScope (..),
                                      broadcastLiveInvalidation,
                                      currentLiveUpdateVersion,
                                      liveUpdateSourceClientId,
                                      mkLiveFragmentRef)
import Application.Helper.Profiling
import Application.Helper.SurfaceProjection
import Application.Helper.Url (appendQueryParams)
import qualified Data.Text as Text
import Data.Time.Calendar (Day, addDays, diffDays)
import Data.Time.Clock (getCurrentTime, utctDay)
import qualified Data.UUID as UUID
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.Timesheets.Paths (timesheetWeekUrl)
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
    , timesheetCurrentViewerStaffId :: Maybe UUID.UUID
    }

data TimesheetProjectionRequest = TimesheetProjectionRequest
    { projectionWeekOffset   :: !Int
    , projectionShowApproved :: !Bool
    , projectionShowAllStaff :: !Bool
    }
    deriving (Eq, Show)

data TimesheetProjectionFragment
    = TimesheetProjectionPage
    | TimesheetProjectionDaySection !Int
    deriving (Eq, Show)

fetchTimesheetDataForWeek :: (?modelContext :: ModelContext, ?context :: ControllerContext) => Day -> Day -> Bool -> Bool -> IO ([TimesheetEntry], [Staff], Maybe UUID.UUID)
fetchTimesheetDataForWeek weekStartDate weekEndDate showApproved showAllStaff = do
    staffMembers <- query @Staff |> filterWhere (#venueId, unpackId currentVenueId) |> orderByAsc #lastName |> fetch

    let weekDays = [weekStartDate .. weekEndDate]
    maybeCurrentViewerStaff <- fetchCurrentUserStaff

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
                case (showAllStaff, maybeCurrentViewerStaff) of
                    (False, Just staff) ->
                        applyApprovedFilter
                            (baseQuery |> filterWhere (#staffId, unpackId (get #id staff)))
                            |> orderByAsc #workedOn
                            |> orderByAsc #isApproved
                            |> orderByAsc #startTime
                            |> fetch
                    (False, Nothing) ->
                        pure []
                    (True, _) ->
                        applyApprovedFilter baseQuery
                            |> orderByAsc #workedOn
                            |> orderByAsc #isApproved
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
                                |> orderByAsc #isApproved
                                |> orderByAsc #startTime
                                |> fetch

    pure (entries, staffMembers, unpackId . get #id <$> maybeCurrentViewerStaff)

fetchStaffForForm :: (?modelContext :: ModelContext, ?context :: ControllerContext) => IO [Staff]
fetchStaffForForm =
    if hasRole ManagerRole'
        then query @Staff |> filterWhere (#venueId, unpackId currentVenueId) |> filterWhere (#isActive, True) |> orderByAsc #lastName |> fetch
        else maybeToList <$> fetchCurrentUserStaff

fetchShiftTypesForForm :: (?modelContext :: ModelContext, ?context :: ControllerContext) => IO [ShiftType]
fetchShiftTypesForForm =
    query @ShiftType
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#isActive, True)
        |> orderByAsc #createdAt
        |> fetch

fetchTimesheetWeekProjection :: (?context :: ControllerContext, ?modelContext :: ModelContext) => TimesheetProjectionRequest -> IO TimesheetWeekProjection
fetchTimesheetWeekProjection TimesheetProjectionRequest { projectionWeekOffset = weekOffset, projectionShowApproved = showApproved, projectionShowAllStaff = showAllStaff } = do
    venueConfig <- fetchVenueConfig
    let weekStartDate = venueWeekStartDate venueConfig weekOffset
    let weekEndDate = addDays 6 weekStartDate

    (entries, staffMembers, currentViewerStaffId) <- profileActionSpan "timesheets.fetch_week_data" (fetchTimesheetDataForWeek weekStartDate weekEndDate showApproved showAllStaff)
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
            , timesheetCurrentViewerStaffId = currentViewerStaffId
            }

timesheetLiveSurfaceDefinition :: (?context :: ControllerContext) => LiveSurfaceDefinition TimesheetProjectionRequest TimesheetProjectionFragment
timesheetLiveSurfaceDefinition =
    LiveSurfaceDefinition
        { surfaceFeature = "timesheets"
        , surfaceScope = \requestKey -> buildTimesheetWeekScope currentVenueId requestKey.projectionWeekOffset
        , surfaceDefaultFragments = const (map TimesheetProjectionDaySection [0 .. 6])
        , surfaceFragmentRef = \requestKey fragment ->
            case fragment of
                TimesheetProjectionPage ->
                    buildTimesheetWeekPageFragmentRef requestKey
                TimesheetProjectionDaySection dayOffset ->
                    buildTimesheetDaySectionFragmentRef requestKey dayOffset
        , surfaceDecorateRequestsWithin = const ["#" <> timesheetWeekShellId]
        }

timesheetProjectionDefinition :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => ProjectionLiveSurfaceDefinition TimesheetProjectionRequest TimesheetWeekProjection TimesheetProjectionFragment
timesheetProjectionDefinition =
    mkSurfaceProjectionDefinition
        timesheetLiveSurfaceDefinition
        "timesheet-week"
        defaultSurfaceProjectionCachePolicy
        (\requestKey ->
            Text.intercalate
                ":"
                [ tshow currentVenueId
                , tshow requestKey.projectionWeekOffset
                , if requestKey.projectionShowApproved then "true" else "false"
                , if requestKey.projectionShowAllStaff then "true" else "false"
                ])
        (pure (tshow currentUser.id))
        (\requestKey -> currentLiveUpdateVersion (buildTimesheetWeekScope currentVenueId requestKey.projectionWeekOffset))
        fetchTimesheetWeekProjection
        renderTimesheetWeekProjectionFragment

fetchTimesheetWeekProjectionCached :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetProjectionRequest -> IO TimesheetWeekProjection
fetchTimesheetWeekProjectionCached requestKey =
    profileActionSpanWithDetail "timesheets.projection.load" do
        before <- readSurfaceProjectionCacheStats
        projection <- loadLiveSurfaceProjection timesheetProjectionDefinition requestKey
        after <- readSurfaceProjectionCacheStats
        pure (projection, surfaceProjectionCacheDeltaDetail before after)

renderTimesheetProjectionFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetProjectionRequest -> TimesheetProjectionFragment -> IO (Maybe Blaze.Html)
renderTimesheetProjectionFragment requestKey fragment =
    profileActionSpanWithDetail "timesheets.projection.render_fragment" do
        before <- readSurfaceProjectionCacheStats
        html <- renderLiveSurfaceProjectionFragment timesheetProjectionDefinition requestKey fragment
        after <- readSurfaceProjectionCacheStats
        pure (html, surfaceProjectionCacheDeltaDetail before after)

renderTimesheetWeekProjectionFragment :: (?context :: ControllerContext, ?request :: Request) => TimesheetWeekProjection -> TimesheetProjectionFragment -> Maybe Blaze.Html
renderTimesheetWeekProjectionFragment projection fragment =
    case fragment of
        TimesheetProjectionPage ->
            Just (renderTimesheetWeekShell (timesheetIndexView projection))
        TimesheetProjectionDaySection dayOffset ->
            Just (renderDaySection (timesheetDayRenderModelFromProjection projection dayOffset))

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
        , dayOffset
        }

timesheetIndexView :: (?context :: ControllerContext) => TimesheetWeekProjection -> IndexView
timesheetIndexView TimesheetWeekProjection { timesheetEntries, timesheetStaffMembers, timesheetShiftTypes, timesheetToday, timesheetEditWindowDays, timesheetWeekOffset, timesheetWeekStartDate, timesheetWeekEndDate, timesheetShowApproved, timesheetShowAllStaff, timesheetCurrentViewerStaffId } =
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
        , currentViewerStaffId = timesheetCurrentViewerStaffId
        , liveUpdateSurface = Just (mkDefinedLiveSurface timesheetLiveSurfaceDefinition (TimesheetProjectionRequest timesheetWeekOffset timesheetShowApproved timesheetShowAllStaff))
        }

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

buildTimesheetWeekScope :: Id Venue -> Int -> LiveUpdateScope
buildTimesheetWeekScope venueId weekOffset =
    TimesheetWeekScope
        { venueId = unpackId venueId
        , weekOffset
        }

buildTimesheetDaySectionFragmentRef :: (?context :: ControllerContext) => TimesheetProjectionRequest -> Int -> LiveFragmentRef
buildTimesheetDaySectionFragmentRef requestKey dayOffset =
    mkLiveFragmentRef
        (TimesheetDaySectionFragment { dayOffset })
        (timesheetDaySectionDomId dayOffset)
        ( appendQueryParams
            (pathTo ShowTimesheetDaySectionFragmentAction { weekOffset = requestKey.projectionWeekOffset, dayOffset })
            [ ("showApproved", if requestKey.projectionShowApproved then "true" else "false")
            , ("showAllStaff", if requestKey.projectionShowAllStaff then "true" else "false")
            ]
        )

buildTimesheetWeekPageFragmentRef :: (?context :: ControllerContext) => TimesheetProjectionRequest -> LiveFragmentRef
buildTimesheetWeekPageFragmentRef requestKey =
    mkLiveFragmentRef
        (TimesheetDaySectionFragment { dayOffset = 0 })
        timesheetWeekShellId
        (timesheetWeekUrl requestKey.projectionWeekOffset requestKey.projectionShowApproved requestKey.projectionShowAllStaff)

broadcastTimesheetDayInvalidation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> Day -> IO ()
broadcastTimesheetDayInvalidation weekOffset workedOn = do
    venueConfig <- fetchVenueConfig
    let weekStartDate = venueWeekStartDate venueConfig weekOffset
    let dayOffset = timesheetDayOffset weekStartDate workedOn
    liftIO $
        broadcastLiveInvalidation
            (buildTimesheetWeekScope currentVenueId weekOffset)
            liveUpdateSourceClientId
            [buildTimesheetDaySectionFragmentRef (TimesheetProjectionRequest weekOffset True True) dayOffset]

broadcastTimesheetEntryMoveInvalidation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Day -> Day -> IO ()
broadcastTimesheetEntryMoveInvalidation oldWorkedOn newWorkedOn = do
    venueConfig <- fetchVenueConfig
    let invalidationTargets =
            nub
                [ (weekOffset, timesheetDayOffset (venueWeekStartDate venueConfig weekOffset) workedOn)
                | workedOn <- [oldWorkedOn, newWorkedOn]
                , let weekOffset = venueWeekOffsetForDay venueConfig workedOn
                ]
    forM_ invalidationTargets \(targetWeekOffset, dayOffset) ->
        liftIO $
            broadcastLiveInvalidation
                (buildTimesheetWeekScope currentVenueId targetWeekOffset)
                liveUpdateSourceClientId
                [buildTimesheetDaySectionFragmentRef (TimesheetProjectionRequest targetWeekOffset True True) dayOffset]

timesheetViewFiltersFromRequest :: (?request :: Request) => (Bool, Bool)
timesheetViewFiltersFromRequest =
    ( paramOrDefault @Bool False "showApproved"
    , paramOrDefault @Bool True "showAllStaff"
    )
