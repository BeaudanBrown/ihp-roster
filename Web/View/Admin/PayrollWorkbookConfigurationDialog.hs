{-# LANGUAGE TypeApplications #-}

module Web.View.Admin.PayrollWorkbookConfigurationDialog
    ( PayrollWorkbookConfigurationDraft (..)
    , newPayrollWorkbookConfigurationDraft
    , savedPayrollWorkbookConfigurationDraft
    , renderPayrollWorkbookConfigurationDialog
    , renderPayrollWorkbookConfigurationDeleteDialog
    ) where

import Application.Helper.Export
import qualified Application.Helper.FrontendContract.AppShell as AppShell
import Application.Helper.FrontendContract.AppShell.Request (appShellActionFields)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             appShellActionByMarker,
                                                             renderAppShellActionForm)
import qualified Application.Helper.FrontendContract.Surface.Admin as Surface
import Application.Helper.FrontendContract.Surface.Attributes (roleAttrs)
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.View.Overlay
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import Data.Text.Encoding (decodeUtf8)
import Web.View.Prelude

data PayrollWorkbookConfigurationDraft = PayrollWorkbookConfigurationDraft
    { payrollWorkbookConfigurationDraftId       :: !(Maybe (Id PayrollWorkbookConfiguration))
    , payrollWorkbookConfigurationDraftName     :: !Text
    , payrollWorkbookConfigurationDraftFamilies :: ![PayrollWorkbookSheetFamily]
    , payrollWorkbookConfigurationDraftRevision :: !Int
    , payrollWorkbookConfigurationDraftError    :: !(Maybe Text)
    }

newPayrollWorkbookConfigurationDraft :: PayrollWorkbookConfigurationDraft
newPayrollWorkbookConfigurationDraft =
    PayrollWorkbookConfigurationDraft
        { payrollWorkbookConfigurationDraftId = Nothing
        , payrollWorkbookConfigurationDraftName = ""
        , payrollWorkbookConfigurationDraftFamilies = []
        , payrollWorkbookConfigurationDraftRevision = 0
        , payrollWorkbookConfigurationDraftError = Nothing
        }

savedPayrollWorkbookConfigurationDraft :: SavedPayrollWorkbookConfiguration -> PayrollWorkbookConfigurationDraft
savedPayrollWorkbookConfigurationDraft configuration =
    PayrollWorkbookConfigurationDraft
        { payrollWorkbookConfigurationDraftId = Just configurationRecord.id
        , payrollWorkbookConfigurationDraftName = configurationRecord.name
        , payrollWorkbookConfigurationDraftFamilies = configuration.savedPayrollWorkbookConfigurationDefinition.payrollWorkbookDefinitionSheetFamilies
        , payrollWorkbookConfigurationDraftRevision = configurationRecord.revision
        , payrollWorkbookConfigurationDraftError = Nothing
        }
  where
    configurationRecord = configuration.savedPayrollWorkbookConfigurationRecord

renderPayrollWorkbookConfigurationDialog :: Day -> PayrollWorkbookConfigurationDraft -> Html
renderPayrollWorkbookConfigurationDialog anchorDate draft =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = if isJust draft.payrollWorkbookConfigurationDraftId then "Edit export" else "Add export"
        , dialogOverlayBody = renderEditorForm anchorDate draft
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons = defaultOverlayButtons editorFormId
        , dialogOverlayDialogClass = "modal-lg"
        }

