module Web.View.LeaveRequests.Index where

import Application.Helper.Controller (LeaveRequestStatus (..),
                                      parseLeaveRequestStatus)
import qualified Application.Helper.FrontendContract.Surface.ContractIR as SurfaceIR
import Application.Helper.FrontendContract.Surface.Contracts (registeredFrontendSurfaceContractIR)
import qualified Application.Helper.FrontendContract.Surface.LeaveRequests as Surface
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            FrontendSurfaceFieldValue (..),
                                                            SurfaceImpl,
                                                            renderFrontendSurfaceActionForm,
                                                            renderFrontendSurfaceActionLink,
                                                            renderFrontendSurfaceMount)
import Data.Coerce (coerce)
import Data.List (sortOn)
import Data.Ord (Down (..))
import Web.View.Prelude

leaveRequestsSurfaceAction :: Text -> SurfaceIR.HtmxActionIR
leaveRequestsSurfaceAction actionName =
    case [action | surface <- registeredFrontendSurfaceContractIR.contractSurfaces, surface.surfaceName == "leave-requests", action <- surface.surfaceHtmxActions, action.htmxActionName == actionName] of
        action : _ -> action
        [] -> error ("missing leave requests surface action: " <> cs actionName)

leaveRequestsActionRoute :: Text -> FrontendSurfaceActionRoute
leaveRequestsActionRoute actionUrl =
    FrontendSurfaceActionRoute
        { actionRouteUrl = actionUrl
        , actionRouteFields = []
        , actionRouteCustomHtmx = []
        , actionRouteStandardUrl = Nothing
        , actionRouteExtraAttrs = []
        }

data IndexView = IndexView
    { leaveRequests        :: [LeaveRequest]
    , staffMembers         :: [Staff]
    , currentViewerStaffId :: Maybe UUID
    , today                :: Day
    , archivePage          :: Int
    , archiveIsOpen        :: Bool
    , liveUpdateSurface    :: Maybe (SurfaceImpl Surface.LeaveRequestsSurface)
    }

leaveRequestsShellId :: Text
leaveRequestsShellId = "leave-requests-shell"

leaveRequestsContentFragmentId :: Text
leaveRequestsContentFragmentId = "leave-requests-content"

leaveSectionCountFragmentKind, leaveSectionListFragmentKind :: Text
leaveSectionCountFragmentKind = "leave-section-count"
leaveSectionListFragmentKind = "leave-section-list"

leavePendingSection, leaveApprovedSection, leaveDeniedSection, leaveArchiveSection :: Text
leavePendingSection = "pending"
leaveApprovedSection = "approved"
leaveDeniedSection = "denied"
leaveArchiveSection = "archive"

leaveSectionCountFragmentId, leaveSectionListFragmentId :: Text -> Text
leaveSectionCountFragmentId section = "leave-" <> section <> "-count"
leaveSectionListFragmentId section
    | section == leaveArchiveSection = "leave-archive-page-content"
    | otherwise = "leave-" <> section <> "-list"

leavePendingCountFragmentId, leavePendingListFragmentId, leaveApprovedCountFragmentId, leaveApprovedListFragmentId, leaveDeniedCountFragmentId, leaveDeniedListFragmentId, leaveArchiveCountFragmentId, leaveArchiveListFragmentId :: Text
leavePendingCountFragmentId = leaveSectionCountFragmentId leavePendingSection
leavePendingListFragmentId = leaveSectionListFragmentId leavePendingSection
leaveApprovedCountFragmentId = leaveSectionCountFragmentId leaveApprovedSection
leaveApprovedListFragmentId = leaveSectionListFragmentId leaveApprovedSection
leaveDeniedCountFragmentId = leaveSectionCountFragmentId leaveDeniedSection
leaveDeniedListFragmentId = leaveSectionListFragmentId leaveDeniedSection
leaveArchiveCountFragmentId = leaveSectionCountFragmentId leaveArchiveSection
leaveArchiveListFragmentId = leaveSectionListFragmentId leaveArchiveSection

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
                , appPanelBody = renderleaveRequestsContentLiveFragment leaveRequests staffMembers currentViewerStaffId today archivePage archiveIsOpen
                }
        page = renderAppPage (AppPageConfig
            { appPageTitle = "Unavailability"
            , appPageDescription = Nothing
            , appPageActions = mempty
            , appPageWidthClass = ""
            , appPageBody = leaveRequestsPanel
            })
        mountedPage = case liveUpdateSurface of
            Just surface -> renderFrontendSurfaceMount surface page
            Nothing      -> page
     in [hsx|
        <section id={leaveRequestsShellId}>
            {mountedPage}
        </section>
    |]

