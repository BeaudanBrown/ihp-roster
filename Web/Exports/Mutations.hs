module Web.Exports.Mutations
    ( exportJobTouchedResources
    , recordExportDownloadMutation
    , requestFixedExportMutation
    ) where

import Application.Helper.Export
import Application.Helper.LiveResource
import Web.Controller.Prelude
import Web.LiveResourceInvalidation (invalidateTouchedResources)

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

exportJobTouchedResources :: ExportJob -> [LiveResource]
exportJobTouchedResources exportJob =
    [AdminExportsResource exportJob.venueId]
