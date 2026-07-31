{-# LANGUAGE TypeApplications #-}

module Web.View.Admin.Exports
    ( renderExportsSection
    , renderExportsSectionFragment
    , renderExportsSectionFragmentWithSwap
    ) where

import Application.Helper.Controller (currentVenueOrNothing)
import Application.Helper.Export
import qualified Application.Helper.FrontendContract.Surface.Admin as Surface
import qualified Application.Helper.FrontendContract.Surface.Admin.Action as AdminAction
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            renderFrontendSurfaceActionFormWithHiddenFields,
                                                            renderFrontendSurfaceMount)
import Application.Helper.FrontendContract.Surface.Values
import qualified Data.Text as Text
import Data.Time.Format (defaultTimeLocale, formatTime)
import Web.Admin.FrontendSurface (AdminVenueScopeValue (..),
                                  adminExportsSurfaceImplForWeek)
import Web.View.Admin.Common
import Web.View.Prelude

adminExportsFragmentId :: Text
adminExportsFragmentId = surfaceFragmentTargetId @Surface.AdminExportsSurface @Surface.AdminExportsFragment noSurfaceFields

currentVenueScopeId :: (?context :: ControllerContext) => UUID
currentVenueScopeId =
    case currentVenueOrNothing of
        Just venue -> unpackId venue.id
        Nothing    -> error "Admin exports live surface requires a current venue"

renderExportsSectionFragment :: ReportWeekSelection -> Html
renderExportsSectionFragment =
    renderExportsSectionFragmentWithSwap Nothing

renderExportsSectionFragmentWithSwap :: Maybe Text -> ReportWeekSelection -> Html
renderExportsSectionFragmentWithSwap maybeSwapOob selection =
    renderFrontendSurfaceMount (adminExportsSurfaceImplForWeek AdminVenueScopeValue { adminVenueId = currentVenueScopeId, adminRosterGroupId = Nothing } selection.weekOffset) [hsx|
        <div id={adminExportsFragmentId}
             hx-swap-oob={maybeSwapOob}>
            {renderExportsSection selection}
        </div>
    |]

renderExportsSection :: ReportWeekSelection -> Html
renderExportsSection selection =
    renderConfigSection
        "admin-exports-section"
        [hsx|
            <p class="small app-muted mb-3">
                Download approved Staff Hours for one roster week. The export is also retained in the venue's export history.
            </p>
        |]
        [hsx|
            {renderExportWeekSelector selection}
            {renderExportGenerationForm selection}
        |]
        mempty

renderExportWeekSelector :: ReportWeekSelection -> Html
renderExportWeekSelector selection = [hsx|
    <div class="d-flex flex-wrap align-items-center gap-2 mb-3">
        <a class={weekNavigationButtonClass ""} href={thisWeekUrl}>This week</a>
        {weekNavigation}
    </div>
|]
  where
    thisWeekUrl = appendQueryParams (pathTo AdminAction) [("showExports", "true")] <> "#exports"
    weekNavigation =
        renderWeekNavigationGroup WeekNavigationConfig
            { weekNavigationAriaLabel = "Export week navigation"
            , weekNavigationExtraClass = ""
            , weekNavigationPrevious = renderWeekLink "<" "Previous week" (selection.weekOffset - 1)
            , weekNavigationCurrentLabel = [hsx|{exportWeekLabel selection}|]
            , weekNavigationLabelClass = ""
            , weekNavigationNext = renderWeekLink ">" "Next week" (selection.weekOffset + 1)
            }

renderWeekLink :: Text -> Text -> Int -> Html
renderWeekLink label ariaLabel targetWeekOffset = [hsx|
    <a class={weekNavigationButtonClass ""}
       href={exportWeekUrl targetWeekOffset}
       aria-label={ariaLabel}
       title={ariaLabel}>{label}</a>
|]

exportWeekUrl :: Int -> Text
exportWeekUrl weekOffset =
    appendQueryParams (pathTo AdminAction)
        [ ("showExports", "true")
        , ("weekOffset", tshow weekOffset)
        ]
        <> "#exports"

exportWeekLabel :: ReportWeekSelection -> Text
exportWeekLabel selection =
    Text.pack (formatTime defaultTimeLocale "%-d %b" selection.weekStart)
        <> " – "
        <> Text.pack (formatTime defaultTimeLocale "%-d %b %Y" selection.weekEnd)

renderExportGenerationForm :: ReportWeekSelection -> Html
renderExportGenerationForm selection =
    renderFrontendSurfaceActionFormWithHiddenFields
        (AdminAction.createExportJobAction fields)
        createExportRoute
        [hsx|
            <div class={appSurfaceClasses "p-3"} data-fixed-export-card="true" data-export-type={exportJobTypeToText StaffPayCsv}>
                <div class="d-flex flex-wrap justify-content-between align-items-center gap-3">
                    <div>
                        <div class="fw-semibold">Staff Hours CSV</div>
                        <div class="small app-muted">Hours grouped by staff member and effective pay level for the selected roster week.</div>
                    </div>
                    <button class="btn btn-primary" type="submit">Download CSV</button>
                </div>
            </div>
        |]
  where
    fields = AdminAction.createExportJobActionFields selection.weekStart selection.weekEnd (exportJobTypeToText StaffPayCsv)

createExportRoute :: FrontendSurfaceActionRoute
createExportRoute = FrontendSurfaceActionRoute
    { actionRouteUrl = pathTo CreateExportJobAction
    , actionRouteCustomHtmx = []
    , actionRouteStandardUrl = Just (pathTo CreateExportJobAction)
    , actionRouteExtraAttrs = [("id", "admin-export-generation-form")]
    }
