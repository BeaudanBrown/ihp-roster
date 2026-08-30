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
                                                            renderFrontendSurfaceActionForm,
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

renderExportsSectionFragment :: ReportWeekSelection -> [SavedPayrollWorkbookConfiguration] -> Html
renderExportsSectionFragment =
    renderExportsSectionFragmentWithSwap Nothing

renderExportsSectionFragmentWithSwap :: Maybe Text -> ReportWeekSelection -> [SavedPayrollWorkbookConfiguration] -> Html
renderExportsSectionFragmentWithSwap maybeSwapOob selection savedConfigurations =
    renderFrontendSurfaceMount (adminExportsSurfaceImplForWindow AdminVenueScopeValue { adminVenueId = currentVenueScopeId, adminRosterGroupId = Nothing } selection.weekStart) [hsx|
        <div id={adminExportsFragmentId}
             hx-swap-oob={maybeSwapOob}>
            {renderExportsSection selection savedConfigurations}
        </div>
    |]

renderExportsSection :: ReportWeekSelection -> [SavedPayrollWorkbookConfiguration] -> Html
renderExportsSection selection savedConfigurations =
    renderConfigSection
        "admin-exports-section"
        [hsx|
            <p class="small app-muted mb-3">
                Download one Payroll Workbook with accountant summaries, daily hours, and daily wages, or download detailed Payroll Earnings CSV for the selected roster week.
            </p>
        |]
        [hsx|
            {renderExportWeekSelector selection}
            {renderExportGenerationForm selection savedConfigurations}
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

renderExportGenerationForm :: ReportWeekSelection -> [SavedPayrollWorkbookConfiguration] -> Html
renderExportGenerationForm selection savedConfigurations = [hsx|
    <div class="d-grid gap-2">
        {renderExportCard selection PayrollWorkbookXlsx Nothing "Payroll Workbook" "Built-in default with every supported Summary, Hours, and Wages sheet." "Download workbook" "admin-export-generation-form"}
        {forEach savedConfigurations (renderSavedConfigurationCard selection)}
        {renderExportCard selection PayrollEarningsCsv Nothing "Payroll Earnings CSV" "Approved payroll earnings by staff, date, earnings bucket, and tracking code." "Download CSV" "admin-payroll-earnings-export-generation-form"}
    </div>
    {renderSavedConfigurationManagement selection savedConfigurations}
|]

renderExportCard :: ReportWeekSelection -> ExportJobType -> Maybe UUID -> Text -> Text -> Text -> Text -> Html
renderExportCard selection exportType maybeConfigurationId label description downloadLabel formId =
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
    fields = AdminAction.createExportJobActionFields selection.weekStart selection.weekEnd exportType maybeConfigurationId

renderSavedConfigurationCard :: ReportWeekSelection -> SavedPayrollWorkbookConfiguration -> Html
renderSavedConfigurationCard selection configuration =
    renderExportCard
        selection
        PayrollWorkbookXlsx
        (Just (unpackId configuration.savedPayrollWorkbookConfigurationRecord.id))
        configuration.savedPayrollWorkbookConfigurationRecord.name
        ("Saved sheets: " <> savedConfigurationSummary configuration)
        "Download workbook"
        ("admin-saved-payroll-workbook-download-" <> tshow configuration.savedPayrollWorkbookConfigurationRecord.id)

savedConfigurationSummary :: SavedPayrollWorkbookConfiguration -> Text
savedConfigurationSummary configuration =
    Text.intercalate
        " → "
        (map payrollWorkbookSheetFamilyLabel configuration.savedPayrollWorkbookConfigurationDefinition.payrollWorkbookDefinitionSheetFamilies)

renderSavedConfigurationManagement :: ReportWeekSelection -> [SavedPayrollWorkbookConfiguration] -> Html
renderSavedConfigurationManagement selection savedConfigurations = [hsx|
    <section id="payroll-workbook-configuration-management" class={appSurfaceClasses "p-3 mt-3"}>
        <div class="mb-3">
            <div class="fw-semibold">Saved Payroll Workbook configurations</div>
            <div class="small app-muted">Choose sheet families in the order they should appear. The hidden Data sheet is always included.</div>
        </div>
        {renderSavedConfigurationCreateForm selection}
        <div class="d-grid gap-2 mt-3" data-payroll-workbook-configuration-list="true">
            {if null savedConfigurations then renderEmptyState "No saved Payroll Workbook configurations yet." else forEach savedConfigurations (renderSavedConfigurationManagementRow selection)}
        </div>
    </section>
|]

renderSavedConfigurationCreateForm :: ReportWeekSelection -> Html
renderSavedConfigurationCreateForm selection =
    renderFrontendSurfaceActionForm (AdminAction.createPayrollWorkbookConfigurationAction fields) route [hsx|
        <input type="hidden" name={surfaceFieldNameFrom @Surface.RangeStart fields} value={tshow selection.weekStart} />
        <div class="row g-2 align-items-end">
            <div class="col-12 col-lg-4">
                <label class="form-label" for="payroll-workbook-configuration-name">Configuration name</label>
                <input id="payroll-workbook-configuration-name" class="form-control" type="text" maxlength="100" required="required" name={surfaceFieldNameFrom @Surface.PayrollWorkbookConfigurationName fields} placeholder="Weekly payroll" />
            </div>
            {renderFamilySelect "payroll-workbook-family-1" (surfaceFieldNameFrom @Surface.PayrollWorkbookSheetFamily1 fields) (Just PayrollWorkbookSummary) True}
            {renderFamilySelect "payroll-workbook-family-2" (surfaceFieldNameFrom @Surface.PayrollWorkbookSheetFamily2 fields) Nothing False}
            {renderFamilySelect "payroll-workbook-family-3" (surfaceFieldNameFrom @Surface.PayrollWorkbookSheetFamily3 fields) Nothing False}
            {renderFamilySelect "payroll-workbook-family-4" (surfaceFieldNameFrom @Surface.PayrollWorkbookSheetFamily4 fields) Nothing False}
            {renderFamilySelect "payroll-workbook-family-5" (surfaceFieldNameFrom @Surface.PayrollWorkbookSheetFamily5 fields) Nothing False}
            <div class="col-12 col-lg-2">
                <button class="btn btn-outline-primary w-100" type="submit">Save configuration</button>
            </div>
        </div>
    |]
  where
    fields =
        AdminAction.createPayrollWorkbookConfigurationActionFields
            selection.weekStart
            ""
            (payrollWorkbookSheetFamilyKey PayrollWorkbookSummary)
            Nothing
            Nothing
            Nothing
            Nothing
    route = FrontendSurfaceActionRoute
        { actionRouteUrl = pathTo CreatePayrollWorkbookConfigurationAction
        , actionRouteCustomHtmx = []
        , actionRouteStandardUrl = Just (pathTo CreatePayrollWorkbookConfigurationAction)
        , actionRouteExtraAttrs = [("id", "payroll-workbook-configuration-form")]
        }

renderFamilySelect :: Text -> Text -> Maybe PayrollWorkbookSheetFamily -> Bool -> Html
renderFamilySelect inputId fieldName selectedFamily isRequired = [hsx|
    <div class="col-12 col-sm-6 col-lg-2">
        <label class="form-label" for={inputId}>{inputLabel}</label>
        {selectControl}
    </div>
|]
  where
    inputLabel :: Text
    inputLabel = if isRequired then "Sheet 1" else "Next sheet"
    selectControl
        | isRequired = [hsx|
            <select id={inputId} class="form-select" name={fieldName} required="required">
                {forEach availablePayrollWorkbookSheetFamilies renderOption}
            </select>
        |]
        | otherwise = [hsx|
            <select id={inputId} class="form-select" name={fieldName}>
                {blankOption}
                {forEach availablePayrollWorkbookSheetFamilies renderOption}
            </select>
        |]
    blankOption
        | isRequired = mempty
        | otherwise = [hsx|<option value="">Not included</option>|]
    renderOption family = [hsx|
        <option value={payrollWorkbookSheetFamilyKey family} selected={selectedFamily == Just family}>{payrollWorkbookSheetFamilyLabel family}</option>
    |]

renderSavedConfigurationManagementRow :: ReportWeekSelection -> SavedPayrollWorkbookConfiguration -> Html
renderSavedConfigurationManagementRow selection configuration = [hsx|
    <div class="d-flex flex-wrap justify-content-between align-items-center gap-3" data-payroll-workbook-configuration={tshow configurationRecord.id}>
        <div>
            <div class="fw-semibold">{configurationRecord.name}</div>
            <div class="small app-muted">{savedConfigurationSummary configuration}</div>
        </div>
        <details>
            <summary class="btn btn-outline-danger btn-sm">Delete</summary>
            <div class="mt-2">{deleteForm}</div>
        </details>
    </div>
|]
  where
    configurationRecord = configuration.savedPayrollWorkbookConfigurationRecord
    deleteForm =
        renderFrontendSurfaceActionForm (AdminAction.deletePayrollWorkbookConfigurationAction fields) route [hsx|
            <button class="btn btn-danger btn-sm" type="submit">Confirm delete {configurationRecord.name}</button>
        |]
    fields = AdminAction.deletePayrollWorkbookConfigurationActionFields
    route = FrontendSurfaceActionRoute
        { actionRouteUrl = pathTo (DeletePayrollWorkbookConfigurationAction configurationRecord.id (tshow selection.weekStart))
        , actionRouteCustomHtmx = []
        , actionRouteStandardUrl = Just (pathTo (DeletePayrollWorkbookConfigurationAction configurationRecord.id (tshow selection.weekStart)))
        , actionRouteExtraAttrs = []
        }

createExportRoute :: Text -> FrontendSurfaceActionRoute
createExportRoute formId = FrontendSurfaceActionRoute
    { actionRouteUrl = pathTo CreateExportJobAction
    , actionRouteCustomHtmx = []
    , actionRouteStandardUrl = Just (pathTo CreateExportJobAction)
    , actionRouteExtraAttrs = [("id", formId)]
    }
