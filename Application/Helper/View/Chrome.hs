module Application.Helper.View.Chrome where

import qualified Data.Text as Text
import Generated.Types
import IHP.ViewPrelude
import Web.Routes ()
import Web.Types

data AppPageConfig = AppPageConfig
    { appPageTitle       :: !Text
    , appPageDescription :: !(Maybe Text)
    , appPageActions     :: !Html
    , appPageWidthClass  :: !Text
    , appPageBody        :: !Html
    }

data AppPanelConfig = AppPanelConfig
    { appPanelTitle           :: !(Maybe Text)
    , appPanelDescription     :: !(Maybe Text)
    , appPanelHasActions      :: !Bool
    , appPanelActions         :: !Html
    , appPanelHasCustomHeader :: !Bool
    , appPanelCustomHeader    :: !Html
    , appPanelClass           :: !Text
    , appPanelBodyClass       :: !Text
    , appPanelBody            :: !Html
    }

data PartialNavigationLink = PartialNavigationLink
    { partialNavigationLabel    :: !Text
    , partialNavigationUrl      :: !Text
    , partialNavigationTargetId :: !Text
    , partialNavigationSelectId :: !(Maybe Text)
    , partialNavigationClass    :: !Text
    , partialNavigationSwap     :: !Text
    , partialNavigationSync     :: !(Maybe Text)
    , partialNavigationPushUrl  :: !Bool
    }

renderAppPage :: AppPageConfig -> Html
renderAppPage AppPageConfig { appPageTitle, appPageDescription, appPageActions, appPageWidthClass, appPageBody } = [hsx|
    <section class={classes [("app-page", True), (appPageWidthClass, not (Text.null appPageWidthClass))]}>
        <header class="app-page-header">
            <div class="app-page-title-block">
                <h1 class="app-page-title">{appPageTitle}</h1>
                {forEach appPageDescription renderAppPageDescription}
            </div>
            {appPageActions}
        </header>
        {appPageBody}
    </section>
|]

renderAppPageDescription :: Text -> Html
renderAppPageDescription description = [hsx|
    <p class="app-page-description">{description}</p>
|]

renderAppPanel :: AppPanelConfig -> Html
renderAppPanel AppPanelConfig { appPanelTitle, appPanelDescription, appPanelHasActions, appPanelActions, appPanelHasCustomHeader, appPanelCustomHeader, appPanelClass, appPanelBodyClass, appPanelBody } = [hsx|
    <div class={classes [("app-panel", True), (appPanelClass, not (Text.null appPanelClass))]}>
        {renderAppPanelHeader appPanelTitle appPanelDescription appPanelHasActions appPanelActions appPanelHasCustomHeader appPanelCustomHeader}
        <div class={classes [("app-panel-body", True), (appPanelBodyClass, not (Text.null appPanelBodyClass))]}>
            {appPanelBody}
        </div>
    </div>
|]

renderAppPanelHeader :: Maybe Text -> Maybe Text -> Bool -> Html -> Bool -> Html -> Html
renderAppPanelHeader maybeTitle maybeDescription hasActions actions hasCustomHeader customHeader
    | hasCustomHeader = customHeader
    | isNothing maybeTitle && isNothing maybeDescription && not hasActions = mempty
    | otherwise = [hsx|
        <div class="app-panel-header">
            <div class="app-panel-heading">
                <div>
                    {forEach maybeTitle renderAppPanelTitle}
                    {forEach maybeDescription renderAppPanelDescription}
                </div>
                {if hasActions then actions else mempty}
            </div>
        </div>
    |]

renderAppPanelTitle :: Text -> Html
renderAppPanelTitle title = [hsx|
    <h2 class="app-panel-title h5">{title}</h2>
|]

renderAppPanelDescription :: Text -> Html
renderAppPanelDescription description = [hsx|
    <p class="app-panel-description">{description}</p>
|]

renderPartialNavigationLink :: PartialNavigationLink -> Html
renderPartialNavigationLink PartialNavigationLink { partialNavigationLabel, partialNavigationUrl, partialNavigationTargetId, partialNavigationSelectId, partialNavigationClass, partialNavigationSwap, partialNavigationSync, partialNavigationPushUrl } = [hsx|
    <a href={partialNavigationUrl}
       class={partialNavigationClass}
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
