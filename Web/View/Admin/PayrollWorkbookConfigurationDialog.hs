{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

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
                                                             RegisteredAppShellAction,
                                                             appShellActionByMarker,
                                                             appShellActionAttrs,
                                                             renderAppShellActionForm)
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.Url (appendQueryParams)
import Application.Helper.View.Overlay
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import Data.Kind (Type)
import qualified Data.List as List
import Data.Text.Encoding (decodeUtf8)
import Data.Typeable (Typeable)
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
            renderAppShellActionForm
                (appShellActionByMarker @AppShell.CreatePayrollWorkbookConfigurationOverlay)
                (editorRoute (pathTo CreatePayrollWorkbookConfigurationAction))
                (renderEditorFields anchorDate draft draftFields)
        Just configurationId ->
            renderAppShellActionForm
                (appShellActionByMarker @AppShell.UpdatePayrollWorkbookConfigurationOverlay)
                (editorRoute (pathTo (UpdatePayrollWorkbookConfigurationAction configurationId)))
                (renderEditorFields anchorDate draft draftFields)
  where
    draftFields =
        appShellActionFields @AppShell.AddPayrollWorkbookConfigurationSheetOverlay
            (surfaceField @AppShell.ExportAnchorDateField anchorDate)
            ( surfaceField @AppShell.PayrollWorkbookConfigurationNameField draft.payrollWorkbookConfigurationDraftName
                &: surfaceField @AppShell.PayrollWorkbookSheetFamiliesField (map payrollWorkbookSheetFamilyKey draft.payrollWorkbookConfigurationDraftFamilies)
                &: surfaceField @AppShell.PayrollWorkbookConfigurationRevisionField draft.payrollWorkbookConfigurationDraftRevision
                &: surfaceOptionalField @AppShell.PayrollWorkbookConfigurationIdField (unpackId <$> draft.payrollWorkbookConfigurationDraftId)
                &: surfaceField @AppShell.PayrollWorkbookConfigurationSheetField ""
                &: noSurfaceFields
            )
    editorRoute actionUrl =
        AppShellActionRoute
            { appShellActionRouteUrl = actionUrl
            , appShellActionRouteFields = []
            , appShellActionRouteCustomHtmx = []
            , appShellActionRouteStandardUrl = Nothing
            , appShellActionRouteExtraAttrs = [("id", editorFormId)]
            }

renderEditorFields saveFieldsAnchor draft saveFields = [hsx|
    {maybe mempty renderError draft.payrollWorkbookConfigurationDraftError}
    <input type="hidden"
           name={surfaceFieldNameFrom @AppShell.ExportAnchorDateField saveFields}
           value={tshow saveFieldsAnchor} />
    <input type="hidden"
           name={surfaceFieldNameFrom @AppShell.PayrollWorkbookSheetFamiliesField saveFields}
           value={encodedFamilies draft.payrollWorkbookConfigurationDraftFamilies} />
    {renderRevisionField saveFields draft}
    {renderConfigurationIdField saveFields draft}
    <div class="mb-4">
        <label class="form-label" for="payroll-workbook-configuration-name">Export name</label>
        <input id="payroll-workbook-configuration-name"
               class="form-control"
               type="text"
               maxlength="100"
               required="required"
               name={surfaceFieldNameFrom @AppShell.PayrollWorkbookConfigurationNameField saveFields}
               value={draft.payrollWorkbookConfigurationDraftName}
               placeholder="Payroll Workbook" />
    </div>
    {renderIncludedSheets (surfaceFieldNameFrom @AppShell.PayrollWorkbookConfigurationSheetField saveFields) draft}
    {renderExcludedSheets (surfaceFieldNameFrom @AppShell.PayrollWorkbookConfigurationSheetField saveFields) draft}
|]
  where
    renderError message = [hsx|<div class="alert alert-danger" role="alert">{message}</div>|]

renderRevisionField saveFields draft = [hsx|
    <input type="hidden"
           name={surfaceFieldNameFrom @AppShell.PayrollWorkbookConfigurationRevisionField saveFields}
           value={tshow draft.payrollWorkbookConfigurationDraftRevision} />
|]

renderConfigurationIdField saveFields draft =
    case draft.payrollWorkbookConfigurationDraftId of
        Nothing -> mempty
        Just configurationId -> [hsx|
            <input type="hidden"
                   name={surfaceFieldNameFrom @AppShell.PayrollWorkbookConfigurationIdField saveFields}
                   value={tshow configurationId} />
        |]

