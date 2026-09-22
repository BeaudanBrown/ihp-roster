{-# LANGUAGE TypeApplications #-}

module Web.LeaveRequests.SelfService
    ( renderSelfServiceLeaveFormFragment
    , renderSelfServiceLeaveFormMount
    , renderSelfServiceLeaveDeleteConfirmation
    , renderSelfServiceLeaveHistory
    , renderStaffLeaveDeleteConfirmation
    , renderStaffLeaveHistory
    , renderSelfServiceLeaveHistoryFragment
    , selfServiceLeaveFormFragmentId
    , selfServiceLeaveFormId
    , renderVisibleUnavailabilityBlackouts
    , renderVisibleUnavailabilityBlackoutsFragment
    , renderVisibleUnavailabilityBlackoutsMount
    ) where

import Application.Helper.Controller (currentVenueId)
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            defaultFrontendSurfaceActionRoute,
                                                            renderFrontendSurfaceActionForm,
                                                            renderFrontendSurfaceMount)
import qualified Application.Helper.FrontendContract.Surface.Profile.Action as ProfileAction
import qualified Application.Helper.FrontendContract.Surface.SelfServiceLeave as Surface
import qualified Application.Helper.FrontendContract.Surface.SelfServiceLeave.Action as SurfaceAction
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.View.Overlay
import Web.LeaveRequests.FrontendSurface (SelfServiceLeaveScopeValue (..),
                                          selfServiceLeaveSurfaceImpl)
import Web.View.LeaveRequests.Index (renderStatusBadge)
import Web.View.LeaveRequests.New (LeaveRequestFieldNames (..),
                                   renderLeaveRequestFormFieldsWithNames)
import Web.View.Prelude

selfServiceLeaveFormFragmentId :: Text
selfServiceLeaveFormFragmentId =
    surfaceFragmentTargetId @Surface.SelfServiceLeaveSurface @Surface.SelfServiceLeaveFormFragment noSurfaceFields

selfServiceLeaveFormId :: Text
selfServiceLeaveFormId = "self-service-leave-form"

selfServiceLeaveHistoryFragmentId :: Text
selfServiceLeaveHistoryFragmentId =
    surfaceFragmentTargetId @Surface.SelfServiceLeaveSurface @Surface.SelfServiceLeaveHistoryFragment noSurfaceFields

renderSelfServiceLeaveFormMount :: (?context :: ControllerContext) => Text -> Bool -> Staff -> LeaveRequest -> [LeaveRequest] -> Html
renderSelfServiceLeaveFormMount mountKey includeHistory staff leaveRequest leaveRequests =
    renderFrontendSurfaceMount
        ( selfServiceLeaveSurfaceImpl
            mountKey
            includeHistory
            SelfServiceLeaveScopeValue
                { selfServiceLeaveVenueId = unpackId currentVenueId
                , selfServiceLeaveStaffId = unpackId staff.id
                }
        )
        ( renderVisibleUnavailabilityBlackoutsMount
            <> if includeHistory
            then [hsx|
                <div class="row g-4 align-items-start">
                    <div class="col-12 col-xl-5">
                        {renderSelfServiceLeaveFormFragment Nothing leaveRequest}
                    </div>
                    <div class="col-12 col-xl-7">
                        {renderSelfServiceLeaveHistoryFragment Nothing leaveRequests}
                    </div>
                </div>
            |]
            else renderSelfServiceLeaveFormFragment Nothing leaveRequest
        )

renderVisibleUnavailabilityBlackoutsMount :: Html
renderVisibleUnavailabilityBlackoutsMount = [hsx|
    <div id={surfaceFragmentTargetId @Surface.SelfServiceLeaveSurface @Surface.VisibleUnavailabilityBlackoutsFragment noSurfaceFields}
         class="mb-3"
         hx-get={ShowVisibleUnavailabilityBlackoutsFragmentAction}
         hx-trigger="load"
         hx-swap="outerHTML">
        <p class="small app-muted mb-0">Loading submission blackout periods…</p>
    </div>
|]

renderVisibleUnavailabilityBlackoutsFragment :: [UnavailabilityBlackout] -> Html
renderVisibleUnavailabilityBlackoutsFragment blackouts = [hsx|
    <div id={surfaceFragmentTargetId @Surface.SelfServiceLeaveSurface @Surface.VisibleUnavailabilityBlackoutsFragment noSurfaceFields} class="mb-3">
        {if null blackouts then mempty else renderVisibleUnavailabilityBlackouts blackouts}
    </div>
|]

