{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.Timesheets.Projection
    ( TimesheetProjectionFragment (..)
    , TimesheetProjectionRequest (..)
    , TimesheetWeekProjection (..)
    , buildTimesheetWeekScope
    , currentTimesheetWeekOffset
    , fetchShiftTypesForForm
    , fetchStaffForForm
    , fetchTimesheetWeekProjection
    , fetchTimesheetWeekProjectionCached
    , renderTimesheetProjectionFragment
    , renderTimesheetWeekProjectionFragment
    , timesheetDayOffset
    , timesheetDayRenderModelFromProjection
    , timesheetDaySectionFragment
    , timesheetDaySectionFragments
    , timesheetDaySectionFragmentRef
    , timesheetIndexView
    , timesheetLiveSurfaceDefinition
    , timesheetLiveSurfaceDefinitionForVenue
    , timesheetProjectionDefinition
    , timesheetViewFiltersFromRequest
    , timesheetWeekPageFragment
    , timesheetWeekPageFragmentRef
    , weekOffsetFromParamOrCurrent
    , weekOffsetFromParamOrEntry
    ) where

import Application.Helper.LiveResource (LiveResource (..))
import Application.Helper.LiveSurface
import Application.Helper.LiveUpdate (LiveFragmentKey (..),
                                      LiveUpdateScope (..),
                                      currentLiveUpdateVersion)
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
    = TimesheetProjectionPage
    | TimesheetProjectionDaySection !Int
    deriving (Eq, Show)

data TimesheetLiveSurface

fetchTimesheetDataForWeek :: (?modelContext :: ModelContext, ?context :: ControllerContext) => Day -> Day -> Bool -> Bool -> Maybe UUID.UUID -> IO ([TimesheetEntry], [Staff], Maybe UUID.UUID, Maybe UUID.UUID)
fetchTimesheetDataForWeek weekStartDate weekEndDate showApproved showAllStaff requestedStaffFilterId = do
    staffMembers <- query @Staff |> filterWhere (#venueId, unpackId currentVenueId) |> orderByAsc #lastName |> fetch

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

timesheetLiveSurfaceDefinition :: (?context :: ControllerContext) => TypedLiveSurfaceDefinition TimesheetLiveSurface TimesheetProjectionRequest TimesheetProjectionFragment
timesheetLiveSurfaceDefinition =
    timesheetLiveSurfaceDefinitionForVenue (unpackId currentVenueId)

timesheetLiveSurfaceDefinitionForVenue :: UUID.UUID -> TypedLiveSurfaceDefinition TimesheetLiveSurface TimesheetProjectionRequest TimesheetProjectionFragment
timesheetLiveSurfaceDefinitionForVenue surfaceVenueId =
    TypedLiveSurfaceDefinition
        { typedSurfaceFeature = "timesheets"
        , typedSurfaceScope = timesheetSurfaceScope
        , typedSurfaceScopeFromWire = timesheetSurfaceScopeFromWire
        , typedSurfaceDefaultFragments = const (timesheetDaySectionFragments [0 .. 6])
        , typedSurfaceFragmentContract = \requestKey fragment ->
            mkSurfaceFragmentContract
                (timesheetFragmentRef requestKey fragment)
                (timesheetFragmentDependencies surfaceVenueId requestKey fragment)
        , typedSurfaceDecorateRequestsWithin = const ["#" <> timesheetWeekShellId, "#roster-staff-self-service-timesheet-live-surface"]
        , typedSurfaceAuthorize = liveSurfaceAuthorizationByRequirement (const (RequireCurrentVenue surfaceVenueId))
        }
    where
        timesheetSurfaceScope requestKey =
            SurfaceScope TimesheetWeekScope { venueId = surfaceVenueId, weekOffset = requestKey.projectionWeekOffset }

        timesheetSurfaceScopeFromWire scope =
            case scope of
                TimesheetWeekScope { venueId, weekOffset } | venueId == surfaceVenueId ->
                    -- The wire scope carries only the venue/week identity used for
                    -- authorization and fan-out. Mounted day-section targets render
                    -- data-live-update-url with the active query filters, and the
                    -- browser live-update runtime prefers that URL when refetching.
                    Just (TimesheetProjectionRequest weekOffset True True Nothing)
                _ ->
                    Nothing

timesheetProjectionDefinition :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => ProjectionLiveSurfaceDefinition TimesheetLiveSurface TimesheetProjectionRequest TimesheetWeekProjection TimesheetProjectionFragment
timesheetProjectionDefinition =
    mkTypedSurfaceProjectionDefinition
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
                , maybe "all" tshow requestKey.projectionStaffFilterId
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
        , liveUpdateSurface = Just (mkTypedDefinedLiveSurface timesheetLiveSurfaceDefinition (TimesheetProjectionRequest timesheetWeekOffset timesheetShowApproved timesheetShowAllStaff timesheetStaffFilterId))
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

timesheetWeekPageFragment :: TimesheetProjectionFragment
timesheetWeekPageFragment =
    TimesheetProjectionPage

timesheetDaySectionFragment :: Int -> TimesheetProjectionFragment
timesheetDaySectionFragment =
    TimesheetProjectionDaySection

timesheetDaySectionFragments :: [Int] -> [TimesheetProjectionFragment]
timesheetDaySectionFragments =
    map timesheetDaySectionFragment . nub

timesheetFragmentRef :: TimesheetProjectionRequest -> TimesheetProjectionFragment -> SurfaceFragmentRef TimesheetLiveSurface
timesheetFragmentRef requestKey TimesheetProjectionPage =
    timesheetWeekPageFragmentRef requestKey
timesheetFragmentRef requestKey (TimesheetProjectionDaySection dayOffset) =
    timesheetDaySectionFragmentRef requestKey dayOffset

timesheetFragmentDependencies :: UUID.UUID -> TimesheetProjectionRequest -> TimesheetProjectionFragment -> FragmentDependencies
timesheetFragmentDependencies surfaceVenueId requestKey TimesheetProjectionPage =
    liveFragmentDependsOn
        (TimesheetWeekResource surfaceVenueId requestKey.projectionWeekOffset)
        [TimesheetWeekBoundaryConfigResource surfaceVenueId]
timesheetFragmentDependencies surfaceVenueId requestKey (TimesheetProjectionDaySection dayOffset) =
    liveFragmentDependsOn
        (TimesheetWeekResource surfaceVenueId requestKey.projectionWeekOffset)
        [ TimesheetDayResource surfaceVenueId requestKey.projectionWeekOffset dayOffset
        , TimesheetWeekBoundaryConfigResource surfaceVenueId
        ]

timesheetDaySectionFragmentRef :: TimesheetProjectionRequest -> Int -> SurfaceFragmentRef TimesheetLiveSurface
timesheetDaySectionFragmentRef requestKey dayOffset =
    mkSurfaceFragmentRef
        (TimesheetDaySectionFragment { dayOffset })
        (timesheetDaySectionDomId dayOffset)
        ( appendQueryParams
            (pathTo ShowTimesheetDaySectionFragmentAction { weekOffset = requestKey.projectionWeekOffset, dayOffset })
            [ ("showApproved", if requestKey.projectionShowApproved then "true" else "false")
            , ("showAllStaff", if requestKey.projectionShowAllStaff then "true" else "false")
            , ("staffFilterId", maybe "" tshow requestKey.projectionStaffFilterId)
            ]
        )

timesheetWeekPageFragmentRef :: TimesheetProjectionRequest -> SurfaceFragmentRef TimesheetLiveSurface
timesheetWeekPageFragmentRef requestKey =
    mkSurfaceFragmentRef
        (TimesheetDaySectionFragment { dayOffset = 0 })
        timesheetWeekShellId
        (timesheetWeekUrl requestKey.projectionWeekOffset requestKey.projectionShowApproved requestKey.projectionShowAllStaff requestKey.projectionStaffFilterId)


timesheetViewFiltersFromRequest :: (?request :: Request) => (Bool, Bool, Maybe UUID.UUID)
timesheetViewFiltersFromRequest =
    ( paramOrDefault @Bool False "showApproved"
    , paramOrDefault @Bool True "showAllStaff"
    , parseUUIDText =<< paramOrNothing @Text "staffFilterId"
    )