renderleaveRequestsContentLiveFragment :: (?context :: ControllerContext) => [LeaveRequest] -> [Staff] -> Maybe UUID -> Day -> Int -> Bool -> Html
renderleaveRequestsContentLiveFragment =
    renderleaveRequestsContentLiveFragmentWithSwap Nothing

renderleaveRequestsContentLiveFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> [LeaveRequest] -> [Staff] -> Maybe UUID -> Day -> Int -> Bool -> Html
renderleaveRequestsContentLiveFragmentWithSwap maybeSwapOob leaveRequests staffMembers currentViewerStaffId today archivePage archiveIsOpen = [hsx|
    <div id={leaveRequestsContentFragmentId} hx-swap-oob={maybeSwapOob}>
        {if currentUserIsManager
            then renderManagerLeaveRequests leaveRequests staffMembers currentViewerStaffId today archivePage archiveIsOpen
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

renderManagerLeaveRequests :: (?context :: ControllerContext) => [LeaveRequest] -> [Staff] -> Maybe UUID -> Day -> Int -> Bool -> Html
renderManagerLeaveRequests leaveRequests staffMembers currentViewerStaffId today archivePage archiveIsOpen = [hsx|
    <div class="accordion leave-request-accordion" id="leave-request-manager-sections">
        {renderManagerSection "leave-pending" "Pending" leavePendingCountFragmentId leavePendingListFragmentId pendingRequests staffMembers currentViewerStaffId (not archiveIsOpen) True}
        {renderManagerSection "leave-approved" "Approved" leaveApprovedCountFragmentId leaveApprovedListFragmentId approvedRequests staffMembers currentViewerStaffId False True}
        {renderManagerSection "leave-denied" "Denied" leaveDeniedCountFragmentId leaveDeniedListFragmentId deniedRequests staffMembers currentViewerStaffId False True}
        {renderArchiveSection archivePagination archivedPageRequests staffMembers currentViewerStaffId archiveIsOpen}
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

renderLeaveSectionCountLiveFragment :: Text -> [LeaveRequest] -> Day -> Html
renderLeaveSectionCountLiveFragment section leaveRequests today
    | section == leaveApprovedSection = renderManagerSectionCount (leaveSectionCountFragmentId section) (approvedLeaveRequests leaveRequests today)
    | section == leaveDeniedSection = renderManagerSectionCount (leaveSectionCountFragmentId section) (deniedLeaveRequests leaveRequests today)
    | section == leaveArchiveSection = renderArchiveCountLiveFragment (buildArchivePagination 1 (archivedLeaveRequests leaveRequests today))
    | otherwise = renderManagerSectionCount (leaveSectionCountFragmentId leavePendingSection) (pendingLeaveRequests leaveRequests today)

renderLeaveSectionListLiveFragment :: (?context :: ControllerContext) => Text -> [LeaveRequest] -> [Staff] -> Maybe UUID -> Day -> ArchivePagination -> [LeaveRequest] -> Html
renderLeaveSectionListLiveFragment section leaveRequests staffMembers currentViewerStaffId today archivePagination archivedPageRequests
    | section == leaveApprovedSection = renderManagerSectionList (leaveSectionListFragmentId section) (approvedLeaveRequests leaveRequests today) staffMembers currentViewerStaffId True
    | section == leaveDeniedSection = renderManagerSectionList (leaveSectionListFragmentId section) (deniedLeaveRequests leaveRequests today) staffMembers currentViewerStaffId True
    | section == leaveArchiveSection = renderArchivePageContent Nothing archivePagination archivedPageRequests staffMembers currentViewerStaffId
    | otherwise = renderManagerSectionList (leaveSectionListFragmentId leavePendingSection) (pendingLeaveRequests leaveRequests today) staffMembers currentViewerStaffId True

renderPendingCountLiveFragment, renderApprovedCountLiveFragment, renderDeniedCountLiveFragment :: [LeaveRequest] -> Day -> Html
renderPendingCountLiveFragment = renderLeaveSectionCountLiveFragment leavePendingSection
renderApprovedCountLiveFragment = renderLeaveSectionCountLiveFragment leaveApprovedSection
renderDeniedCountLiveFragment = renderLeaveSectionCountLiveFragment leaveDeniedSection

renderPendingListLiveFragment, renderApprovedListLiveFragment, renderDeniedListLiveFragment :: (?context :: ControllerContext) => [LeaveRequest] -> [Staff] -> Maybe UUID -> Day -> Html
renderPendingListLiveFragment leaveRequests staffMembers currentViewerStaffId today = renderManagerSectionList leavePendingListFragmentId (pendingLeaveRequests leaveRequests today) staffMembers currentViewerStaffId True
renderApprovedListLiveFragment leaveRequests staffMembers currentViewerStaffId today = renderManagerSectionList leaveApprovedListFragmentId (approvedLeaveRequests leaveRequests today) staffMembers currentViewerStaffId True
renderDeniedListLiveFragment leaveRequests staffMembers currentViewerStaffId today = renderManagerSectionList leaveDeniedListFragmentId (deniedLeaveRequests leaveRequests today) staffMembers currentViewerStaffId True

pendingLeaveRequests, approvedLeaveRequests, deniedLeaveRequests :: [LeaveRequest] -> Day -> [LeaveRequest]
pendingLeaveRequests leaveRequests today = sortOn (Down . (.startDate)) (filter ((== Just LeavePending) . parseLeaveRequestStatus . (.status)) (activeLeaveRequests leaveRequests today))
approvedLeaveRequests leaveRequests today = sortOn (Down . (.startDate)) (filter ((== Just LeaveApproved) . parseLeaveRequestStatus . (.status)) (activeLeaveRequests leaveRequests today))
deniedLeaveRequests leaveRequests today = sortOn (Down . (.startDate)) (filter ((== Just LeaveDenied) . parseLeaveRequestStatus . (.status)) (activeLeaveRequests leaveRequests today))

activeLeaveRequests, archivedLeaveRequests :: [LeaveRequest] -> Day -> [LeaveRequest]
activeLeaveRequests leaveRequests today = filter (not . leaveRequestIsArchived today) leaveRequests
archivedLeaveRequests leaveRequests today = sortOn (Down . (.endDate)) (filter (leaveRequestIsArchived today) leaveRequests)

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

renderArchiveSection :: (?context :: ControllerContext) => ArchivePagination -> [LeaveRequest] -> [Staff] -> Maybe UUID -> Bool -> Html
renderArchiveSection archivePagination@ArchivePagination { archivePaginationTotalItems } requests staffMembers currentViewerStaffId archiveIsOpen = [hsx|
    <section class="accordion-item app-panel mb-3 leave-request-section" id="leave-archive">
        <h2 class="accordion-header" id="leave-archive-heading">
            <button
                class={if archiveIsOpen then ("accordion-button" :: Text) else "accordion-button collapsed"}
                type="button"
                data-bs-toggle="collapse"
                data-bs-target="#leave-archive-collapse"
                aria-expanded={if archiveIsOpen then ("true" :: Text) else "false"}
                aria-controls="leave-archive-collapse"
                aria-label="Archive"
            >
                <span class="leave-request-accordion-title" data-label={"Archive (" <> tshow archivePaginationTotalItems <> ")"}>Archive (<span id={leaveArchiveCountFragmentId}>{tshow archivePaginationTotalItems}</span>)</span>
            </button>
        </h2>
        <div
            id="leave-archive-collapse"
            class={if archiveIsOpen then ("accordion-collapse collapse show" :: Text) else "accordion-collapse collapse"}
            aria-labelledby="leave-archive-heading"
            data-bs-parent="#leave-request-manager-sections"
        >
            <div class="accordion-body">
                {renderArchivePageContent Nothing archivePagination requests staffMembers currentViewerStaffId}
            </div>
        </div>
    </section>
|]

renderArchivePageContentOob :: (?context :: ControllerContext) => [LeaveRequest] -> [Staff] -> Maybe UUID -> Day -> Int -> Html
renderArchivePageContentOob leaveRequests staffMembers currentViewerStaffId today archivePage =
    renderArchivePageContent (Just "outerHTML") archivePagination archivedPageRequests staffMembers currentViewerStaffId
    where
        archivedRequests = sortOn (Down . (.endDate)) (filter (leaveRequestIsArchived today) leaveRequests)
        archivePagination = buildArchivePagination archivePage archivedRequests
        archivedPageRequests = archivePageItems archivePagination archivedRequests

renderArchiveCountLiveFragment :: ArchivePagination -> Html
renderArchiveCountLiveFragment ArchivePagination { archivePaginationTotalItems } = [hsx|
    <span id={leaveArchiveCountFragmentId}>{tshow archivePaginationTotalItems}</span>
|]

renderArchivePageContent :: (?context :: ControllerContext) => Maybe Text -> ArchivePagination -> [LeaveRequest] -> [Staff] -> Maybe UUID -> Html
renderArchivePageContent maybeSwapOob archivePagination requests staffMembers currentViewerStaffId = [hsx|
    <div id={leaveArchiveListFragmentId} hx-swap-oob={maybeSwapOob}>
        {renderArchivePagination "leave-request-archive-pagination-top" archivePagination}
        {unless (null requests) (renderArchiveRequestList requests staffMembers currentViewerStaffId)}
        {renderArchivePagination "leave-request-archive-pagination-bottom" archivePagination}
    </div>
|]

renderArchiveRequestList :: (?context :: ControllerContext) => [LeaveRequest] -> [Staff] -> Maybe UUID -> Html
renderArchiveRequestList requests staffMembers currentViewerStaffId = [hsx|
    <div class="leave-request-list leave-request-list-archive">
        <div class="leave-request-list-head">
            <div>Staff</div>
            <div>Dates</div>
            <div>Notes</div>
        </div>
        <div class="leave-request-list-body">
            {forEach requests (renderManagerLeaveRequestRow staffMembers currentViewerStaffId False)}
        </div>
    </div>
|]

renderArchivePagination :: (?context :: ControllerContext) => Text -> ArchivePagination -> Html
renderArchivePagination extraClass pagination@ArchivePagination { archivePaginationCurrentPage, archivePaginationTotalPages, archivePaginationTotalItems }
    | archivePaginationTotalItems <= archivePageSize = mempty
    | otherwise = [hsx|
        <nav class={classes [("leave-request-archive-pagination", True), (extraClass, extraClass /= "")]} aria-label="Unavailability archive pages">
            <div class="btn-group leave-request-archive-page-selector" role="group" aria-label="Archive pagination">
                {renderArchivePageLink pagination (archivePaginationCurrentPage - 1) "<" (archivePaginationCurrentPage <= 1) "Newer archive page"}
                {renderArchiveFirstPageBoundary pagination}
                {renderArchiveLeadingEllipsis pagination}
                {forEach (archiveVisiblePages pagination) (renderArchivePageNumber pagination)}
                {renderArchiveTrailingEllipsis pagination}
                {renderArchiveLastPageBoundary pagination}
                {renderArchivePageLink pagination (archivePaginationCurrentPage + 1) ">" (archivePaginationCurrentPage >= archivePaginationTotalPages) "Older archive page"}
            </div>
        </nav>
    |]

archiveVisiblePages :: ArchivePagination -> [Int]
archiveVisiblePages ArchivePagination { archivePaginationCurrentPage, archivePaginationTotalPages } =
    [startPage..endPage]
    where
        startPage = max 1 (archivePaginationCurrentPage - 1)
        endPage = min archivePaginationTotalPages (archivePaginationCurrentPage + 1)

renderArchiveFirstPageBoundary :: (?context :: ControllerContext) => ArchivePagination -> Html
renderArchiveFirstPageBoundary pagination =
    if maybe False (> 1) (listToMaybe (archiveVisiblePages pagination))
        then renderArchivePageNumber pagination 1
        else mempty

renderArchiveLeadingEllipsis :: ArchivePagination -> Html
renderArchiveLeadingEllipsis pagination =
    if maybe False (> 2) (listToMaybe (archiveVisiblePages pagination))
        then renderArchiveEllipsis
        else mempty

renderArchiveTrailingEllipsis :: ArchivePagination -> Html
renderArchiveTrailingEllipsis pagination@ArchivePagination { archivePaginationTotalPages } =
    if maybe False (< archivePaginationTotalPages - 1) (lastMay (archiveVisiblePages pagination))
        then renderArchiveEllipsis
        else mempty

renderArchiveLastPageBoundary :: (?context :: ControllerContext) => ArchivePagination -> Html
renderArchiveLastPageBoundary pagination@ArchivePagination { archivePaginationTotalPages } =
    if maybe False (< archivePaginationTotalPages) (lastMay (archiveVisiblePages pagination))
        then renderArchivePageNumber pagination archivePaginationTotalPages
        else mempty

renderArchiveEllipsis :: Html
renderArchiveEllipsis = [hsx|
    <span class="btn btn-sm btn-outline-secondary disabled leave-request-archive-page-button leave-request-archive-page-ellipsis" aria-hidden="true">...</span>
|]

renderArchivePageNumber :: (?context :: ControllerContext) => ArchivePagination -> Int -> Html
renderArchivePageNumber pagination@ArchivePagination { archivePaginationCurrentPage } pageNumber
    | pageNumber == archivePaginationCurrentPage = [hsx|
        <span class="btn btn-sm btn-outline-secondary active leave-request-archive-page-button" aria-current="page">{tshow pageNumber}</span>
    |]
    | otherwise = renderArchivePageLink pagination pageNumber (tshow pageNumber) False ("Archive page " <> tshow pageNumber)

renderArchivePageLink :: (?context :: ControllerContext) => ArchivePagination -> Int -> Text -> Bool -> Text -> Html
renderArchivePageLink ArchivePagination { archivePaginationCurrentPage, archivePaginationTotalPages } requestedPage label isDisabled ariaLabel =
    renderFrontendSurfaceActionLink
        (leaveRequestsSurfaceAction "archive-leave-requests-page")
        (leaveRequestsActionRoute fragmentHref)
            { actionRouteFields = [FrontendSurfaceFieldValue "archivePage" (tshow effectivePage)]
            , actionRouteStandardUrl = Just href
            , actionRouteExtraAttrs =
                [ ("class", classes [("btn btn-sm btn-outline-secondary leave-request-archive-page-button", True), ("disabled", isDisabled)])
                , ("aria-label", ariaLabel)
                , ("aria-disabled", if isDisabled then "true" else "false")
                , ("hx-push-url", href)
                ]
            }
        [hsx|{label}|]
    where
        targetPage = min archivePaginationTotalPages (max 1 requestedPage)
        effectivePage = if isDisabled then archivePaginationCurrentPage else targetPage
        pageParam = [("archivePage", tshow effectivePage), ("openSection", "archive")]
        href = appendQueryParams (pathTo LeaveRequestsAction) pageParam
        fragmentHref = appendQueryParams (pathTo ShowleaveRequestsContentLiveFragmentAction) (pageParam <> [("swapOob", "true")])

renderManagerSection :: (?context :: ControllerContext) => Text -> Text -> Text -> Text -> [LeaveRequest] -> [Staff] -> Maybe UUID -> Bool -> Bool -> Html
renderManagerSection sectionId title countFragmentId listFragmentId requests staffMembers currentViewerStaffId isOpen showActions =
    renderAppAccordionItem AppAccordionItemConfig
        { appAccordionItemId = sectionId
        , appAccordionItemParentId = "leave-request-manager-sections"
        , appAccordionItemTitle = title
        , appAccordionItemIsOpen = isOpen
        , appAccordionItemClass = "leave-request-section"
        , appAccordionItemBodyClass = ""
        , appAccordionItemButtonContent = [hsx|
            <span class="leave-request-accordion-title" data-label={title <> " (" <> tshow (length requests) <> ")"}>{title} ({renderManagerSectionCount countFragmentId requests})</span>
        |]
        , appAccordionItemBody = renderManagerSectionList listFragmentId requests staffMembers currentViewerStaffId showActions
        }

renderManagerSectionCount :: Text -> [LeaveRequest] -> Html
renderManagerSectionCount countFragmentId requests = [hsx|
    <span id={countFragmentId}>{tshow (length requests)}</span>
|]

renderManagerSectionList :: (?context :: ControllerContext) => Text -> [LeaveRequest] -> [Staff] -> Maybe UUID -> Bool -> Html
renderManagerSectionList listFragmentId requests staffMembers currentViewerStaffId showActions = [hsx|
    <div id={listFragmentId}>
        {sectionBody}
    </div>
|]
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
renderManagerActionsHeader True  = [hsx|<div>Actions</div>|]

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
renderActions _currentViewerStaffId =
    renderReviewActions

renderReviewActions :: (?context :: ControllerContext) => LeaveRequest -> Html
renderReviewActions leaveRequest
    | not currentUserIsManager = mempty
    | otherwise =
        case parseLeaveRequestStatus leaveRequest.status of
            Just LeaveApproved -> renderReviewActionForm (DenyLeaveRequestAction leaveRequest.id) "btn btn-sm btn-outline-danger me-1" "Deny"
            Just LeaveDenied   -> renderReviewActionForm (ApproveLeaveRequestAction leaveRequest.id) "btn btn-sm btn-outline-success me-1" "Approve"
            _ ->
                renderReviewActionForm (ApproveLeaveRequestAction leaveRequest.id) "btn btn-sm btn-outline-success me-1" "Approve"
                    <> renderReviewActionForm (DenyLeaveRequestAction leaveRequest.id) "btn btn-sm btn-outline-danger me-1" "Deny"

renderReviewActionForm :: (?context :: ControllerContext) => LeaveRequestsController -> Text -> Text -> Html
renderReviewActionForm action buttonClass label =
    renderFrontendSurfaceActionForm
        (leaveRequestsSurfaceAction actionName)
        (leaveRequestsActionRoute (pathTo action))
            { actionRouteStandardUrl = Just (pathTo action)
            , actionRouteExtraAttrs = [("class", "d-inline"), ("data-disable-javascript-submission", "true")]
            }
        [hsx|<button type="submit" class={buttonClass}>{label}</button>|]
    where
        actionName =
            case action of
                ApproveLeaveRequestAction {} -> "approve-leave-request"
                DenyLeaveRequestAction {}    -> "deny-leave-request"
                _                            -> error "unsupported leave request review action"

