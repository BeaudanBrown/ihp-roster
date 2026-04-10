module Web.View.Exports.Index where

import Application.Helper.Export
import qualified Data.Text as Text
import Data.Time.Format (defaultTimeLocale, formatTime)
import Web.View.Prelude

data IndexView = IndexView
    { exportJobs                 :: [ExportJob]
    , reportDefinitions          :: [VenueReportDefinition]
    , allReportDefinitions       :: [VenueReportDefinition]
    , shiftTypes                 :: [ShiftType]
    , canManageReportDefinitions :: Bool
    , reportWeekSelection        :: ReportWeekSelection
    , defaultRangeStart          :: Day
    , defaultRangeEnd            :: Day
    }

instance View IndexView where
    html IndexView { .. } =
        let exportSetupPanel =
                renderAppPanel AppPanelConfig
                    { appPanelTitle = Nothing
                    , appPanelDescription = Nothing
                    , appPanelHasActions = False
                    , appPanelActions = mempty
                    , appPanelHasCustomHeader = False
                    , appPanelCustomHeader = mempty
                    , appPanelClass = "h-100"
                    , appPanelBodyClass = ""
                    , appPanelBody = [hsx|
                        <div class="border rounded p-3 mb-4 bg-light-subtle">
                            <div class="d-flex justify-content-between align-items-start gap-3 mb-3">
                                <div>
                                    <div class="fw-semibold mb-1">Payroll Reports</div>
                                    <div class="small app-muted">
                                        Week of {tshow reportWeekSelection.weekStart} to {tshow reportWeekSelection.weekEnd}
                                    </div>
                                </div>
                                <div class="btn-group btn-group-sm" role="group" aria-label="Report week navigation">
                                    <a
                                        href={appendQueryParams (pathTo ExportJobsAction) [("weekOffset", tshow (reportWeekSelection.weekOffset - 1))]}
                                        class="btn btn-outline-secondary"
                                    >
                                        Previous
                                    </a>
                                    <a href={ExportJobsAction} class="btn btn-outline-secondary">Current</a>
                                    <a
                                        href={appendQueryParams (pathTo ExportJobsAction) [("weekOffset", tshow (reportWeekSelection.weekOffset + 1))]}
                                        class="btn btn-outline-secondary"
                                    >
                                        Next
                                    </a>
                                </div>
                            </div>
                            <div class="small app-muted mb-3">
                                Venue report definitions decide which payroll exports are available for this venue. Staff-pay CSV and hourly ZIP reports both run through the same export-job lifecycle.
                            </div>
                            {renderReportDefinitionList reportWeekSelection reportDefinitions}
                            {if canManageReportDefinitions then renderReportDefinitionManagement allReportDefinitions shiftTypes else mempty}
                        </div>
                        <div class="border rounded p-3">
                            <div class="fw-semibold mb-2">Approved Timesheets CSV</div>
                            <div class="small app-muted mb-3">
                                Range-based CSV export for approved timesheet entries. This is separate from the legacy payroll report definitions.
                            </div>
                            <form method="POST" action={CreateExportJobAction} class="d-grid gap-3" data-disable-javascript-submission="true">
                                <div>
                                    <label class="form-label" for="rangeStart">From</label>
                                    <input
                                        id="rangeStart"
                                        class="form-control"
                                        type="date"
                                        name="rangeStart"
                                        value={tshow defaultRangeStart}
                                        required={True}
                                    />
                                </div>
                                <div>
                                    <label class="form-label" for="rangeEnd">To</label>
                                    <input
                                        id="rangeEnd"
                                        class="form-control"
                                        type="date"
                                        name="rangeEnd"
                                        value={tshow defaultRangeEnd}
                                        required={True}
                                    />
                                </div>
                                <div class="small app-muted">
                                    Scope is always limited to the current venue and the selected date range.
                                </div>
                                <button class="btn btn-primary" type="submit">Generate Export</button>
                            </form>
                        </div>
                    |]
                    }
            recentExportsPanel =
                renderAppPanel AppPanelConfig
                    { appPanelTitle = Just "Recent Exports"
                    , appPanelDescription = Nothing
                    , appPanelHasActions = True
                    , appPanelActions = [hsx|<a href={AdminAction} class="btn btn-outline-secondary btn-sm">Back to admin</a>|]
                    , appPanelHasCustomHeader = False
                    , appPanelCustomHeader = mempty
                    , appPanelClass = "h-100"
                    , appPanelBodyClass = ""
                    , appPanelBody = if null exportJobs then renderEmptyState else renderExportTable exportJobs
                    }
         in renderAppPage (AppPageConfig
            { appPageTitle = "Export Jobs"
            , appPageDescription = Nothing
            , appPageActions = mempty
            , appPageWidthClass = ""
            , appPageBody = [hsx|
                <div class="row g-3">
                    <div class="col-12 col-xl-5">
                        {exportSetupPanel}
                    </div>
                    <div class="col-12 col-xl-7">
                        {recentExportsPanel}
                    </div>
                </div>
            |]
            })

