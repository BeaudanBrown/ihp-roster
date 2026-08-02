{-# LANGUAGE TypeApplications #-}

module Web.View.LeaveRequests.Index where

import Application.Helper.Controller (leaveRequestIsArchivedOn)
import qualified Application.Helper.FrontendContract.Surface.LeaveRequests as Surface
import qualified Application.Helper.FrontendContract.Surface.LeaveRequests.Action as LeaveRequestsAction
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            SurfaceImpl,
                                                            renderFrontendSurfaceActionForm,
                                                            renderFrontendSurfaceActionLink,
                                                            renderFrontendSurfaceMount)
import Application.Helper.FrontendContract.Surface.Values
import Data.Coerce (coerce)
import Data.List (sortOn)
import Data.Ord (Down (..))
import Web.LeaveRequests.AvailabilityWarnings
import Web.LeaveRequests.Blackouts
import Web.View.Prelude

leaveRequestsActionRoute :: Text -> FrontendSurfaceActionRoute
leaveRequestsActionRoute actionUrl =
    FrontendSurfaceActionRoute
        { actionRouteUrl = actionUrl
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
    , warningThreshold     :: Maybe Int
    , warningPeriods       :: [AvailabilityWarningPeriod]
    , venueToday           :: Day
    , blackouts            :: [UnavailabilityBlackout]
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
leaveSectionCountFragmentId section =
    surfaceFragmentTargetId @Surface.LeaveRequestsSurface @Surface.LeaveSectionCount
        ( surfaceField @Surface.LeaveSection section
            &: surfaceField @Surface.LeaveTargetSuffix "count"
            &: noSurfaceFields
        )
leaveSectionListFragmentId section =
    surfaceFragmentTargetId @Surface.LeaveRequestsSurface @Surface.LeaveSectionList
        ( surfaceField @Surface.LeaveSection section
            &: surfaceField @Surface.LeaveTargetSuffix (if section == leaveArchiveSection then "page-content" else "list")
            &: noSurfaceFields
        )

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
                , appPanelBody = renderleaveRequestsContentLiveFragment leaveRequests staffMembers currentViewerStaffId today archivePage archiveIsOpen warningThreshold warningPeriods
                }
        page = renderAppPage (AppPageConfig
            { appPageTitle = "Unavailability"
            , appPageDescription = Nothing
            , appPageActions = mempty
            , appPageHelpTopic = Just (PageHelpTopicId "leave")
            , appPageWidthClass = ""
            , appPageBody =
                renderUnavailabilityBlackoutsLiveFragment venueToday blackouts leaveRequests staffMembers
                    <> leaveRequestsPanel
            })
        mountedPage = case liveUpdateSurface of
            Just surface -> renderFrontendSurfaceMount surface page
            Nothing      -> page
     in [hsx|
        <section id={leaveRequestsShellId}>
            {mountedPage}
        </section>
    |]

renderUnavailabilityBlackoutsLiveFragment :: (?context :: ControllerContext) => Day -> [UnavailabilityBlackout] -> [LeaveRequest] -> [Staff] -> Html
renderUnavailabilityBlackoutsLiveFragment today blackouts leaveRequests staffMembers =
    renderUnavailabilityBlackoutsValidationFragment today blackouts leaveRequests staffMembers Nothing

renderUnavailabilityBlackoutsValidationFragment :: (?context :: ControllerContext) => Day -> [UnavailabilityBlackout] -> [LeaveRequest] -> [Staff] -> Maybe UnavailabilityBlackout -> Html
renderUnavailabilityBlackoutsValidationFragment today persistedBlackouts leaveRequests staffMembers submittedBlackout = [hsx|
    <section id={surfaceFragmentTargetId @Surface.LeaveRequestsSurface @Surface.UnavailabilityBlackouts noSurfaceFields} class="mb-4">
        <div class="card shadow-sm">
            <div class="card-body">
                <div class="d-flex flex-wrap justify-content-between gap-2 align-items-start mb-3">
                    <div>
                        <h2 class="h5 mb-1">Submission blackout periods</h2>
                        <p class="small app-muted mb-0">Staff cannot add unavailable time that overlaps these inclusive dates.</p>
                    </div>
                </div>
                {if currentUserCanManageBlackouts then renderCreateBlackoutForm today createFormBlackout else mempty}
                {renderBlackoutPeriods leaveRequests staffMembers renderedBlackouts}
            </div>
        </div>
    </section>
|]
  where
    defaultBlackout =
        newRecord @UnavailabilityBlackout
            |> set #startDate today
            |> set #endDate today
            |> set #reason ""
    createFormBlackout = fromMaybe defaultBlackout (submittedBlackout >>= \blackout -> if isNew blackout then Just blackout else Nothing)
    renderedBlackouts =
        case submittedBlackout >>= \blackout -> if isNew blackout then Nothing else Just blackout of
            Nothing -> persistedBlackouts
            Just invalidUpdate -> map (\blackout -> if blackout.id == invalidUpdate.id then invalidUpdate else blackout) persistedBlackouts

