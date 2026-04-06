module Web.View.LeaveRequests.Index where

import Application.Helper.Controller (LeaveRequestStatus (..),
                                      leaveRequestCanBeDeleted,
                                      parseLeaveRequestStatus)
import Application.Helper.LiveUpdate (LiveUpdateScope (..))
import Data.Coerce (coerce)
import Web.View.Prelude

data IndexView = IndexView
    { leaveRequests        :: [LeaveRequest]
    , staffMembers         :: [Staff]
    , currentViewerStaffId :: Maybe UUID
    , liveUpdateScope      :: Maybe LiveUpdateScope
    }

leaveRequestsShellId :: Text
leaveRequestsShellId = "leave-requests-shell"

leaveRequestsContentFragmentId :: Text
leaveRequestsContentFragmentId = "leave-requests-content"

instance View IndexView where
    html IndexView { .. } = [hsx|
        <section id={leaveRequestsShellId}
                 data-live-update-owner="true"
                 data-live-update-feature="leave-requests"
                 data-live-updates-path="/live-updates"
                 data-live-update-content-url={pathTo ShowLeaveRequestsContentFragmentAction}
                 data-live-update-client-enabled={isJust liveUpdateScope}
                 data-live-update-client-id=""
                 data-live-update-scope-kind={liveUpdateScopeKind <$> liveUpdateScope}
                 data-live-update-venue-id={liveUpdateVenueId <$> liveUpdateScope}>
            <div class="d-flex justify-content-between align-items-center mb-3">
                <h1>Leave Requests</h1>
                <a href={NewLeaveRequestAction}
                   class="btn btn-primary"
                   hx-get={NewLeaveRequestAction}
                   hx-target={"#" <> dialogOverlayMountId}
                   hx-swap="innerHTML"
                   hx-push-url="false">
                    New Request
                </a>
            </div>

            {renderLeaveRequestsContentFragment leaveRequests staffMembers currentViewerStaffId}
        </section>
    |]

renderLeaveRequestsContentFragment :: (?context :: ControllerContext) => [LeaveRequest] -> [Staff] -> Maybe UUID -> Html
renderLeaveRequestsContentFragment =
    renderLeaveRequestsContentFragmentWithSwap Nothing

renderLeaveRequestsContentFragmentOob :: (?context :: ControllerContext) => [LeaveRequest] -> [Staff] -> Maybe UUID -> Html
renderLeaveRequestsContentFragmentOob =
    renderLeaveRequestsContentFragmentWithSwap (Just "outerHTML")

renderLeaveRequestsContentFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> [LeaveRequest] -> [Staff] -> Maybe UUID -> Html
renderLeaveRequestsContentFragmentWithSwap maybeSwapOob leaveRequests staffMembers currentViewerStaffId = [hsx|
    <div id={leaveRequestsContentFragmentId} hx-swap-oob={maybeSwapOob}>
        {if null leaveRequests
            then renderEmptyState
            else renderLeaveRequestsTable leaveRequests staffMembers currentViewerStaffId
        }
    </div>
|]

renderEmptyState :: Html
renderEmptyState = [hsx|
    <div class="app-panel app-form-width">
        <div class="app-panel-body">
            <p class="app-muted mb-0">No leave requests yet.</p>
        </div>
    </div>
|]

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
liveUpdateScopeKind LeaveRequestsScope {} = "leave_requests"
liveUpdateScopeKind RosterWeekScope {}    = "roster_week"
liveUpdateScopeKind RosterGroupConfigScope {} = "roster_group_config"
liveUpdateScopeKind TimesheetWeekScope {} = "timesheet_week"

liveUpdateVenueId :: LiveUpdateScope -> Text
liveUpdateVenueId LeaveRequestsScope { venueId } = tshow venueId
liveUpdateVenueId RosterWeekScope { venueId }    = tshow venueId
liveUpdateVenueId RosterGroupConfigScope { venueId } = tshow venueId
liveUpdateVenueId TimesheetWeekScope { venueId } = tshow venueId