renderIncludedSheets :: Text -> PayrollWorkbookConfigurationDraft -> Html
renderIncludedSheets sheetFieldName draft = [hsx|
    <section class="mb-4" aria-labelledby="payroll-workbook-included-sheets-heading">
        <h3 id="payroll-workbook-included-sheets-heading" class="h6 mb-2">Included sheets</h3>
        <div class="d-grid gap-2">{renderIncludedRows}</div>
    </section>
|]
  where
    families = draft.payrollWorkbookConfigurationDraftFamilies
    renderIncludedRows
        | null families = [hsx|<p class="small app-muted mb-0">No sheets included.</p>|]
        | otherwise = forEach (zip [0 :: Int ..] families) renderIncludedSheet
    renderIncludedSheet (index, family) = [hsx|
        <div class="d-flex align-items-center gap-2 border rounded p-2">
            <span class="flex-grow-1 fw-semibold">{payrollWorkbookSheetFamilyConfigurationLabel family}</span>
            {renderDraftControl @AppShell.MovePayrollWorkbookConfigurationSheetUpOverlay
                sheetFieldName
                MovePayrollWorkbookConfigurationSheetUpDraftAction
                family
                "↑"
                ("Move " <> payrollWorkbookSheetFamilyConfigurationLabel family <> " up")
                "btn btn-outline-secondary btn-sm"
                (index == 0)}
            {renderDraftControl @AppShell.MovePayrollWorkbookConfigurationSheetDownOverlay
                sheetFieldName
                MovePayrollWorkbookConfigurationSheetDownDraftAction
                family
                "↓"
                ("Move " <> payrollWorkbookSheetFamilyConfigurationLabel family <> " down")
                "btn btn-outline-secondary btn-sm"
                (index == length families - 1)}
            {renderDraftControl @AppShell.RemovePayrollWorkbookConfigurationSheetOverlay
                sheetFieldName
                RemovePayrollWorkbookConfigurationSheetDraftAction
                family
                "Remove"
                ("Remove " <> payrollWorkbookSheetFamilyConfigurationLabel family)
                "btn btn-outline-danger btn-sm"
                False}
        </div>
    |]

renderExcludedSheets :: Text -> PayrollWorkbookConfigurationDraft -> Html
renderExcludedSheets sheetFieldName draft = [hsx|
    <section aria-labelledby="payroll-workbook-excluded-sheets-heading">
        <h3 id="payroll-workbook-excluded-sheets-heading" class="h6 mb-2">Excluded sheets</h3>
        <div class="d-grid gap-2">{renderExcludedRows}</div>
    </section>
|]
  where
    excludedFamilies = availablePayrollWorkbookSheetFamilies List.\\ draft.payrollWorkbookConfigurationDraftFamilies
    renderExcludedRows
        | null excludedFamilies = [hsx|<p class="small app-muted mb-0">No sheets excluded.</p>|]
        | otherwise = forEach excludedFamilies renderExcludedSheet
    renderExcludedSheet family = [hsx|
        <div class="d-flex align-items-center gap-2 border rounded p-2">
            <span class="flex-grow-1 fw-semibold">{payrollWorkbookSheetFamilyConfigurationLabel family}</span>
            {renderDraftControl @AppShell.AddPayrollWorkbookConfigurationSheetOverlay
                sheetFieldName
                AddPayrollWorkbookConfigurationSheetDraftAction
                family
                "Add"
                ("Add " <> payrollWorkbookSheetFamilyConfigurationLabel family)
                "btn btn-outline-primary btn-sm"
                False}
        </div>
    |]

renderDraftControl :: forall (marker :: Type). (Typeable marker, RegisteredAppShellAction marker) => Text -> ExportsController -> PayrollWorkbookSheetFamily -> Text -> Text -> Text -> Bool -> Html
renderDraftControl sheetFieldName action family label ariaLabel buttonClass disabled =
    [hsx|
        <button type="button" class={buttonClass} aria-label={ariaLabel} disabled={disabled} {...attributes}>
            {label}
        </button>
    |]
  where
    attributes = appShellActionAttrs
        (appShellActionByMarker @marker)
        AppShellActionRoute
            { appShellActionRouteUrl =
                appendQueryParams
                    (pathTo action)
                    [(sheetFieldName, payrollWorkbookSheetFamilyKey family)]
            , appShellActionRouteFields = []
            , appShellActionRouteCustomHtmx = []
            , appShellActionRouteStandardUrl = Nothing
            , appShellActionRouteExtraAttrs = []
            }

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
