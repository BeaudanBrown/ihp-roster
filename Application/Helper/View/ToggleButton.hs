module Application.Helper.View.ToggleButton
    ( AppToggleButtonConfig (..)
    , defaultAppToggleButtonConfig
    , renderAppToggleButton
    ) where

import qualified Data.Text as Text
import IHP.ViewPrelude

data AppToggleButtonConfig = AppToggleButtonConfig
    { appToggleInputId                         :: !Text
    , appToggleInputName                       :: !(Maybe Text)
    , appToggleInputValue                      :: !Text
    , appToggleChecked                         :: !Bool
    , appToggleLabel                           :: !Html
    , appToggleButtonClass                     :: !Text
    , appToggleInputClass                      :: !Text
    , appToggleRoleSwitch                      :: !Bool
    , appToggleOnChange                        :: !(Maybe Text)
    , appToggleHxGet                           :: !(Maybe Text)
    , appToggleHxPost                          :: !(Maybe Text)
    , appToggleHxTrigger                       :: !(Maybe Text)
    , appToggleHxInclude                       :: !(Maybe Text)
    , appToggleHxTarget                        :: !(Maybe Text)
    , appToggleHxSwap                          :: !(Maybe Text)
    , appToggleHxPushUrl                       :: !(Maybe Text)
    , appToggleHxSync                          :: !(Maybe Text)
    , appToggleHiddenInputId                   :: !(Maybe Text)
    , appToggleHiddenInputCheckedValue         :: !(Maybe Text)
    , appToggleHiddenInputUncheckedValue       :: !(Maybe Text)
    , appToggleBreakTarget                     :: !(Maybe Text)
    , appToggleShiftPreferenceAvailable        :: !Bool
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
    , appToggleHxGet = Nothing
    , appToggleHxPost = Nothing
    , appToggleHxTrigger = Nothing
    , appToggleHxInclude = Nothing
    , appToggleHxTarget = Nothing
    , appToggleHxSwap = Nothing
    , appToggleHxPushUrl = Nothing
    , appToggleHxSync = Nothing
    , appToggleHiddenInputId = Nothing
    , appToggleHiddenInputCheckedValue = Nothing
    , appToggleHiddenInputUncheckedValue = Nothing
    , appToggleBreakTarget = Nothing
    , appToggleShiftPreferenceAvailable = False
    }

renderAppToggleButton :: AppToggleButtonConfig -> Html
renderAppToggleButton config@AppToggleButtonConfig { .. } = [hsx|
    <label class={appToggleButtonClasses config}
           for={appToggleInputId}
           data-app-toggle-button="true"
           aria-pressed={boolAttr appToggleChecked}>
        <input id={appToggleInputId}
               class={appToggleInputClasses config}
               type="checkbox"
               role={switchRoleAttr appToggleRoleSwitch}
               aria-checked={switchAriaCheckedAttr appToggleRoleSwitch appToggleChecked}
               name={appToggleInputName}
               value={appToggleInputValue}
               checked={appToggleChecked}
               onchange={appToggleOnChange}
               hx-get={appToggleHxGet}
               hx-post={appToggleHxPost}
               hx-trigger={appToggleHxTrigger}
               hx-include={appToggleHxInclude}
               hx-target={appToggleHxTarget}
               hx-swap={appToggleHxSwap}
               hx-push-url={appToggleHxPushUrl}
               hx-sync={appToggleHxSync}
               data-app-toggle-button-input="true"
               data-app-toggle-hidden-input-id={appToggleHiddenInputId}
               data-app-toggle-hidden-checked-value={appToggleHiddenInputCheckedValue}
               data-app-toggle-hidden-unchecked-value={appToggleHiddenInputUncheckedValue}
               data-break-toggle={breakToggleAttr appToggleBreakTarget}
               data-break-target={appToggleBreakTarget}
               data-shift-preference-available={boolDataAttr appToggleShiftPreferenceAvailable} />
        {appToggleLabel}
    </label>
|]

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
switchRoleAttr True = Just "switch"
switchRoleAttr False = Nothing

switchAriaCheckedAttr :: Bool -> Bool -> Maybe Text
switchAriaCheckedAttr True checked = Just (boolAttr checked)
switchAriaCheckedAttr False _ = Nothing

breakToggleAttr :: Maybe Text -> Maybe Text
breakToggleAttr (Just _) = Just "true"
breakToggleAttr Nothing = Nothing

boolDataAttr :: Bool -> Maybe Text
boolDataAttr True = Just "true"
boolDataAttr False = Nothing

boolAttr :: Bool -> Text
boolAttr True = "true"
boolAttr False = "false"
