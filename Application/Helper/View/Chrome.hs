{-# LANGUAGE LambdaCase       #-}
{-# LANGUAGE TypeApplications #-}

module Application.Helper.View.Chrome
    ( AppAccordionItemConfig (..)
    , AppPageConfig (..)
    , AppPanelConfig (..)
    , PartialNavigationLink (..)
    , appSurfaceClasses
    , defaultAppPanelConfig
    , renderAppAccordionItem
    , renderAppPage
    , renderAppPanel
    , renderPartialNavigationLink
    , simpleAppPanel
    ) where

import Application.Helper.FrontendContract.AppShell (OpenPageHelpDialog,
                                                     PartialNavigate)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             AppShellCustomHtmxAttrs (..),
                                                             appShellActionByMarker,
                                                             defaultAppShellActionRoute,
                                                             renderAppShellActionLink)
import Application.Helper.View.PageHelp (PageHelpTopicId, pageHelpTopicIdToText)
import qualified Data.Text as Text
import IHP.ViewPrelude
import Web.Routes ()
import Web.Types

data AppPageConfig = AppPageConfig
    { appPageTitle       :: !Text
    , appPageDescription :: !(Maybe Text)
    , appPageActions     :: !Html
    , appPageHelpTopic   :: !(Maybe PageHelpTopicId)
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


renderAppPage :: AppPageConfig -> Html
renderAppPage AppPageConfig { appPageTitle, appPageDescription, appPageActions, appPageHelpTopic, appPageWidthClass, appPageBody } = [hsx|
    <section class={classes [("app-page", True), (appPageWidthClass, not (Text.null appPageWidthClass))]}>
        <header class="app-page-header">
            <div class="app-page-title-block">
                <div class="app-page-title-row d-flex align-items-center gap-2 flex-wrap">
                    <h1 class="app-page-title mb-0">{appPageTitle}</h1>
                    {forEach appPageHelpTopic (renderPageHelpTrigger appPageTitle)}
                </div>
                {forEach appPageDescription renderAppPageDescription}
            </div>
            {appPageActions}
        </header>
        {appPageBody}
    </section>
|]

renderPageHelpTrigger :: Text -> PageHelpTopicId -> Html
renderPageHelpTrigger title topicId =
    renderAppShellActionLink
        (appShellActionByMarker @OpenPageHelpDialog)
        ((defaultAppShellActionRoute (pathTo ShowPageHelpAction { topic = pageHelpTopicIdToText topicId }))
            { appShellActionRouteStandardUrl = Just (pathTo ShowPageHelpAction { topic = pageHelpTopicIdToText topicId })
            , appShellActionRouteExtraAttrs = [ ("class", "btn btn-sm btn-outline-secondary app-page-help-trigger")
                , ("aria-label", "Help for " <> title)
                , ("title", "Help for " <> title)
                , ("data-turbolinks", "false")
                ]
            })
        [hsx|
            <i class="bi bi-question-circle" aria-hidden="true"></i>
            <span>Help</span>
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

renderPartialNavigationLink :: PartialNavigationLink -> Html
renderPartialNavigationLink PartialNavigationLink { partialNavigationLabel, partialNavigationUrl, partialNavigationTargetId, partialNavigationSelectId, partialNavigationClass, partialNavigationSwap, partialNavigationSync, partialNavigationPushUrl } =
    renderAppShellActionLink
        (appShellActionByMarker @PartialNavigate)
        ((defaultAppShellActionRoute (partialNavigationUrl))
            { appShellActionRouteCustomHtmx = [ AppShellCustomHtmxAttrs
                    { appShellCustomHtmxAttrMarker = "partial-navigation-htmx-attrs"
                    , appShellCustomHtmxAttrValues =
                        [ ("hx-target", "#" <> partialNavigationTargetId)
                        , ("hx-swap", partialNavigationSwap)
                        , ("hx-push-url", pushUrlValue)
                        ]
                            <> maybeAttrPair "hx-select" (fmap ("#" <>) partialNavigationSelectId)
                            <> maybeAttrPair "hx-sync" partialNavigationSync
                    }
                ]
            , appShellActionRouteStandardUrl = Just partialNavigationUrl
            , appShellActionRouteExtraAttrs = [ ("class", partialNavigationClass)
                , ("data-turbolinks", "false")
                ]
            })
        [hsx|{partialNavigationLabel}|]
    where
        pushUrlValue :: Text
        pushUrlValue = if partialNavigationPushUrl then "true" else "false"

        maybeAttrPair :: Text -> Maybe Text -> [(Text, Text)]
        maybeAttrPair name = \case
            Nothing -> []
            Just value -> [(name, value)]
