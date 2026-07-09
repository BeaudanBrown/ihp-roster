{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.LeaveRequests.ReadModel
    ( LeaveRequestsReadModel (..)
    , LeaveRequestsFragment (..)
    , LeaveRequestsFragmentRenderMode (..)
    , affectedRosterWeekInvalidationTargetsForScopes
    , buildLeaveRequestsScope
    , currentLeaveArchiveOpen
    , currentLeaveArchivePage
    , fetchLeaveRequestsReadModel
    , leaveRequestsIndexView
    , renderLeaveRequestsFragment
    , renderLeaveRequestsFragmentFromReadModel
    ) where

import qualified Application.Helper.FrontendContract.Surface.LeaveRequests as Surface
import Application.Helper.FrontendContract.Surface.Runtime (SurfaceImpl)
import Application.Helper.LiveUpdate
import Application.Helper.Profiling
import Application.Helper.View.Oob (OobSwapAttr)
import Data.Coerce (coerce)
import qualified Data.Set as Set
import Data.Time.Clock (getCurrentTime, utctDay)
import qualified Data.UUID as UUID
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.LeaveRequests.FrontendSurface (LeaveRequestsScopeValue (..),
                                          leaveRequestsSurfaceImpl)
import Web.View.LeaveRequests.Index

data LeaveRequestsReadModel = LeaveRequestsReadModel
    { leaveReadModelRequests             :: [LeaveRequest]
    , leaveReadModelStaffMembers         :: [Staff]
    , leaveReadModelCurrentViewerStaffId :: Maybe UUID.UUID
    , leaveReadModelToday                :: Day
    }

data LeaveRequestsFragment
    = LeaveRequestsContent
    | LeavePendingCount
    | LeavePendingList
    | LeaveApprovedCount
    | LeaveApprovedList
    | LeaveDeniedCount
    | LeaveDeniedList
    | LeaveArchiveCount
    | LeaveArchiveList
    deriving (Eq, Show)

data LeaveRequestsFragmentRenderMode
    = LeaveRequestsFragmentPlain
    | LeaveRequestsFragmentOob !OobSwapAttr

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
        pure (renderLeaveRequestsFragmentFromReadModel LeaveRequestsFragmentPlain readModel fragment)

renderLeaveRequestsFragmentFromReadModel :: (?context :: ControllerContext, ?request :: Request) => LeaveRequestsFragmentRenderMode -> LeaveRequestsReadModel -> LeaveRequestsFragment -> Maybe Blaze.Html
renderLeaveRequestsFragmentFromReadModel renderMode readModel fragment =
    Just $ case fragment of
        LeaveRequestsContent ->
            contentRenderer
                readModel.leaveReadModelRequests
                readModel.leaveReadModelStaffMembers
                readModel.leaveReadModelCurrentViewerStaffId
                readModel.leaveReadModelToday
                currentLeaveArchivePage
                currentLeaveArchiveOpen
        LeavePendingCount ->
            renderPendingCountLiveFragment readModel.leaveReadModelRequests readModel.leaveReadModelToday
        LeavePendingList ->
            renderPendingListLiveFragment readModel.leaveReadModelRequests readModel.leaveReadModelStaffMembers readModel.leaveReadModelCurrentViewerStaffId readModel.leaveReadModelToday
        LeaveApprovedCount ->
            renderApprovedCountLiveFragment readModel.leaveReadModelRequests readModel.leaveReadModelToday
        LeaveApprovedList ->
            renderApprovedListLiveFragment readModel.leaveReadModelRequests readModel.leaveReadModelStaffMembers readModel.leaveReadModelCurrentViewerStaffId readModel.leaveReadModelToday
        LeaveDeniedCount ->
            renderDeniedCountLiveFragment readModel.leaveReadModelRequests readModel.leaveReadModelToday
        LeaveDeniedList ->
            renderDeniedListLiveFragment readModel.leaveReadModelRequests readModel.leaveReadModelStaffMembers readModel.leaveReadModelCurrentViewerStaffId readModel.leaveReadModelToday
        LeaveArchiveCount ->
            renderArchiveCountLiveFragment archivePagination
        LeaveArchiveList ->
            renderArchivePageContent Nothing archivePagination archivedPageRequests readModel.leaveReadModelStaffMembers readModel.leaveReadModelCurrentViewerStaffId
    where
        contentRenderer = case renderMode of
            LeaveRequestsFragmentPlain        -> renderleaveRequestsContentLiveFragment
            LeaveRequestsFragmentOob swapAttr -> renderleaveRequestsContentLiveFragmentWithSwap swapAttr
        archivedRequests = archivedLeaveRequests readModel.leaveReadModelRequests readModel.leaveReadModelToday
        archivePagination = buildArchivePagination currentLeaveArchivePage archivedRequests
        archivedPageRequests = archivePageItems archivePagination archivedRequests

leaveRequestsIndexView :: (?context :: ControllerContext, ?request :: Request) => LeaveRequestsReadModel -> IndexView
leaveRequestsIndexView LeaveRequestsReadModel { leaveReadModelRequests, leaveReadModelStaffMembers, leaveReadModelCurrentViewerStaffId, leaveReadModelToday } =
    IndexView
        { leaveRequests = leaveReadModelRequests
        , staffMembers = leaveReadModelStaffMembers
        , currentViewerStaffId = leaveReadModelCurrentViewerStaffId
        , today = leaveReadModelToday
        , archivePage = currentLeaveArchivePage
        , archiveIsOpen = currentLeaveArchiveOpen
        , liveUpdateSurface = Just currentLeaveRequestsSurface
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

buildLeaveRequestsScope :: Id Venue -> SurfaceScope
buildLeaveRequestsScope venueId =
    leaveRequestsLiveScope (unpackId venueId)

currentLeaveRequestsSurface :: (?context :: ControllerContext) => SurfaceImpl Surface.LeaveRequestsSurface
currentLeaveRequestsSurface =
    leaveRequestsSurfaceImpl LeaveRequestsScopeValue { leaveRequestsVenueId = unpackId currentVenueId }
