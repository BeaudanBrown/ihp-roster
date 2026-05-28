module Web.View.LeaveRequests.Index where

import Application.Helper.Controller (LeaveRequestStatus (..),
                                      parseLeaveRequestStatus)
import Application.Helper.LiveSurface (LiveSurfaceConfig (..),
                                       liveSurfaceConfigJson)
import Data.Coerce (coerce)
import Data.List (sortOn)
import Data.Ord (Down (..))
import Web.View.Prelude

data IndexView = IndexView
    { leaveRequests        :: [LeaveRequest]
    , staffMembers         :: [Staff]
    , currentViewerStaffId :: Maybe UUID
    , today                :: Day
    , archivePage          :: Int
    , liveUpdateSurface    :: Maybe LiveSurfaceConfig
    }

leaveRequestsShellId :: Text
leaveRequestsShellId = "leave-requests-shell"

leaveRequestsContentFragmentId :: Text
leaveRequestsContentFragmentId = "leave-requests-content"

instance View IndexView where
    html = renderLeaveRequestsShell

renderLeaveRequestsShell :: IndexView -> Html
renderLeaveRequestsShell IndexView { .. } =
    let leaveRequestsPanel =
            renderAppPanel AppPanelConfig
                { appPanelTitle = Nothing
                , appPanelDescription = Nothing
                , appPanelHasActions = False
                , appPanelActions = mempty
                , appPanelHasCustomHeader = False
                , appPanelCustomHeader = mempty
                , appPanelClass = "overflow-hidden"
                , appPanelBodyClass = ""
                , appPanelBody = renderLeaveRequestsContentFragment leaveRequests staffMembers currentViewerStaffId today archivePage
                }
        page = renderAppPage (AppPageConfig
            { appPageTitle = "Unavailability"
            , appPageDescription = Nothing
            , appPageActions = mempty
            , appPageWidthClass = ""
            , appPageBody = leaveRequestsPanel
            })
     in [hsx|
        <section id={leaveRequestsShellId}
                 data-live-update-surface={liveSurfaceConfigJson <$> liveUpdateSurface}>
            {page}
        </section>
    |]

renderLeaveRequestsContentFragment :: (?context :: ControllerContext) => [LeaveRequest] -> [Staff] -> Maybe UUID -> Day -> Int -> Html
renderLeaveRequestsContentFragment =
    renderLeaveRequestsContentFragmentWithSwap Nothing

renderLeaveRequestsContentFragmentOob :: (?context :: ControllerContext) => [LeaveRequest] -> [Staff] -> Maybe UUID -> Day -> Int -> Html
renderLeaveRequestsContentFragmentOob =
    renderLeaveRequestsContentFragmentWithSwap (Just "outerHTML")

renderLeaveRequestsContentFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> [LeaveRequest] -> [Staff] -> Maybe UUID -> Day -> Int -> Html
renderLeaveRequestsContentFragmentWithSwap maybeSwapOob leaveRequests staffMembers currentViewerStaffId today archivePage = [hsx|
    <div id={leaveRequestsContentFragmentId} hx-swap-oob={maybeSwapOob}>
        {if currentUserIsManager
            then renderManagerLeaveRequests leaveRequests staffMembers currentViewerStaffId today archivePage
            else if null leaveRequests
                then renderEmptyState
                else renderLeaveRequestsTable leaveRequests staffMembers currentViewerStaffId
        }
    </div>
|]

renderEmptyState :: Html
renderEmptyState = [hsx|<p class="app-muted mb-0">No unavailable periods yet.</p>|]

renderLeaveRequestsTable :: (?context :: ControllerContext) => [LeaveRequest] -> [Staff] -> Maybe UUID -> Html
renderLeaveRequestsTable leaveRequests staffMembers currentViewerStaffId = [hsx|
    <div class="table-responsive">
        <table class="table table-striped align-middle">
            <thead>
                <tr>
                    <th>Unavailable From</th>
                    <th>Available Again</th>
                    <th>Staff</th>
                    <th>Status</th>
                    <th>Notes</th>
                    <th></th>
                </tr>
            </thead>
            <tbody>
                {forEach leaveRequests (renderLeaveRequestRow staffMembers currentViewerStaffId)}
            </tbody>
        </table>
    </div>
|]

