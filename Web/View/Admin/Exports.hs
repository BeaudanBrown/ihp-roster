{-# LANGUAGE TypeApplications #-}

module Web.View.Admin.Exports
    ( renderExportsSection
    , renderExportsSectionMount
    , renderExportsSectionFragment
    , renderExportsSectionFragmentWithSwap
    ) where

import Application.Helper.Export
import qualified Application.Helper.FrontendContract.AppShell as AppShell
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             appShellActionAttrs,
                                                             appShellActionByMarker,
                                                             defaultAppShellActionRoute)
import qualified Application.Helper.FrontendContract.Surface.Admin as Surface
import qualified Application.Helper.FrontendContract.Surface.Admin.Action as AdminAction
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            defaultFrontendSurfaceActionRoute,
                                                            renderFrontendSurfaceActionFormWithHiddenFields,
                                                            renderFrontendSurfaceMount)
import Application.Helper.FrontendContract.Surface.Values
import qualified Data.Text as Text
import Web.Admin.FrontendSurface (AdminVenueScopeValue (..),
                                  adminExportsSurfaceImplForWindow)
import Web.Exports.Selection (renderFilteredExportButton)
import Web.View.Admin.Common
import Web.View.Prelude

adminExportsFragmentId :: Text
adminExportsFragmentId = surfaceFragmentTargetId @Surface.AdminExportsSurface @Surface.AdminExportsFragment noSurfaceFields

-- The page owns the mount; live responses replace only its inner target.
renderExportsSectionMount :: Bool -> ReportWeekSelection -> [SavedPayrollWorkbookConfiguration] -> Html
renderExportsSectionMount canEmail selection savedConfigurations =
    renderFrontendSurfaceMount (adminExportsSurfaceImplForWindow AdminVenueScopeValue { adminVenueId = currentAdminVenueScopeId, adminRosterGroupId = Nothing } selection.weekStart)
        (renderExportsSectionFragment canEmail selection savedConfigurations)

renderExportsSectionFragment :: Bool -> ReportWeekSelection -> [SavedPayrollWorkbookConfiguration] -> Html
renderExportsSectionFragment =
    renderExportsSectionFragmentWithSwap Nothing

renderExportsSectionFragmentWithSwap :: Maybe Text -> Bool -> ReportWeekSelection -> [SavedPayrollWorkbookConfiguration] -> Html
renderExportsSectionFragmentWithSwap maybeSwapOob canEmail selection savedConfigurations =
    [hsx|
        <div id={adminExportsFragmentId}
             hx-swap-oob={maybeSwapOob}>
            {renderExportsSection canEmail selection savedConfigurations}
        </div>
    |]

renderExportsSection :: Bool -> ReportWeekSelection -> [SavedPayrollWorkbookConfiguration] -> Html
renderExportsSection canEmail selection savedConfigurations =
    renderConfigSection
        "admin-exports-section"
        mempty
        [hsx|
            <button type="button" class="btn btn-outline-primary mb-3" {...appShellActionAttrs (appShellActionByMarker @AppShell.OpenPayrollReports) (defaultAppShellActionRoute (pathTo PayrollReportsAction))}>Scheduled reports</button>
            {renderExportWeekSelector selection}
            {unless canEmail incompleteWeekMessage}
            {renderExportGenerationForm canEmail selection savedConfigurations}
        |]
        mempty

incompleteWeekMessage :: Html
incompleteWeekMessage = [hsx|<p class="small app-muted">Email is available only for completed roster weeks. Select a previous week to email an export.</p>|]

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

renderExportGenerationForm :: Bool -> ReportWeekSelection -> [SavedPayrollWorkbookConfiguration] -> Html
renderExportGenerationForm canEmail selection savedConfigurations = [hsx|
    <div class="d-flex flex-wrap justify-content-between align-items-center gap-2 mb-3">
        <div class="fw-semibold">Payroll Workbook exports</div>
        {renderAddExportButton selection}
    </div>
    <div class="d-grid gap-2" data-payroll-workbook-configuration-list="true">
        {if null savedConfigurations then renderEmptyState "No Payroll Workbook exports configured." else forEach savedConfigurations (renderSavedConfigurationCard canEmail selection)}
    </div>
|]

