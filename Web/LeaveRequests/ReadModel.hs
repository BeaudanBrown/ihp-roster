{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.LeaveRequests.ReadModel
    ( LeaveRequestsReadModel (..)
    , LeaveRequestsFragment (..)
    , LeaveRequestsSectionFragment (..)
    , currentLeaveArchiveOpen
    , currentLeaveArchivePage
    , currentLeaveArchivePageResult
    , fetchLeaveRequestsReadModel
    , leaveRequestsIndexView
    , renderLeaveRequestsFragment
    , renderLeaveRequestsFragmentFromReadModel
    ) where

import Application.Helper.Controller (venueRoleToText)
import Application.Helper.FrontendContract.Surface.FragmentRender (FragmentRenderMode (..))
import Application.Helper.FrontendContract.Surface.LeaveRequests (LeaveSectionValue)
import qualified Application.Helper.FrontendContract.Surface.LeaveRequests as Surface
import qualified Application.Helper.FrontendContract.Surface.LeaveRequests.Action as LeaveRequestsAction
import Application.Helper.FrontendContract.Surface.LeaveRequests.Live (leaveRequestsLiveScope)
import Application.Helper.FrontendContract.Surface.Live (SurfaceScope)
import Application.Helper.FrontendContract.Surface.Request (SurfaceRequestFieldError)
import Application.Helper.FrontendContract.Surface.Runtime (SurfaceImpl)
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldValue)
import Application.Helper.Profiling
import Application.Helper.Staff (isTrialStaff)
import Data.Coerce (coerce)
import qualified Data.Map.Strict as Map
import Data.Time.Clock (getCurrentTime, utctDay)
import qualified Data.UUID as UUID
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.LeaveRequests.AvailabilityWarnings
import Web.LeaveRequests.Blackouts
import Web.LeaveRequests.FrontendSurface (LeaveRequestsScopeValue (..),
                                          leaveRequestsSurfaceImpl)
import Web.View.LeaveRequests.Index

data LeaveRequestsReadModel = LeaveRequestsReadModel
    { leaveReadModelRequests             :: [LeaveRequest]
    , leaveReadModelStaffMembers         :: [Staff]
    , leaveReadModelCurrentViewerStaffId :: Maybe UUID.UUID
    , leaveReadModelStaffPanelEntries    :: [LeaveStaffPanelEntry]
    , leaveReadModelToday                :: Day
    , leaveReadModelWarningThreshold     :: Maybe Int
    , leaveReadModelWarningPeriods       :: [AvailabilityWarningPeriod]
    , leaveReadModelVenueToday           :: Day
    , leaveReadModelBlackouts            :: [UnavailabilityBlackout]
    }

data LeaveRequestsFragment
    = LeaveRequestsContent
    | LeaveSidePanelContent
    | UnavailabilityBlackouts
    | LeaveAvailabilityWarnings
    | LeaveRequestsSectionCount !LeaveSectionValue
    | LeaveRequestsSectionList !LeaveSectionValue
    deriving (Eq, Show)

data LeaveRequestsSectionFragment
    = LeaveRequestsSectionCountFragment
    | LeaveRequestsSectionListFragment
    deriving (Eq, Show)

