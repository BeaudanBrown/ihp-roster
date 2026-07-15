module Web.Exports.Mutations
    ( exportJobTouchedResources
    , recordExportDownloadMutation
    , requestFixedExportMutation
    ) where

import Application.Helper.Export
import Application.Helper.FrontendContract.Surface.Admin.Resource (adminExportsResource)
import Application.Helper.SurfaceResource
import Web.Controller.Prelude
import Web.SurfaceInvalidation (invalidateTouchedResources)

requestFixedExportMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => ExportJobType -> Day -> Day -> IO (Either Text (LiveMutationResult ExportJob))
requestFixedExportMutation exportType rangeStart rangeEnd = do
    requestFixedExport exportType rangeStart rangeEnd >>= \case
        Left message -> pure (Left message)
        Right exportJob -> do
            result <-
                invalidateTouchedResources "export.create" $
                    liveMutationResult exportJob (exportJobTouchedResources exportJob)
            pure (Right result)

recordExportDownloadMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => ExportJob -> IO (LiveMutationResult ExportJob)
recordExportDownloadMutation exportJob = do
    updatedExportJob <- recordExportDownload exportJob
    invalidateTouchedResources "export.download" $
        liveMutationResult updatedExportJob (exportJobTouchedResources updatedExportJob)

exportJobTouchedResources :: ExportJob -> [SurfaceResourceValue]
exportJobTouchedResources exportJob =
    [adminExportsResource exportJob.venueId]
