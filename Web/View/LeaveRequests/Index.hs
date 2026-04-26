module Web.View.LeaveRequests.Index where

import Application.Helper.Controller (LeaveRequestStatus (..),
                                      leaveRequestCanBeDeleted,
                                      parseLeaveRequestStatus)
import Application.Helper.LiveUpdate (LiveUpdateScope (..))
import Data.Coerce (coerce)
import Data.List (sortOn)
import Data.Ord (Down (..))
import qualified Data.Text as Text
import Data.Time.Format (defaultTimeLocale, formatTime)
import Web.View.Prelude

data IndexView = IndexView
    { leaveRequests        :: [LeaveRequest]
    , staffMembers         :: [Staff]
    , currentViewerStaffId :: Maybe UUID
    , today                :: Day
    , liveUpdateScope      :: Maybe LiveUpdateScope
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
                , appPanelBody = renderLeaveRequestsContentFragment leaveRequests staffMembers currentViewerStaffId today
                }
        page = renderAppPage (AppPageConfig
            { appPageTitle = "Leave Requests"
            , appPageDescription = Nothing
            , appPageActions = if currentUserIsSupportAdmin then mempty else renderNewLeaveRequestAction
            , appPageWidthClass = ""
            , appPageBody = leaveRequestsPanel
            })
     in [hsx|
        <section id={leaveRequestsShellId}
                 data-live-update-owner="true"
                 data-live-update-feature="leave-requests"
                 data-live-updates-path="/live-updates"
                 data-live-update-content-url={pathTo ShowLeaveRequestsContentFragmentAction}
                 data-live-update-client-enabled={isJust liveUpdateScope}
                 data-live-update-client-id=""
                 data-live-update-scope-kind={liveUpdateScopeKind <$> liveUpdateScope}
                 data-live-update-venue-id={liveUpdateVenueId <$> liveUpdateScope}>
            {page}
        </section>
    |]

renderNewLeaveRequestAction :: Html
renderNewLeaveRequestAction = [hsx|
    <a href={pathTo NewLeaveRequestAction}
       class="btn btn-primary"
       data-disable-javascript-submission="true"
       hx-get={pathTo NewLeaveRequestAction}
       hx-target={"#" <> dialogOverlayMountId}
       hx-swap="innerHTML"
       hx-push-url="false">
        New Request
    </a>
|]

renderLeaveRequestsContentFragment :: (?context :: ControllerContext) => [LeaveRequest] -> [Staff] -> Maybe UUID -> Day -> Html
renderLeaveRequestsContentFragment =
    renderLeaveRequestsContentFragmentWithSwap Nothing

renderLeaveRequestsContentFragmentOob :: (?context :: ControllerContext) => [LeaveRequest] -> [Staff] -> Maybe UUID -> Day -> Html
renderLeaveRequestsContentFragmentOob =
    renderLeaveRequestsContentFragmentWithSwap (Just "outerHTML")

renderLeaveRequestsContentFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> [LeaveRequest] -> [Staff] -> Maybe UUID -> Day -> Html
renderLeaveRequestsContentFragmentWithSwap maybeSwapOob leaveRequests staffMembers currentViewerStaffId today = [hsx|
    <div id={leaveRequestsContentFragmentId} hx-swap-oob={maybeSwapOob}>
        {if currentUserIsManager
            then renderManagerLeaveRequests leaveRequests staffMembers currentViewerStaffId today
            else if null leaveRequests
                then renderEmptyState
                else renderLeaveRequestsTable leaveRequests staffMembers currentViewerStaffId
        }
    </div>
|]

renderEmptyState :: Html
renderEmptyState = [hsx|<p class="app-muted mb-0">No leave requests yet.</p>|]

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

renderManagerLeaveRequests :: (?context :: ControllerContext) => [LeaveRequest] -> [Staff] -> Maybe UUID -> Day -> Html
renderManagerLeaveRequests leaveRequests staffMembers currentViewerStaffId today = [hsx|
    <div class="accordion leave-request-accordion" id="leave-request-manager-sections">
        {renderManagerSection "leave-pending" "Pending" pendingRequests staffMembers currentViewerStaffId True}
        {renderManagerSection "leave-approved" "Approved" approvedRequests staffMembers currentViewerStaffId False}
        {renderManagerSection "leave-denied" "Denied" deniedRequests staffMembers currentViewerStaffId False}
        {renderManagerSection "leave-archive" "Archive" archivedRequests staffMembers currentViewerStaffId False}
    </div>
|]
    where
        activeRequests = filter (not . leaveRequestIsArchived today) leaveRequests
        archivedRequests = sortOn (Down . (.endDate)) (filter (leaveRequestIsArchived today) leaveRequests)
        pendingRequests = sortOn (Down . (.startDate)) (filter ((== Just LeavePending) . parseLeaveRequestStatus . (.status)) activeRequests)
        approvedRequests = sortOn (Down . (.startDate)) (filter ((== Just LeaveApproved) . parseLeaveRequestStatus . (.status)) activeRequests)
        deniedRequests = sortOn (Down . (.startDate)) (filter ((== Just LeaveDenied) . parseLeaveRequestStatus . (.status)) activeRequests)

leaveRequestIsArchived :: Day -> LeaveRequest -> Bool
leaveRequestIsArchived today leaveRequest =
    leaveRequest.endDate < today