renderEmptyState :: Html
renderEmptyState = [hsx|
    <div class="app-muted mb-0">No export jobs yet.</div>
|]

renderReportDefinitionList :: ReportWeekSelection -> [VenueReportDefinition] -> Html
renderReportDefinitionList reportWeekSelection reportDefinitions
    | null reportDefinitions = [hsx|<div class="app-muted mb-0">No payroll report definitions are available for this venue yet.</div>|]
    | otherwise = [hsx|
        <div class="d-grid gap-2">
            {forEach reportDefinitions (renderReportDefinitionRow reportWeekSelection)}
        </div>
    |]

renderReportDefinitionRow :: ReportWeekSelection -> VenueReportDefinition -> Html
renderReportDefinitionRow reportWeekSelection reportDefinition = [hsx|
    <div class="border rounded p-2 bg-white">
        <div class="d-flex justify-content-between align-items-start gap-3">
            <div>
                <div class="fw-semibold">{reportDefinition.definition.name}</div>
                <div class="small app-muted font-monospace">{reportDefinition.definition.slug}</div>
            </div>
            <span class="badge bg-secondary-subtle text-secondary-emphasis">{renderReportEngineLabel reportDefinition.engine}</span>
        </div>
        <div class="small mt-2">{fromMaybe "" reportDefinition.definition.description}</div>
        {renderShiftTypeFilterSummary reportDefinition}
        <div class="mt-3">
            {renderReportDefinitionAction reportWeekSelection reportDefinition}
        </div>
    </div>
|]

renderReportEngineLabel :: ReportDefinitionEngine -> Text
renderReportEngineLabel StaffPayCsvReport        = "staff_pay_csv"
renderReportEngineLabel HourlyBreakdownZipReport = "hourly_breakdown_zip"

renderShiftTypeFilterSummary :: VenueReportDefinition -> Html
renderShiftTypeFilterSummary reportDefinition
    | null reportDefinition.shiftTypeFilters = [hsx|
        <div class="small app-muted mt-2">Applies to all shift types.</div>
    |]
    | otherwise = [hsx|
        <div class="small app-muted mt-2">
            Shift-type filter: {Text.intercalate ", " (map (.name) reportDefinition.shiftTypeFilters)}
        </div>
    |]

renderReportDefinitionAction :: ReportWeekSelection -> VenueReportDefinition -> Html
renderReportDefinitionAction reportWeekSelection reportDefinition = [hsx|
    <form method="POST" action={CreateExportJobAction} class="d-inline" data-disable-javascript-submission="true">
        <input type="hidden" name="reportSlug" value={reportDefinition.definition.slug} />
        <input type="hidden" name="weekOffset" value={tshow reportWeekSelection.weekOffset} />
        <button class="btn btn-primary btn-sm" type="submit">{renderGenerateButtonLabel reportDefinition.engine}</button>
    </form>
|]

renderGenerateButtonLabel :: ReportDefinitionEngine -> Text
renderGenerateButtonLabel StaffPayCsvReport        = "Generate CSV"
renderGenerateButtonLabel HourlyBreakdownZipReport = "Generate ZIP"

renderReportDefinitionManagement :: [VenueReportDefinition] -> [ShiftType] -> Html
renderReportDefinitionManagement reportDefinitions shiftTypes = [hsx|
    <div class="border-top mt-4 pt-4">
        <div class="fw-semibold mb-2">Manage Report Definitions</div>
        <div class="small app-muted mb-3">
            These venue-scoped definitions replace the old hardcoded report config. Use them to control report names, slugs, order, engine type, and optional shift-type filters.
        </div>
        <div class="d-grid gap-3">
            {renderReportDefinitionCreateForm shiftTypes}
            {forEach reportDefinitions (renderReportDefinitionEditor shiftTypes)}
        </div>
    </div>
|]

