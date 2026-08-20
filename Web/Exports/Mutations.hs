module Web.Exports.Mutations
    ( exportJobTouchedResources
    , recordExportDownloadMutation
    , requestFixedExportMutation
    ) where

import Application.Helper.Export
import Application.Helper.FrontendContract.Surface.Admin.Resource (adminExportsResource)
import Application.Helper.SurfaceResource
import Web.Controller.Prelude
import qualified Data.Set as Set
import Web.SurfaceInvalidation (withDurableLiveMutation,
                                withDurableLiveMutationOutcome)

requestFixedExportMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => ExportJobType -> Day -> Day -> IO (Either Text (LiveMutationResult ExportJob))
requestFixedExportMutation exportType rangeStart rangeEnd = do
    outcome <-
        withDurableLiveMutationOutcome publicationFor $
            requestFixedExport exportType rangeStart rangeEnd
    pure (fmap (\exportJob -> liveMutationResult exportJob (exportJobTouchedResources exportJob)) outcome)
    where
        publicationFor = \case
            Left _ -> Nothing
            Right exportJob -> Just ("export.create", Set.fromList (exportJobTouchedResources exportJob))

recordExportDownloadMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => ExportJob -> IO (LiveMutationResult ExportJob)
recordExportDownloadMutation exportJob =
    withDurableLiveMutation "export.download" do
        updatedExportJob <- recordExportDownload exportJob
        pure (liveMutationResult updatedExportJob (exportJobTouchedResources updatedExportJob))

exportJobTouchedResources :: ExportJob -> [SurfaceResourceValue]
exportJobTouchedResources exportJob =
    [adminExportsResource exportJob.venueId]