renderManagerLeaveRequests :: (?context :: ControllerContext) => [LeaveRequest] -> [Staff] -> Maybe UUID -> Day -> Int -> Html
renderManagerLeaveRequests leaveRequests staffMembers currentViewerStaffId today archivePage = [hsx|
    <div class="accordion leave-request-accordion" id="leave-request-manager-sections">
        {renderManagerSection "leave-pending" "Pending" (length pendingRequests) pendingRequests staffMembers currentViewerStaffId True True}
        {renderManagerSection "leave-approved" "Approved" (length approvedRequests) approvedRequests staffMembers currentViewerStaffId False True}
        {renderManagerSection "leave-denied" "Denied" (length deniedRequests) deniedRequests staffMembers currentViewerStaffId False True}
        {renderManagerSection "leave-archive" "Archive" (archivePaginationTotalItems archivePagination) archivedPageRequests staffMembers currentViewerStaffId False False}
        {renderArchivePagination archivePagination}
    </div>
|]
    where
        activeRequests = filter (not . leaveRequestIsArchived today) leaveRequests
        archivedRequests = sortOn (Down . (.endDate)) (filter (leaveRequestIsArchived today) leaveRequests)
        archivePagination = buildArchivePagination archivePage archivedRequests
        archivedPageRequests = archivePageItems archivePagination archivedRequests
        pendingRequests = sortOn (Down . (.startDate)) (filter ((== Just LeavePending) . parseLeaveRequestStatus . (.status)) activeRequests)
        approvedRequests = sortOn (Down . (.startDate)) (filter ((== Just LeaveApproved) . parseLeaveRequestStatus . (.status)) activeRequests)
        deniedRequests = sortOn (Down . (.startDate)) (filter ((== Just LeaveDenied) . parseLeaveRequestStatus . (.status)) activeRequests)

leaveRequestIsArchived :: Day -> LeaveRequest -> Bool
leaveRequestIsArchived today leaveRequest =
    leaveRequest.endDate < today

archivePageSize :: Int
archivePageSize = 10

data ArchivePagination = ArchivePagination
    { archivePaginationCurrentPage :: Int
    , archivePaginationTotalPages  :: Int
    , archivePaginationTotalItems  :: Int
    }

buildArchivePagination :: Int -> [LeaveRequest] -> ArchivePagination
buildArchivePagination requestedPage archivedRequests =
    ArchivePagination
        { archivePaginationCurrentPage = currentPage
        , archivePaginationTotalPages = totalPages
        , archivePaginationTotalItems = totalItems
        }
    where
        totalItems = length archivedRequests
        totalPages = max 1 ((totalItems + archivePageSize - 1) `div` archivePageSize)
        currentPage = min totalPages (max 1 requestedPage)

archivePageItems :: ArchivePagination -> [LeaveRequest] -> [LeaveRequest]
archivePageItems ArchivePagination { archivePaginationCurrentPage } =
    take archivePageSize . drop ((archivePaginationCurrentPage - 1) * archivePageSize)

renderArchivePagination :: (?context :: ControllerContext) => ArchivePagination -> Html
renderArchivePagination pagination@ArchivePagination { archivePaginationCurrentPage, archivePaginationTotalPages, archivePaginationTotalItems }
    | archivePaginationTotalItems <= archivePageSize = mempty
    | otherwise = [hsx|
        <nav class="d-flex flex-column flex-sm-row align-items-sm-center justify-content-between gap-2 mt-3" aria-label="Unavailability archive pages">
            <div class="small app-muted">
                Showing archive page {archivePaginationCurrentPage} of {archivePaginationTotalPages} ({archivePaginationTotalItems} unavailable periods)
            </div>
            <div class="btn-group" role="group" aria-label="Archive pagination">
                {renderArchivePageLink pagination (archivePaginationCurrentPage - 1) "Newer" (archivePaginationCurrentPage <= 1)}
                {renderArchivePageLink pagination (archivePaginationCurrentPage + 1) "Older" (archivePaginationCurrentPage >= archivePaginationTotalPages)}
            </div>
        </nav>
    |]

