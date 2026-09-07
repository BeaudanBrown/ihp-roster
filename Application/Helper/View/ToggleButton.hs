module Application.Helper.View.ToggleButton
    ( AppToggleButtonConfig (..)
    , AppToggleButtonLabel (..)
    , ToggleBreakRegion
    , ToggleFieldBinding
    , ToggleSubmissionPolicy (..)
    , defaultAppToggleButtonConfig
    , defaultAppToggleStateButtonConfig
    , namedBooleanToggleField
    , renderAppToggleBreakRegion
    , renderAppToggleButton
    , renderAppToggleHiddenField
    , surfaceToggleListItemField
    , surfaceToggleScalarField
    , toggleBreakRegion
    ) where

import Application.Helper.FrontendContract.Toggle.Runtime
import qualified Data.Text as Text
import IHP.ViewPrelude

data AppToggleButtonLabel
    = AppToggleStaticLabel !Html
    | AppToggleStateLabels
        { appToggleCheckedLabel   :: !Html
        , appToggleUncheckedLabel :: !Html
        }

data AppToggleButtonConfig = AppToggleButtonConfig
    { appToggleInputId      :: !Text
    , appToggleFieldBinding :: !ToggleFieldBinding
    , appToggleChecked      :: !Bool
    , appToggleLabel        :: !AppToggleButtonLabel
    , appToggleButtonClass  :: !Text
    , appToggleInputClass   :: !Text
    , appToggleRoleSwitch   :: !Bool
    , appToggleSubmitPolicy :: !ToggleSubmissionPolicy
    , appToggleBreakRegion  :: !(Maybe ToggleBreakRegion)
    }

defaultAppToggleButtonConfig :: Text -> ToggleFieldBinding -> Bool -> Html -> AppToggleButtonConfig
defaultAppToggleButtonConfig inputId fieldBinding checked label = AppToggleButtonConfig
    { appToggleInputId = inputId
    , appToggleFieldBinding = fieldBinding
    , appToggleChecked = checked
    , appToggleLabel = AppToggleStaticLabel label
    , appToggleButtonClass = ""
    , appToggleInputClass = ""
    , appToggleRoleSwitch = False
    , appToggleSubmitPolicy = ToggleSubmitDeferred
    , appToggleBreakRegion = Nothing
    }

defaultAppToggleStateButtonConfig :: Text -> ToggleFieldBinding -> Bool -> Html -> Html -> AppToggleButtonConfig
defaultAppToggleStateButtonConfig inputId fieldBinding checked checkedLabel uncheckedLabel =
    (defaultAppToggleButtonConfig inputId fieldBinding checked mempty)
        { appToggleLabel = AppToggleStateLabels { appToggleCheckedLabel = checkedLabel, appToggleUncheckedLabel = uncheckedLabel }
        }

renderAppToggleButton :: AppToggleButtonConfig -> Html
renderAppToggleButton config@AppToggleButtonConfig { .. } =
    [hsx|<label class={appToggleButtonClasses config} for={appToggleInputId} {...[(toggleDom.toggleRootAttribute, transportKey)]} aria-pressed={boolAttr appToggleChecked}>{renderAppToggleTransport config}{renderAppToggleInput config}{renderAppToggleLabel appToggleChecked appToggleLabel}</label>|]
  where
    toggleDom = canonicalToggleDomAttributes
    transportKey = toggleTransportKey appToggleInputId

renderAppToggleLabel :: Bool -> AppToggleButtonLabel -> Html
renderAppToggleLabel _ (AppToggleStaticLabel label) = label
renderAppToggleLabel checked AppToggleStateLabels { .. } =
    renderStateLabel ToggleChecked checked appToggleCheckedLabel
        <> renderStateLabel ToggleUnchecked (not checked) appToggleUncheckedLabel

renderStateLabel :: TogglePresentationState -> Bool -> Html -> Html
renderStateLabel state visible label =
    [hsx|<span {...attributes}>{label}</span>|]
  where
    attributes = [(canonicalToggleDomAttributes.toggleLabelStateAttribute, togglePresentationStateValue state)]
        <> hiddenAttr (not visible)

