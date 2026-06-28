module Application.Helper.View.LazySurface
    ( lazyFragmentPlaceholderCustom
    , lazyFragmentPlaceholderList
    , lazyFragmentPlaceholderPanel
    , lazyFragmentPlaceholderSpinner
    , lazyFragmentPlaceholderTable
    , lazySurfacePlaceholderRootClasses
    , renderLazySurfacePlaceholder
    , renderLazySurfacePlaceholderBody
    , renderLazySurfacePlaceholderWithCustom
    ) where

import Application.Helper.LiveSurface (LazyFragmentConfig (..))
import qualified Data.Text as Text
import IHP.ViewPrelude

lazyFragmentPlaceholderPanel :: Text
lazyFragmentPlaceholderPanel = "panel"

lazyFragmentPlaceholderTable :: Text
lazyFragmentPlaceholderTable = "table"

lazyFragmentPlaceholderList :: Text
lazyFragmentPlaceholderList = "list"

lazyFragmentPlaceholderSpinner :: Text
lazyFragmentPlaceholderSpinner = "spinner"

lazyFragmentPlaceholderCustom :: Text
lazyFragmentPlaceholderCustom = "custom"

renderLazySurfacePlaceholder :: LazyFragmentConfig -> Html
renderLazySurfacePlaceholder config =
    renderLazySurfacePlaceholderWithCustom config mempty

renderLazySurfacePlaceholderWithCustom :: LazyFragmentConfig -> Html -> Html
renderLazySurfacePlaceholderWithCustom config customBody = [hsx|
    <div class={lazySurfacePlaceholderRootClasses config}
         role="status"
         aria-live="polite"
         aria-busy="true"
         aria-label={config.lazyFragmentAccessibleLabel}>
        <span class="visually-hidden">{config.lazyFragmentAccessibleLabel}</span>
        {renderLazySurfacePlaceholderBody config customBody}
    </div>
|]

renderLazySurfacePlaceholderBody :: LazyFragmentConfig -> Html -> Html
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

lazySurfacePlaceholderKindClass :: Text -> Text
lazySurfacePlaceholderKindClass kind
    | kind == lazyFragmentPlaceholderPanel = "panel"
    | kind == lazyFragmentPlaceholderTable = "table"
    | kind == lazyFragmentPlaceholderList = "list"
    | kind == lazyFragmentPlaceholderSpinner = "spinner"
    | kind == lazyFragmentPlaceholderCustom = "custom"
    | otherwise = "spinner"

renderPanelSkeleton :: Html
renderPanelSkeleton = [hsx|
    <div class="app-lazy-surface-skeleton app-lazy-surface-panel-skeleton" aria-hidden="true">
        <div class="app-lazy-surface-bar app-lazy-surface-bar-title"></div>
        <div class="app-lazy-surface-stack">
            {forEach ([1..4] :: [Int]) renderSkeletonRow}
        </div>
    </div>
|]

renderTableSkeleton :: Html
renderTableSkeleton = [hsx|
    <div class="app-lazy-surface-skeleton app-lazy-surface-table-skeleton" aria-hidden="true">
        <div class="app-lazy-surface-table-row app-lazy-surface-table-row-head">
            {forEach ([1..4] :: [Int]) renderSkeletonCell}
        </div>
        {forEach ([1..4] :: [Int]) renderSkeletonTableRow}
    </div>
|]

renderListSkeleton :: Html
renderListSkeleton = [hsx|
    <div class="app-lazy-surface-skeleton app-lazy-surface-list-skeleton" aria-hidden="true">
        {forEach ([1..5] :: [Int]) renderSkeletonRow}
    </div>
|]

renderCompactSpinner :: Html
renderCompactSpinner = [hsx|
    <div class="app-lazy-surface-spinner" aria-hidden="true">
        <span class="spinner-border spinner-border-sm" role="presentation"></span>
    </div>
|]

renderSkeletonRow :: Int -> Html
renderSkeletonRow index = [hsx|
    <div class="app-lazy-surface-row">
        <div class={classes [("app-lazy-surface-bar", True), ("app-lazy-surface-bar-short", index `mod` 3 == 0)]}></div>
        <div class="app-lazy-surface-bar app-lazy-surface-bar-muted"></div>
    </div>
|]

renderSkeletonTableRow :: Int -> Html
renderSkeletonTableRow _ = [hsx|
    <div class="app-lazy-surface-table-row">
        {forEach ([1..4] :: [Int]) renderSkeletonCell}
    </div>
|]

renderSkeletonCell :: Int -> Html
renderSkeletonCell index = [hsx|
    <div class={classes [("app-lazy-surface-cell", True), ("app-lazy-surface-cell-narrow", index == 4)]}>
        <div class="app-lazy-surface-bar"></div>
    </div>
|]
