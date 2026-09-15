module Web.Exports.Selection
    ( openExportSelection
    , refreshExportSelection
    , changeExportSelectionGroup
    , generateSelectedExport
    , renderFilteredExportButton
    ) where

import Application.Helper.Export
import Application.Helper.TimesheetSelection
import Application.Helper.Url (appendQueryParams)
import qualified Application.Helper.FrontendContract.AppShell as Shell
import Application.Helper.FrontendContract.AppShell.Request
import Application.Helper.FrontendContract.AppShell.Runtime
import Application.Helper.FrontendContract.Surface.Request (surfaceRequestFieldErrorsMessage)
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.SurfaceResource (LiveMutationResult (..))
import Application.Helper.View.Overlay
import Web.TimesheetSelection (fetchTimesheetSelectionRows)
import qualified Data.Text as Text
import Web.Controller.Prelude
import Web.Exports.Mutations (requestSelectedExportMutation)
import Web.View.TimesheetSelection
import IHP.ViewPrelude (Html)

-- HTTP transport is confined to this workflow; Application consumes only the
-- shared typed selection and never reads request parameters.
data ExportSelectionRequest = ExportSelectionRequest
    { rangeStart :: Day
    , rangeEnd :: Day
    , exportType :: ExportJobType
    , configurationId :: Maybe UUID
    , tokens :: [Text]
    }

openExportSelection :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => IO ResponseReceived
openExportSelection =
    case parseAppShellActionParams @Shell.OpenTimesheetSelectionDialog of
        Left errors -> respondHtml [hsx|{surfaceRequestFieldErrorsMessage errors}|]
        Right fields -> showSelection True Nothing ExportSelectionRequest
            { rangeStart = surfaceFieldValue @Shell.SelectionRangeStartField fields
            , rangeEnd = surfaceFieldValue @Shell.SelectionRangeEndField fields
            , exportType = surfaceFieldValue @Shell.SelectionExportTypeField fields
            , configurationId = surfaceFieldValue @Shell.PayrollWorkbookConfigurationIdField fields
            , tokens = []
            }

refreshExportSelection :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => IO ResponseReceived
refreshExportSelection =
    case parseAppShellActionParams @Shell.RefreshTimesheetSelectionDialog of
        Left errors -> respondHtml [hsx|{surfaceRequestFieldErrorsMessage errors}|]
        Right fields -> showSelection False Nothing ExportSelectionRequest
            { rangeStart = surfaceFieldValue @Shell.SelectionRangeStartField fields
            , rangeEnd = surfaceFieldValue @Shell.SelectionRangeEndField fields
            , exportType = surfaceFieldValue @Shell.SelectionExportTypeField fields
            , configurationId = surfaceFieldValue @Shell.PayrollWorkbookConfigurationIdField fields
            , tokens = filter (not . Text.null) (surfaceFieldValue @Shell.SelectedTimesheetEntriesField fields)
            }

changeExportSelectionGroup :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => Maybe Day -> Bool -> IO ResponseReceived
changeExportSelectionGroup day selected =
    case parseAppShellActionParams @Shell.ChangeTimesheetSelectionGroup of
        Left errors -> respondHtml [hsx|{surfaceRequestFieldErrorsMessage errors}|]
        Right fields -> do
            let request = ExportSelectionRequest
                    { rangeStart = surfaceFieldValue @Shell.SelectionRangeStartField fields
                    , rangeEnd = surfaceFieldValue @Shell.SelectionRangeEndField fields
                    , exportType = surfaceFieldValue @Shell.SelectionExportTypeField fields
                    , configurationId = surfaceFieldValue @Shell.PayrollWorkbookConfigurationIdField fields
                    , tokens = filter (not . Text.null) (surfaceFieldValue @Shell.SelectedTimesheetEntriesField fields)
                    }
            entries <- fetchExportSelectionCandidates request.exportType request.rangeStart request.rangeEnd
            let groupTokens = map (encodeTimesheetSelectionIdentity . timesheetSelectionIdentity)
                    (filter (\entry -> maybe True (== entry.operationalDate) day) entries)
                tokens = if selected then request.tokens <> groupTokens else filter (`notElem` groupTokens) request.tokens
            showSelection False Nothing request { tokens }

