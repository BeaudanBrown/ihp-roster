module Application.Helper.View.ToggleButton
    ( AppToggleButtonConfig (..)
    , defaultAppToggleButtonConfig
    , renderAppToggleButton
    ) where

import qualified Data.Text as Text
import IHP.ViewPrelude
import Text.Blaze (toValue, (!))
import qualified Text.Blaze.Html as Blaze
import qualified Text.Blaze.Html5 as Html5
import Text.Blaze.Internal (customAttribute, textTag)

data AppToggleButtonConfig = AppToggleButtonConfig
    { appToggleInputId                   :: !Text
    , appToggleInputName                 :: !(Maybe Text)
    , appToggleInputValue                :: !Text
    , appToggleChecked                   :: !Bool
    , appToggleLabel                     :: !Html
    , appToggleButtonClass               :: !Text
    , appToggleInputClass                :: !Text
    , appToggleRoleSwitch                :: !Bool
    , appToggleOnChange                  :: !(Maybe Text)
    , appToggleHiddenInputId             :: !(Maybe Text)
    , appToggleHiddenInputCheckedValue   :: !(Maybe Text)
    , appToggleHiddenInputUncheckedValue :: !(Maybe Text)
    , appToggleBreakTarget               :: !(Maybe Text)
    , appToggleShiftPreferenceAvailable  :: !Bool
    , appToggleInputExtraAttrs           :: ![(Text, Text)]
    }

defaultAppToggleButtonConfig :: Text -> Bool -> Html -> AppToggleButtonConfig
defaultAppToggleButtonConfig inputId checked label = AppToggleButtonConfig
    { appToggleInputId = inputId
    , appToggleInputName = Nothing
    , appToggleInputValue = "true"
    , appToggleChecked = checked
    , appToggleLabel = label
    , appToggleButtonClass = ""
    , appToggleInputClass = ""
    , appToggleRoleSwitch = False
    , appToggleOnChange = Nothing
    , appToggleHiddenInputId = Nothing
    , appToggleHiddenInputCheckedValue = Nothing
    , appToggleHiddenInputUncheckedValue = Nothing
    , appToggleBreakTarget = Nothing
    , appToggleShiftPreferenceAvailable = False
    , appToggleInputExtraAttrs = []
    }

renderAppToggleButton :: AppToggleButtonConfig -> Html
renderAppToggleButton config@AppToggleButtonConfig { .. } = [hsx|
    <label class={appToggleButtonClasses config}
           for={appToggleInputId}
           data-app-toggle-button="true"
           aria-pressed={boolAttr appToggleChecked}>
        {renderAppToggleInput config}
        {appToggleLabel}
    </label>
|]

renderAppToggleInput :: AppToggleButtonConfig -> Html
renderAppToggleInput config@AppToggleButtonConfig { .. } =
    applyAttributes
        Html5.input
        ( [ attr "id" appToggleInputId
          , attr "class" (appToggleInputClasses config)
          , attr "type" "checkbox"
          , maybeAttr "role" (switchRoleAttr appToggleRoleSwitch)
          , maybeAttr "aria-checked" (switchAriaCheckedAttr appToggleRoleSwitch appToggleChecked)
          , maybeAttr "name" appToggleInputName
          , attr "value" appToggleInputValue
          , checkedAttr appToggleChecked
          , maybeAttr "onchange" appToggleOnChange
          , attr "data-app-toggle-button-input" "true"
          , maybeAttr "data-app-toggle-hidden-input-id" appToggleHiddenInputId
          , maybeAttr "data-app-toggle-hidden-checked-value" appToggleHiddenInputCheckedValue
          , maybeAttr "data-app-toggle-hidden-unchecked-value" appToggleHiddenInputUncheckedValue
          , maybeAttr "data-break-toggle" (breakToggleAttr appToggleBreakTarget)
          , maybeAttr "data-break-target" appToggleBreakTarget
          , maybeAttr "data-shift-preference-available" (boolDataAttr appToggleShiftPreferenceAvailable)
          ]
            <> fmap (uncurry attr) appToggleInputExtraAttrs
        )

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

appToggleButtonClasses :: AppToggleButtonConfig -> Text
appToggleButtonClasses AppToggleButtonConfig { appToggleChecked, appToggleButtonClass } =
    classes
        [ ("btn", True)
        , ("app-toggle-button", True)
        , ("btn-success", appToggleChecked)
        , ("btn-outline-success", not appToggleChecked)
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

breakToggleAttr :: Maybe Text -> Maybe Text
breakToggleAttr (Just _) = Just "true"
breakToggleAttr Nothing  = Nothing

boolDataAttr :: Bool -> Maybe Text
boolDataAttr True  = Just "true"
boolDataAttr False = Nothing

boolAttr :: Bool -> Text
boolAttr True  = "true"
boolAttr False = "false"
