module Application.Helper.View.Toast where

import Application.Helper.ControllerContext (currentImpersonationReturnFallbackVisible)
import Application.Helper.FrontendContract.Overlay.Runtime
import Application.Helper.Impersonation (impersonationReturnFallbackMessage)
import Application.Helper.View.Oob
import Generated.Types
import IHP.ControllerSupport (ControllerContext)
import IHP.ViewPrelude
import Network.Wai.Middleware.FlashMessages (FlashMessage (..))
import Web.Routes ()

toastOverlayMountId :: Text
toastOverlayMountId = canonicalOverlayDom.overlayToastMountId

data ToastOverlayConfig = ToastOverlayConfig
    { toastOverlayTitle      :: !(Maybe Text)
    , toastOverlayMessage    :: !Text
    , toastOverlayClass      :: !Text
    , toastOverlayAutoHideMs :: !Int
    }

data ToastOverlayPosition
    = ToastBottomLeft
    | ToastBottomCenter
    | ToastBottomRight
    deriving (Eq)

renderToastOverlayHost :: ToastOverlayPosition -> [ToastOverlayConfig] -> Html
renderToastOverlayHost =
    renderToastOverlayHostWith noOobSwap

renderToastOverlayHostOob :: ToastOverlayPosition -> [ToastOverlayConfig] -> Html
renderToastOverlayHostOob =
    renderToastOverlayHostWith innerHtmlOobSwap

renderToastOverlayHostWith :: OobSwapAttr -> ToastOverlayPosition -> [ToastOverlayConfig] -> Html
renderToastOverlayHostWith maybeOobSwap position toasts = [hsx|
    <div id={toastOverlayMountId} class={toastOverlayHostClass position} hx-swap-oob={maybeOobSwap}>
        {forEach toasts renderToastOverlay}
    </div>
|]

renderToastOob :: ToastOverlayPosition -> ToastOverlayConfig -> Html
renderToastOob position toast =
    renderToastOverlayHostOob position [toast]

successToast :: Text -> ToastOverlayConfig
successToast message =
    ToastOverlayConfig
        { toastOverlayTitle = Just "Success"
        , toastOverlayMessage = message
        , toastOverlayClass = "app-toast-success"
        , toastOverlayAutoHideMs = 3200
        }

errorToast :: Text -> ToastOverlayConfig
errorToast message =
    ToastOverlayConfig
        { toastOverlayTitle = Just "Error"
        , toastOverlayMessage = message
        , toastOverlayClass = "app-toast-error"
        , toastOverlayAutoHideMs = 4200
        }

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
         {...toastMountAttrs toast.toastOverlayAutoHideMs}>
        <div class="app-toast-body">
            {renderToastCopy toast}
            <button type="button"
                    class="btn-close btn-close-white app-toast-close"
                    aria-label="Dismiss"
                    {...toastCloseAttrs}></button>
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

renderFlashOverlayToasts :: (?context :: ControllerContext, ?request :: Request) => Html
renderFlashOverlayToasts =
    renderToastOverlayHost ToastBottomCenter
        ( map flashMessageToToast (requestFlashMessages ?request)
            <> [errorToast impersonationReturnFallbackMessage | currentImpersonationReturnFallbackVisible]
        )

flashMessageToToast :: FlashMessage -> ToastOverlayConfig
flashMessageToToast = \case
    SuccessFlashMessage message ->
        ToastOverlayConfig
            { toastOverlayTitle = Just "Success"
            , toastOverlayMessage = message
            , toastOverlayClass = "app-toast-success"
            , toastOverlayAutoHideMs = 3200
            }
    ErrorFlashMessage message ->
        ToastOverlayConfig
            { toastOverlayTitle = Just "Error"
            , toastOverlayMessage = message
            , toastOverlayClass = "app-toast-error"
            , toastOverlayAutoHideMs = 4200
            }