generateSelectedExport :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => (ExportJob -> IO ResponseReceived) -> IO ResponseReceived
generateSelectedExport complete =
    case parseAppShellActionParams @Shell.GenerateSelectedTimesheetExport of
        Left errors -> respondHtml [hsx|{surfaceRequestFieldErrorsMessage errors}|]
        Right fields -> do
            let request = ExportSelectionRequest
                    { rangeStart = surfaceFieldValue @Shell.SelectionRangeStartField fields
                    , rangeEnd = surfaceFieldValue @Shell.SelectionRangeEndField fields
                    , exportType = surfaceFieldValue @Shell.SelectionExportTypeField fields
                    , configurationId = surfaceFieldValue @Shell.PayrollWorkbookConfigurationIdField fields
                    , tokens = filter (not . Text.null) (surfaceFieldValue @Shell.SelectedTimesheetEntriesField fields)
                    }
            case parseExplicitTimesheetSelection request.tokens of
                Left failure -> showSelection False (Just (renderTimesheetSelectionFailure failure)) request
                Right selection -> requestSelectedExportMutation selection request.exportType (Id <$> request.configurationId) request.rangeStart request.rangeEnd >>= \case
                    Left message -> showSelection False (Just message) request
                    Right result -> complete result.liveMutationValue

showSelection :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => Bool -> Maybe Text -> ExportSelectionRequest -> IO ResponseReceived
showSelection initiallyAll errorMessage request = do
    -- Saved definitions are always resolved through their venue-scoped owner.
    configurationError <- case request.configurationId of
        Nothing -> pure Nothing
        Just configurationId -> if request.exportType /= PayrollWorkbookXlsx
            then pure (Just "This configuration can only generate Payroll Workbooks.")
            else fetchSavedPayrollWorkbookConfiguration (Id configurationId) >>= \case
                Left _ -> pure (Just "That Payroll Workbook configuration is unavailable. Close the dialog and choose an existing export.")
                Right _ -> pure Nothing
    case configurationError of
        Just message -> respondHtml message
        Nothing -> do
            entries <- fetchExportSelectionCandidates request.exportType request.rangeStart request.rangeEnd
            rows <- fetchTimesheetSelectionRows entries
            let available = map (.selectionRowToken) rows
                selected = if initiallyAll then available else filter (`elem` request.tokens) available
                changed = any (`notElem` available) request.tokens
                message = errorMessage <|> if changed then Just (renderTimesheetSelectionFailure ChangedTimesheetSelection) else Nothing
            respondHtml (renderSelection request rows selected message)
