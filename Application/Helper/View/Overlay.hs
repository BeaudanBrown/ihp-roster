{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

module Application.Helper.View.Overlay
    ( DialogOverlayConfig (..)
    , OverlayButton (..)
    , OverlayButtonAction (..)
    , OverlayFormMode (..)
    , defaultOverlayButtons
    , dialogOverlayMountId
    , renderDialogOverlay
    , renderKeyboardDialogOverlay
    , renderDialogOverlayBodyOnly
    , renderDialogOverlayWithCloseRole
    , renderPageDialogModal
    ) where

import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             AppShellFieldValue (..),
                                                             renderAppShellActionForm)
import Application.Helper.FrontendContract.IR (AppShellActionIR)
import Application.Helper.FrontendContract.Overlay.Runtime
import Application.Helper.FrontendContract.Values (domAttrValue)
import qualified Data.Text as Text
import Data.Typeable (Typeable)
import Generated.Types
import IHP.ViewPrelude
import Web.Routes ()
import Web.Types

dialogOverlayMountId :: Text
dialogOverlayMountId = canonicalOverlayDom.overlayDialogMountId

data OverlayFormMode
    = HtmxOverlayForm
    | PageOverlayForm

data OverlayButtonAction
    = OverlayCloseAction
    | OverlaySubmitFormAction !Text
    | OverlaySubmitFormLoadingAction !Text !Text
    | OverlayNavigateAction !Text
    | DialogFormAction !Text !Text ![(Text, Text)] !(Maybe Text)
    | DialogNavigationLoadingFormAction !Text !Text ![(Text, Text)] !(Maybe Text) !Text !Text
    | GeneratedDialogFormAction !AppShellActionIR !AppShellActionRoute ![(Text, Text)] !(Maybe Text)

data OverlayButton = OverlayButton
    { overlayButtonLabel  :: !Text
    , overlayButtonClass  :: !Text
    , overlayButtonAction :: !OverlayButtonAction
    }

