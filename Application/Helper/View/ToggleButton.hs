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
    , surfaceToggleListItemField
    , surfaceToggleScalarField
    , toggleBreakRegion
    ) where

import Application.Helper.FrontendContract.Toggle.Runtime
import qualified Data.Text as Text
import IHP.ViewPrelude
import Text.Blaze (toValue, (!))
import qualified Text.Blaze.Html as Blaze
import qualified Text.Blaze.Html5 as Html5
import Text.Blaze.Internal (customAttribute, textTag)

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
    applyAttributes
        (Html5.label $ do
            renderAppToggleTransport config
            renderAppToggleInput config
            renderAppToggleLabel appToggleChecked appToggleLabel)
        [ attr "class" (appToggleButtonClasses config)
        , attr "for" appToggleInputId
        , attr toggleDom.toggleRootAttribute transportKey
        , attr "aria-pressed" (boolAttr appToggleChecked)
        ]
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
    applyAttributes
        (Html5.span label)
        [ attr canonicalToggleDomAttributes.toggleLabelStateAttribute (togglePresentationStateValue state)
        , hiddenAttr (not visible)
        ]

renderAppToggleTransport :: AppToggleButtonConfig -> Html
renderAppToggleTransport AppToggleButtonConfig { appToggleInputId, appToggleFieldBinding, appToggleChecked } =
    applyAttributes
        Html5.input
        [ attr "type" "hidden"
        , attr "name" (toggleFieldName appToggleFieldBinding)
        , attr "value" transportValue
        , attr canonicalToggleDomAttributes.toggleTransportAttribute (toggleTransportKey appToggleInputId)
        , disabledAttr transportOmitted
        ]
  where
    target = toggleTargetForState appToggleFieldBinding (togglePresentationState appToggleChecked)
    (transportValue, transportOmitted) = case target of
        ToggleTargetValue value -> (value, False)
        ToggleTargetOmitted     -> ("", True)

renderAppToggleInput :: AppToggleButtonConfig -> Html
renderAppToggleInput config@AppToggleButtonConfig { .. } =
    applyAttributes
        Html5.input
        [ attr "id" appToggleInputId
        , attr "class" (appToggleInputClasses config)
        , attr "type" "checkbox"
        , maybeAttr "role" (switchRoleAttr appToggleRoleSwitch)
        , maybeAttr "aria-checked" (switchAriaCheckedAttr appToggleRoleSwitch appToggleChecked)
        , maybeAttr "aria-controls" (toggleBreakRegionId <$> appToggleBreakRegion)
        , checkedAttr appToggleChecked
        , attr canonicalToggleDomAttributes.toggleInputAttribute (toggleTransportKey appToggleInputId)
        , attr canonicalToggleDomAttributes.toggleConfigAttribute
            (toggleConfigJson appToggleInputId appToggleFieldBinding appToggleChecked appToggleSubmitPolicy appToggleBreakRegion)
        ]

-- | Render the native fieldset controlled by a toggle. The generated opaque key
-- is the browser relationship; the id is retained only for aria-controls.
renderAppToggleBreakRegion :: ToggleBreakRegion -> Bool -> Text -> Html -> Html
renderAppToggleBreakRegion region enabled className body =
    applyAttributes
        (Html5.fieldset body)
        [ attr "id" (toggleBreakRegionId region)
        , attr "class" className
        , attr canonicalToggleDomAttributes.toggleBreakRegionAttribute (toggleBreakRegionKey region)
        , disabledAttr (not enabled)
        , attr "aria-disabled" (boolAttr (not enabled))
        ]

applyAttributes :: Blaze.Html -> [Blaze.Attribute] -> Blaze.Html
applyAttributes = foldl' (!)

attr :: Text -> Text -> Blaze.Attribute
attr name value = customAttribute (textTag name) (toValue value)

maybeAttr :: Text -> Maybe Text -> Blaze.Attribute
maybeAttr _ Nothing         = mempty
maybeAttr name (Just value) = attr name value

checkedAttr :: Bool -> Blaze.Attribute
checkedAttr True  = attr "checked" "checked"
checkedAttr False = mempty

disabledAttr :: Bool -> Blaze.Attribute
disabledAttr True  = attr "disabled" "disabled"
disabledAttr False = mempty

hiddenAttr :: Bool -> Blaze.Attribute
hiddenAttr True  = attr "hidden" "hidden"
hiddenAttr False = mempty

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