renderArchivePageLink :: (?context :: ControllerContext) => ArchivePagination -> Int -> Text -> Bool -> Html
renderArchivePageLink _ targetPage label isDisabled = [hsx|
    <a href={href}
       class={classes [("btn btn-sm btn-outline-secondary", True), ("disabled", isDisabled)]}
       aria-disabled={if isDisabled then ("true" :: Text) else ("false" :: Text)}
       hx-get={fragmentHref}
       hx-target={"#" <> leaveRequestsContentFragmentId}
       hx-swap="outerHTML"
       hx-push-url={href}>
        {label}
    </a>
|]
    where
        pageParam = [("archivePage", tshow targetPage)]
        href = appendQueryParams (pathTo LeaveRequestsAction) pageParam
        fragmentHref = appendQueryParams (pathTo ShowLeaveRequestsContentFragmentAction) pageParam

renderManagerSection :: (?context :: ControllerContext) => Text -> Text -> Int -> [LeaveRequest] -> [Staff] -> Maybe UUID -> Bool -> Bool -> Html
renderManagerSection sectionId title displayCount requests staffMembers currentViewerStaffId isOpen showActions =
    renderAppAccordionItem AppAccordionItemConfig
        { appAccordionItemId = sectionId
        , appAccordionItemParentId = "leave-request-manager-sections"
        , appAccordionItemTitle = title
        , appAccordionItemIsOpen = isOpen
        , appAccordionItemClass = "leave-request-section"
        , appAccordionItemBodyClass = ""
        , appAccordionItemButtonContent = [hsx|
            <span class="leave-request-accordion-title">{title <> " (" <> tshow displayCount <> ")"}</span>
        |]
        , appAccordionItemBody = sectionBody
        }
    where
        sectionBody
            | null requests =
                mempty
            | otherwise =
                [hsx|
                    <div class="leave-request-list">
                        <div class="leave-request-list-head">
                            <div>Staff</div>
                            <div>Dates</div>
                            <div>Notes</div>
                            {renderManagerActionsHeader showActions}
                        </div>
                        <div class="leave-request-list-body">
                            {forEach requests (renderManagerLeaveRequestRow staffMembers currentViewerStaffId showActions)}
                        </div>
                    </div>
                |]

renderManagerLeaveRequestRow :: (?context :: ControllerContext) => [Staff] -> Maybe UUID -> Bool -> LeaveRequest -> Html
renderManagerLeaveRequestRow staffMembers currentViewerStaffId showActions leaveRequest = [hsx|
    <article class="leave-request-row">
        <div class="leave-request-row-staff">
            <div class="leave-request-row-name">{resolveStaffName leaveRequest.staffId staffMembers}</div>
            <div class="leave-request-row-status">{renderStatusBadge leaveRequest.status}</div>
        </div>
        <div class="leave-request-row-dates">{renderDateRangeText leaveRequest}</div>
        <div class="leave-request-row-notes">{fromMaybe "No notes" (leaveRequest.notes >>= nonEmptyText)}</div>
        {renderManagerActionsCell currentViewerStaffId showActions leaveRequest}
    </article>
|]

renderManagerActionsHeader :: Bool -> Html
renderManagerActionsHeader False = mempty
renderManagerActionsHeader True = [hsx|<div>Actions</div>|]

renderManagerActionsCell :: (?context :: ControllerContext) => Maybe UUID -> Bool -> LeaveRequest -> Html
renderManagerActionsCell _currentViewerStaffId False _leaveRequest = mempty
renderManagerActionsCell currentViewerStaffId True leaveRequest = [hsx|
    <div class="leave-request-row-actions">{renderActions currentViewerStaffId leaveRequest}</div>
|]

