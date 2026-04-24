module Application.Helper.View.Overlay where

import qualified Data.Text as Text
import Generated.Types
import IHP.ViewPrelude
import Web.Routes ()
import Web.Types

dialogOverlayMountId :: Text
dialogOverlayMountId = "dialog-overlay-mount"

htmxModalMountId :: Text
htmxModalMountId = dialogOverlayMountId

data OverlayFormMode
    = HtmxOverlayForm
    | PageOverlayForm

data OverlayButtonAction
    = OverlayCloseAction
    | OverlaySubmitFormAction !Text
    | OverlayNavigateAction !Text
    | OverlayFormAction !Text !Text ![(Text, Text)] !Text !(Maybe Text)

data OverlayButton = OverlayButton
    { overlayButtonLabel  :: !Text
    , overlayButtonClass  :: !Text
    , overlayButtonAction :: !OverlayButtonAction
    }

data DialogOverlayConfig = DialogOverlayConfig
    { dialogOverlayTitle       :: !Text
    , dialogOverlayBody        :: !Html
    , dialogOverlayStartButtons :: ![OverlayButton]
    , dialogOverlayButtons     :: ![OverlayButton]
    , dialogOverlayDialogClass :: !Text
    }

defaultOverlayButtons :: Text -> [OverlayButton]
defaultOverlayButtons formId =
    [ OverlayButton
        { overlayButtonLabel = "Cancel"
        , overlayButtonClass = "btn btn-outline-secondary"
        , overlayButtonAction = OverlayCloseAction
        }
    , OverlayButton
        { overlayButtonLabel = "Save"
        , overlayButtonClass = "btn btn-primary"
        , overlayButtonAction = OverlaySubmitFormAction formId
        }
    ]

renderDialogOverlay :: DialogOverlayConfig -> Html
renderDialogOverlay DialogOverlayConfig { dialogOverlayTitle, dialogOverlayBody, dialogOverlayStartButtons, dialogOverlayButtons, dialogOverlayDialogClass } = [hsx|
    <div class="modal fade show d-block"
         data-dialog-overlay="true"
         tabindex="-1"
         role="dialog"
         aria-modal="true"
         aria-labelledby="dialog-overlay-title">
        <div class={classes [("modal-dialog", True), ("modal-dialog-centered", True), (dialogOverlayDialogClass, not (Text.null dialogOverlayDialogClass))]}
             role="document">
            <div class="modal-content shadow">
                <div class="modal-header">
                    <h5 class="modal-title" id="dialog-overlay-title">{dialogOverlayTitle}</h5>
                    <button type="button" class="btn-close" aria-label="Close" data-dialog-overlay-close="true"></button>
                </div>
                <div class="modal-body">{dialogOverlayBody}</div>
                {renderDialogOverlayFooter dialogOverlayStartButtons dialogOverlayButtons}
            </div>
        </div>
    </div>
    <div class="modal-backdrop fade show" data-dialog-overlay-backdrop="true"></div>
|]

renderDialogOverlayFooter :: [OverlayButton] -> [OverlayButton] -> Html
renderDialogOverlayFooter startButtons buttons
    | null startButtons && null buttons = mempty
    | otherwise = [hsx|
        <div class="modal-footer app-modal-footer">
            <div class="app-modal-footer-start">
                {forEach startButtons renderDialogOverlayButton}
            </div>
            <div class="app-modal-footer-end">
                {forEach buttons renderDialogOverlayButton}
            </div>
        </div>
    |]

renderDialogOverlayButton :: OverlayButton -> Html
renderDialogOverlayButton button =
    case button.overlayButtonAction of
        OverlayCloseAction -> [hsx|
            <button type="button" class={button.overlayButtonClass} data-dialog-overlay-close="true">
                {button.overlayButtonLabel}
            </button>
        |]
        OverlaySubmitFormAction formId -> [hsx|
            <button type="submit" class={button.overlayButtonClass} form={formId}>
                {button.overlayButtonLabel}
            </button>
        |]
        OverlayNavigateAction targetUrl -> [hsx|
            <a href={targetUrl} class={button.overlayButtonClass}>
                {button.overlayButtonLabel}
            </a>
        |]
        OverlayFormAction method targetUrl fields hxTarget maybeConfirm -> [hsx|
            <form method="POST"
                  action={targetUrl}
                  class="app-modal-footer-form"
                  data-disable-javascript-submission="true"
                  hx-delete={targetUrl}
                  hx-target={hxTarget}
                  hx-swap="innerHTML"
                  hx-push-url="false"
                  hx-confirm={maybeConfirm}>
                <input type="hidden" name="_method" value={method} />
                {forEach fields renderOverlayFormHiddenField}
                <button type="submit" class={button.overlayButtonClass}>
                    {button.overlayButtonLabel}
                </button>
            </form>
        |]

renderOverlayFormHiddenField :: (Text, Text) -> Html
renderOverlayFormHiddenField (fieldName, fieldValue) = [hsx|
    <input type="hidden" name={fieldName} value={fieldValue} />
|]

confirmSubmitAttribute :: Maybe Text -> Text
confirmSubmitAttribute Nothing = ""
confirmSubmitAttribute (Just message) = "return window.confirm(" <> show message <> ");"

renderPageDialogModal :: Text -> DialogOverlayConfig -> Html
renderPageDialogModal closeUrl DialogOverlayConfig { dialogOverlayTitle, dialogOverlayBody, dialogOverlayStartButtons, dialogOverlayButtons } =
    renderModal Modal
        { modalTitle = dialogOverlayTitle
        , modalCloseUrl = closeUrl
        , modalFooter = Just (renderPageDialogFooter closeUrl dialogOverlayStartButtons dialogOverlayButtons)
        , modalContent = dialogOverlayBody
        }

renderPageDialogFooter :: Text -> [OverlayButton] -> [OverlayButton] -> Html
renderPageDialogFooter closeUrl startButtons buttons
    | null startButtons && null buttons = mempty
    | otherwise = [hsx|
        <div class="app-modal-footer app-modal-footer-inner">
            <div class="app-modal-footer-start">
                {forEach startButtons (renderPageDialogButton closeUrl)}
            </div>
            <div class="app-modal-footer-end">
                {forEach buttons (renderPageDialogButton closeUrl)}
            </div>
        </div>
    |]

renderPageDialogButton :: Text -> OverlayButton -> Html
renderPageDialogButton closeUrl button =
    case button.overlayButtonAction of
        OverlayCloseAction -> [hsx|
            <a href={closeUrl} class={button.overlayButtonClass}>
                {button.overlayButtonLabel}
            </a>
        |]
        OverlaySubmitFormAction formId -> [hsx|
            <button type="submit" class={button.overlayButtonClass} form={formId}>
                {button.overlayButtonLabel}
            </button>
        |]
        OverlayNavigateAction targetUrl -> [hsx|
            <a href={targetUrl} class={button.overlayButtonClass}>
                {button.overlayButtonLabel}
            </a>
        |]
        OverlayFormAction method targetUrl fields _hxTarget maybeConfirm -> [hsx|
            <form method="POST"
                  action={targetUrl}
                  class="app-modal-footer-form"
                  onsubmit={confirmSubmitAttribute maybeConfirm}>
                <input type="hidden" name="_method" value={method} />
                {forEach fields renderOverlayFormHiddenField}
                <button type="submit" class={button.overlayButtonClass}>
                    {button.overlayButtonLabel}
                </button>
            </form>
        |]