renderEditorForm :: Day -> PayrollWorkbookConfigurationDraft -> Html
renderEditorForm anchorDate draft =
    case draft.payrollWorkbookConfigurationDraftId of
        Nothing ->
            let fields =
                    appShellActionFields @AppShell.CreatePayrollWorkbookConfigurationOverlay
                        (surfaceField @AppShell.ExportAnchorDateField anchorDate)
                        ( surfaceField @AppShell.PayrollWorkbookConfigurationNameField draft.payrollWorkbookConfigurationDraftName
                            &: surfaceField @AppShell.PayrollWorkbookSheetFamiliesField (map payrollWorkbookSheetFamilyKey draft.payrollWorkbookConfigurationDraftFamilies)
                            &: noSurfaceFields
                        )
             in renderAppShellActionForm
                    (appShellActionByMarker @AppShell.CreatePayrollWorkbookConfigurationOverlay)
                    (editorRoute (pathTo CreatePayrollWorkbookConfigurationAction))
                    [hsx|
                        <input type="hidden" name={surfaceFieldNameFrom @AppShell.ExportAnchorDateField fields} value={tshow anchorDate} />
                        {renderEditorFields fields draft}
                    |]
        Just configurationId ->
            let fields =
                    appShellActionFields @AppShell.UpdatePayrollWorkbookConfigurationOverlay
                        (surfaceField @AppShell.ExportAnchorDateField anchorDate)
                        ( surfaceField @AppShell.PayrollWorkbookConfigurationNameField draft.payrollWorkbookConfigurationDraftName
                            &: surfaceField @AppShell.PayrollWorkbookSheetFamiliesField (map payrollWorkbookSheetFamilyKey draft.payrollWorkbookConfigurationDraftFamilies)
                            &: surfaceField @AppShell.PayrollWorkbookConfigurationRevisionField draft.payrollWorkbookConfigurationDraftRevision
                            &: noSurfaceFields
                        )
             in renderAppShellActionForm
                    (appShellActionByMarker @AppShell.UpdatePayrollWorkbookConfigurationOverlay)
                    (editorRoute (pathTo (UpdatePayrollWorkbookConfigurationAction configurationId)))
                    [hsx|
                        <input type="hidden" name={surfaceFieldNameFrom @AppShell.ExportAnchorDateField fields} value={tshow anchorDate} />
                        <input type="hidden" name={surfaceFieldNameFrom @AppShell.PayrollWorkbookConfigurationRevisionField fields} value={tshow draft.payrollWorkbookConfigurationDraftRevision} />
                        {renderEditorFields fields draft}
                    |]
  where
    editorRoute actionUrl =
        AppShellActionRoute
            { appShellActionRouteUrl = actionUrl
            , appShellActionRouteFields = []
            , appShellActionRouteCustomHtmx = []
            , appShellActionRouteStandardUrl = Nothing
            , appShellActionRouteExtraAttrs = [("id", editorFormId)]
            }

renderEditorFields fields draft = [hsx|
    <div {...roleAttrs (surfaceBrowserRoleValue @Surface.AdminExportsSurface @Surface.PayrollWorkbookEditorRootRole)}>
        {maybe mempty renderError draft.payrollWorkbookConfigurationDraftError}
        <input type="hidden"
               name={surfaceFieldNameFrom @AppShell.PayrollWorkbookSheetFamiliesField fields}
               value={encodedFamilies draft.payrollWorkbookConfigurationDraftFamilies}
               {...roleAttrs (surfaceBrowserRoleValue @Surface.AdminExportsSurface @Surface.PayrollWorkbookFamilyValueRole)} />
        <div class="mb-3">
            <label class="form-label" for="payroll-workbook-configuration-name">Export name</label>
            <input id="payroll-workbook-configuration-name"
                   class="form-control"
                   type="text"
                   maxlength="100"
                   required="required"
                   name={surfaceFieldNameFrom @AppShell.PayrollWorkbookConfigurationNameField fields}
                   value={draft.payrollWorkbookConfigurationDraftName}
                   placeholder="Payroll Workbook" />
        </div>
        <div class="mb-3">
            <div class="form-label">Included sheet families</div>
            <div class="d-grid gap-2"
                 {...roleAttrs (surfaceBrowserRoleValue @Surface.AdminExportsSurface @Surface.PayrollWorkbookFamilyListRole)}>
                {forEach draft.payrollWorkbookConfigurationDraftFamilies renderFamilyRow}
            </div>
            <div class="small app-muted py-2"
                 {...roleAttrs (surfaceBrowserRoleValue @Surface.AdminExportsSurface @Surface.PayrollWorkbookFamilyEmptyRole)}>
                No sheet families included yet.
            </div>
        </div>
        <div class="d-flex flex-wrap align-items-end gap-2 mb-3">
            <div class="flex-grow-1">
                <label class="form-label" for="payroll-workbook-family-picker">Add sheet</label>
                <select id="payroll-workbook-family-picker"
                        class="form-select"
                        {...roleAttrs (surfaceBrowserRoleValue @Surface.AdminExportsSurface @Surface.PayrollWorkbookFamilyPickerRole)}>
                    <option value="">Choose a sheet family</option>
                    {forEach availablePayrollWorkbookSheetFamilies renderPickerOption}
                </select>
            </div>
            <button type="button"
                    class="btn btn-outline-primary"
                    {...roleAttrs (surfaceBrowserRoleValue @Surface.AdminExportsSurface @Surface.PayrollWorkbookFamilyAddRole)}>
                Add sheet
            </button>
        </div>
        <div class="small app-muted border-top pt-3">
            <span class="fw-semibold">Data</span> is included automatically and hidden. It cannot be removed or reordered.
        </div>
    </div>
|]
  where
    renderError message = [hsx|<div class="alert alert-danger" role="alert">{message}</div>|]
    renderPickerOption family = [hsx|
        <option value={payrollWorkbookSheetFamilyKey family}>{payrollWorkbookSheetFamilyLabel family}</option>
    |]