renderManagerSection :: (?context :: ControllerContext) => Text -> Text -> [LeaveRequest] -> [Staff] -> Maybe UUID -> Bool -> Html
renderManagerSection sectionId title requests staffMembers currentViewerStaffId isOpen = [hsx|
    <div class="accordion-item app-panel mb-3 leave-request-section">
        <h2 class="accordion-header" id={sectionId <> "-heading"}>
            <button
                class={accordionButtonClass isOpen}
                type="button"
                data-bs-toggle="collapse"
                data-bs-target={"#" <> sectionId <> "-collapse"}
                aria-expanded={if isOpen then ("true" :: Text) else "false"}
                aria-controls={sectionId <> "-collapse"}
            >
                <span class="leave-request-accordion-title">{title <> " (" <> tshow (length requests) <> ")"}</span>
            </button>
        </h2>
        <div
            id={sectionId <> "-collapse"}
            class={accordionCollapseClass isOpen}
            aria-labelledby={sectionId <> "-heading"}
            data-bs-parent="#leave-request-manager-sections"
        >
            <div class="accordion-body">
                {sectionBody}
            </div>
        </div>
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
                            <div>Actions</div>
                        </div>
                        <div class="leave-request-list-body">
                            {forEach requests (renderManagerLeaveRequestRow staffMembers currentViewerStaffId)}
                        </div>
                    </div>
                |]

renderManagerLeaveRequestRow :: (?context :: ControllerContext) => [Staff] -> Maybe UUID -> LeaveRequest -> Html
renderManagerLeaveRequestRow staffMembers currentViewerStaffId leaveRequest = [hsx|
    <article class="leave-request-row">
        <div class="leave-request-row-staff">
            <div class="leave-request-row-name">{resolveStaffName leaveRequest.staffId staffMembers}</div>
            <div class="leave-request-row-status">{renderStatusBadge leaveRequest.status}</div>
        </div>
        <div class="leave-request-row-dates">{renderDateRangeText leaveRequest}</div>
        <div class="leave-request-row-notes">{fromMaybe "No notes" (leaveRequest.notes >>= nonEmptyText)}</div>
        <div class="leave-request-row-actions">{renderActions currentViewerStaffId leaveRequest}</div>
    </article>
|]

accordionButtonClass :: Bool -> Text
accordionButtonClass isOpen =
    if isOpen
        then "accordion-button"
        else "accordion-button collapsed"

accordionCollapseClass :: Bool -> Text
accordionCollapseClass isOpen =
    if isOpen
        then "accordion-collapse collapse show"
        else "accordion-collapse collapse"

nonEmptyText :: Text -> Maybe Text
nonEmptyText text =
    let trimmed = Text.strip text
     in if trimmed == ""
            then Nothing
            else Just trimmed

renderDateRangeText :: LeaveRequest -> Text
renderDateRangeText leaveRequest =
    renderShortDate leaveRequest.startDate <> " to " <> renderShortDate leaveRequest.endDate

renderShortDate :: Day -> Text
renderShortDate day =
    cs (formatTime defaultTimeLocale "%d/%m/%y" day)

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
        Just LeaveApproved -> [hsx|<span class="badge bg-success">Approved</span>|]
        Just LeaveDenied -> [hsx|<span class="badge bg-danger">Denied</span>|]
        _ -> [hsx|<span class="badge bg-warning text-dark">Pending</span>|]

renderActions :: (?context :: ControllerContext) => Maybe UUID -> LeaveRequest -> Html
renderActions currentViewerStaffId leaveRequest = [hsx|
    {renderReviewActions leaveRequest}
    {renderDeleteAction currentViewerStaffId leaveRequest}
|]

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

renderDeleteAction :: (?context :: ControllerContext) => Maybe UUID -> LeaveRequest -> Html
renderDeleteAction currentViewerStaffId leaveRequest =
    if canDelete
        then [hsx|
            <form method="POST"
                  action={DeleteLeaveRequestAction leaveRequest.id}
                  class="d-inline"
                  hx-delete={DeleteLeaveRequestAction leaveRequest.id}
                  hx-target={"#" <> leaveRequestsContentFragmentId}
                  hx-swap="outerHTML"
                  hx-push-url="false">
                <input type="hidden" name="_method" value="DELETE"/>
                <button type="submit" class="btn btn-sm btn-outline-danger">Delete</button>
            </form>
        |]
        else mempty
    where
        canDelete =
            leaveRequestCanBeDeleted leaveRequest
                && (currentUserIsManager || isCurrentUsersLeaveRequest currentViewerStaffId leaveRequest)

isCurrentUsersLeaveRequest :: Maybe UUID -> LeaveRequest -> Bool
isCurrentUsersLeaveRequest currentViewerStaffId leaveRequest =
    maybe False (== leaveRequest.staffId) currentViewerStaffId

liveUpdateScopeKind :: LiveUpdateScope -> Text
liveUpdateScopeKind LeaveRequestsScope {}     = "leave_requests"
liveUpdateScopeKind RosterWeekScope {}        = "roster_week"
liveUpdateScopeKind RosterGroupConfigScope {} = "roster_group_config"
liveUpdateScopeKind AdminSlotNamesScope {}    = "admin_slot_names"
liveUpdateScopeKind AdminInvitesScope {}      = "admin_invites"
liveUpdateScopeKind TimesheetWeekScope {}     = "timesheet_week"

liveUpdateVenueId :: LiveUpdateScope -> Text
liveUpdateVenueId LeaveRequestsScope { venueId }     = tshow venueId
liveUpdateVenueId RosterWeekScope { venueId }        = tshow venueId
liveUpdateVenueId RosterGroupConfigScope { venueId } = tshow venueId
liveUpdateVenueId AdminSlotNamesScope { venueId }    = tshow venueId
liveUpdateVenueId AdminInvitesScope { venueId }      = tshow venueId
liveUpdateVenueId TimesheetWeekScope { venueId }     = tshow venueId
