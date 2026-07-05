{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.View.Admin.Exports
    ( renderExportsSection
    , renderExportsSectionFragment
    , renderExportsSectionFragmentWithSwap
    ) where

import Application.Helper.Controller (currentVenueOrNothing)
import Application.Helper.Export
import Application.Helper.FrontendContract.Surface.Runtime (renderFrontendSurfaceMount)
import Web.Admin.FrontendSurface (AdminVenueScopeValue (..),
                                  adminExportsSurfaceImpl)
import Web.View.Admin.Common
import Web.View.Prelude

adminExportsFragmentId :: Text
adminExportsFragmentId = "admin-exports-fragment"

currentVenueScopeId :: (?context :: ControllerContext) => UUID
currentVenueScopeId =
    case currentVenueOrNothing of
        Just venue -> unpackId venue.id
        Nothing -> error "Admin exports live surface requires a current venue"

renderExportsSectionFragment :: ReportWeekSelection -> Day -> Day -> [ExportJob] -> Html
renderExportsSectionFragment =
    renderExportsSectionFragmentWithSwap Nothing

renderExportsSectionFragmentWithSwap :: Maybe Text -> ReportWeekSelection -> Day -> Day -> [ExportJob] -> Html
renderExportsSectionFragmentWithSwap maybeSwapOob reportWeekSelection defaultRangeStart defaultRangeEnd exportJobs =
    renderFrontendSurfaceMount (adminExportsSurfaceImpl AdminVenueScopeValue { adminVenueId = currentVenueScopeId, adminRosterGroupId = Nothing }) [hsx|
        <div id={adminExportsFragmentId}
             hx-swap-oob={maybeSwapOob}>
            {renderExportsSection reportWeekSelection defaultRangeStart defaultRangeEnd exportJobs}
        </div>
    |]

renderExportsSection :: ReportWeekSelection -> Day -> Day -> [ExportJob] -> Html
renderExportsSection _reportWeekSelection defaultRangeStart defaultRangeEnd exportJobs =
    renderConfigSection
        "admin-exports-section"
        (renderExportSummary exportJobs)
        mempty
        [hsx|
            <form id="admin-export-generation-form"
                  method="POST"
                  action={CreateExportJobAction}
                  class={appSurfaceClasses "p-3"}
                  data-disable-javascript-submission="true"
                  hx-post={CreateExportJobAction}
                  hx-target={"#" <> adminExportsFragmentId}
                  hx-swap="none"
                  hx-push-url="false">
                <div class="row g-3 align-items-end">
                    <div class="col-12 col-md-4 col-lg-3">
                        <label class="form-label" for="admin-export-range-start">From</label>
                        <input id="admin-export-range-start" class="form-control" type="date" name="rangeStart" value={tshow defaultRangeStart} required={True} />
                    </div>
                    <div class="col-12 col-md-4 col-lg-3">
                        <label class="form-label" for="admin-export-range-end">To</label>
                        <input id="admin-export-range-end" class="form-control" type="date" name="rangeEnd" value={tshow defaultRangeEnd} required={True} />
                    </div>
                    <div class="col-12">
                        <div class="row g-2">
                            {forEach fixedExportDefinitions renderFixedExportAction}
                        </div>
                    </div>
                </div>
            </form>
            <div class="mt-4">
                <div class="fw-semibold mb-2">Recent Exports</div>
                {if null exportJobs then renderEmptyState "No export jobs yet." else renderExportTable exportJobs}
            </div>
        |]

renderExportSummary :: [ExportJob] -> Html
renderExportSummary exportJobs = [hsx|
    <p class="small app-muted mb-3">
        {tshow (length fixedExportDefinitions)} fixed export formats are available. {tshow (length exportJobs)} recent export jobs are listed below.
    </p>
|]

renderFixedExportAction :: FixedExportDefinition -> Html
renderFixedExportAction exportDefinition = [hsx|
    <div class="col-12 col-lg-6">
        <div class={appSurfaceClasses "p-3 h-100"} data-fixed-export-card="true" data-export-type={exportJobTypeToText exportDefinition.fixedExportType}>
            <div class="d-flex justify-content-between align-items-start gap-3">
                <div>
                    <div class="fw-semibold">{exportDefinition.fixedExportLabel}</div>
                    <div class="small app-muted">{exportDefinition.fixedExportDescription}</div>
                </div>
                {renderAppStatusBadge AppStatusNeutral (exportJobTypeToText exportDefinition.fixedExportType)}
            </div>
            <div class="mt-3">
                <button
                    class="btn btn-outline-primary btn-sm"
                    type="submit"
                    name="exportType"
                    value={exportJobTypeToText exportDefinition.fixedExportType}
                >
                    Generate
                </button>
            </div>
        </div>
    </div>
|]

renderExportTable :: [ExportJob] -> Html
renderExportTable exportJobs = [hsx|
    <div class="table-responsive">
        <table id="export-jobs-table" class="table table-sm align-middle mb-0">
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
    <tr data-export-job-row="true" data-export-job-file={fromMaybe exportJob.exportType exportJob.fileName} data-export-job-status={exportJob.status}>
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
        Just ExportReady -> [hsx|<span class={appStatusBadgeClass AppStatusSuccess} data-export-job-status-badge="ready">ready</span>|]
        Just ExportExpired -> [hsx|<span class={appStatusBadgeClass AppStatusNeutral} data-export-job-status-badge="expired">expired</span>|]
        _ -> [hsx|<span class={appStatusBadgeClass AppStatusWarning} data-export-job-status-badge="pending">pending</span>|]

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
