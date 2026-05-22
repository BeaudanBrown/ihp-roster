{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.View.Admin.Exports
    ( AdminExportsLiveFragment (..)
    , adminExportsFragment
    , adminExportsLiveSurfaceDefinition
    , renderExportsSection
    , renderExportsSectionFragment
    ) where

import Application.Helper.Controller (currentVenueOrNothing)
import Application.Helper.Export
import Application.Helper.LiveResource (LiveResource (..))
import Application.Helper.LiveSurface
import Application.Helper.LiveUpdate
import Web.View.Admin.Common
import Web.View.Prelude

data AdminExportsSurface

data AdminExportsLiveFragment
    = AdminExportsLiveFragment
    deriving (Eq, Show)

adminExportsFragment :: AdminExportsLiveFragment
adminExportsFragment =
    AdminExportsLiveFragment

adminExportsFragmentId :: Text
adminExportsFragmentId = "admin-exports-fragment"

adminExportsLiveSurfaceDefinition :: (?context :: ControllerContext) => TypedLiveSurfaceDefinition AdminExportsSurface () AdminExportsLiveFragment
adminExportsLiveSurfaceDefinition =
    TypedLiveSurfaceDefinition
        { typedSurfaceFeature = "admin-exports"
        , typedSurfaceScope = const (SurfaceScope AdminExportsScope { venueId = currentVenueScopeId })
        , typedSurfaceScopeFromWire = \case
            AdminExportsScope { venueId } | venueId == currentVenueScopeId -> Just ()
            _ -> Nothing
        , typedSurfaceDefaultFragments = const [adminExportsFragment]
        , typedSurfaceFragmentContract = \() fragment ->
            mkSurfaceFragmentContract
                (adminExportsLiveFragmentRef fragment)
                (liveFragmentDependsOn (AdminExportsResource currentVenueScopeId) [])
        , typedSurfaceDecorateRequestsWithin = const ["#" <> adminExportsFragmentId]
        , typedSurfaceAuthorize = liveSurfaceAuthorizationByRequirement (const (RequireCurrentVenueAdmin currentVenueScopeId))
        }

adminExportsLiveFragmentRef :: (?context :: ControllerContext) => AdminExportsLiveFragment -> SurfaceFragmentRef AdminExportsSurface
adminExportsLiveFragmentRef AdminExportsLiveFragment =
    mkSurfaceFragmentRef
        AdminExportsFragment
        adminExportsFragmentId
        (pathTo ShowAdminExportsFragmentAction)

currentVenueScopeId :: (?context :: ControllerContext) => UUID
currentVenueScopeId =
    case currentVenueOrNothing of
        Just venue -> unpackId venue.id
        Nothing -> error "Admin exports live surface requires a current venue"

renderExportsSectionFragment :: ReportWeekSelection -> Day -> Day -> [ExportJob] -> Html
renderExportsSectionFragment reportWeekSelection defaultRangeStart defaultRangeEnd exportJobs = [hsx|
    <div id={adminExportsFragmentId}
         data-live-update-surface={liveSurfaceConfigJson (mkTypedDefinedLiveSurface adminExportsLiveSurfaceDefinition ())}>
        {renderExportsSection reportWeekSelection defaultRangeStart defaultRangeEnd exportJobs}
    </div>
|]

renderExportsSection :: ReportWeekSelection -> Day -> Day -> [ExportJob] -> Html
renderExportsSection reportWeekSelection defaultRangeStart defaultRangeEnd exportJobs =
    renderConfigSection
        "exports"
        "Exports"
        ("Generate venue exports for approved shifts. The date range defaults to the current roster week: " <> tshow reportWeekSelection.weekStart <> " to " <> tshow reportWeekSelection.weekEnd <> ".")
        (renderExportSummary exportJobs)
        mempty
        [hsx|
            <form id="admin-export-generation-form" method="POST" action={CreateExportJobAction} class={appSurfaceClasses "p-3"} data-disable-javascript-submission="true">
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
