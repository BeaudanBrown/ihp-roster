module Application.Helper.View.LazySurface
    ( lazyFragmentPlaceholderCustom
    , lazyFragmentPlaceholderList
    , lazyFragmentPlaceholderPanel
    , lazyFragmentPlaceholderSpinner
    , lazyFragmentPlaceholderTable
    , lazySurfacePlaceholderRootClasses
    , renderLazyLiveFragmentMount
    , renderLazySurfacePlaceholder
    , renderLazySurfacePlaceholderBody
    , renderLazySurfacePlaceholderWithCustom
    , renderLiveSurfaceFragmentMount
    , renderLiveSurfaceFragmentMountWithPlaceholder
    ) where

import Application.Helper.LiveSurface (FragmentContract (..),
                                       FragmentLoadPolicy (..),
                                       LazyFragmentConfig (..),
                                       SurfaceFragmentRef,
                                       TypedLiveSurfaceDefinition (..),
                                       lazyFragmentPlaceholderCustom,
                                       lazyFragmentPlaceholderList,
                                       lazyFragmentPlaceholderPanel,
                                       lazyFragmentPlaceholderSpinner,
                                       lazyFragmentPlaceholderTable,
                                       surfaceFragmentRefTargetId,
                                       surfaceFragmentRefUrl)
import Application.Helper.UiRegion (UiRegionDomAttributes (..),
                                    canonicalUiRegionDomAttributes,
                                    uiRegionFragmentEnabledValue,
                                    uiRegionTransitionProfileText)
import qualified Data.Text as Text
import IHP.ViewPrelude
import qualified Text.Blaze.Html as Blaze
import Text.Blaze.Html ((!))
import qualified Text.Blaze.Html5 as Html5

renderLiveSurfaceFragmentMount ::
    TypedLiveSurfaceDefinition surface scope fragment layer session intent ->
    scope ->
    fragment ->
    Blaze.Html ->
    Blaze.Html
renderLiveSurfaceFragmentMount definition scope fragment eagerHtml =
    renderLiveSurfaceFragmentMountWithPlaceholder definition scope fragment mempty eagerHtml

renderLiveSurfaceFragmentMountWithPlaceholder ::
    TypedLiveSurfaceDefinition surface scope fragment layer session intent ->
    scope ->
    fragment ->
    Blaze.Html ->
    Blaze.Html ->
    Blaze.Html
renderLiveSurfaceFragmentMountWithPlaceholder definition scope fragment placeholderHtml eagerHtml =
    case contract.fragmentContractLoadPolicy of
        FragmentEager -> eagerHtml
        FragmentLazy config -> renderLazyLiveFragmentMountWithPlaceholder config contract.fragmentContractRef placeholderHtml
    where
        contract = definition.typedSurfaceFragmentContract scope fragment

renderLazyLiveFragmentMount :: LazyFragmentConfig -> SurfaceFragmentRef surface -> Blaze.Html
renderLazyLiveFragmentMount config fragmentRef =
    renderLazyLiveFragmentMountWithPlaceholder config fragmentRef mempty

renderLazyLiveFragmentMountWithPlaceholder :: LazyFragmentConfig -> SurfaceFragmentRef surface -> Blaze.Html -> Blaze.Html
renderLazyLiveFragmentMountWithPlaceholder config fragmentRef placeholderHtml =
    Html5.div
        ! attr "id" (surfaceFragmentRefTargetId fragmentRef)
        ! attr "class" (lazySurfacePlaceholderRootClasses config)
        ! attr canonicalUiRegionDomAttributes.uiRegionFragmentAttribute uiRegionFragmentEnabledValue
        ! attr canonicalUiRegionDomAttributes.uiRegionLazySurfaceAttribute uiRegionFragmentEnabledValue
        ! attr canonicalUiRegionDomAttributes.uiRegionLazyFragmentAttribute (surfaceFragmentRefTargetId fragmentRef)
        ! attr canonicalUiRegionDomAttributes.uiRegionLazyRetryAttribute uiRegionFragmentEnabledValue
        ! attr canonicalUiRegionDomAttributes.uiRegionTransitionAttribute (uiRegionTransitionProfileText config.lazyFragmentTransition)
        ! attr "hx-get" (surfaceFragmentRefUrl fragmentRef)
        ! attr "hx-trigger" (lazySurfaceHtmxTrigger config)
        ! attr "hx-target" "this"
        ! attr "hx-swap" "outerHTML"
        ! attr "hx-push-url" "false"
        ! attr "role" "status"
        ! attr "aria-live" "polite"
        ! attr "aria-busy" "true"
        ! attr "aria-label" config.lazyFragmentAccessibleLabel
        $ do
            Html5.span ! attr "class" "visually-hidden" $ Html5.toHtml config.lazyFragmentAccessibleLabel
            renderLazySurfacePlaceholderBody config placeholderHtml

renderLazySurfacePlaceholder :: LazyFragmentConfig -> Blaze.Html
renderLazySurfacePlaceholder config =
    renderLazySurfacePlaceholderWithCustom config mempty

