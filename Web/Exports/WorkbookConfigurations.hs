{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

-- | Request-facing saved Workbook workflows. The controller retains lifecycle,
-- permission responses and writability checks; this owner adapts the existing
-- nominal AppShell fields and returns completion data without rendering HTTP.
module Web.Exports.WorkbookConfigurations
    ( WorkbookEditorOutcome (..)
    , createSavedWorkbookFromRequest
    , editSavedWorkbookFromRequest
    ) where

import Application.Helper.Export
import qualified Application.Helper.FrontendContract.AppShell as AppShell
import Application.Helper.FrontendContract.AppShell.Request (parseAppShellActionParams)
import Application.Helper.FrontendContract.Surface.Request (SurfaceRequestFieldError)
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldValue)
import Application.Helper.SurfaceResource (LiveMutationResult)
import Web.Controller.Prelude
import Web.Exports.Mutations (createPayrollWorkbookConfigurationMutation,
                              updatePayrollWorkbookConfigurationMutation)
import Web.View.Admin.PayrollWorkbookConfigurationDialog

-- Transport failures and semantic failures deliberately carry different drafts.
-- Success can only be returned after the existing durable mutation has committed.
data WorkbookEditorOutcome
    = WorkbookEditorInvalidFields !Day !PayrollWorkbookConfigurationDraft ![SurfaceRequestFieldError]
    | WorkbookEditorRejected !Day !PayrollWorkbookConfigurationDraft !PayrollWorkbookConfigurationError
    | WorkbookCreated !Day !(LiveMutationResult SavedPayrollWorkbookConfiguration)
    | WorkbookUpdated !Day !(LiveMutationResult SavedPayrollWorkbookConfiguration)

createSavedWorkbookFromRequest ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO WorkbookEditorOutcome
createSavedWorkbookFromRequest =
    case parseAppShellActionParams @AppShell.CreatePayrollWorkbookConfigurationOverlay of
        Left errors -> invalidFields Nothing errors
        Right fields -> do
            let anchorDate = surfaceFieldValue @AppShell.ExportAnchorDateField fields
            let familyKeys = surfaceFieldValue @AppShell.PayrollWorkbookSheetFamiliesField fields
            case mapM payrollWorkbookSheetFamilyFromText familyKeys of
                Left message -> pure (WorkbookEditorRejected anchorDate newPayrollWorkbookConfigurationDraft (PayrollWorkbookConfigurationInvalidDefinition message))
                Right families -> do
                    let draft =
                            newPayrollWorkbookConfigurationDraft
                                { payrollWorkbookConfigurationDraftName = surfaceFieldValue @AppShell.PayrollWorkbookConfigurationNameField fields
                                , payrollWorkbookConfigurationDraftFamilies = families
                                }
                    let input =
                            NewPayrollWorkbookConfiguration
                                { newPayrollWorkbookConfigurationName = draft.payrollWorkbookConfigurationDraftName
                                , newPayrollWorkbookConfigurationDefinitionVersion = currentPayrollWorkbookDefinitionVersion
                                , newPayrollWorkbookConfigurationFamilyKeys = familyKeys
                                }
                    createPayrollWorkbookConfigurationMutation input >>= \case
                        Left configurationError -> pure (WorkbookEditorRejected anchorDate draft configurationError)
                        Right result -> pure (WorkbookCreated anchorDate result)

editSavedWorkbookFromRequest ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id PayrollWorkbookConfiguration ->
    IO WorkbookEditorOutcome
editSavedWorkbookFromRequest configurationId =
    case parseAppShellActionParams @AppShell.UpdatePayrollWorkbookConfigurationOverlay of
        Left errors -> invalidFields (Just configurationId) errors
        Right fields -> do
            let anchorDate = surfaceFieldValue @AppShell.ExportAnchorDateField fields
            let familyKeys = surfaceFieldValue @AppShell.PayrollWorkbookSheetFamiliesField fields
            let expectedRevision = surfaceFieldValue @AppShell.PayrollWorkbookConfigurationRevisionField fields
            case mapM payrollWorkbookSheetFamilyFromText familyKeys of
                Left message ->
                    pure (WorkbookEditorRejected
                        anchorDate
                        newPayrollWorkbookConfigurationDraft
                            { payrollWorkbookConfigurationDraftId = Just configurationId
                            , payrollWorkbookConfigurationDraftRevision = expectedRevision
                            }
                        (PayrollWorkbookConfigurationInvalidDefinition message))
                Right families -> do
                    let draft =
                            PayrollWorkbookConfigurationDraft
                                { payrollWorkbookConfigurationDraftId = Just configurationId
                                , payrollWorkbookConfigurationDraftName = surfaceFieldValue @AppShell.PayrollWorkbookConfigurationNameField fields
                                , payrollWorkbookConfigurationDraftFamilies = families
                                , payrollWorkbookConfigurationDraftRevision = expectedRevision
                                , payrollWorkbookConfigurationDraftError = Nothing
                                }
                    let input =
                            UpdatePayrollWorkbookConfiguration
                                { updatePayrollWorkbookConfigurationName = draft.payrollWorkbookConfigurationDraftName
                                , updatePayrollWorkbookConfigurationDefinitionVersion = currentPayrollWorkbookDefinitionVersion
                                , updatePayrollWorkbookConfigurationFamilyKeys = familyKeys
                                , updatePayrollWorkbookConfigurationExpectedRevision = expectedRevision
                                }
                    -- Do not pre-load or validate names here: the existing
                    -- current-venue row lock precedes name/definition/revision
                    -- validation, so an absent row still wins over those errors.
                    updatePayrollWorkbookConfigurationMutation configurationId input >>= \case
                        Left configurationError -> pure (WorkbookEditorRejected anchorDate draft configurationError)
                        Right result -> pure (WorkbookUpdated anchorDate result)

invalidFields ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Maybe (Id PayrollWorkbookConfiguration) ->
    [SurfaceRequestFieldError] ->
    IO WorkbookEditorOutcome
invalidFields configurationId errors = do
    fallbackSelection <- currentExportWeekSelection
    pure (WorkbookEditorInvalidFields
        fallbackSelection.weekStart
        newPayrollWorkbookConfigurationDraft { payrollWorkbookConfigurationDraftId = configurationId }
        errors)