renderReportDefinitionCreateForm :: [ShiftType] -> Html
renderReportDefinitionCreateForm shiftTypes = [hsx|
    <form method="POST" action={CreateReportDefinitionAction} class="border rounded p-3 bg-white" data-disable-javascript-submission="true">
        <div class="fw-semibold mb-3">Add Report Definition</div>
        {renderReportDefinitionFields Nothing shiftTypes}
        <div class="mt-3">
            <button class="btn btn-outline-primary btn-sm" type="submit">Add Report Definition</button>
        </div>
    </form>
|]

renderReportDefinitionEditor :: [ShiftType] -> VenueReportDefinition -> Html
renderReportDefinitionEditor shiftTypes reportDefinition = [hsx|
    <form method="POST" action={UpdateReportDefinitionAction (get #id reportDefinition.definition)} class="border rounded p-3 bg-white" data-disable-javascript-submission="true">
        <div class="d-flex justify-content-between align-items-start gap-3 mb-3">
            <div>
                <div class="fw-semibold">{reportDefinition.definition.name}</div>
                <div class="small app-muted font-monospace">{reportDefinition.definition.slug}</div>
            </div>
            <span class={reportDefinitionStatusClass reportDefinition}>
                {if reportDefinition.definition.isActive then ("active" :: Text) else "inactive"}
            </span>
        </div>
        {renderReportDefinitionFields (Just reportDefinition) shiftTypes}
        <div class="mt-3">
            <button class="btn btn-outline-secondary btn-sm" type="submit">Update Report Definition</button>
        </div>
    </form>
|]

renderReportDefinitionFields :: Maybe VenueReportDefinition -> [ShiftType] -> Html
renderReportDefinitionFields maybeReportDefinition shiftTypes = [hsx|
    <div class="row g-2">
        <div class="col-12 col-md-4">
            <label class="form-label">Slug</label>
            <input class="form-control" type="text" name="slug" value={fromMaybe "" (fmap (.definition.slug) maybeReportDefinition)} placeholder="staff_hours" />
        </div>
        <div class="col-12 col-md-4">
            <label class="form-label">Name</label>
            <input class="form-control" type="text" name="name" value={fromMaybe "" (fmap (.definition.name) maybeReportDefinition)} placeholder="Staff Hours Report" />
        </div>
        <div class="col-12 col-md-2">
            <label class="form-label">Engine</label>
            <select class="form-select" name="engine">
                {renderEngineOption maybeReportDefinition StaffPayCsvReport}
                {renderEngineOption maybeReportDefinition HourlyBreakdownZipReport}
            </select>
        </div>
        <div class="col-12 col-md-2">
            <label class="form-label">Sort Order</label>
            <input class="form-control" type="number" name="sortOrder" value={tshow (fromMaybe 0 (fmap (.definition.sortOrder) maybeReportDefinition))} />
        </div>
        <div class="col-12">
            <label class="form-label">Description</label>
            <textarea class="form-control" rows="2" name="description">{fromMaybe "" (join (fmap (.definition.description) maybeReportDefinition))}</textarea>
        </div>
        <div class="col-12 col-md-3">
            <label class="form-label">Status</label>
            <select class="form-select" name="isActive">
                <option value="true" selected={fromMaybe True (fmap (.definition.isActive) maybeReportDefinition)}>Active</option>
                <option value="false" selected={not (fromMaybe True (fmap (.definition.isActive) maybeReportDefinition))}>Inactive</option>
            </select>
        </div>
        <div class="col-12">
            <label class="form-label">Shift-Type Filter</label>
            <div class="row g-2">
                {forEach shiftTypes (renderReportDefinitionShiftTypeCheckbox maybeReportDefinition)}
            </div>
            <div class="small app-muted mt-2">Leave all unchecked to include all shift types.</div>
        </div>
    </div>
|]

renderEngineOption :: Maybe VenueReportDefinition -> ReportDefinitionEngine -> Html
renderEngineOption maybeReportDefinition engine = [hsx|
    <option value={renderReportEngineLabel engine} selected={currentEngine == engine}>{renderReportEngineLabel engine}</option>
|]
    where
        currentEngine = maybe StaffPayCsvReport (.engine) maybeReportDefinition

renderReportDefinitionShiftTypeCheckbox :: Maybe VenueReportDefinition -> ShiftType -> Html
renderReportDefinitionShiftTypeCheckbox maybeReportDefinition shiftType = [hsx|
    <div class="col-12 col-md-6">
        <label class="form-check border rounded p-2 d-flex align-items-center gap-2">
            <input
                class="form-check-input mt-0"
                type="checkbox"
                name="shiftTypeIds"
                value={tshow (unpackId (get #id shiftType))}
                checked={isChecked}
            />
            <span class="form-check-label">{shiftType.name}</span>
        </label>
    </div>
|]
    where
        selectedShiftTypeIds = fromMaybe [] (fmap (map (unpackId . get #id) . (.shiftTypeFilters)) maybeReportDefinition)
        isChecked = unpackId (get #id shiftType) `elem` selectedShiftTypeIds

reportDefinitionStatusClass :: VenueReportDefinition -> Text
reportDefinitionStatusClass reportDefinition =
    if reportDefinition.definition.isActive
        then "badge bg-success-subtle text-success-emphasis"
        else "badge bg-secondary-subtle text-secondary-emphasis"

renderExportTable :: [ExportJob] -> Html
renderExportTable exportJobs = [hsx|
    <div class="table-responsive">
        <table class="table table-sm align-middle mb-0">
            <thead>
                <tr>
                    <th>Export</th>
                    <th>Created</th>
                    <th>Range</th>
                    <th>Status</th>
                    <th>Expires</th>
                    <th class="text-end">Action</th>
                </tr>
            </thead>
            <tbody>
                {forEach exportJobs renderExportJobRow}
            </tbody>
        </table>
    </div>
|]

renderExportJobRow :: ExportJob -> Html
renderExportJobRow exportJob = [hsx|
    <tr>
        <td>{renderExportDescriptor exportJob}</td>
        <td>{formatTimestamp exportJob.createdAt}</td>
        <td>{renderRange exportJob}</td>
        <td>{renderStatusBadge exportJob}</td>
        <td>{formatTimestamp exportJob.expiresAt}</td>
        <td class="text-end">{renderDownloadAction exportJob}</td>
    </tr>
|]

renderRange :: ExportJob -> Html
renderRange exportJob =
    case (exportJob.rangeStart, exportJob.rangeEnd) of
        (Just rangeStart, Just rangeEnd) -> [hsx|{tshow rangeStart} to {tshow rangeEnd}|]
        _ -> [hsx|<span class="app-muted">Unscoped</span>|]

renderStatusBadge :: ExportJob -> Html
renderStatusBadge exportJob =
    case parseExportJobStatus exportJob.status of
        Just ExportReady -> [hsx|<span class="badge bg-success-subtle text-success-emphasis">ready</span>|]
        Just ExportExpired -> [hsx|<span class="badge bg-secondary">expired</span>|]
        _ -> [hsx|<span class="badge bg-warning-subtle text-warning-emphasis">pending</span>|]

renderExportDescriptor :: ExportJob -> Html
renderExportDescriptor exportJob = [hsx|
    <div class="d-grid gap-1">
        <span class="fw-semibold">{fromMaybe exportJob.exportType exportJob.fileName}</span>
        <span class="small app-muted font-monospace">{exportJob.exportType}</span>
    </div>
|]

renderDownloadAction :: ExportJob -> Html
renderDownloadAction exportJob =
    case (parseExportJobStatus exportJob.status, exportJob.fileName) of
        (Just ExportReady, Just _) ->
            let downloadUrl = appendQueryParams (pathTo (DownloadExportJobAction (get #id exportJob))) [("token", tshow exportJob.downloadToken)]
             in [hsx|
                    <a href={downloadUrl} class="btn btn-outline-primary btn-sm">Download</a>
                |]
        _ -> [hsx|<span class="app-muted small">Unavailable</span>|]

formatTimestamp :: UTCTime -> Text
formatTimestamp timestamp = Text.pack (formatTime defaultTimeLocale "%Y-%m-%d %H:%M UTC" timestamp)
