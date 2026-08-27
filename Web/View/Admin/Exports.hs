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
                                  adminExportsSurfaceImplForWindow)
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
    renderFrontendSurfaceMount (adminExportsSurfaceImplForWindow AdminVenueScopeValue { adminVenueId = currentVenueScopeId, adminRosterGroupId = Nothing } selection.weekStart) [hsx|
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
                Download one Payroll Workbook with accountant summaries, daily hours, and daily wages, or download detailed Payroll Earnings CSV for the selected roster week.
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
            , weekNavigationPrevious = renderWeekLink "<" "Previous week" (addDays (-7) selection.weekStart)
            , weekNavigationCurrentLabel = [hsx|{exportWeekLabel selection}|]
            , weekNavigationLabelClass = ""
            , weekNavigationNext = renderWeekLink ">" "Next week" (addDays 7 selection.weekStart)
            }

renderWeekLink :: Text -> Text -> Day -> Html
renderWeekLink label ariaLabel anchorDate = [hsx|
    <a class={weekNavigationButtonClass ""}
       href={exportWeekUrl anchorDate}
       aria-label={ariaLabel}
       title={ariaLabel}>{label}</a>
|]

exportWeekUrl :: Day -> Text
exportWeekUrl anchorDate =
    appendQueryParams (pathTo AdminAction)
        [ ("showExports", "true")
        , ("anchorDate", tshow anchorDate)
        ]
        <> "#exports"

exportWeekLabel :: ReportWeekSelection -> Text
exportWeekLabel selection =
    Text.pack (formatTime defaultTimeLocale "%-d %b" selection.weekStart)
        <> " – "
        <> Text.pack (formatTime defaultTimeLocale "%-d %b %Y" selection.weekEnd)

renderExportGenerationForm :: ReportWeekSelection -> Html
renderExportGenerationForm selection = [hsx|
    <div class="d-grid gap-2">
        {renderExportCard selection PayrollWorkbookXlsx "Payroll Workbook" "Accountant Summary sheets plus daily Hours and Wages sheets in one Excel and Google Sheets compatible workbook." "Download workbook" "admin-export-generation-form"}
        {renderExportCard selection PayrollEarningsCsv "Payroll Earnings CSV" "Approved payroll earnings by staff, date, earnings bucket, and tracking code." "Download CSV" "admin-payroll-earnings-export-generation-form"}
    </div>
|]

renderExportCard :: ReportWeekSelection -> ExportJobType -> Text -> Text -> Text -> Text -> Html
renderExportCard selection exportType label description downloadLabel formId =
    renderFrontendSurfaceActionFormWithHiddenFields
        (AdminAction.createExportJobAction fields)
        (createExportRoute formId)
        [hsx|
            <div class={appSurfaceClasses "p-3"} data-fixed-export-card="true" data-export-type={exportJobTypeToText exportType}>
                <div class="d-flex flex-wrap justify-content-between align-items-center gap-3">
                    <div>
                        <div class="fw-semibold">{label}</div>
                        <div class="small app-muted">{description}</div>
                    </div>
                    <button class="btn btn-primary" type="submit">{downloadLabel}</button>
                </div>
            </div>
        |]
  where
    fields = AdminAction.createExportJobActionFields selection.weekStart selection.weekEnd exportType

createExportRoute :: Text -> FrontendSurfaceActionRoute
createExportRoute formId = FrontendSurfaceActionRoute
    { actionRouteUrl = pathTo CreateExportJobAction
    , actionRouteCustomHtmx = []
    , actionRouteStandardUrl = Just (pathTo CreateExportJobAction)
    , actionRouteExtraAttrs = [("id", formId)]
    }
