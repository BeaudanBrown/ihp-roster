module Web.LeaveRequests.Projection
    ( LeaveRequestsProjection (..)
    , LeaveRequestsProjectionFragment (..)
    , affectedRosterWeekInvalidationTargetsForScopes
    , buildLeaveRequestsContentFragmentRef
    , buildLeaveRequestsPageFragmentRef
    , buildLeaveRequestsScope
    , broadcastLeaveRequestsInvalidation
    , fetchLeaveRequestsProjection
    , fetchLeaveRequestsProjectionCached
    , invalidateAffectedRosterWeeksForLeave
    , leaveRequestsContentFragmentRefs
    , leaveRequestsIndexView
    , leaveRequestsLiveSurfaceDefinition
    , leaveRequestsProjectionDefinition
    , renderLeaveRequestsProjectionFragment
    , renderLeaveRequestsProjectionHtml
    ) where

import Application.Helper.LiveSurface
import Application.Helper.LiveUpdate (LiveFragmentKey (..),
                                      LiveFragmentRef (..),
                                      LiveUpdateScope (..),
                                      activeRosterWeekScopes,
                                      broadcastLiveInvalidation,
                                      currentLiveUpdateVersion,
                                      liveUpdateSourceClientId,
                                      mkLiveFragmentRef)
import Application.Helper.Profiling
import Application.Helper.SurfaceProjection
import Data.Coerce (coerce)
import qualified Data.Set as Set
import Data.Time.Clock (getCurrentTime, utctDay)
import qualified Data.UUID as UUID
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.LeaveRequests.ProfileSelfService (profileLeaveRequestsContentFragmentRef)
import Web.RosterWeeks.LiveUpdates (broadcastRosterWeekInvalidation)
import Web.RosterWeeks.Projection (buildRosterContentFragmentRef,
                                   buildRosterStaffPanelFragmentRef)
import Web.View.LeaveRequests.Index

data LeaveRequestsProjection = LeaveRequestsProjection
    { leaveProjectionRequests             :: [LeaveRequest]
    , leaveProjectionStaffMembers         :: [Staff]
    , leaveProjectionCurrentViewerStaffId :: Maybe UUID.UUID
    , leaveProjectionToday                :: Day
    }

data LeaveRequestsProjectionFragment
    = LeaveRequestsProjectionPage
    | LeaveRequestsProjectionContent
    deriving (Eq, Show)

