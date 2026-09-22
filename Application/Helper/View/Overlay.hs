{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE KindSignatures      #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

module Application.Helper.View.Overlay
    ( ConfirmationDialogConfig (..)
    , ConfirmationDialogTone (..)
    , DialogOverlayConfig (..)
    , OverlayButton (..)
    , OverlayButtonAction (..)
    , OverlayFormMode (..)
    , defaultConfirmationDialogConfig
    , defaultDialogOverlayConfig
    , defaultOverlayButtons
    , dialogOverlayCloseButton
    , dialogOverlayMountId
    , dialogOverlaySubmitButton
    , renderConfirmationDialog
    , renderDialogOverlay
    , renderDialogOverlayClearOob
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
import Application.Helper.FrontendContract.Values (RegisteredDomAttr,
                                                   domAttrValue)
import qualified Data.Text as Text
import IHP.ViewPrelude
import Web.Routes ()

dialogOverlayMountId :: Text
dialogOverlayMountId = canonicalOverlayDom.overlayDialogMountId

data OverlayFormMode
    = HtmxOverlayForm
    | PageOverlayForm

-- Only close navigation and generated form transport differ by rendering context.
data OverlayButtonContext
    = MountedOverlayButton
    | PageOverlayButton !Text

data OverlayButtonAction
    = OverlayCloseAction
    | OverlaySubmitFormAction !Text
    | OverlaySubmitFormLoadingAction !Text !Text
    | OverlayNavigateAction !Text
    | DialogNavigationLoadingFormAction !Text !Text ![(Text, Text)] !Text !Text
    | GeneratedDialogFormAction !AppShellActionIR !AppShellActionRoute ![(Text, Text)]

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

data ConfirmationDialogTone
    = ConfirmationPrimary
    | ConfirmationDanger
    | ConfirmationWarning
    deriving (Eq, Show)

data ConfirmationDialogConfig = ConfirmationDialogConfig
    { confirmationDialogTitle        :: !Text
    , confirmationDialogBody         :: !Html
    , confirmationDialogFormId       :: !Text
    , confirmationDialogForm         :: !Html
    , confirmationDialogApproveLabel :: !Text
    , confirmationDialogApproveTone  :: !ConfirmationDialogTone
    , confirmationDialogLoadingLabel :: !Text
    , confirmationDialogRejectButton :: !OverlayButton
    , confirmationDialogClass        :: !Text
    }

defaultConfirmationDialogConfig :: Text -> Html -> Text -> Html -> ConfirmationDialogConfig
defaultConfirmationDialogConfig title body formId form = ConfirmationDialogConfig
    { confirmationDialogTitle = title
    , confirmationDialogBody = body
    , confirmationDialogFormId = formId
    , confirmationDialogForm = form
    , confirmationDialogApproveLabel = "Confirm"
    , confirmationDialogApproveTone = ConfirmationPrimary
    , confirmationDialogLoadingLabel = "Working…"
    , confirmationDialogRejectButton = dialogOverlayCloseButton "Cancel"
    , confirmationDialogClass = ""
    }

defaultDialogOverlayConfig :: Text -> Html -> [OverlayButton] -> DialogOverlayConfig
defaultDialogOverlayConfig title body buttons = DialogOverlayConfig
    { dialogOverlayTitle = title
    , dialogOverlayBody = body
    , dialogOverlayStartButtons = []
    , dialogOverlayButtons = buttons
    , dialogOverlayDialogClass = ""
    }

dialogOverlayCloseButton :: Text -> OverlayButton
dialogOverlayCloseButton label = OverlayButton
    { overlayButtonLabel = label
    , overlayButtonClass = "btn btn-outline-secondary"
    , overlayButtonAction = OverlayCloseAction
    }

dialogOverlaySubmitButton :: Text -> Text -> OverlayButton
dialogOverlaySubmitButton label formId = OverlayButton
    { overlayButtonLabel = label
    , overlayButtonClass = "btn btn-primary"
    , overlayButtonAction = OverlaySubmitFormAction formId
    }

defaultOverlayButtons :: Text -> [OverlayButton]
defaultOverlayButtons formId =
    [ dialogOverlayCloseButton "Cancel"
    , dialogOverlaySubmitButton "Save" formId
    ]

renderConfirmationDialog :: ConfirmationDialogConfig -> Html
renderConfirmationDialog ConfirmationDialogConfig
        { confirmationDialogTitle
        , confirmationDialogBody
        , confirmationDialogFormId
        , confirmationDialogForm
        , confirmationDialogApproveLabel
        , confirmationDialogApproveTone
        , confirmationDialogLoadingLabel
        , confirmationDialogRejectButton
        , confirmationDialogClass
        } =
    renderDialogOverlayWithOptions dialogConfirmationAttrs [] False DialogOverlayConfig
        { dialogOverlayTitle = confirmationDialogTitle
        , dialogOverlayBody = confirmationDialogBody <> confirmationDialogForm
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons =
            [ confirmationDialogRejectButton
            , OverlayButton
                { overlayButtonLabel = confirmationDialogApproveLabel
                , overlayButtonClass = confirmationToneButtonClass confirmationDialogApproveTone
                , overlayButtonAction = OverlaySubmitFormLoadingAction confirmationDialogFormId confirmationDialogLoadingLabel
                }
            ]
        , dialogOverlayDialogClass = confirmationDialogClass
        }

confirmationToneButtonClass :: ConfirmationDialogTone -> Text
confirmationToneButtonClass ConfirmationPrimary = "btn btn-primary"
confirmationToneButtonClass ConfirmationDanger  = "btn btn-danger"
confirmationToneButtonClass ConfirmationWarning = "btn btn-warning"

renderDialogOverlay :: DialogOverlayConfig -> Html
renderDialogOverlay = renderDialogOverlayWithOptions [] [] False

renderDialogOverlayClearOob :: Html
renderDialogOverlayClearOob = [hsx|<div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>|]

renderKeyboardDialogOverlay :: DialogOverlayConfig -> Html
renderKeyboardDialogOverlay = renderDialogOverlayWithOptions [] [] True

renderDialogOverlayWithCloseRole :: forall (marker :: Type). (Typeable marker, RegisteredDomAttr marker) => DialogOverlayConfig -> Html
renderDialogOverlayWithCloseRole =
    renderDialogOverlayWithOptions [] [(domAttrValue @marker, "true")] False

renderDialogOverlayWithOptions :: [(Text, Text)] -> [(Text, Text)] -> Bool -> DialogOverlayConfig -> Html
renderDialogOverlayWithOptions mountAttrs closeAttrs keyboardEnabled DialogOverlayConfig { dialogOverlayTitle, dialogOverlayBody, dialogOverlayStartButtons, dialogOverlayButtons, dialogOverlayDialogClass } = [hsx|
    <div class="modal fade show d-block"
         {...dialogMountAttrs <> mountAttrs <> if keyboardEnabled then dialogKeyboardAttrs else []}
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
                {forEach startButtons (renderOverlayButton MountedOverlayButton)}
            </div>
            <div class="app-modal-footer-end">
                {forEach buttons (renderOverlayButton MountedOverlayButton)}
            </div>
        </div>
    |]

renderOverlayButton :: OverlayButtonContext -> OverlayButton -> Html
renderOverlayButton context button =
    case button.overlayButtonAction of
        OverlayCloseAction -> case context of
            MountedOverlayButton -> [hsx|
                <button type="button" class={button.overlayButtonClass} {...dialogCloseAttrs}>
                    {button.overlayButtonLabel}
                </button>
            |]
            PageOverlayButton closeUrl -> [hsx|
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
        DialogNavigationLoadingFormAction method targetUrl fields loadingTitle loadingMessage -> [hsx|
            <form method="POST"
                  action={targetUrl}
                  class="app-modal-footer-form"
                  {...navigationLoadingAttrs loadingTitle loadingMessage}>
                <input type="hidden" name="_method" value={method} />
                {forEach fields renderOverlayFormHiddenField}
                <button type="submit" class={button.overlayButtonClass}>
                    {button.overlayButtonLabel}
                </button>
            </form>
        |]
        GeneratedDialogFormAction appShellAction route hiddenFields -> case context of
            MountedOverlayButton ->
                renderAppShellActionForm
                    appShellAction
                    route
                        { appShellActionRouteFields = route.appShellActionRouteFields <> fmap AppShellFieldValue hiddenFields
                        , appShellActionRouteExtraAttrs =
                            route.appShellActionRouteExtraAttrs <> [("class", "app-modal-footer-form")]
                        }
                    [hsx|
                        <button type="submit" class={button.overlayButtonClass}>
                            {button.overlayButtonLabel}
                        </button>
                    |]
            PageOverlayButton _ -> [hsx|
                <form method="POST"
                      action={fromMaybe route.appShellActionRouteUrl route.appShellActionRouteStandardUrl}
                      class="app-modal-footer-form">
                    {forEach (route.appShellActionRouteFields <> fmap AppShellFieldValue hiddenFields) renderGeneratedOverlayFormHiddenField}
                    <button type="submit" class={button.overlayButtonClass}>
                        {button.overlayButtonLabel}
                    </button>
                </form>
            |]

renderOverlayFormHiddenField :: (Text, Text) -> Html
renderOverlayFormHiddenField (fieldName, fieldValue) = [hsx|
    <input type="hidden" name={fieldName} value={fieldValue} />
|]

renderGeneratedOverlayFormHiddenField :: AppShellFieldValue -> Html
renderGeneratedOverlayFormHiddenField (AppShellFieldValue (fieldName, fieldValue)) = [hsx|
    <input type="hidden" name={fieldName} value={fieldValue} />
|]

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
                {forEach startButtons (renderOverlayButton (PageOverlayButton closeUrl))}
            </div>
            <div class="app-modal-footer-end">
                {forEach buttons (renderOverlayButton (PageOverlayButton closeUrl))}
            </div>
        </div>
    |]