renderLeaveRequestRow :: (?context :: ControllerContext) => [Staff] -> Maybe UUID -> LeaveRequest -> Html
renderLeaveRequestRow staffMembers currentViewerStaffId leaveRequest = [hsx|
    <tr>
        <td>{leaveRequest.startDate}</td>
        <td>{leaveRequest.endDate}</td>
        <td>{resolveStaffName leaveRequest.staffId staffMembers}</td>
        <td>{renderStatusBadge leaveRequest.status}</td>
        <td>{fromMaybe "-" leaveRequest.notes}</td>
        <td class="text-end">{renderActions currentViewerStaffId leaveRequest}</td>
    </tr>
|]

resolveStaffName :: UUID -> [Staff] -> Text
resolveStaffName staffUuid staffMembers =
    case find (\staff -> coerce (get #id staff) == staffUuid) staffMembers of
        Just staff -> staff.firstName <> " " <> staff.lastName
        Nothing    -> "Unknown" :: Text

renderStatusBadge :: InputValue value => value -> Html
renderStatusBadge status =
    case parseLeaveRequestStatus status of
        Just LeaveApproved -> renderAppStatusBadge AppStatusSuccess "Approved"
        Just LeaveDenied   -> renderAppStatusBadge AppStatusDanger "Denied"
        _                  -> renderAppStatusBadge AppStatusWarning "Pending"

renderActions :: (?context :: ControllerContext) => Maybe UUID -> LeaveRequest -> Html
renderActions _currentViewerStaffId leaveRequest =
    renderReviewActions leaveRequest

renderReviewActions :: (?context :: ControllerContext) => LeaveRequest -> Html
renderReviewActions leaveRequest
    | not currentUserIsManager = mempty
    | otherwise =
        case parseLeaveRequestStatus leaveRequest.status of
            Just LeaveApproved -> [hsx|
                <form method="POST"
                      action={DenyLeaveRequestAction leaveRequest.id}
                      class="d-inline"
                      data-disable-javascript-submission="true"
                      hx-post={DenyLeaveRequestAction leaveRequest.id}
                      hx-target={"#" <> leaveRequestsContentFragmentId}
                      hx-swap="outerHTML"
                      hx-push-url="false">
                    <button type="submit" class="btn btn-sm btn-outline-danger me-1">Deny</button>
                </form>
            |]
            Just LeaveDenied -> [hsx|
                <form method="POST"
                      action={ApproveLeaveRequestAction leaveRequest.id}
                      class="d-inline"
                      data-disable-javascript-submission="true"
                      hx-post={ApproveLeaveRequestAction leaveRequest.id}
                      hx-target={"#" <> leaveRequestsContentFragmentId}
                      hx-swap="outerHTML"
                      hx-push-url="false">
                    <button type="submit" class="btn btn-sm btn-outline-success me-1">Approve</button>
                </form>
            |]
            _ -> [hsx|
                <form method="POST"
                      action={ApproveLeaveRequestAction leaveRequest.id}
                      class="d-inline"
                      data-disable-javascript-submission="true"
                      hx-post={ApproveLeaveRequestAction leaveRequest.id}
                      hx-target={"#" <> leaveRequestsContentFragmentId}
                      hx-swap="outerHTML"
                      hx-push-url="false">
                    <button type="submit" class="btn btn-sm btn-outline-success me-1">Approve</button>
                </form>
                <form method="POST"
                      action={DenyLeaveRequestAction leaveRequest.id}
                      class="d-inline"
                      data-disable-javascript-submission="true"
                      hx-post={DenyLeaveRequestAction leaveRequest.id}
                      hx-target={"#" <> leaveRequestsContentFragmentId}
                      hx-swap="outerHTML"
                      hx-push-url="false">
                    <button type="submit" class="btn btn-sm btn-outline-danger me-1">Deny</button>
                </form>
            |]