renderSavedConfigurationCard :: Bool -> ReportWeekSelection -> SavedPayrollWorkbookConfiguration -> Html
renderSavedConfigurationCard canEmail selection configuration = [hsx|
    <div class={appSurfaceClasses "p-3"}
         data-fixed-export-card="true"
         data-export-type={exportJobTypeToText PayrollWorkbookXlsx}
         data-payroll-workbook-configuration={tshow configurationRecord.id}>
        <div class="d-flex flex-wrap justify-content-between align-items-center gap-3">
            <div>
                <div class="fw-semibold">{configurationRecord.name}</div>
                <div class="small app-muted">{savedConfigurationSummary configuration}</div>
            </div>
            <div class="d-flex flex-wrap gap-2">
                {downloadForm}
                {renderFilteredExportButton selection.weekStart selection.weekEnd PayrollWorkbookXlsx (Just (unpackId configurationRecord.id))}
                {emailButton}
                {renderEditExportButton selection configurationRecord}
                {renderDeleteExportButton selection configurationRecord}
            </div>
        </div>
    </div>
|]
  where
    configurationRecord = configuration.savedPayrollWorkbookConfigurationRecord
    emailButton = [hsx|<button type="button" class="btn btn-outline-primary" disabled={not canEmail} {...emailAttrs}>Email…</button>|]
    emailAttrs = appShellActionAttrs (appShellActionByMarker @AppShell.OpenPayrollReportEmail)
        (defaultAppShellActionRoute (pathTo (EmailPayrollReportAction configurationRecord.id (tshow selection.weekStart))))
    fields = AdminAction.createExportJobActionFields selection.weekStart selection.weekEnd PayrollWorkbookXlsx (Just (unpackId configurationRecord.id))
    downloadForm =
        renderFrontendSurfaceActionFormWithHiddenFields
            (AdminAction.createExportJobAction fields)
            (createExportRoute ("admin-saved-payroll-workbook-download-" <> tshow configurationRecord.id))
            [hsx|<button class="btn btn-primary" type="submit">Download</button>|]

savedConfigurationSummary :: SavedPayrollWorkbookConfiguration -> Text
savedConfigurationSummary configuration =
    "Sheets: "
        <> Text.intercalate
            " → "
            (map payrollWorkbookSheetFamilyConfigurationLabel configuration.savedPayrollWorkbookConfigurationDefinition.payrollWorkbookDefinitionSheetFamilies)

renderAddExportButton :: ReportWeekSelection -> Html
renderAddExportButton selection =
    [hsx|<button {...attributes}>Create new export</button>|]
  where
    attributes = appShellActionAttrs
        (appShellActionByMarker @AppShell.OpenPayrollWorkbookConfigurationDialog)
        (exportDialogActionRoute
            (pathTo (NewPayrollWorkbookConfigurationAction (tshow selection.weekStart)))
            "btn btn-outline-primary")

renderEditExportButton :: ReportWeekSelection -> PayrollWorkbookConfiguration -> Html
renderEditExportButton selection configuration =
    [hsx|<button {...attributes}>Edit</button>|]
  where
    attributes = appShellActionAttrs
        (appShellActionByMarker @AppShell.OpenPayrollWorkbookConfigurationDialog)
        (exportDialogActionRoute
            (pathTo (EditPayrollWorkbookConfigurationAction configuration.id (tshow selection.weekStart)))
            "btn btn-outline-secondary")

renderDeleteExportButton :: ReportWeekSelection -> PayrollWorkbookConfiguration -> Html
renderDeleteExportButton selection configuration =
    [hsx|<button {...attributes}>Delete</button>|]
  where
    attributes = appShellActionAttrs
        (appShellActionByMarker @AppShell.OpenPayrollWorkbookConfigurationDeleteDialog)
        (exportDialogActionRoute
            (pathTo (ConfirmDeletePayrollWorkbookConfigurationAction configuration.id (tshow selection.weekStart)))
            "btn btn-outline-danger")

exportDialogActionRoute :: Text -> Text -> AppShellActionRoute
exportDialogActionRoute url buttonClass =
    (defaultAppShellActionRoute url)
        { appShellActionRouteExtraAttrs = [("class", buttonClass), ("type", "button")]
        }

createExportRoute :: Text -> FrontendSurfaceActionRoute
createExportRoute formId = ((defaultFrontendSurfaceActionRoute (pathTo CreateExportJobAction))
    { actionRouteStandardUrl = Just (pathTo CreateExportJobAction)
    , actionRouteExtraAttrs = [("id", formId)]
    })
