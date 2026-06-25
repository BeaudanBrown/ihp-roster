{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.LeaveRequests.Projection
    ( LeaveRequestsProjection (..)
    , LeaveRequestsProjectionFragment (..)
    , affectedRosterWeekInvalidationTargetsForScopes
    , buildLeaveRequestsContentFragmentRef
    , buildLeaveRequestsPageFragmentRef
    , buildLeaveRequestsScope
    , currentLeaveArchiveOpen
    , currentLeaveArchivePage
    , fetchLeaveRequestsProjection
    , fetchLeaveRequestsProjectionCached
    , leaveRequestsIndexView
    , leaveRequestsLiveSurfaceDefinition
    , leaveRequestsProjectionDefinition
    , renderLeaveRequestsProjectionFragment
    , renderLeaveRequestsProjectionHtml
    ) where

import Application.Helper.LiveResource (LiveResource (..))
import Application.Helper.LiveSurface
import Application.Helper.LiveUpdate (LiveFragmentKey (..),
                                      LiveUpdateScope (..),
                                      currentLiveUpdateVersion)
import Application.Helper.Profiling
import Application.Helper.SurfaceProjection
import Data.Coerce (coerce)
import qualified Data.Set as Set
import Data.Time.Clock (getCurrentTime, utctDay)
import qualified Data.UUID as UUID
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
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

data LeaveRequestsSurface

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

leaveRequestsLiveSurfaceDefinition :: (?context :: ControllerContext) => TypedLiveSurfaceDefinition LeaveRequestsSurface () LeaveRequestsProjectionFragment EmptyInteractionLayer EmptyInteractionSession EmptyInteractionIntent
leaveRequestsLiveSurfaceDefinition =
    TypedLiveSurfaceDefinition
        { typedSurfaceFeature = "leave-requests"
        , typedSurfaceScope = const (SurfaceScope (buildLeaveRequestsScope currentVenueId))
        , typedSurfaceScopeFromWire = \case
            LeaveRequestsScope { venueId } | venueId == unpackId currentVenueId -> Just ()
            _ -> Nothing
        , typedSurfaceDefaultFragments = const [LeaveRequestsProjectionContent]
        , typedSurfaceFragmentContract = \() fragment ->
            mkSurfaceFragmentContract
                (leaveRequestsFragmentRef fragment)
                (liveFragmentDependsOn (LeaveRequestsResource (unpackId currentVenueId)) [])
        , typedSurfaceDecorateRequestsWithin = const ["#" <> leaveRequestsShellId]
        , typedSurfaceAuthorize = liveSurfaceAuthorizationByRequirement (const (RequireCurrentVenueManager (unpackId currentVenueId)))
        , typedSurfaceInteractionSchema = emptyInteractionStaticSchema
        , typedSurfaceInteraction = const emptyInteractionCapability
        }

leaveRequestsProjectionDefinition :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => ProjectionLiveSurfaceDefinition LeaveRequestsSurface () LeaveRequestsProjection LeaveRequestsProjectionFragment
leaveRequestsProjectionDefinition =
    mkTypedSurfaceProjectionDefinition
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
                    currentLeaveArchivePage
                    currentLeaveArchiveOpen
                )

leaveRequestsIndexView :: (?context :: ControllerContext, ?request :: Request) => LeaveRequestsProjection -> IndexView
leaveRequestsIndexView LeaveRequestsProjection { leaveProjectionRequests, leaveProjectionStaffMembers, leaveProjectionCurrentViewerStaffId, leaveProjectionToday } =
    IndexView
        { leaveRequests = leaveProjectionRequests
        , staffMembers = leaveProjectionStaffMembers
        , currentViewerStaffId = leaveProjectionCurrentViewerStaffId
        , today = leaveProjectionToday
        , archivePage = currentLeaveArchivePage
        , archiveIsOpen = currentLeaveArchiveOpen
        , liveUpdateSurface = Just (mkTypedDefinedLiveSurface leaveRequestsLiveSurfaceDefinition ())
        }

currentLeaveArchivePage :: (?request :: Request) => Int
currentLeaveArchivePage =
    fromMaybe 1 (paramOrNothing @Int "archivePage")

currentLeaveArchiveOpen :: (?request :: Request) => Bool
currentLeaveArchiveOpen =
    paramOrDefault @Text "" "openSection" == "archive"

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

leaveRequestsFragmentRef :: (?context :: ControllerContext) => LeaveRequestsProjectionFragment -> SurfaceFragmentRef LeaveRequestsSurface
leaveRequestsFragmentRef LeaveRequestsProjectionPage =
    buildLeaveRequestsPageFragmentRef
leaveRequestsFragmentRef LeaveRequestsProjectionContent =
    buildLeaveRequestsContentFragmentRef

buildLeaveRequestsContentFragmentRef :: (?context :: ControllerContext) => SurfaceFragmentRef LeaveRequestsSurface
buildLeaveRequestsContentFragmentRef =
    mkSurfaceFragmentRef
        LeaveRequestsContentFragment
        leaveRequestsContentFragmentId
        (pathTo ShowLeaveRequestsContentFragmentAction)

buildLeaveRequestsPageFragmentRef :: (?context :: ControllerContext) => SurfaceFragmentRef LeaveRequestsSurface
buildLeaveRequestsPageFragmentRef =
    mkSurfaceFragmentRef
        LeaveRequestsContentFragment
        leaveRequestsShellId
        (pathTo LeaveRequestsAction)

