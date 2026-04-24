module Web.View.LeaveRequests.New where

import Web.View.Prelude

newtype NewView = NewView
    { leaveRequest :: LeaveRequest
    }

instance View NewView where
    html NewView { .. } =
        renderPageDialogModal
            (pathTo LeaveRequestsAction)
            DialogOverlayConfig
                { dialogOverlayTitle = "New Leave Request"
                , dialogOverlayBody = renderLeaveRequestForm PageOverlayForm leaveRequest
                , dialogOverlayStartButtons = []
                , dialogOverlayButtons = defaultOverlayButtons leaveRequestFormId
                , dialogOverlayDialogClass = ""
                }

leaveRequestFormId :: Text
leaveRequestFormId = "leave-request-form"

renderNewLeaveRequestDialog :: LeaveRequest -> Html
renderNewLeaveRequestDialog leaveRequest =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = "New Leave Request"
        , dialogOverlayBody = renderLeaveRequestForm HtmxOverlayForm leaveRequest
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons = defaultOverlayButtons leaveRequestFormId
        , dialogOverlayDialogClass = ""
        }

renderLeaveRequestForm :: OverlayFormMode -> LeaveRequest -> Html
renderLeaveRequestForm formMode leaveRequest =
    case formMode of
        HtmxOverlayForm -> [hsx|
            <form id={leaveRequestFormId}
                  method="POST"
                  action={CreateLeaveRequestAction}
                  class="mt-3"
                  data-disable-javascript-submission="true"
                  hx-post={CreateLeaveRequestAction}
                  hx-target={"#" <> dialogOverlayMountId}
                  hx-swap="innerHTML"
                  hx-push-url="false">
                {renderLeaveRequestFormFields leaveRequest}
            </form>
        |]
        PageOverlayForm -> [hsx|
            <form id={leaveRequestFormId}
                  method="POST"
                  action={CreateLeaveRequestAction}
                  class="mt-3">
                {renderLeaveRequestFormFields leaveRequest}
            </form>
        |]

renderLeaveRequestFormFields :: LeaveRequest -> Html
renderLeaveRequestFormFields leaveRequest = [hsx|
    <div class="app-form-width">
        <div class="mb-3">
            <label for="startDate" class="form-label">Unavailable From</label>
            <input
                id="startDate"
                name="startDate"
                type="date"
                class={classes [("form-control", True), ("is-invalid", leaveHasErrorFor leaveRequest "startDate")]}
                value={tshow leaveRequest.startDate}
                required="required"
            />
            {renderLeaveFieldError leaveRequest "startDate"}
        </div>

        <div class="mb-3">
            <label for="endDate" class="form-label">Available Again</label>
            <input
                id="endDate"
                name="endDate"
                type="date"
                class={classes [("form-control", True), ("is-invalid", leaveHasErrorFor leaveRequest "endDate")]}
                value={tshow leaveRequest.endDate}
                required="required"
            />
            <div class="form-text">Available again must be at least one day after unavailable from.</div>
            {renderLeaveFieldError leaveRequest "endDate"}
        </div>

        <div class="mb-3">
            <label for="notes" class="form-label">Notes</label>
            <textarea
                id="notes"
                name="notes"
                rows="3"
                class={classes [("form-control", True), ("is-invalid", leaveHasErrorFor leaveRequest "notes")]}
            >{fromMaybe "" leaveRequest.notes}</textarea>
            {renderLeaveFieldError leaveRequest "notes"}
        </div>
    </div>
|]

renderLeaveFieldError :: LeaveRequest -> Text -> Html
renderLeaveFieldError leaveRequest fieldName =
    case lookup fieldName leaveRequest.meta.annotations of
        Just (TextViolation msg) -> [hsx|<div class="invalid-feedback d-block">{msg}</div>|]
        Just (HtmlViolation msg) -> [hsx|<div class="invalid-feedback d-block">{msg}</div>|]
        Nothing -> mempty

leaveHasErrorFor :: LeaveRequest -> Text -> Bool
leaveHasErrorFor leaveRequest fieldName = isJust (lookup fieldName leaveRequest.meta.annotations)