renderVisibleUnavailabilityBlackouts :: [UnavailabilityBlackout] -> Html
renderVisibleUnavailabilityBlackouts blackouts = [hsx|
    <div class="alert alert-warning mb-0">
        <h5 class="mb-2">Unavailable submission blackout periods</h5>
        <p class="small mb-2">New unavailable time cannot overlap these inclusive dates.</p>
        <ul class="small mb-0">
            {forEach blackouts renderVisibleUnavailabilityBlackout}
        </ul>
    </div>
|]

renderVisibleUnavailabilityBlackout :: UnavailabilityBlackout -> Html
renderVisibleUnavailabilityBlackout blackout = [hsx|
    <li><strong>{formatDateDisplay blackout.startDate} – {formatDateDisplay blackout.endDate}</strong>: {blackout.reason}</li>
|]

renderSelfServiceLeaveFormFragment :: (?context :: ControllerContext) => Maybe Text -> LeaveRequest -> Html
renderSelfServiceLeaveFormFragment maybeSwapOob leaveRequest = [hsx|
    <div id={selfServiceLeaveFormFragmentId} hx-swap-oob={maybeSwapOob}>
        {renderSelfServiceLeaveForm leaveRequest}
    </div>
|]

renderSelfServiceLeaveForm :: (?context :: ControllerContext) => LeaveRequest -> Html
renderSelfServiceLeaveForm leaveRequest =
    renderFrontendSurfaceActionForm
        (SurfaceAction.createSelfServiceLeaveRequestAction fields)
        ((defaultFrontendSurfaceActionRoute (createSelfServiceLeaveRequestPath))
            { actionRouteStandardUrl = Just createSelfServiceLeaveRequestPath
            , actionRouteExtraAttrs = [("id", selfServiceLeaveFormId)]
            })
        [hsx|
            <input type="hidden" name="responseContext" value="self-service"/>
            {renderLeaveRequestFormFieldsWithNames fieldNames leaveRequest}
            <div class="d-grid mt-4 app-form-width">
                <button type="submit" class="btn btn-primary">Add unavailable time</button>
            </div>
        |]
  where
    fields =
        SurfaceAction.createSelfServiceLeaveRequestActionFields
            leaveRequest.startDate
            leaveRequest.endDate
            (fromMaybe "" leaveRequest.notes)
    fieldNames =
        LeaveRequestFieldNames
            { leaveRequestStartDateFieldName = surfaceFieldNameFrom @Surface.StartDate fields
            , leaveRequestEndDateFieldName = surfaceFieldNameFrom @Surface.EndDate fields
            , leaveRequestNotesFieldName = surfaceFieldNameFrom @Surface.Notes fields
            }

renderSelfServiceLeaveHistoryFragment :: (?context :: ControllerContext) => Maybe Text -> [LeaveRequest] -> Html
renderSelfServiceLeaveHistoryFragment maybeSwapOob leaveRequests = [hsx|
    <div id={selfServiceLeaveHistoryFragmentId} hx-swap-oob={maybeSwapOob}>
        <h5 class="mb-3">Unavailable periods</h5>
        {renderSelfServiceLeaveHistory leaveRequests}
    </div>
|]

data LeaveDeleteMode
    = SelfServiceLeaveDelete
    | StaffLeaveDelete

renderSelfServiceLeaveHistory :: (?context :: ControllerContext) => [LeaveRequest] -> Html
renderSelfServiceLeaveHistory = renderLeaveHistory SelfServiceLeaveDelete

renderStaffLeaveHistory :: (?context :: ControllerContext) => [LeaveRequest] -> Html
renderStaffLeaveHistory = renderLeaveHistory StaffLeaveDelete

renderLeaveHistory :: (?context :: ControllerContext) => LeaveDeleteMode -> [LeaveRequest] -> Html
renderLeaveHistory deleteMode leaveRequests
    | null leaveRequests =
        renderAppPanel AppPanelConfig
            { appPanelTitle = Nothing
            , appPanelDescription = Nothing
            , appPanelHasActions = False
            , appPanelActions = mempty
            , appPanelHasCustomHeader = False
            , appPanelCustomHeader = mempty
            , appPanelClass = "app-form-width"
            , appPanelBodyClass = ""
            , appPanelBody = [hsx|<p class="app-muted mb-0">No unavailable periods submitted yet.</p>|]
            }
    | otherwise = [hsx|
        <div class="leave-request-list">
            <div class="leave-request-list-head">
                <div>Dates</div>
                <div>Status</div>
                <div>Notes</div>
                <div>Actions</div>
            </div>
            <div class="leave-request-list-body">
                {forEach sortedLeaveRequests (renderLeaveRequestRow deleteMode)}
            </div>
        </div>
    |]
  where
    sortedLeaveRequests = sortOn (Down . (.startDate)) leaveRequests