-- | Render a non-interactive hidden field through the same typed field mapping
-- used by toggle controls. This is for retained repeated values that have no
-- visible choice in the current form.
renderAppToggleHiddenField :: ToggleFieldBinding -> Bool -> Html
renderAppToggleHiddenField fieldBinding checked =
    case toggleTargetForState fieldBinding (togglePresentationState checked) of
        ToggleTargetValue value ->
            [hsx|<input type="hidden" name={toggleFieldName fieldBinding} value={value}/>|]
        ToggleTargetOmitted -> mempty

renderAppToggleTransport :: AppToggleButtonConfig -> Html
renderAppToggleTransport AppToggleButtonConfig { appToggleInputId, appToggleFieldBinding, appToggleChecked } =
    [hsx|<input type="hidden" name={toggleFieldName appToggleFieldBinding} value={transportValue} {...attributes}/>|]
  where
    attributes = [(canonicalToggleDomAttributes.toggleTransportAttribute, toggleTransportKey appToggleInputId)]
        <> disabledAttr transportOmitted
    target = toggleTargetForState appToggleFieldBinding (togglePresentationState appToggleChecked)
    (transportValue, transportOmitted) = case target of
        ToggleTargetValue value -> (value, False)
        ToggleTargetOmitted     -> ("", True)

renderAppToggleInput :: AppToggleButtonConfig -> Html
renderAppToggleInput config@AppToggleButtonConfig { .. } =
    [hsx|<input id={appToggleInputId} class={appToggleInputClasses config} type="checkbox" {...attributes}/>|]
  where
    attributes = maybeAttr "role" (switchRoleAttr appToggleRoleSwitch)
        <> maybeAttr "aria-checked" (switchAriaCheckedAttr appToggleRoleSwitch appToggleChecked)
        <> maybeAttr "aria-controls" (toggleBreakRegionId <$> appToggleBreakRegion)
        <> checkedAttr appToggleChecked
        <> [ (canonicalToggleDomAttributes.toggleInputAttribute, toggleTransportKey appToggleInputId)
           , (canonicalToggleDomAttributes.toggleConfigAttribute,
                toggleConfigJson appToggleInputId appToggleFieldBinding appToggleChecked appToggleSubmitPolicy appToggleBreakRegion)
           ]

-- | Render the native fieldset controlled by a toggle. The generated opaque key
-- is the browser relationship; the id is retained only for aria-controls.
renderAppToggleBreakRegion :: ToggleBreakRegion -> Bool -> Text -> Html -> Html
renderAppToggleBreakRegion region enabled className body =
    [hsx|<fieldset id={toggleBreakRegionId region} class={className} {...attributes} aria-disabled={boolAttr (not enabled)}>{body}</fieldset>|]
  where
    attributes = [(canonicalToggleDomAttributes.toggleBreakRegionAttribute, toggleBreakRegionKey region)]
        <> disabledAttr (not enabled)

maybeAttr :: Text -> Maybe Text -> [(Text, Text)]
maybeAttr _ Nothing         = []
maybeAttr name (Just value) = [(name, value)]

checkedAttr :: Bool -> [(Text, Text)]
checkedAttr True  = [("checked", "checked")]
checkedAttr False = []

disabledAttr :: Bool -> [(Text, Text)]
disabledAttr True  = [("disabled", "disabled")]
disabledAttr False = []

hiddenAttr :: Bool -> [(Text, Text)]
hiddenAttr True  = [("hidden", "hidden")]
hiddenAttr False = []

appToggleButtonClasses :: AppToggleButtonConfig -> Text
appToggleButtonClasses AppToggleButtonConfig { appToggleButtonClass } =
    classes
        [ ("btn", True)
        , ("btn-outline-success", True)
        , ("app-toggle-button", True)
        , (appToggleButtonClass, not (Text.null appToggleButtonClass))
        ]

appToggleInputClasses :: AppToggleButtonConfig -> Text
appToggleInputClasses AppToggleButtonConfig { appToggleInputClass } =
    classes
        [ ("visually-hidden", True)
        , ("app-toggle-button-input", True)
        , (appToggleInputClass, not (Text.null appToggleInputClass))
        ]

switchRoleAttr :: Bool -> Maybe Text
switchRoleAttr True  = Just "switch"
switchRoleAttr False = Nothing

switchAriaCheckedAttr :: Bool -> Bool -> Maybe Text
switchAriaCheckedAttr True checked = Just (boolAttr checked)
switchAriaCheckedAttr False _      = Nothing

boolAttr :: Bool -> Text
boolAttr True  = "true"
boolAttr False = "false"
