{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.LeaveRequests.ReadModel
    ( LeaveRequestsReadModel (..)
    , LeaveRequestsFragment (..)
    , LeaveRequestsSurface
    , affectedRosterWeekInvalidationTargetsForScopes
    , buildLeaveRequestsContentFragmentRef
    , buildLeaveRequestsScope
    , currentLeaveArchiveOpen
    , currentLeaveArchivePage
    , fetchLeaveRequestsReadModel
    , leaveRequestsIndexView
    , leaveRequestsLiveSurfaceDefinition
    , leaveRequestsLiveSurfaceDefinitionForVenue
    , renderLeaveRequestsFragment
    , renderLeaveRequestsFragmentFromReadModel
    ) where

import Application.Helper.LiveResource (LiveResource (..))
import Application.Helper.LiveSurface
import Application.Helper.LiveUpdate (LiveFragmentKey (..),
                                      LiveUpdateScope (..))
import Application.Helper.Profiling
import Data.Coerce (coerce)
import qualified Data.Set as Set
import Data.Time.Clock (getCurrentTime, utctDay)
import qualified Data.UUID as UUID
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.View.LeaveRequests.Index

data LeaveRequestsReadModel = LeaveRequestsReadModel
    { leaveReadModelRequests             :: [LeaveRequest]
    , leaveReadModelStaffMembers         :: [Staff]
    , leaveReadModelCurrentViewerStaffId :: Maybe UUID.UUID
    , leaveReadModelToday                :: Day
    }

data LeaveRequestsFragment
    = LeaveRequestsContent
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

leaveRequestsLiveSurfaceDefinition :: (?context :: ControllerContext) => TypedLiveSurfaceDefinition LeaveRequestsSurface () LeaveRequestsFragment EmptyInteractionLayer EmptyInteractionSession EmptyInteractionIntent
leaveRequestsLiveSurfaceDefinition =
    leaveRequestsLiveSurfaceDefinitionForVenue (unpackId currentVenueId)

leaveRequestsLiveSurfaceDefinitionForVenue :: UUID.UUID -> TypedLiveSurfaceDefinition LeaveRequestsSurface () LeaveRequestsFragment EmptyInteractionLayer EmptyInteractionSession EmptyInteractionIntent
leaveRequestsLiveSurfaceDefinitionForVenue surfaceVenueId =
    TypedLiveSurfaceDefinition
        { typedSurfaceFeature = "leave-requests"
        , typedSurfaceScope = const (SurfaceScope LeaveRequestsScope { venueId = surfaceVenueId })
        , typedSurfaceScopeFromWire = \case
            LeaveRequestsScope { venueId } | venueId == surfaceVenueId -> Just ()
            _ -> Nothing
        , typedSurfaceDefaultFragments = const [LeaveRequestsContent]
        , typedSurfaceFragmentContract = \() fragment ->
            mkSurfaceFragmentContract
                (leaveRequestsFragmentRef fragment)
                (liveFragmentDependsOn (LeaveRequestsResource surfaceVenueId) [])
        , typedSurfaceDecorateRequestsWithin = const ["#" <> leaveRequestsShellId]
        , typedSurfaceAuthorize = liveSurfaceAuthorizationByRequirement (const (RequireCurrentVenueManager surfaceVenueId))
        , typedSurfaceInteractionSchema = emptyInteractionStaticSchema
        , typedSurfaceInteraction = const emptyInteractionCapability
        }

fetchLeaveRequestsReadModel :: (?modelContext :: ModelContext, ?context :: ControllerContext) => IO LeaveRequestsReadModel
fetchLeaveRequestsReadModel = do
    leaveReadModelStaffMembers <- profileActionSpan "leave.fetch_staff_members" fetchStaffMembersForCurrentVenue
    leaveReadModelRequests <- profileActionSpan "leave.fetch_requests" fetchVisibleLeaveRequests
    leaveReadModelCurrentViewerStaffId <- fmap (fmap (coerce . get #id)) fetchCurrentUserStaff
    leaveReadModelToday <- liftIO (utctDay <$> getCurrentTime)
    pure LeaveRequestsReadModel { .. }

renderLeaveRequestsFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => LeaveRequestsFragment -> IO (Maybe Blaze.Html)
renderLeaveRequestsFragment fragment =
    profileActionSpan "leave.read_model.render_fragment" do
        readModel <- fetchLeaveRequestsReadModel
        pure (renderLeaveRequestsFragmentFromReadModel FragmentPlain readModel fragment)

renderLeaveRequestsFragmentFromReadModel :: (?context :: ControllerContext, ?request :: Request) => FragmentRenderMode -> LeaveRequestsReadModel -> LeaveRequestsFragment -> Maybe Blaze.Html
renderLeaveRequestsFragmentFromReadModel renderMode readModel LeaveRequestsContent =
    Just
        (contentRenderer
            readModel.leaveReadModelRequests
            readModel.leaveReadModelStaffMembers
            readModel.leaveReadModelCurrentViewerStaffId
            readModel.leaveReadModelToday
            currentLeaveArchivePage
            currentLeaveArchiveOpen
        )
    where
        contentRenderer = case renderMode of
            FragmentPlain        -> renderLeaveRequestsContentFragment
            FragmentOob swapAttr -> renderLeaveRequestsContentFragmentWithSwap swapAttr

leaveRequestsIndexView :: (?context :: ControllerContext, ?request :: Request) => LeaveRequestsReadModel -> IndexView
leaveRequestsIndexView LeaveRequestsReadModel { leaveReadModelRequests, leaveReadModelStaffMembers, leaveReadModelCurrentViewerStaffId, leaveReadModelToday } =
    IndexView
        { leaveRequests = leaveReadModelRequests
        , staffMembers = leaveReadModelStaffMembers
        , currentViewerStaffId = leaveReadModelCurrentViewerStaffId
        , today = leaveReadModelToday
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

leaveRequestsFragmentRef :: LeaveRequestsFragment -> SurfaceFragmentRef LeaveRequestsSurface
leaveRequestsFragmentRef LeaveRequestsContent =
    buildLeaveRequestsContentFragmentRef

buildLeaveRequestsContentFragmentRef :: SurfaceFragmentRef LeaveRequestsSurface
buildLeaveRequestsContentFragmentRef =
    mkSurfaceFragmentRef
        LeaveRequestsContentFragment
        leaveRequestsContentFragmentId
        (pathTo ShowLeaveRequestsContentFragmentAction)