renderSelection :: ExportSelectionRequest -> [TimesheetSelectionRow] -> [Text] -> Maybe Text -> Html
renderSelection request rows selected message = renderDialogOverlay DialogOverlayConfig
    { dialogOverlayTitle = "Choose shifts for export"
    , dialogOverlayBody = renderAppShellActionForm
        (appShellActionByMarker @Shell.RefreshTimesheetSelectionDialog)
        ((defaultAppShellActionRoute (pathTo RefreshTimesheetExportSelectionAction)) { appShellActionRouteExtraAttrs = [("id", "timesheet-selection-form")] })
        [hsx|
            {maybe mempty renderError message}
            <p>{tshow request.rangeStart} – {tshow request.rangeEnd}. Review this selection before downloading.</p>
            <input type="hidden" name={surfaceFieldNameFrom @Shell.SelectionRangeStartField fields} value={tshow request.rangeStart} />
            <input type="hidden" name={surfaceFieldNameFrom @Shell.SelectionRangeEndField fields} value={tshow request.rangeEnd} />
            <input type="hidden" name={surfaceFieldNameFrom @Shell.SelectionExportTypeField fields} value={exportJobTypeToText request.exportType} />
            <input type="hidden" name={surfaceFieldNameFrom @Shell.PayrollWorkbookConfigurationIdField fields} value={maybe "" tshow request.configurationId} />
            {renderTimesheetSelectionChecklist (surfaceFieldNameFrom @Shell.SelectedTimesheetEntriesField fields) rows selected groupControl}
            <button {...generateAttrs} disabled={null selected}>Download selected shifts</button>
        |]
    , dialogOverlayStartButtons = []
    , dialogOverlayButtons = [dialogOverlayCloseButton "Cancel"]
    , dialogOverlayDialogClass = "modal-lg"
    }
  where
    renderError text = [hsx|<p class="alert alert-warning" role="alert">{text}</p>|]
    fields = appShellActionFields @Shell.RefreshTimesheetSelectionDialog
        (surfaceField @Shell.SelectionRangeStartField request.rangeStart)
        (surfaceField @Shell.SelectionRangeEndField request.rangeEnd
            &: surfaceField @Shell.SelectionExportTypeField request.exportType
            &: surfaceOptionalField @Shell.PayrollWorkbookConfigurationIdField request.configurationId
            &: surfaceField @Shell.SelectedTimesheetEntriesField selected
            &: noSurfaceFields)
    buttonRoute url = (defaultAppShellActionRoute url) { appShellActionRouteExtraAttrs = [("type", "button"), ("class", "btn btn-outline-primary")] }
    generateAttrs = appShellActionAttrs (appShellActionByMarker @Shell.GenerateSelectedTimesheetExport) (buttonRoute (pathTo GenerateSelectedTimesheetExportAction))
    groupControl day select = [hsx|<button {...attributes}>{label}</button>|]
      where
        attributes = appShellActionAttrs (appShellActionByMarker @Shell.ChangeTimesheetSelectionGroup) (buttonRoute (pathTo (if select then SelectTimesheetExportGroupAction (tshow <$> day) else ClearTimesheetExportGroupAction (tshow <$> day))))
        label = (if select then "Select " else "Clear ") <> (if isNothing day then "all" else "day") :: Text

renderFilteredExportButton :: Day -> Day -> ExportJobType -> Maybe UUID -> Html
renderFilteredExportButton start end exportType configurationId = [hsx|<button {...attributes}>Filtered…</button>|]
  where
    fields = appShellActionFields @Shell.OpenTimesheetSelectionDialog
        (surfaceField @Shell.SelectionRangeStartField start)
        (surfaceField @Shell.SelectionRangeEndField end
            &: surfaceField @Shell.SelectionExportTypeField exportType
            &: surfaceOptionalField @Shell.PayrollWorkbookConfigurationIdField configurationId
            &: surfaceField @Shell.SelectedTimesheetEntriesField ([] :: [Text])
            &: noSurfaceFields)
    attributes = appShellActionAttrs (appShellActionByMarker @Shell.OpenTimesheetSelectionDialog)
        ((defaultAppShellActionRoute (appendQueryParams (pathTo OpenTimesheetExportSelectionAction)
            [ (surfaceFieldNameFrom @Shell.SelectionRangeStartField fields, tshow start)
            , (surfaceFieldNameFrom @Shell.SelectionRangeEndField fields, tshow end)
            , (surfaceFieldNameFrom @Shell.SelectionExportTypeField fields, exportJobTypeToText exportType)
            , (surfaceFieldNameFrom @Shell.PayrollWorkbookConfigurationIdField fields, maybe "" tshow configurationId)
            , (surfaceFieldNameFrom @Shell.SelectedTimesheetEntriesField fields, "[]")
            ]))
            { appShellActionRouteExtraAttrs = [("type", "button"), ("class", "btn btn-outline-primary")]
            })
