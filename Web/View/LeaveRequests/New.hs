{-# LANGUAGE TypeApplications #-}

module Web.View.LeaveRequests.New where

import Application.Helper.FrontendContract.AppShell (CreateLeaveRequestOverlay)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             appShellActionByMarker,
                                                             defaultAppShellActionRoute,
                                                             renderAppShellActionForm)
import Web.View.Prelude

newtype NewView = NewView
    { leaveRequest :: LeaveRequest
    }

instance View NewView where
    html NewView { .. } =
        renderPageDialogModal
            (pathTo LeaveRequestsAction)
            DialogOverlayConfig
                { dialogOverlayTitle = "Add Unavailable Time"
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
        { dialogOverlayTitle = "Add Unavailable Time"
        , dialogOverlayBody = renderLeaveRequestForm HtmxOverlayForm leaveRequest
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons = defaultOverlayButtons leaveRequestFormId
        , dialogOverlayDialogClass = ""
        }

renderLeaveRequestForm :: OverlayFormMode -> LeaveRequest -> Html
renderLeaveRequestForm formMode leaveRequest =
    case formMode of
        HtmxOverlayForm ->
            renderAppShellActionForm
                (appShellActionByMarker @CreateLeaveRequestOverlay)
                ((defaultAppShellActionRoute (pathTo CreateLeaveRequestAction))
                    { appShellActionRouteExtraAttrs = [ ("id", leaveRequestFormId)
                        , ("class", "mt-3")

                        ]
                    })
                (renderLeaveRequestFormFields leaveRequest)
        PageOverlayForm -> [hsx|
            <form id={leaveRequestFormId}
                  method="POST"
                  action={CreateLeaveRequestAction}
                  class="mt-3">
                {renderLeaveRequestFormFields leaveRequest}
            </form>
        |]

data LeaveRequestFieldNames = LeaveRequestFieldNames
    { leaveRequestStartDateFieldName :: Text
    , leaveRequestEndDateFieldName   :: Text
    , leaveRequestNotesFieldName     :: Text
    }

renderLeaveRequestFormFields :: LeaveRequest -> Html
renderLeaveRequestFormFields =
    renderLeaveRequestFormFieldsWithNames
        LeaveRequestFieldNames
            { leaveRequestStartDateFieldName = "startDate"
            , leaveRequestEndDateFieldName = "endDate"
            , leaveRequestNotesFieldName = "notes"
            }

renderLeaveRequestFormFieldsWithNames :: LeaveRequestFieldNames -> LeaveRequest -> Html
renderLeaveRequestFormFieldsWithNames fieldNames leaveRequest = [hsx|
    <div class="app-form-width">
        <div class="mb-3">
            <label for="startDate" class="form-label">Unavailable From</label>
            <input
                id="startDate"
                name={fieldNames.leaveRequestStartDateFieldName}
                type="date"
                class={classes [("form-control", True), ("is-invalid", leaveHasErrorFor leaveRequest fieldNames.leaveRequestStartDateFieldName)]}
                value={tshow leaveRequest.startDate}
                required="required"
            />
            {renderLeaveFieldError leaveRequest fieldNames.leaveRequestStartDateFieldName}
        </div>

        <div class="mb-3">
            <label for="endDate" class="form-label">Available Again</label>
            <input
                id="endDate"
                name={fieldNames.leaveRequestEndDateFieldName}
                type="date"
                class={classes [("form-control", True), ("is-invalid", leaveHasErrorFor leaveRequest fieldNames.leaveRequestEndDateFieldName)]}
                value={tshow leaveRequest.endDate}
                required="required"
            />
            <div class="form-text">Available again must be at least one day after unavailable from.</div>
            {renderLeaveFieldError leaveRequest fieldNames.leaveRequestEndDateFieldName}
        </div>

        <div class="mb-3">
            <label for="notes" class="form-label">Notes</label>
            <textarea
                id="notes"
                name={fieldNames.leaveRequestNotesFieldName}
                rows="3"
                class={classes [("form-control", True), ("is-invalid", leaveHasErrorFor leaveRequest fieldNames.leaveRequestNotesFieldName)]}
            >{fromMaybe "" leaveRequest.notes}</textarea>
            {renderLeaveFieldError leaveRequest fieldNames.leaveRequestNotesFieldName}
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