data DialogOverlayConfig = DialogOverlayConfig
    { dialogOverlayTitle        :: !Text
    , dialogOverlayBody         :: !Html
    , dialogOverlayStartButtons :: ![OverlayButton]
    , dialogOverlayButtons      :: ![OverlayButton]
    , dialogOverlayDialogClass  :: !Text
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
renderDialogOverlay = renderDialogOverlayWithOptions [] False

renderKeyboardDialogOverlay :: DialogOverlayConfig -> Html
renderKeyboardDialogOverlay = renderDialogOverlayWithOptions [] True

renderDialogOverlayWithCloseRole :: forall marker. Typeable marker => DialogOverlayConfig -> Html
renderDialogOverlayWithCloseRole =
    renderDialogOverlayWithOptions [(domAttrValue @marker, "true")] False

renderDialogOverlayWithOptions :: [(Text, Text)] -> Bool -> DialogOverlayConfig -> Html
renderDialogOverlayWithOptions closeAttrs keyboardEnabled DialogOverlayConfig { dialogOverlayTitle, dialogOverlayBody, dialogOverlayStartButtons, dialogOverlayButtons, dialogOverlayDialogClass } = [hsx|
    <div class="modal fade show d-block"
         {...dialogMountAttrs <> if keyboardEnabled then dialogKeyboardAttrs else []}
         tabindex="-1"
         role="dialog"
         aria-modal="true"
         aria-labelledby="dialog-overlay-title">
        <div class={classes [("modal-dialog", True), ("modal-dialog-centered", True), (dialogOverlayDialogClass, not (Text.null dialogOverlayDialogClass))]}
             role="document">
            <div class="modal-content shadow">
                <div class="modal-header">
                    <h5 class="modal-title" id="dialog-overlay-title">{dialogOverlayTitle}</h5>
                    <button type="button" class="btn-close" aria-label="Close" {...dialogCloseAttrs <> closeAttrs}></button>
                </div>
                <div class="modal-body" {...if keyboardEnabled then dialogFocusRegionAttrs else []}>{dialogOverlayBody}</div>
                {renderDialogOverlayFooter dialogOverlayStartButtons dialogOverlayButtons}
            </div>
        </div>
    </div>
    <div class="modal-backdrop fade show" {...dialogBackdropAttrs}></div>
|]

renderDialogOverlayBodyOnly :: Text -> Text -> Html -> Html
renderDialogOverlayBodyOnly ariaLabel dialogOverlayDialogClass dialogOverlayBody = [hsx|
    <div class="modal fade show d-block"
         {...dialogMountAttrs}
         tabindex="-1"
         role="dialog"
         aria-modal="true"
         aria-label={ariaLabel}>
        <div class={classes [("modal-dialog", True), ("modal-dialog-centered", True), (dialogOverlayDialogClass, not (Text.null dialogOverlayDialogClass))]}
             role="document">
            <div class="modal-content shadow">
                <div class="modal-body">{dialogOverlayBody}</div>
            </div>
        </div>
    </div>
    <div class="modal-backdrop fade show" {...dialogBackdropAttrs}></div>
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
            <button type="button" class={button.overlayButtonClass} {...dialogCloseAttrs}>
                {button.overlayButtonLabel}
            </button>
        |]
        OverlaySubmitFormAction formId -> [hsx|
            <button type="submit"
                    class={button.overlayButtonClass}
                    form={formId}
                    {...dialogSubmitAttrs "Working..."}>
                {button.overlayButtonLabel}
            </button>
        |]
        OverlaySubmitFormLoadingAction formId loadingLabel -> [hsx|
            <button type="submit"
                    class={button.overlayButtonClass}
                    form={formId}
                    {...dialogSubmitAttrs loadingLabel}>
                {button.overlayButtonLabel}
            </button>
        |]
        OverlayNavigateAction targetUrl -> [hsx|
            <a href={targetUrl} class={button.overlayButtonClass}>
                {button.overlayButtonLabel}
            </a>
        |]
        DialogFormAction method targetUrl fields maybeConfirm -> [hsx|
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
        DialogNavigationLoadingFormAction method targetUrl fields maybeConfirm loadingTitle loadingMessage -> [hsx|
            <form method="POST"
                  action={targetUrl}
                  class="app-modal-footer-form"
                  onsubmit={confirmSubmitAttribute maybeConfirm}
                  {...navigationLoadingAttrs loadingTitle loadingMessage}>
                <input type="hidden" name="_method" value={method} />
                {forEach fields renderOverlayFormHiddenField}
                <button type="submit" class={button.overlayButtonClass}>
                    {button.overlayButtonLabel}
                </button>
            </form>
        |]
        GeneratedDialogFormAction appShellAction route hiddenFields _maybeConfirm ->
            renderAppShellActionForm
                appShellAction
                route
                    { appShellActionRouteFields = route.appShellActionRouteFields <> fmap AppShellFieldValue hiddenFields
                    , appShellActionRouteExtraAttrs =
                        route.appShellActionRouteExtraAttrs
                            <> [ ("class", "app-modal-footer-form")

                               ]
                    }
                [hsx|
                    <button type="submit" class={button.overlayButtonClass}>
                        {button.overlayButtonLabel}
                    </button>
                |]

renderOverlayFormHiddenField :: (Text, Text) -> Html
renderOverlayFormHiddenField (fieldName, fieldValue) = [hsx|
    <input type="hidden" name={fieldName} value={fieldValue} />
|]

renderGeneratedOverlayFormHiddenField :: AppShellFieldValue -> Html
renderGeneratedOverlayFormHiddenField (AppShellFieldValue (fieldName, fieldValue)) = [hsx|
    <input type="hidden" name={fieldName} value={fieldValue} />
|]

confirmSubmitAttribute :: Maybe Text -> Text
confirmSubmitAttribute Nothing = ""
confirmSubmitAttribute (Just message) = "return window.confirm(" <> show message <> ");"

renderPageDialogModal :: Text -> DialogOverlayConfig -> Html
renderPageDialogModal closeUrl DialogOverlayConfig { dialogOverlayTitle, dialogOverlayBody, dialogOverlayStartButtons, dialogOverlayButtons, dialogOverlayDialogClass } = [hsx|
    <div class="modal fade overflow-auto show app-page-dialog-modal"
         id="modal"
         tabindex="-1"
         role="dialog"
         aria-labelledby="modal-title"
         aria-hidden="true"
         onclick="if (event.target.id === 'modal') document.getElementById('modal-backdrop').click()">
        <div class={classes [("modal-dialog", True), (dialogOverlayDialogClass, not (Text.null dialogOverlayDialogClass))]}
             role="document"
             id="modal-inner">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 class="modal-title" id="modal-title">{dialogOverlayTitle}</h5>
                    <a href={closeUrl} class="btn-close" aria-label="Close"></a>
                </div>
                <div class="modal-body">{dialogOverlayBody}</div>
                <div class="modal-footer">{renderPageDialogFooter closeUrl dialogOverlayStartButtons dialogOverlayButtons}</div>
            </div>
        </div>
    </div>
    <a id="modal-backdrop" href={closeUrl} class="modal-backdrop fade show app-page-dialog-backdrop"></a>
|]

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
            <button type="submit"
                    class={button.overlayButtonClass}
                    form={formId}
                    {...dialogSubmitAttrs "Working..."}>
                {button.overlayButtonLabel}
            </button>
        |]
        OverlaySubmitFormLoadingAction formId loadingLabel -> [hsx|
            <button type="submit"
                    class={button.overlayButtonClass}
                    form={formId}
                    {...dialogSubmitAttrs loadingLabel}>
                {button.overlayButtonLabel}
            </button>
        |]
        OverlayNavigateAction targetUrl -> [hsx|
            <a href={targetUrl} class={button.overlayButtonClass}>
                {button.overlayButtonLabel}
            </a>
        |]
        DialogFormAction method targetUrl fields maybeConfirm -> [hsx|
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
        DialogNavigationLoadingFormAction method targetUrl fields maybeConfirm loadingTitle loadingMessage -> [hsx|
            <form method="POST"
                  action={targetUrl}
                  class="app-modal-footer-form"
                  onsubmit={confirmSubmitAttribute maybeConfirm}
                  {...navigationLoadingAttrs loadingTitle loadingMessage}>
                <input type="hidden" name="_method" value={method} />
                {forEach fields renderOverlayFormHiddenField}
                <button type="submit" class={button.overlayButtonClass}>
                    {button.overlayButtonLabel}
                </button>
            </form>
        |]
        GeneratedDialogFormAction _appShellAction route hiddenFields maybeConfirm -> [hsx|
            <form method="POST"
                  action={fromMaybe route.appShellActionRouteUrl route.appShellActionRouteStandardUrl}
                  class="app-modal-footer-form"
                  onsubmit={confirmSubmitAttribute maybeConfirm}>
                {forEach (route.appShellActionRouteFields <> fmap AppShellFieldValue hiddenFields) renderGeneratedOverlayFormHiddenField}
                <button type="submit" class={button.overlayButtonClass}>
                    {button.overlayButtonLabel}
                </button>
            </form>
        |]
