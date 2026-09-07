module Web.Exports.Mutations
    ( createPayrollWorkbookConfigurationMutation
    , updatePayrollWorkbookConfigurationMutation
    , deletePayrollWorkbookConfigurationMutation
    , exportJobTouchedResources
    , recordExportDownloadMutation
    , requestFixedExportMutation
    , requestFixedExportWithPayrollWorkbookDefinitionMutation
    ) where

import Application.Error.Runtime (throwExternalRuntime)
import Application.Helper.Export
import Application.Helper.FrontendContract.Surface.Admin.Resource (adminExportsResource)
import Application.Helper.SurfaceResource
import qualified Control.Exception as Exception
import qualified Data.Set as Set
import IHP.ModelSupport.Types (HasqlSessionError)
import Web.Controller.Prelude
import Web.SurfaceInvalidation (withDurableLiveMutation,
                                withDurableLiveMutationOutcome)

requestFixedExportMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => ExportJobType -> Day -> Day -> IO (Either Text (LiveMutationResult ExportJob))
requestFixedExportMutation exportType rangeStart rangeEnd =
    requestExportMutation (requestFixedExport exportType rangeStart rangeEnd)

requestFixedExportWithPayrollWorkbookDefinitionMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => PayrollWorkbookDefinition -> Day -> Day -> IO (Either Text (LiveMutationResult ExportJob))
requestFixedExportWithPayrollWorkbookDefinitionMutation definition rangeStart rangeEnd =
    requestExportMutation (requestPayrollWorkbookXlsxExportWithDefinition definition rangeStart rangeEnd)

-- Keep the database context abstract until the durable transaction supplies it;
-- a pre-built IO action would perform export writes on the outer connection.
requestExportMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => ((?modelContext :: ModelContext) => IO (Either Text ExportJob)) -> IO (Either Text (LiveMutationResult ExportJob))
requestExportMutation requestExport = do
    outcome <-
        withDurableLiveMutationOutcome publicationFor requestExport
    pure (fmap (\exportJob -> liveMutationResult exportJob (exportJobTouchedResources exportJob)) outcome)
    where
        publicationFor = \case
            Left _ -> Nothing
            Right exportJob -> Just ("export.create", Set.fromList (exportJobTouchedResources exportJob))

createPayrollWorkbookConfigurationMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => NewPayrollWorkbookConfiguration -> IO (Either PayrollWorkbookConfigurationError (LiveMutationResult SavedPayrollWorkbookConfiguration))
createPayrollWorkbookConfigurationMutation input = do
    transactionResult :: Either HasqlSessionError (Either PayrollWorkbookConfigurationError SavedPayrollWorkbookConfiguration) <-
        Exception.try $
            withDurableLiveMutationOutcome publicationFor $
                createSavedPayrollWorkbookConfigurationInCurrentTransaction input
    case transactionResult of
        Right outcome -> pure (fmap (\configuration -> liveMutationResult configuration [adminExportsResource (unpackId currentVenueId)]) outcome)
        Left sessionError ->
            case payrollWorkbookConfigurationPersistenceError normalizedName sessionError of
                Just configurationError -> pure (Left configurationError)
                Nothing                 -> throwExternalRuntime sessionError
  where
    normalizedName = normalizePayrollWorkbookConfigurationName input.newPayrollWorkbookConfigurationName
    publicationFor = \case
        Left _ -> Nothing
        Right _ -> Just ("payroll_workbook_configuration.create", Set.singleton (adminExportsResource (unpackId currentVenueId)))

updatePayrollWorkbookConfigurationMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id PayrollWorkbookConfiguration -> UpdatePayrollWorkbookConfiguration -> IO (Either PayrollWorkbookConfigurationError (LiveMutationResult SavedPayrollWorkbookConfiguration))
updatePayrollWorkbookConfigurationMutation configurationId input = do
    transactionResult :: Either HasqlSessionError (Either PayrollWorkbookConfigurationError SavedPayrollWorkbookConfiguration) <-
        Exception.try $
            withDurableLiveMutationOutcome publicationFor do
                lockedRows :: [Only UUID] <- unsafeSqlQuery
                    "SELECT id FROM payroll_workbook_configurations WHERE id = ? AND venue_id = ? FOR UPDATE"
                    (unpackId configurationId, unpackId currentVenueId)
                if null lockedRows
                    then pure (Left PayrollWorkbookConfigurationNotFound)
                    else updateSavedPayrollWorkbookConfigurationInCurrentTransaction configurationId input
    case transactionResult of
        Right outcome -> pure (fmap (\configuration -> liveMutationResult configuration [adminExportsResource (unpackId currentVenueId)]) outcome)
        Left sessionError ->
            case payrollWorkbookConfigurationPersistenceError normalizedName sessionError of
                Just configurationError -> pure (Left configurationError)
                Nothing                 -> throwExternalRuntime sessionError
  where
    normalizedName = normalizePayrollWorkbookConfigurationName input.updatePayrollWorkbookConfigurationName
    publicationFor = \case
        Left _ -> Nothing
        Right _ -> Just ("payroll_workbook_configuration.update", Set.singleton (adminExportsResource (unpackId currentVenueId)))

deletePayrollWorkbookConfigurationMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id PayrollWorkbookConfiguration -> IO (Either PayrollWorkbookConfigurationError (LiveMutationResult ()))
deletePayrollWorkbookConfigurationMutation configurationId = do
    outcome <-
        withDurableLiveMutationOutcome publicationFor do
            -- QueryBuilder has no row-lock combinator. Serialize concurrent
            -- delete confirmations so a request that becomes stale resolves to
            -- NotFound instead of attempting a second delete.
            lockedRows :: [Only UUID] <- unsafeSqlQuery
                "SELECT id FROM payroll_workbook_configurations WHERE id = ? AND venue_id = ? FOR UPDATE"
                (unpackId configurationId, unpackId currentVenueId)
            if null lockedRows
                then pure (Left PayrollWorkbookConfigurationNotFound)
                else deleteSavedPayrollWorkbookConfiguration configurationId
    pure (fmap (\() -> liveMutationResult () [adminExportsResource (unpackId currentVenueId)]) outcome)
  where
    publicationFor = \case
        Left _ -> Nothing
        Right () -> Just ("payroll_workbook_configuration.delete", Set.singleton (adminExportsResource (unpackId currentVenueId)))

recordExportDownloadMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => ExportJob -> IO (LiveMutationResult ExportJob)
recordExportDownloadMutation exportJob =
    withDurableLiveMutation "export.download" do
        updatedExportJob <- recordExportDownload exportJob
        pure (liveMutationResult updatedExportJob (exportJobTouchedResources updatedExportJob))

exportJobTouchedResources :: ExportJob -> [SurfaceResourceValue]
exportJobTouchedResources exportJob =
    [adminExportsResource exportJob.venueId]
