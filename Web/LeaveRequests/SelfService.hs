{-# LANGUAGE TypeApplications #-}

module Web.LeaveRequests.SelfService
    ( renderSelfServiceLeaveFormFragment
    , renderSelfServiceLeaveFormMount
    , renderSelfServiceLeaveHistory
    , renderSelfServiceLeaveHistoryFragment
    , selfServiceLeaveFormFragmentId
    , selfServiceLeaveFormId
    , renderVisibleUnavailabilityBlackouts
    , renderVisibleUnavailabilityBlackoutsFragment
    , renderVisibleUnavailabilityBlackoutsMount
    ) where

import Application.Helper.Controller (currentVenueId)
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            renderFrontendSurfaceActionForm,
                                                            renderFrontendSurfaceMount)
import qualified Application.Helper.FrontendContract.Surface.SelfServiceLeave as Surface
import qualified Application.Helper.FrontendContract.Surface.SelfServiceLeave.Action as SurfaceAction
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.Url (appendQueryParams)
import Data.List (sortOn)
import Data.Ord (Down (..))
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
        FrontendSurfaceActionRoute
            { actionRouteUrl = createSelfServiceLeaveRequestPath
            , actionRouteCustomHtmx = []
            , actionRouteStandardUrl = Just createSelfServiceLeaveRequestPath
            , actionRouteExtraAttrs = [("id", selfServiceLeaveFormId)]
            }
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

renderSelfServiceLeaveHistoryFragment :: Maybe Text -> [LeaveRequest] -> Html
renderSelfServiceLeaveHistoryFragment maybeSwapOob leaveRequests = [hsx|
    <div id={selfServiceLeaveHistoryFragmentId} hx-swap-oob={maybeSwapOob}>
        <h5 class="mb-3">Unavailable periods</h5>
        {renderSelfServiceLeaveHistory leaveRequests}
    </div>
|]

renderSelfServiceLeaveHistory :: [LeaveRequest] -> Html
renderSelfServiceLeaveHistory leaveRequests
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
            </div>
            <div class="leave-request-list-body">
                {forEach sortedLeaveRequests renderLeaveRequestRow}
            </div>
        </div>
    |]
  where
    sortedLeaveRequests = sortOn (Down . (.startDate)) leaveRequests

renderLeaveRequestRow :: LeaveRequest -> Html
renderLeaveRequestRow leaveRequest = [hsx|
    <article class="leave-request-row">
        <div class="leave-request-row-dates">{renderDateRangeText leaveRequest}</div>
        <div class="leave-request-row-status">{renderStatusBadge leaveRequest.status}</div>
        <div class="leave-request-row-notes">{fromMaybe "No notes" (leaveRequest.notes >>= nonEmptyText)}</div>
    </article>
|]

createSelfServiceLeaveRequestPath :: Text
createSelfServiceLeaveRequestPath =
    appendQueryParams
        (pathTo CreateLeaveRequestAction)
        [("responseContext", "self-service")]
