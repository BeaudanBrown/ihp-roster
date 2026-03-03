module Application.Helper.View where

import qualified Data.Text as Text
import Generated.Types
import IHP.ViewPrelude
import Web.Routes ()
import Web.Types

dialogOverlayMountId :: Text
dialogOverlayMountId = "dialog-overlay-mount"

htmxModalMountId :: Text
htmxModalMountId = dialogOverlayMountId

toastOverlayMountId :: Text
toastOverlayMountId = "toast-overlay-mount"

data OverlayFormMode
    = HtmxOverlayForm
    | PageOverlayForm

data OverlayButtonAction
    = OverlayCloseAction
    | OverlaySubmitFormAction !Text
    | OverlayNavigateAction !Text

data OverlayButton = OverlayButton
    { overlayButtonLabel :: !Text
    , overlayButtonClass :: !Text
    , overlayButtonAction :: !OverlayButtonAction
    }

data DialogOverlayConfig = DialogOverlayConfig
    { dialogOverlayTitle :: !Text
    , dialogOverlayBody :: !Html
    , dialogOverlayButtons :: ![OverlayButton]
    , dialogOverlayDialogClass :: !Text
    }

data ToastOverlayConfig = ToastOverlayConfig
    { toastOverlayTitle :: !(Maybe Text)
    , toastOverlayMessage :: !Text
    , toastOverlayClass :: !Text
    , toastOverlayAutoHideMs :: !Int
    }

data ToastOverlayPosition
    = ToastBottomLeft
    | ToastBottomCenter
    | ToastBottomRight
    deriving (Eq)

data PartialNavigationLink = PartialNavigationLink
    { partialNavigationLabel :: !Text
    , partialNavigationUrl :: !Text
    , partialNavigationTargetId :: !Text
    , partialNavigationSelectId :: !(Maybe Text)
    , partialNavigationClass :: !Text
    , partialNavigationSwap :: !Text
    , partialNavigationSync :: !(Maybe Text)
    , partialNavigationPushUrl :: !Bool
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

renderPartialNavigationLink :: PartialNavigationLink -> Html
renderPartialNavigationLink PartialNavigationLink { partialNavigationLabel, partialNavigationUrl, partialNavigationTargetId, partialNavigationSelectId, partialNavigationClass, partialNavigationSwap, partialNavigationSync, partialNavigationPushUrl } = [hsx|
    <a href={partialNavigationUrl}
       class={partialNavigationClass}
       data-turbolinks="false"
       hx-get={partialNavigationUrl}
       hx-target={"#" <> partialNavigationTargetId}
       hx-swap={partialNavigationSwap}
       hx-select={fmap ("#" <>) partialNavigationSelectId}
       hx-push-url={pushUrlValue}
       hx-sync={partialNavigationSync}>
        {partialNavigationLabel}
    </a>
|]
    where
        pushUrlValue :: Text
        pushUrlValue = if partialNavigationPushUrl then "true" else "false"

renderToastOverlayHost :: ToastOverlayPosition -> [ToastOverlayConfig] -> Html
renderToastOverlayHost position toasts = [hsx|
    <div id={toastOverlayMountId} class={toastOverlayHostClass position}>
        {forEach toasts renderToastOverlay}
    </div>
|]

renderToastOverlayHostOob :: ToastOverlayPosition -> [ToastOverlayConfig] -> Html
renderToastOverlayHostOob position toasts = [hsx|
    <div id={toastOverlayMountId} class={toastOverlayHostClass position} hx-swap-oob="innerHTML">
        {forEach toasts renderToastOverlay}
    </div>
|]

toastOverlayHostClass :: ToastOverlayPosition -> Text
toastOverlayHostClass position =
    classes
        [ ("app-toast-host", True)
        , ("app-toast-host-left", position == ToastBottomLeft)
        , ("app-toast-host-center", position == ToastBottomCenter)
        , ("app-toast-host-right", position == ToastBottomRight)
        ]

renderToastOverlay :: ToastOverlayConfig -> Html
renderToastOverlay toast = [hsx|
    <div class={classes [("app-toast", True), (toast.toastOverlayClass, True)]}
         data-overlay-toast="true"
         data-auto-hide-ms={tshow toast.toastOverlayAutoHideMs}>
        <div class="app-toast-body">
            {renderToastCopy toast}
            <button type="button"
                    class="btn-close btn-close-white app-toast-close"
                    aria-label="Dismiss"
                    data-toast-close="true"></button>
        </div>
    </div>
|]

renderToastCopy :: ToastOverlayConfig -> Html
renderToastCopy toast =
    case toast.toastOverlayTitle of
        Nothing -> [hsx|<span>{toast.toastOverlayMessage}</span>|]
        Just title -> [hsx|
            <div>
                <div class="app-toast-title">{title}</div>
                <div>{toast.toastOverlayMessage}</div>
            </div>
        |]