renderLazySurfacePlaceholderWithCustom :: LazyFragmentConfig -> Blaze.Html -> Blaze.Html
renderLazySurfacePlaceholderWithCustom config customBody =
    Html5.div
        ! attr "class" (lazySurfacePlaceholderRootClasses config)
        ! attr "role" "status"
        ! attr "aria-live" "polite"
        ! attr "aria-busy" "true"
        ! attr "aria-label" config.lazyFragmentAccessibleLabel
        $ do
            Html5.span ! attr "class" "visually-hidden" $ Html5.toHtml config.lazyFragmentAccessibleLabel
            renderLazySurfacePlaceholderBody config customBody

renderLazySurfacePlaceholderBody :: LazyFragmentConfig -> Blaze.Html -> Blaze.Html
renderLazySurfacePlaceholderBody config customBody
    | config.lazyFragmentPlaceholderKind == lazyFragmentPlaceholderPanel = renderPanelSkeleton
    | config.lazyFragmentPlaceholderKind == lazyFragmentPlaceholderTable = renderTableSkeleton
    | config.lazyFragmentPlaceholderKind == lazyFragmentPlaceholderList = renderListSkeleton
    | config.lazyFragmentPlaceholderKind == lazyFragmentPlaceholderSpinner = renderCompactSpinner
    | config.lazyFragmentPlaceholderKind == lazyFragmentPlaceholderCustom = customBody
    | otherwise = renderCompactSpinner

lazySurfacePlaceholderRootClasses :: LazyFragmentConfig -> Text
lazySurfacePlaceholderRootClasses config =
    Text.unwords $
        filter
            (not . Text.null)
            ( [ "app-lazy-surface"
              , "app-lazy-surface-" <> lazySurfacePlaceholderKindClass config.lazyFragmentPlaceholderKind
              ]
                <> config.lazyFragmentClasses
            )

lazySurfaceHtmxTrigger :: LazyFragmentConfig -> Text
lazySurfaceHtmxTrigger config =
    case config.lazyFragmentDelayMs of
        Just delayMs -> trigger <> " delay:" <> tshow delayMs <> "ms"
        Nothing      -> trigger
    where
        trigger =
            if Text.null config.lazyFragmentTrigger
                then "revealed"
                else config.lazyFragmentTrigger

lazySurfacePlaceholderKindClass :: Text -> Text
lazySurfacePlaceholderKindClass kind
    | kind == lazyFragmentPlaceholderPanel = "panel"
    | kind == lazyFragmentPlaceholderTable = "table"
    | kind == lazyFragmentPlaceholderList = "list"
    | kind == lazyFragmentPlaceholderSpinner = "spinner"
    | kind == lazyFragmentPlaceholderCustom = "custom"
    | otherwise = "spinner"

renderPanelSkeleton :: Blaze.Html
renderPanelSkeleton = [hsx|
    <div class="app-lazy-surface-skeleton app-lazy-surface-panel-skeleton" aria-hidden="true">
        <div class="app-lazy-surface-bar app-lazy-surface-bar-title"></div>
        <div class="app-lazy-surface-stack">
            {forEach skeletonPlaceholderItems4 renderSkeletonRow}
        </div>
    </div>
|]

renderTableSkeleton :: Blaze.Html
renderTableSkeleton = [hsx|
    <div class="app-lazy-surface-skeleton app-lazy-surface-table-skeleton" aria-hidden="true">
        <div class="app-lazy-surface-table-row app-lazy-surface-table-row-head">
            {forEach skeletonPlaceholderItems4 renderSkeletonCell}
        </div>
        {forEach skeletonPlaceholderItems4 renderSkeletonTableRow}
    </div>
|]

renderListSkeleton :: Blaze.Html
renderListSkeleton = [hsx|
    <div class="app-lazy-surface-skeleton app-lazy-surface-list-skeleton" aria-hidden="true">
        {forEach skeletonPlaceholderItems5 renderSkeletonRow}
    </div>
|]

renderCompactSpinner :: Blaze.Html
renderCompactSpinner = [hsx|
    <div class="app-lazy-surface-spinner" aria-hidden="true">
        <span class="spinner-border spinner-border-sm" role="presentation"></span>
    </div>
|]

skeletonPlaceholderItems4 :: [Int]
skeletonPlaceholderItems4 = [1, 2, 3, 4]

skeletonPlaceholderItems5 :: [Int]
skeletonPlaceholderItems5 = [1, 2, 3, 4, 5]

renderSkeletonRow :: Int -> Blaze.Html
renderSkeletonRow index = [hsx|
    <div class="app-lazy-surface-row">
        <div class={classes [("app-lazy-surface-bar", True), ("app-lazy-surface-bar-short", index `mod` 3 == 0)]}></div>
        <div class="app-lazy-surface-bar app-lazy-surface-bar-muted"></div>
    </div>
|]

renderSkeletonTableRow :: Int -> Blaze.Html
renderSkeletonTableRow _ = [hsx|
    <div class="app-lazy-surface-table-row">
        {forEach skeletonPlaceholderItems4 renderSkeletonCell}
    </div>
|]

renderSkeletonCell :: Int -> Blaze.Html
renderSkeletonCell index = [hsx|
    <div class={classes [("app-lazy-surface-cell", True), ("app-lazy-surface-cell-narrow", index == 4)]}>
        <div class="app-lazy-surface-bar"></div>
    </div>
|]

attr :: Text -> Text -> Blaze.Attribute
attr name value =
    Blaze.customAttribute (Blaze.textTag name) (Blaze.toValue value)
