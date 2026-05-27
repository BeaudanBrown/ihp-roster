module Application.Helper.View.Chrome
    ( AppAccordionItemConfig (..)
    , AppPageConfig (..)
    , AppPanelConfig (..)
    , PartialNavigationLink (..)
    , appPanelWithActions
    , appSurfaceClasses
    , defaultAppPanelConfig
    , renderAppAccordionItem
    , renderAppPage
    , renderAppPanel
    , renderAppSettingsMenuButton
    , renderPartialNavigationLink
    , simpleAppPanel
    ) where

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

data AppAccordionItemConfig = AppAccordionItemConfig
    { appAccordionItemId            :: !Text
    , appAccordionItemParentId      :: !Text
    , appAccordionItemTitle         :: !Text
    , appAccordionItemIsOpen        :: !Bool
    , appAccordionItemClass         :: !Text
    , appAccordionItemBodyClass     :: !Text
    , appAccordionItemButtonContent :: !Html
    , appAccordionItemBody          :: !Html
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

appSurfaceClasses :: Text -> Text
appSurfaceClasses extraClasses =
    Text.unwords (filter (not . Text.null) ["app-surface", extraClasses])

defaultAppPanelConfig :: Html -> AppPanelConfig
defaultAppPanelConfig appPanelBody =
    AppPanelConfig
        { appPanelTitle = Nothing
        , appPanelDescription = Nothing
        , appPanelHasActions = False
        , appPanelActions = mempty
        , appPanelHasCustomHeader = False
        , appPanelCustomHeader = mempty
        , appPanelClass = ""
        , appPanelBodyClass = ""
        , appPanelBody
        }

simpleAppPanel :: Text -> Maybe Text -> Html -> Html
simpleAppPanel title description body =
    renderAppPanel (defaultAppPanelConfig body)
        { appPanelTitle = Just title
        , appPanelDescription = description
        }

appPanelWithActions :: Text -> Maybe Text -> Html -> Html -> Html
appPanelWithActions title description actions body =
    renderAppPanel (defaultAppPanelConfig body)
        { appPanelTitle = Just title
        , appPanelDescription = description
        , appPanelHasActions = True
        , appPanelActions = actions
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

renderAppAccordionItem :: AppAccordionItemConfig -> Html
renderAppAccordionItem AppAccordionItemConfig { appAccordionItemId, appAccordionItemParentId, appAccordionItemTitle, appAccordionItemIsOpen, appAccordionItemClass, appAccordionItemBodyClass, appAccordionItemButtonContent, appAccordionItemBody } = [hsx|
    <section class={classes [("accordion-item app-panel mb-3", True), (appAccordionItemClass, not (Text.null appAccordionItemClass))]} id={appAccordionItemId}>
        <h2 class="accordion-header" id={appAccordionItemId <> "-heading"}>
            <button
                class={accordionButtonClass appAccordionItemIsOpen}
                type="button"
                data-bs-toggle="collapse"
                data-bs-target={"#" <> appAccordionItemId <> "-collapse"}
                aria-expanded={if appAccordionItemIsOpen then ("true" :: Text) else "false"}
                aria-controls={appAccordionItemId <> "-collapse"}
                aria-label={appAccordionItemTitle}
            >
                {appAccordionItemButtonContent}
            </button>
        </h2>
        <div
            id={appAccordionItemId <> "-collapse"}
            class={accordionCollapseClass appAccordionItemIsOpen}
            aria-labelledby={appAccordionItemId <> "-heading"}
            data-bs-parent={"#" <> appAccordionItemParentId}
        >
            <div class={classes [("accordion-body", True), (appAccordionItemBodyClass, not (Text.null appAccordionItemBodyClass))]}>
                {appAccordionItemBody}
            </div>
        </div>
    </section>
|]

accordionButtonClass :: Bool -> Text
accordionButtonClass isOpen =
    if isOpen
        then "accordion-button"
        else "accordion-button collapsed"

accordionCollapseClass :: Bool -> Text
accordionCollapseClass isOpen =
    if isOpen
        then "accordion-collapse collapse show"
        else "accordion-collapse collapse"

renderAppSettingsMenuButton :: Text -> Text -> Html
renderAppSettingsMenuButton buttonId ariaLabel = [hsx|
    <button class="btn btn-outline-secondary app-settings-menu-button"
            type="button"
            id={buttonId}
            data-bs-toggle="dropdown"
            data-bs-auto-close="outside"
            aria-expanded="false"
            aria-label={ariaLabel}
            title={ariaLabel}>
        <i class="bi bi-gear" aria-hidden="true"></i>
    </button>
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