fetchStaffMembersForCurrentVenue :: (?modelContext :: ModelContext, ?context :: ControllerContext) => IO [Staff]
fetchStaffMembersForCurrentVenue =
    query @Staff |> filterWhere (#venueId, unpackId currentVenueId) |> orderByAsc #lastName |> fetch

fetchVisibleLeaveRequests :: (?modelContext :: ModelContext, ?context :: ControllerContext) => IO [LeaveRequest]
fetchVisibleLeaveRequests = do
    if hasRole ManagerRole'
        then
            query @LeaveRequest
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhere (#deletedAt, Nothing)
                |> orderByDesc #startDate
                |> fetch
        else do
            maybeStaff <- fetchCurrentUserStaff
            case maybeStaff of
                Nothing -> pure []
                Just staff ->
                    query @LeaveRequest
                        |> filterWhere (#venueId, unpackId currentVenueId)
                        |> filterWhere (#staffId, coerce (get #id staff))
                        |> filterWhere (#deletedAt, Nothing)
                        |> orderByDesc #startDate
                        |> fetch

leaveRequestsLiveSurfaceDefinition :: (?context :: ControllerContext) => LiveSurfaceDefinition () LeaveRequestsProjectionFragment
leaveRequestsLiveSurfaceDefinition =
    LiveSurfaceDefinition
        { surfaceFeature = "leave-requests"
        , surfaceScope = const (buildLeaveRequestsScope currentVenueId)
        , surfaceDefaultFragments = const [LeaveRequestsProjectionContent]
        , surfaceFragmentRef = \() fragment ->
            case fragment of
                LeaveRequestsProjectionPage -> buildLeaveRequestsPageFragmentRef
                LeaveRequestsProjectionContent -> buildLeaveRequestsContentFragmentRef
        , surfaceDecorateRequestsWithin = const ["#" <> leaveRequestsShellId]
        }

leaveRequestsProjectionDefinition :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => ProjectionLiveSurfaceDefinition () LeaveRequestsProjection LeaveRequestsProjectionFragment
leaveRequestsProjectionDefinition =
    mkSurfaceProjectionDefinition
        leaveRequestsLiveSurfaceDefinition
        "leave-requests"
        defaultSurfaceProjectionCachePolicy
        (const (tshow currentVenueId))
        (pure (tshow currentUser.id))
        (const (currentLiveUpdateVersion (buildLeaveRequestsScope currentVenueId)))
        (const fetchLeaveRequestsProjection)
        renderLeaveRequestsProjectionHtml

fetchLeaveRequestsProjectionCached :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO LeaveRequestsProjection
fetchLeaveRequestsProjectionCached =
    profileActionSpanWithDetail "leave.projection.load" do
        before <- readSurfaceProjectionCacheStats
        projection <- loadLiveSurfaceProjection leaveRequestsProjectionDefinition ()
        after <- readSurfaceProjectionCacheStats
        pure (projection, surfaceProjectionCacheDeltaDetail before after)

renderLeaveRequestsProjectionFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => LeaveRequestsProjectionFragment -> IO (Maybe Blaze.Html)
renderLeaveRequestsProjectionFragment fragment =
    profileActionSpanWithDetail "leave.projection.render_fragment" do
        before <- readSurfaceProjectionCacheStats
        html <- renderLiveSurfaceProjectionFragment leaveRequestsProjectionDefinition () fragment
        after <- readSurfaceProjectionCacheStats
        pure (html, surfaceProjectionCacheDeltaDetail before after)

fetchLeaveRequestsProjection :: (?modelContext :: ModelContext, ?context :: ControllerContext) => IO LeaveRequestsProjection
fetchLeaveRequestsProjection = do
    leaveProjectionStaffMembers <- profileActionSpan "leave.fetch_staff_members" fetchStaffMembersForCurrentVenue
    leaveProjectionRequests <- profileActionSpan "leave.fetch_requests" fetchVisibleLeaveRequests
    leaveProjectionCurrentViewerStaffId <- fmap (fmap (coerce . get #id)) fetchCurrentUserStaff
    leaveProjectionToday <- liftIO (utctDay <$> getCurrentTime)
    pure LeaveRequestsProjection { .. }

renderLeaveRequestsProjectionHtml :: (?context :: ControllerContext, ?request :: Request) => LeaveRequestsProjection -> LeaveRequestsProjectionFragment -> Maybe Blaze.Html
renderLeaveRequestsProjectionHtml projection fragment =
    case fragment of
        LeaveRequestsProjectionPage ->
            Just (renderLeaveRequestsShell (leaveRequestsIndexView projection))
        LeaveRequestsProjectionContent ->
            Just
                (renderLeaveRequestsContentFragment
                    projection.leaveProjectionRequests
                    projection.leaveProjectionStaffMembers
                    projection.leaveProjectionCurrentViewerStaffId
                    projection.leaveProjectionToday
                )

leaveRequestsIndexView :: (?context :: ControllerContext) => LeaveRequestsProjection -> IndexView
leaveRequestsIndexView LeaveRequestsProjection { leaveProjectionRequests, leaveProjectionStaffMembers, leaveProjectionCurrentViewerStaffId, leaveProjectionToday } =
    IndexView
        { leaveRequests = leaveProjectionRequests
        , staffMembers = leaveProjectionStaffMembers
        , currentViewerStaffId = leaveProjectionCurrentViewerStaffId
        , today = leaveProjectionToday
        , liveUpdateSurface = Just (mkDefinedLiveSurface leaveRequestsLiveSurfaceDefinition ())
        }

invalidateAffectedRosterWeeksForLeave :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => LeaveRequest -> IO ()
invalidateAffectedRosterWeeksForLeave leaveRequest = do
    venueConfig <- fetchVenueConfig
    activeScopes <- activeRosterWeekScopes
    forM_ (affectedRosterWeekInvalidationTargetsForScopes currentVenueId venueConfig leaveRequest activeScopes) \(rosterGroupId, weekOffset) ->
        broadcastRosterWeekInvalidation
            rosterGroupId
            weekOffset
            [ buildRosterContentFragmentRef rosterGroupId weekOffset
            , buildRosterStaffPanelFragmentRef rosterGroupId weekOffset
            ]

affectedRosterWeekInvalidationTargetsForScopes ::
    Id Venue ->
    VenueConfig ->
    LeaveRequest ->
    [(UUID.UUID, UUID.UUID, Int)] ->
    [(Id RosterGroup, Int)]
affectedRosterWeekInvalidationTargetsForScopes venueId venueConfig leaveRequest activeScopes =
    Set.toList $
        Set.fromList
            [ (Id rosterGroupUuid, weekOffset)
            | (activeVenueUuid, rosterGroupUuid, weekOffset) <- activeScopes
            , activeVenueUuid == unpackId venueId
            , weekOffset `Set.member` affectedOffsets
            ]
    where
        affectedOffsets =
            Set.fromList $
                affectedVenueWeekOffsetsForDateRange
                    venueConfig
                    leaveRequest.startDate
                    leaveRequest.endDate

buildLeaveRequestsScope :: Id Venue -> LiveUpdateScope
buildLeaveRequestsScope venueId =
    LeaveRequestsScope
        { venueId = unpackId venueId
        }

buildLeaveRequestsContentFragmentRef :: (?context :: ControllerContext) => LiveFragmentRef
buildLeaveRequestsContentFragmentRef =
    mkLiveFragmentRef
        LeaveRequestsContentFragment
        leaveRequestsContentFragmentId
        (pathTo ShowLeaveRequestsContentFragmentAction)

leaveRequestsContentFragmentRefs :: (?context :: ControllerContext) => [LiveFragmentRef]
leaveRequestsContentFragmentRefs =
    [ buildLeaveRequestsContentFragmentRef
    , profileLeaveRequestsContentFragmentRef
    ]

buildLeaveRequestsPageFragmentRef :: (?context :: ControllerContext) => LiveFragmentRef
buildLeaveRequestsPageFragmentRef =
    mkLiveFragmentRef
        LeaveRequestsContentFragment
        leaveRequestsShellId
        (pathTo LeaveRequestsAction)

broadcastLeaveRequestsInvalidation ::
    (?context :: ControllerContext, ?request :: Request) =>
    [LiveFragmentRef] ->
    IO ()
broadcastLeaveRequestsInvalidation fragments =
    unless (null fragments) do
        liftIO $
            broadcastLiveInvalidation
                (buildLeaveRequestsScope currentVenueId)
                liveUpdateSourceClientId
                fragments
