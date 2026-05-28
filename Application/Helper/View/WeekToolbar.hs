module Application.Helper.View.WeekToolbar
    ( WeekToolbarConfig (..)
    , WeekToolbarVariant (..)
    , renderWeekToolbar
    ) where

import qualified Data.Text as Text
import IHP.ViewPrelude

-- | Shared responsive week-toolbar chrome. Feature views own the controls and URLs;
-- this helper only arranges them consistently across desktop and mobile.
data WeekToolbarVariant
    = WeekToolbarRoster
    | WeekToolbarTimesheets

instance Eq WeekToolbarVariant where
    WeekToolbarRoster == WeekToolbarRoster = True
    WeekToolbarTimesheets == WeekToolbarTimesheets = True
    _ == _ = False

data WeekToolbarConfig = WeekToolbarConfig
    { weekToolbarVariant       :: !WeekToolbarVariant
    , weekToolbarAriaLabel     :: !Text
    , weekToolbarExtraClass    :: !Text
    , weekToolbarPrimary       :: !Html
    , weekToolbarReset         :: !Html
    , weekToolbarNavigation    :: !Html
    , weekToolbarSettings      :: !Html
    , weekToolbarAuxiliary     :: !Html
    }

renderWeekToolbar :: WeekToolbarConfig -> Html
renderWeekToolbar WeekToolbarConfig { weekToolbarVariant, weekToolbarAriaLabel, weekToolbarExtraClass, weekToolbarPrimary, weekToolbarReset, weekToolbarNavigation, weekToolbarSettings, weekToolbarAuxiliary } = [hsx|
    <div class={toolbarClass}
         role="navigation"
         aria-label={weekToolbarAriaLabel}
         data-week-toolbar={variantName}>
        <div class="app-week-toolbar-section app-week-toolbar-quick app-week-toolbar-desktop-start" data-week-toolbar-section="quick">
            {weekToolbarPrimary}
            {weekToolbarReset}
            <div class="app-week-toolbar-aux app-week-toolbar-aux-desktop" data-week-toolbar-section="auxiliary-desktop">
                {weekToolbarAuxiliary}
            </div>
        </div>
        <div class="app-week-toolbar-section app-week-toolbar-primary app-week-toolbar-mobile-control" data-week-toolbar-section="primary">
            {weekToolbarPrimary}
        </div>
        <div class="app-week-toolbar-section app-week-toolbar-reset app-week-toolbar-mobile-control" data-week-toolbar-section="reset">
            {weekToolbarReset}
        </div>
        <div class="app-week-toolbar-section app-week-toolbar-navigation" data-week-toolbar-section="navigation">
            {weekToolbarNavigation}
        </div>
        <div class="app-week-toolbar-section app-week-toolbar-settings" data-week-toolbar-section="settings">
            {weekToolbarSettings}
        </div>
        <div class="app-week-toolbar-section app-week-toolbar-aux app-week-toolbar-aux-mobile" data-week-toolbar-section="auxiliary">
            {weekToolbarAuxiliary}
        </div>
    </div>
|]
    where
        variantName :: Text
        variantName = case weekToolbarVariant of
            WeekToolbarRoster     -> "roster"
            WeekToolbarTimesheets -> "timesheets"

        variantClass :: Text
        variantClass = "app-week-toolbar-" <> variantName

        toolbarClass :: Text
        toolbarClass = Text.unwords (filter (not . Text.null)
            [ "app-panel-header"
            , "app-week-toolbar"
            , variantClass
            , weekToolbarExtraClass
            ])