renderLeaveRequestRow :: (?context :: ControllerContext) => LeaveDeleteMode -> LeaveRequest -> Html
renderLeaveRequestRow deleteMode leaveRequest = [hsx|
    <article class="leave-request-row">
        <div class="leave-request-row-dates">{renderDateRangeText leaveRequest}</div>
        <div class="leave-request-row-status">{renderStatusBadge leaveRequest.status}</div>
        <div class="leave-request-row-notes">{fromMaybe "No notes" (leaveRequest.notes >>= nonEmptyText)}</div>
        <div class="leave-request-row-actions">{renderPendingLeaveRequestDelete deleteMode leaveRequest}</div>
    </article>
|]

renderPendingLeaveRequestDelete :: (?context :: ControllerContext) => LeaveDeleteMode -> LeaveRequest -> Html
renderPendingLeaveRequestDelete deleteMode leaveRequest
    | leaveRequest.status /= LeaveRequestStatusEnumPending = mempty
    | otherwise = case deleteMode of
        SelfServiceLeaveDelete ->
            renderFrontendSurfaceActionForm
                (SurfaceAction.openSelfServiceLeaveDeleteConfirmationAction SurfaceAction.openSelfServiceLeaveDeleteConfirmationActionFields)
                (defaultFrontendSurfaceActionRoute (pathTo (ShowSelfServiceLeaveDeleteConfirmationAction leaveRequest.id)))
                deleteButton
        StaffLeaveDelete ->
            renderFrontendSurfaceActionForm
                (ProfileAction.openStaffLeaveDeleteConfirmationAction ProfileAction.openStaffLeaveDeleteConfirmationActionFields)
                (defaultFrontendSurfaceActionRoute (pathTo (ShowStaffLeaveDeleteConfirmationAction leaveRequest.id)))
                deleteButton
  where
    deleteButton = [hsx|<button type="submit" class="btn btn-sm btn-outline-danger">Delete</button>|]

renderSelfServiceLeaveDeleteConfirmation :: (?context :: ControllerContext) => LeaveRequest -> Html
renderSelfServiceLeaveDeleteConfirmation leaveRequest =
    renderLeaveDeleteConfirmation leaveRequest formId deleteForm
  where
    formId = "delete-self-service-leave-request-confirmation-form"
    deleteForm =
        renderFrontendSurfaceActionForm
            (SurfaceAction.deleteSelfServiceLeaveRequestAction SurfaceAction.deleteSelfServiceLeaveRequestActionFields)
            ((defaultFrontendSurfaceActionRoute (pathTo (DeleteSelfServiceLeaveRequestAction leaveRequest.id)))
                { actionRouteExtraAttrs = [("id", formId)]
                })
            mempty

renderStaffLeaveDeleteConfirmation :: (?context :: ControllerContext) => LeaveRequest -> Html
renderStaffLeaveDeleteConfirmation leaveRequest =
    renderLeaveDeleteConfirmation leaveRequest formId deleteForm
  where
    formId = "delete-staff-leave-request-confirmation-form"
    deleteForm =
        renderFrontendSurfaceActionForm
            (ProfileAction.deleteStaffLeaveRequestAction ProfileAction.deleteStaffLeaveRequestActionFields)
            ((defaultFrontendSurfaceActionRoute (pathTo (DeleteStaffLeaveRequestAction leaveRequest.id)))
                { actionRouteExtraAttrs = [("id", formId)]
                })
            mempty

renderLeaveDeleteConfirmation :: LeaveRequest -> Text -> Html -> Html
renderLeaveDeleteConfirmation leaveRequest formId deleteForm =
    renderConfirmationDialog
        (defaultConfirmationDialogConfig
            "Delete unavailable period?"
            [hsx|<p class="mb-0">Delete the pending unavailable period {renderDateRangeText leaveRequest}?</p>|]
            formId
            deleteForm)
            { confirmationDialogApproveLabel = "Delete"
            , confirmationDialogApproveTone = ConfirmationDanger
            , confirmationDialogLoadingLabel = "Deleting…"
            }

createSelfServiceLeaveRequestPath :: Text
createSelfServiceLeaveRequestPath =
    appendQueryParams
        (pathTo CreateLeaveRequestAction)
        [("responseContext", "self-service")]