renderFamilyRow :: PayrollWorkbookSheetFamily -> Html
renderFamilyRow family = [hsx|
    <div class="d-flex align-items-center gap-2 border rounded p-2"
         draggable="true"
         {...familyKeyAttrs (surfaceBrowserRoleValue @Surface.AdminExportsSurface @Surface.PayrollWorkbookFamilyRowRole) family}>
        <span class="text-body-secondary" aria-hidden="true">⋮⋮</span>
        <span class="flex-grow-1 fw-semibold">{payrollWorkbookSheetFamilyLabel family}</span>
        <button type="button" class="btn btn-outline-secondary btn-sm" aria-label={"Move " <> payrollWorkbookSheetFamilyLabel family <> " up"}
                {...roleAttrs (surfaceBrowserRoleValue @Surface.AdminExportsSurface @Surface.PayrollWorkbookFamilyMoveUpRole)}>↑</button>
        <button type="button" class="btn btn-outline-secondary btn-sm" aria-label={"Move " <> payrollWorkbookSheetFamilyLabel family <> " down"}
                {...roleAttrs (surfaceBrowserRoleValue @Surface.AdminExportsSurface @Surface.PayrollWorkbookFamilyMoveDownRole)}>↓</button>
        <button type="button" class="btn btn-outline-danger btn-sm" aria-label={"Remove " <> payrollWorkbookSheetFamilyLabel family}
                {...roleAttrs (surfaceBrowserRoleValue @Surface.AdminExportsSurface @Surface.PayrollWorkbookFamilyRemoveRole)}>Remove</button>
    </div>
|]

familyKeyAttrs attribute family =
    [(name, payrollWorkbookSheetFamilyKey family) | (name, _) <- roleAttrs attribute]

encodedFamilies :: [PayrollWorkbookSheetFamily] -> Text
encodedFamilies families =
    decodeUtf8 (LBS.toStrict (Aeson.encode (map payrollWorkbookSheetFamilyKey families)))

renderPayrollWorkbookConfigurationDeleteDialog :: Day -> SavedPayrollWorkbookConfiguration -> Html
renderPayrollWorkbookConfigurationDeleteDialog anchorDate configuration =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = "Delete export"
        , dialogOverlayBody = [hsx|
            <p class="mb-0">Delete <strong>{configurationRecord.name}</strong>? Existing generated exports will remain available until their normal expiry.</p>
        |]
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons =
            [ OverlayButton "Cancel" "btn btn-outline-secondary" OverlayCloseAction
            , OverlayButton
                "Delete"
                "btn btn-danger"
                (DialogFormAction "DELETE" (pathTo (DeletePayrollWorkbookConfigurationAction configurationRecord.id (tshow anchorDate))) [] Nothing)
            ]
        , dialogOverlayDialogClass = ""
        }
  where
    configurationRecord = configuration.savedPayrollWorkbookConfigurationRecord

editorFormId :: Text
editorFormId = "payroll-workbook-configuration-editor-form"