renderBlackoutPeriods :: (?context :: ControllerContext) => [LeaveRequest] -> [Staff] -> [UnavailabilityBlackout] -> Html
renderBlackoutPeriods _ _ [] = [hsx|<p class="small app-muted mb-0">No current or upcoming blackout periods.</p>|]
renderBlackoutPeriods leaveRequests staffMembers blackouts = [hsx|
    <div class="d-grid gap-3">{forEach blackouts (renderBlackoutPeriod leaveRequests staffMembers)}</div>
|]

currentUserCanManageBlackouts :: (?context :: ControllerContext) => Bool
currentUserCanManageBlackouts = currentUserIsAdmin

renderCreateBlackoutForm :: (?context :: ControllerContext) => Day -> UnavailabilityBlackout -> Html
renderCreateBlackoutForm today blackout =
    renderFrontendSurfaceActionForm
        (LeaveRequestsAction.createUnavailabilityBlackoutAction fields)
        (leaveRequestsActionRouteWithStandard (pathTo CreateUnavailabilityBlackoutAction))
        [hsx|
            <div class="row g-2 align-items-end mb-3">
                <div class="col-12 col-md-3">
                    <label class="form-label" for="blackout-start-date">First blocked date</label>
                    <input id="blackout-start-date" class={blackoutInputClass (getValidationFailure #startDate blackout)} type="date" name={surfaceFieldNameFrom @Surface.StartDate fields} value={tshow blackout.startDate} min={tshow today} required/>
                    {renderBlackoutStartDateError blackout}
                </div>
                <div class="col-12 col-md-3">
                    <label class="form-label" for="blackout-end-date">Last blocked date</label>
                    <input id="blackout-end-date" class={blackoutInputClass (getValidationFailure #endDate blackout)} type="date" name={surfaceFieldNameFrom @Surface.EndDate fields} value={tshow blackout.endDate} min={tshow today} required/>
                    {renderBlackoutEndDateError blackout}
                </div>
                <div class="col-12 col-md-4">
                    <label class="form-label" for="blackout-reason">Staff-visible reason</label>
                    <input id="blackout-reason" class={blackoutInputClass (getValidationFailure #reason blackout)} type="text" name={surfaceFieldNameFrom @Surface.Reason fields} value={blackout.reason} minlength="3" maxlength="160" required/>
                    {renderBlackoutReasonError blackout}
                </div>
                <div class="col-12 col-md-2 d-grid">
                    <button class="btn btn-primary" type="submit">Add blackout</button>
                </div>
            </div>
        |]
  where
    fields = LeaveRequestsAction.createUnavailabilityBlackoutActionFields blackout.startDate blackout.endDate blackout.reason

blackoutInputClass :: Maybe Text -> Text
blackoutInputClass maybeError = classes ["form-control", ("is-invalid", isJust maybeError)]

renderBlackoutStartDateError :: UnavailabilityBlackout -> Html
renderBlackoutStartDateError = renderBlackoutValidationError . getValidationFailure #startDate

renderBlackoutEndDateError :: UnavailabilityBlackout -> Html
renderBlackoutEndDateError = renderBlackoutValidationError . getValidationFailure #endDate

renderBlackoutReasonError :: UnavailabilityBlackout -> Html
renderBlackoutReasonError = renderBlackoutValidationError . getValidationFailure #reason

renderBlackoutValidationError :: Maybe Text -> Html
renderBlackoutValidationError Nothing = mempty
renderBlackoutValidationError (Just message) = [hsx|<div class="invalid-feedback">{message}</div>|]

renderBlackoutPeriod :: (?context :: ControllerContext) => [LeaveRequest] -> [Staff] -> UnavailabilityBlackout -> Html
renderBlackoutPeriod leaveRequests staffMembers blackout = [hsx|
    <article class="border rounded p-3" data-blackout-id={tshow blackout.id}>
        <div class="d-flex flex-wrap justify-content-between gap-2">
            <div>
                <strong>{formatDateDisplay blackout.startDate} – {formatDateDisplay blackout.endDate}</strong>
                <div class="small">{blackout.reason}</div>
            </div>
            {if currentUserCanManageBlackouts then renderDeleteBlackoutForm blackout else mempty}
        </div>
        {if currentUserCanManageBlackouts then renderBlackoutExceptions (blackoutExceptions leaveRequests staffMembers blackout) else mempty}
        {if currentUserCanManageBlackouts then renderUpdateBlackoutForm blackout else mempty}
    </article>
|]

renderBlackoutExceptions :: [BlackoutException] -> Html
renderBlackoutExceptions [] = mempty
renderBlackoutExceptions exceptions = [hsx|
    <div class="alert alert-warning py-2 mt-3 mb-0">
        <strong>Pre-existing exceptions</strong>
        <ul class="small mb-0 mt-1">
            {forEach exceptions renderBlackoutException}
        </ul>
    </div>
|]

renderBlackoutException :: BlackoutException -> Html
renderBlackoutException exception = [hsx|
    <li>{exception.blackoutExceptionStaff.firstName} {exception.blackoutExceptionStaff.lastName} — {formatDateDisplay exception.blackoutExceptionRequest.startDate} to {formatDateDisplay (addDays (-1) exception.blackoutExceptionRequest.endDate)} ({inputValue exception.blackoutExceptionRequest.status})</li>
|]

renderUpdateBlackoutForm :: (?context :: ControllerContext) => UnavailabilityBlackout -> Html
renderUpdateBlackoutForm blackout = [hsx|
    <details class="mt-3" open={not (isValid blackout)}>
        <summary>Edit period</summary>
        <div class="mt-2">
            {updateForm}
        </div>
    </details>
|]
  where
    fields = LeaveRequestsAction.updateUnavailabilityBlackoutActionFields blackout.startDate blackout.endDate blackout.reason
    updateForm =
        renderFrontendSurfaceActionForm
            (LeaveRequestsAction.updateUnavailabilityBlackoutAction fields)
            (leaveRequestsActionRouteWithStandard (pathTo (UpdateUnavailabilityBlackoutAction blackout.id)))
            [hsx|
                <div class="row g-2 align-items-end">
                    <div class="col-12 col-md-3"><label class="form-label">First blocked date</label><input class={blackoutInputClass (getValidationFailure #startDate blackout)} type="date" name={surfaceFieldNameFrom @Surface.StartDate fields} value={tshow blackout.startDate} required/>{renderBlackoutStartDateError blackout}</div>
                    <div class="col-12 col-md-3"><label class="form-label">Last blocked date</label><input class={blackoutInputClass (getValidationFailure #endDate blackout)} type="date" name={surfaceFieldNameFrom @Surface.EndDate fields} value={tshow blackout.endDate} required/>{renderBlackoutEndDateError blackout}</div>
                    <div class="col-12 col-md-4"><label class="form-label">Staff-visible reason</label><input class={blackoutInputClass (getValidationFailure #reason blackout)} type="text" name={surfaceFieldNameFrom @Surface.Reason fields} value={blackout.reason} minlength="3" maxlength="160" required/>{renderBlackoutReasonError blackout}</div>
                    <div class="col-12 col-md-2 d-grid"><button class="btn btn-outline-primary" type="submit">Save blackout</button></div>
                </div>
            |]

renderDeleteBlackoutForm :: (?context :: ControllerContext) => UnavailabilityBlackout -> Html
renderDeleteBlackoutForm blackout =
    renderFrontendSurfaceActionForm
        (LeaveRequestsAction.deleteUnavailabilityBlackoutAction LeaveRequestsAction.deleteUnavailabilityBlackoutActionFields)
        (leaveRequestsActionRouteWithStandard (pathTo (DeleteUnavailabilityBlackoutAction blackout.id)))
        [hsx|<button class="btn btn-sm btn-outline-danger" type="submit">Remove</button>|]

leaveRequestsActionRouteWithStandard :: Text -> FrontendSurfaceActionRoute
leaveRequestsActionRouteWithStandard actionUrl =
    (leaveRequestsActionRoute actionUrl) { actionRouteStandardUrl = Just actionUrl }

renderleaveRequestsContentLiveFragment :: (?context :: ControllerContext) => [LeaveRequest] -> [Staff] -> Maybe UUID -> Day -> Int -> Bool -> Maybe Int -> [AvailabilityWarningPeriod] -> Html
renderleaveRequestsContentLiveFragment =
    renderleaveRequestsContentLiveFragmentWithSwap Nothing

renderleaveRequestsContentLiveFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> [LeaveRequest] -> [Staff] -> Maybe UUID -> Day -> Int -> Bool -> Maybe Int -> [AvailabilityWarningPeriod] -> Html
renderleaveRequestsContentLiveFragmentWithSwap maybeSwapOob leaveRequests staffMembers currentViewerStaffId today archivePage archiveIsOpen warningThreshold warningPeriods = [hsx|
    <div id={leaveRequestsContentFragmentId} hx-swap-oob={maybeSwapOob}>
        {if currentUserIsManager
            then renderAvailabilityWarningsLiveFragment warningThreshold warningPeriods <> renderManagerLeaveRequests leaveRequests staffMembers currentViewerStaffId today archivePage archiveIsOpen
            else if null leaveRequests
                then renderEmptyState
                else renderLeaveRequestsTable leaveRequests staffMembers currentViewerStaffId
        }
    </div>
|]

renderAvailabilityWarningsLiveFragment :: Maybe Int -> [AvailabilityWarningPeriod] -> Html
renderAvailabilityWarningsLiveFragment warningThreshold warningPeriods = [hsx|
    <div id={surfaceFragmentTargetId @Surface.LeaveRequestsSurface @Surface.LeaveAvailabilityWarnings noSurfaceFields} class="mb-3">
        {renderAvailabilityWarningContent warningThreshold warningPeriods}
    </div>
|]

renderAvailabilityWarningContent :: Maybe Int -> [AvailabilityWarningPeriod] -> Html
renderAvailabilityWarningContent Nothing _ = mempty
renderAvailabilityWarningContent (Just _) [] = mempty
renderAvailabilityWarningContent (Just threshold) warningPeriods = [hsx|
    <div class="alert alert-warning mb-0" role="status">
        <h2 class="h6 mb-2">Unavailable-staff threshold reached</h2>
        <p class="small mb-2">Warning threshold: {threshold} active staff. Requests remain available and are not blocked.</p>
        <div class="d-grid gap-2">
            {forEach warningPeriods renderAvailabilityWarningPeriod}
        </div>
    </div>
|]

renderAvailabilityWarningPeriod :: AvailabilityWarningPeriod -> Html
renderAvailabilityWarningPeriod warningPeriod = [hsx|
    <details>
        <summary>{warningPeriodLabel warningPeriod} — {warningPeriod.availabilityWarningCount} staff unavailable</summary>
        <ul class="small mb-0 mt-2">
            {forEach warningPeriod.availabilityWarningStaff renderAvailabilityWarningStaff}
        </ul>
    </details>
|]

renderAvailabilityWarningStaff :: AvailabilityWarningStaff -> Html
renderAvailabilityWarningStaff warningStaff = [hsx|
    <li>{warningStaff.availabilityWarningStaffName} — {warningStatusLabel warningStaff.availabilityWarningStaffStatuses}</li>
|]

warningPeriodLabel :: AvailabilityWarningPeriod -> Text
warningPeriodLabel warningPeriod
    | warningPeriod.availabilityWarningEndDate == addDays 1 warningPeriod.availabilityWarningStartDate = formatDateDisplay warningPeriod.availabilityWarningStartDate
    | otherwise = formatDateDisplay warningPeriod.availabilityWarningStartDate <> " – " <> formatDateDisplay (addDays (-1) warningPeriod.availabilityWarningEndDate)

warningStatusLabel :: [LeaveRequestStatusEnum] -> Text
warningStatusLabel statuses
    | statuses == [LeaveRequestStatusEnumPending] = "Pending"
    | statuses == [LeaveRequestStatusEnumApproved] = "Approved"
    | otherwise = "Pending and approved"

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
        activeRequests = filter (not . leaveRequestIsArchivedOn today) leaveRequests
        archivedRequests = sortOn (Down . (.endDate)) (filter (leaveRequestIsArchivedOn today) leaveRequests)
        archivePagination = buildArchivePagination archivePage archivedRequests
        archivedPageRequests = archivePageItems archivePagination archivedRequests
        pendingRequests = sortOn (Down . (.startDate)) (filter ((== LeaveRequestStatusEnumPending) . (.status)) activeRequests)
        approvedRequests = sortOn (Down . (.startDate)) (filter ((== LeaveRequestStatusEnumApproved) . (.status)) activeRequests)
        deniedRequests = sortOn (Down . (.startDate)) (filter ((== LeaveRequestStatusEnumDenied) . (.status)) activeRequests)

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
pendingLeaveRequests leaveRequests today = sortOn (Down . (.startDate)) (filter ((== LeaveRequestStatusEnumPending) . (.status)) (activeLeaveRequests leaveRequests today))
approvedLeaveRequests leaveRequests today = sortOn (Down . (.startDate)) (filter ((== LeaveRequestStatusEnumApproved) . (.status)) (activeLeaveRequests leaveRequests today))
deniedLeaveRequests leaveRequests today = sortOn (Down . (.startDate)) (filter ((== LeaveRequestStatusEnumDenied) . (.status)) (activeLeaveRequests leaveRequests today))

activeLeaveRequests, archivedLeaveRequests :: [LeaveRequest] -> Day -> [LeaveRequest]
activeLeaveRequests leaveRequests today = filter (not . leaveRequestIsArchivedOn today) leaveRequests
archivedLeaveRequests leaveRequests today = sortOn (Down . (.endDate)) (filter (leaveRequestIsArchivedOn today) leaveRequests)

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
        archivedRequests = sortOn (Down . (.endDate)) (filter (leaveRequestIsArchivedOn today) leaveRequests)
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
        (LeaveRequestsAction.archiveLeaveRequestsPageAction fields)
        (leaveRequestsActionRoute fragmentHref)
            { actionRouteStandardUrl = Just href
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
        fields = LeaveRequestsAction.archiveLeaveRequestsPageActionFields effectivePage
        pageParam = [(surfaceFieldNameFrom @Surface.ArchivePage fields, tshow effectivePage), ("openSection", "archive")]
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
        <td>{formatDateDisplay leaveRequest.startDate}</td>
        <td>{formatDateDisplay leaveRequest.endDate}</td>
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

renderStatusBadge :: LeaveRequestStatusEnum -> Html
renderStatusBadge LeaveRequestStatusEnumApproved = renderAppStatusBadge AppStatusSuccess "Approved"
renderStatusBadge LeaveRequestStatusEnumDenied = renderAppStatusBadge AppStatusDanger "Denied"
renderStatusBadge LeaveRequestStatusEnumPending = renderAppStatusBadge AppStatusWarning "Pending"

renderActions :: (?context :: ControllerContext) => Maybe UUID -> LeaveRequest -> Html
renderActions _currentViewerStaffId =
    renderReviewActions

renderReviewActions :: (?context :: ControllerContext) => LeaveRequest -> Html
renderReviewActions leaveRequest
    | not currentUserIsManager = mempty
    | otherwise =
        case leaveRequest.status of
            LeaveRequestStatusEnumApproved -> renderReviewActionForm (DenyLeaveRequestAction leaveRequest.id) "btn btn-sm btn-outline-danger me-1" "Deny"
            LeaveRequestStatusEnumDenied -> renderReviewActionForm (ApproveLeaveRequestAction leaveRequest.id) "btn btn-sm btn-outline-success me-1" "Approve"
            LeaveRequestStatusEnumPending ->
                renderReviewActionForm (ApproveLeaveRequestAction leaveRequest.id) "btn btn-sm btn-outline-success me-1" "Approve"
                    <> renderReviewActionForm (DenyLeaveRequestAction leaveRequest.id) "btn btn-sm btn-outline-danger me-1" "Deny"

renderReviewActionForm :: (?context :: ControllerContext) => LeaveRequestsController -> Text -> Text -> Html
renderReviewActionForm action buttonClass label =
    case action of
        ApproveLeaveRequestAction {} -> render (LeaveRequestsAction.approveLeaveRequestAction LeaveRequestsAction.approveLeaveRequestActionFields)
        DenyLeaveRequestAction {} -> render (LeaveRequestsAction.denyLeaveRequestAction LeaveRequestsAction.denyLeaveRequestActionFields)
        _ -> error "unsupported leave request review action"
    where
        render actionContract =
            renderFrontendSurfaceActionForm
                actionContract
                (leaveRequestsActionRoute (pathTo action))
                    { actionRouteStandardUrl = Just (pathTo action)
                    , actionRouteExtraAttrs = [("class", "d-inline")]
                    }
                [hsx|<button type="submit" class={buttonClass}>{label}</button>|]