fetchStaffMembersForCurrentVenue :: (?modelContext :: ModelContext, ?context :: ControllerContext) => IO [Staff]
fetchStaffMembersForCurrentVenue =
    query @Staff |> filterWhere (#venueId, unpackId currentVenueId) |> orderByAsc #lastName |> fetch

fetchVisibleLeaveRequests :: (?modelContext :: ModelContext, ?context :: ControllerContext) => IO [LeaveRequest]
fetchVisibleLeaveRequests = do
    if hasRole Manager
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
    leaveReadModelStaffPanelEntries <- profileActionSpan "leave.build_staff_panel" (buildLeaveStaffPanelEntries leaveReadModelToday leaveReadModelStaffMembers leaveReadModelRequests)
    venueConfig <- profileActionSpan "leave.fetch_venue_config" fetchVenueConfig
    leaveReadModelVenueToday <- profileActionSpan "leave.fetch_venue_today" (currentVenueCalendarDay venueConfig)
    leaveReadModelBlackouts <- profileActionSpan "leave.fetch_blackouts" (fetchCurrentAndFutureUnavailabilityBlackouts leaveReadModelVenueToday)
    let leaveReadModelWarningThreshold = venueConfig.unavailableStaffWarningThreshold
    let leaveReadModelWarningPeriods =
            maybe
                []
                (\threshold -> buildAvailabilityWarningPeriods threshold leaveReadModelStaffMembers leaveReadModelRequests)
                leaveReadModelWarningThreshold
    pure LeaveRequestsReadModel { .. }

buildLeaveStaffPanelEntries :: (?modelContext :: ModelContext, ?context :: ControllerContext) => Day -> [Staff] -> [LeaveRequest] -> IO [LeaveStaffPanelEntry]
buildLeaveStaffPanelEntries today staffMembers leaveRequests = do
    let eligibleStaff = filter (\staff -> staff.isActive && isNothing staff.archivedAt) staffMembers
    let linkedUserIds = mapMaybe (.userId) eligibleStaff
    memberships <-
        if null linkedUserIds
            then pure []
            else query @VenueMembership
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhereIn (#userId, linkedUserIds)
                |> filterWhere (#isActive, True)
                |> fetch
    let membershipsByUserId = Map.fromList [(membership.userId, membership) | membership <- memberships]
    let currentAndFutureRequests = activeLeaveRequests leaveRequests today
    let periodCountByStaffId = Map.fromListWith (+) [(request.staffId, 1 :: Int) | request <- currentAndFutureRequests]
    let pendingCountByStaffId = Map.fromListWith (+) [(request.staffId, 1 :: Int) | request <- currentAndFutureRequests, request.status == LeaveRequestStatusEnumPending]
    pure
        [ LeaveStaffPanelEntry
            { panelStaff = staff
            , panelStaffRole =
                if isTrialStaff staff
                    then "trial"
                    else maybe (venueRoleToText Worker) (venueRoleToText . (.venueRole)) (staff.userId >>= (`Map.lookup` membershipsByUserId))
            , panelPeriodCount = Map.findWithDefault 0 (unpackId staff.id) periodCountByStaffId
            , panelPendingCount = Map.findWithDefault 0 (unpackId staff.id) pendingCountByStaffId
            }
        | staff <- eligibleStaff
        ]

renderLeaveRequestsFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => LeaveRequestsFragment -> IO (Maybe Blaze.Html)
renderLeaveRequestsFragment fragment =
    profileActionSpan "leave.read_model.render_fragment" do
        readModel <- fetchLeaveRequestsReadModel
        pure (renderLeaveRequestsFragmentFromReadModel FragmentPlain readModel fragment)

renderLeaveRequestsFragmentFromReadModel :: (?context :: ControllerContext, ?request :: Request) => FragmentRenderMode -> LeaveRequestsReadModel -> LeaveRequestsFragment -> Maybe Blaze.Html
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
                readModel.leaveReadModelWarningThreshold
                readModel.leaveReadModelWarningPeriods
        LeaveSidePanelContent ->
            renderLeaveSidePanelWithSwap
                (fragmentRenderSwap renderMode)
                readModel.leaveReadModelVenueToday
                readModel.leaveReadModelBlackouts
                readModel.leaveReadModelRequests
                readModel.leaveReadModelStaffMembers
                readModel.leaveReadModelStaffPanelEntries
        UnavailabilityBlackouts ->
            renderUnavailabilityBlackoutsLiveFragment readModel.leaveReadModelVenueToday readModel.leaveReadModelBlackouts readModel.leaveReadModelRequests readModel.leaveReadModelStaffMembers
        LeaveAvailabilityWarnings ->
            renderAvailabilityWarningsLiveFragment readModel.leaveReadModelWarningThreshold readModel.leaveReadModelWarningPeriods
        LeaveRequestsSectionCount section ->
            renderLeaveSectionCountLiveFragment section readModel.leaveReadModelRequests readModel.leaveReadModelToday
        LeaveRequestsSectionList section ->
            renderLeaveSectionListLiveFragment section readModel.leaveReadModelRequests readModel.leaveReadModelStaffMembers readModel.leaveReadModelCurrentViewerStaffId readModel.leaveReadModelToday archivePagination archivedPageRequests
    where
        fragmentRenderSwap = \case
            FragmentPlain        -> Nothing
            FragmentOob swapAttr -> swapAttr
        contentRenderer = case renderMode of
            FragmentPlain        -> renderleaveRequestsContentLiveFragment
            FragmentOob swapAttr -> renderleaveRequestsContentLiveFragmentWithSwap swapAttr
        archivedRequests = archivedLeaveRequests readModel.leaveReadModelRequests readModel.leaveReadModelToday
        archivePagination = buildArchivePagination currentLeaveArchivePage archivedRequests
        archivedPageRequests = archivePageItems archivePagination archivedRequests

leaveRequestsIndexView :: (?context :: ControllerContext, ?request :: Request) => LeaveRequestsReadModel -> IndexView
leaveRequestsIndexView LeaveRequestsReadModel { leaveReadModelRequests, leaveReadModelStaffMembers, leaveReadModelCurrentViewerStaffId, leaveReadModelStaffPanelEntries, leaveReadModelToday, leaveReadModelWarningThreshold, leaveReadModelWarningPeriods, leaveReadModelVenueToday, leaveReadModelBlackouts } =
    IndexView
        { leaveRequests = leaveReadModelRequests
        , staffMembers = leaveReadModelStaffMembers
        , currentViewerStaffId = leaveReadModelCurrentViewerStaffId
        , staffPanelEntries = leaveReadModelStaffPanelEntries
        , today = leaveReadModelToday
        , archivePage = currentLeaveArchivePage
        , archiveIsOpen = currentLeaveArchiveOpen
        , warningThreshold = leaveReadModelWarningThreshold
        , warningPeriods = leaveReadModelWarningPeriods
        , venueToday = leaveReadModelVenueToday
        , blackouts = leaveReadModelBlackouts
        , liveUpdateSurface = Just currentLeaveRequestsSurface
        }

currentLeaveArchivePage :: (?request :: Request) => Int
currentLeaveArchivePage =
    case currentLeaveArchivePageResult of
        Left _     -> 1
        Right page -> page

currentLeaveArchivePageResult :: (?request :: Request) => Either [SurfaceRequestFieldError] Int
currentLeaveArchivePageResult
    | not (LeaveRequestsAction.archiveLeaveRequestsPageActionParamsPresent) = Right 1
    | otherwise = max 1 . surfaceFieldValue @Surface.ArchivePage <$> LeaveRequestsAction.parseArchiveLeaveRequestsPageActionParams

currentLeaveArchiveOpen :: (?request :: Request) => Bool
currentLeaveArchiveOpen =
    paramOrDefault @Text "" "openSection" == "archive"

currentLeaveRequestsSurface :: (?context :: ControllerContext) => SurfaceImpl Surface.LeaveRequestsSurface
currentLeaveRequestsSurface =
    leaveRequestsSurfaceImpl LeaveRequestsScopeValue { leaveRequestsVenueId = unpackId currentVenueId }
