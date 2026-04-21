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

data OverlayButton = OverlayButton
    { overlayButtonLabel  :: !Text
    , overlayButtonClass  :: !Text
    , overlayButtonAction :: !OverlayButtonAction
    }

data DialogOverlayConfig = DialogOverlayConfig
    { dialogOverlayTitle       :: !Text
    , dialogOverlayBody        :: !Html
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
renderDialogOverlay DialogOverlayConfig { dialogOverlayTitle, dialogOverlayBody, dialogOverlayButtons, dialogOverlayDialogClass } = [hsx|
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
                {renderDialogOverlayFooter dialogOverlayButtons}
            </div>
        </div>
    </div>
    <div class="modal-backdrop fade show" data-dialog-overlay-backdrop="true"></div>
|]

renderDialogOverlayFooter :: [OverlayButton] -> Html
renderDialogOverlayFooter buttons
    | null buttons = mempty
    | otherwise = [hsx|
        <div class="modal-footer">
            {forEach buttons renderDialogOverlayButton}
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

renderPageDialogModal :: Text -> DialogOverlayConfig -> Html
renderPageDialogModal closeUrl DialogOverlayConfig { dialogOverlayTitle, dialogOverlayBody, dialogOverlayButtons } =
    renderModal Modal
        { modalTitle = dialogOverlayTitle
        , modalCloseUrl = closeUrl
        , modalFooter = Just (renderPageDialogFooter closeUrl dialogOverlayButtons)
        , modalContent = dialogOverlayBody
        }

renderPageDialogFooter :: Text -> [OverlayButton] -> Html
renderPageDialogFooter closeUrl buttons
    | null buttons = mempty
    | otherwise = [hsx|
        <div class="modal-footer">
            {forEach buttons (renderPageDialogButton closeUrl)}
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
