module Web.View.Daysheets.Index
    ( IndexView (..), EntryFeedback (..), renderDaysheetBody ) where

import qualified Application.Daysheet.Contract as D
import Application.Helper.ControllerContext (currentVenueMembershipOrNothing)
import Application.Daysheet.DailyStorage (DailyState (..))
import Application.Daysheet.EntryLayout
import qualified Application.Daysheet.Evaluation as E
import qualified Application.Helper.FrontendContract.Surface.Daysheet as Surface
import qualified Application.Helper.FrontendContract.Surface.Daysheet.Action as Action
import Application.Helper.FrontendContract.Surface.Runtime
import Application.Helper.FrontendContract.Surface.Values
import qualified Data.Map.Strict as Map
import Data.List (groupBy)
import Web.Daysheets.LiveUpdates
import Web.Daysheets.ReadModel
import Web.View.Daysheets.Cell
import Web.View.Prelude

data EntryFeedback
    = CellProblem Int (Maybe E.RowId) CellFeedback
    | DeletedCellProblem Int (Maybe UUID) Text

data IndexView = IndexView
    { operationalDate :: Day, model :: Maybe EntryModel, rowKeys :: Map.Map D.ListId UUID
    , feedback :: Maybe EntryFeedback
    }
instance View IndexView where
    html IndexView { .. } = case model of
        Just entry -> renderDaysheetBody entry rowKeys feedback
        Nothing -> renderAppPage AppPageConfig
            { appPageTitle = "Daysheets", appPageDescription = Nothing
            , appPageActions = designerLink, appPageHelpTopic = Nothing, appPageWidthClass = ""
            , appPageBody = [hsx|{dateNavigation operationalDate False}<p>No Daysheet exists for this Operational date.</p>{create}|]
            }
      where
        fields = Action.createDaysheetActionFields operationalDate
        create = renderFrontendSurfaceActionFormWithHiddenFields (Action.createDaysheetAction fields)
            (defaultFrontendSurfaceActionRoute (pathTo CreateDaysheetAction))
            [hsx|<button type="submit" class="btn btn-primary">Create Daysheet</button><p class="form-text">An admin must publish a template before a Daysheet can be created.</p>|]

renderDaysheetBody :: EntryModel -> Map.Map D.ListId UUID -> Maybe EntryFeedback -> Html
renderDaysheetBody model newRows feedback = renderFrontendSurfaceFragmentMount @Surface.DaysheetSurface @Surface.DaysheetBody
    noSurfaceFields (daysheetSurface model (isJust feedback)) (renderAppPage page)
  where
    record = model.state.daysheet
    page = AppPageConfig
        { appPageTitle = "Daysheet — " <> tshow record.operationalDate
        , appPageDescription = Nothing
        , appPageActions = renderFrontendSurfaceActionForm (Action.submitDaysheetAction Action.submitDaysheetActionFields)
            ((defaultFrontendSurfaceActionRoute (pathTo (SubmitDaysheetAction record.id))) { actionRouteExtraAttrs = finalActionAttrs })
            [hsx|<button class="btn btn-primary" type="submit" disabled={isJust feedback}>Submit saved Daysheet</button>|]
        , appPageHelpTopic = Nothing, appPageWidthClass = ""
        , appPageBody = [hsx|
            <div class="app-page-stack">
                {designerLink}
                {dateNavigation record.operationalDate (isJust feedback)}
                <p>Changes save when a field changes or you leave it. Amounts are AUD; enter percentages such as 1.6 for 1.6%.</p>
                <noscript><p>JavaScript is off. Use Save for each changed field before submitting.</p></noscript>
                <p {...pendingNoticeAttrs} class="alert alert-warning" role="status" hidden="hidden">Finish saving and resolve unsaved or conflicting edits before continuing.</p>
                <p>Last saved: {dateTime record.lastEditedAt}. {submissionStatus}</p>
                {deletedNotice}
                {forEach (entrySections model.layout) renderSection}
            </div>
        |]
        }
    deletedNotice = case feedback of
        Just (DeletedCellProblem index row raw) -> renderDeletedEntryCell model index row (Just raw)
        _ -> mempty
    submissionStatus = case record.submittedAt of
        Nothing -> [hsx|<strong>Draft</strong>|]
        Just submitted -> [hsx|<strong>Submitted</strong> {dateTime submitted}. Later edits remain permitted.|]
    renderSection (EntrySection _ label blocks) = renderAppPanel (defaultAppPanelConfig [hsx|
        <h2 class="h4">{label}</h2>{forEach blocks renderBlock}
    |])
    renderBlock = \case
        EntryInstructions text -> [hsx|<p class="text-break">{text}</p>|]
        EntryField placement -> renderPlacement placement Nothing
        EntryAdvisory advisory -> renderAdvisory Nothing advisory
        EntryRowAdvisory source advisory -> forEach (Map.findWithDefault [] (D.listId source) model.rows) (rowAdvisory source advisory)
        EntryTable source placements grouping ordering -> renderTable source placements grouping ordering
    renderPlacement placement row = case resolveEntryCell model.layout model.snapshot model.state.content (occurrenceIndex placement) row of
        Left _ -> [hsx|<span class="text-muted">This entry is no longer available.</span>|]
        Right cell -> renderEntryCell model cell (case feedback of
            Just (CellProblem index failedRow problem) | index == occurrenceIndex placement && failedRow == row -> Just problem
            _ -> Nothing)
    rowAdvisory source advisory row = [hsx|<div><strong>{referenceLabel model (D.listId source) row}</strong>{renderAdvisory (Just (D.listId source, row)) advisory}</div>|]
    renderAdvisory scope advisory = case E.evaluateAdvisory model.evaluation scope advisory of
        Right (D.Passed message) -> [hsx|<p class="small text-muted mb-2">{message}</p>|]
        Right (D.Concern message) -> [hsx|<div class="alert alert-warning">{message}</div>|]
        Right (D.NotEvaluated reason) -> [hsx|<div class="alert alert-secondary">Not evaluated: {E.explainUnavailable model.evaluation reason}</div>|]
        Left _ -> [hsx|<div class="alert alert-secondary">Not evaluated: this check is unavailable.</div>|]
    renderTable source placements grouping ordering = [hsx|
        <section class="mb-4">
            <h3 class="h5">{D.listLabel source}</h3>
            <div class="table-responsive" role="region" aria-label={D.listLabel source} tabindex="0">
                <table class="table align-middle">
                    <thead><tr>{forEach placements heading}<th scope="col">Actions</th></tr></thead>
                    {forEach groups (renderGroup source placements grouping)}
                </table>
            </div>
            {if null ordered then emptyRows else mempty}
            {addRow source}
        </section>
    |]
      where
        ordered = tableRows model source grouping ordering
        groups = case grouping of
            Nothing -> [ordered]
            Just field -> groupBy (\a b -> resultFor model (E.RowTarget (D.listId source) a field) == resultFor model (E.RowTarget (D.listId source) b field)) ordered
    emptyRows = [hsx|<p class="text-muted">No rows.</p>|]
    heading placement = [hsx|<th scope="col">{D.fieldLabel (occurrenceField placement)}</th>|]
    renderGroup source placements grouping rows = [hsx|<tbody>{groupHeading}{forEach rows (renderRow source placements)}</tbody>|]
      where
        groupHeading = case (grouping, headMay rows) of
            (Just key, Just row) -> case find ((== key) . D.fieldId) (D.listFields source) of
                Just field -> let label = case resultFor model (E.RowTarget (D.listId source) row key) of
                                        D.Known value -> valueText model field value
                                        D.Unavailable _ -> "Unavailable group"
                    in [hsx|<tr><th scope="rowgroup" colspan={length placements + 1}>{label}</th></tr>|]
                Nothing -> mempty
            _ -> mempty
    renderRow source placements row = [hsx|<tr>{forEach placements (tableCell row)}<td>{deleteControl source row}</td></tr>|]
    tableCell row placement = [hsx|<td>{renderPlacement placement (Just row)}</td>|]
    addRow source = case (D.listMode source, Map.lookup (D.listId source) newRows) of
        (D.OpenDaily, Just key) -> let
            fields = Action.addDaysheetRowActionFields key
            D.ListId list = D.listId source
            route = (defaultFrontendSurfaceActionRoute (pathTo (AddDaysheetRowAction record.id list))) { actionRouteExtraAttrs = finalActionAttrs }
            in renderFrontendSurfaceActionFormWithHiddenFields (Action.addDaysheetRowAction fields) route [hsx|<button type="submit" class="btn btn-sm btn-outline-primary" disabled={isJust feedback}>Add row</button>|]
        _ -> mempty
    deleteControl source (E.RowId row) = case D.listMode source of
        D.OpenDaily -> let
            D.ListId list = D.listId source
            route = (defaultFrontendSurfaceActionRoute (pathTo (ShowDaysheetRowDeletionAction record.id list row))) { actionRouteExtraAttrs = finalActionAttrs }
            in renderFrontendSurfaceActionForm (Action.openDaysheetRowDeletionAction Action.openDaysheetRowDeletionActionFields) route
                [hsx|<button type="submit" class="btn btn-sm btn-outline-danger" disabled={isJust feedback}>Delete row…</button>|]
        _ -> mempty

designerLink :: (?context :: ControllerContext) => Html
designerLink = case currentVenueMembershipOrNothing of
    Just member | member.venueRole `elem` [VenueAdmin, VenueOwner] ->
        renderFrontendSurfaceActionForm (Action.openDaysheetDesignerAction Action.openDaysheetDesignerActionFields)
            ((defaultFrontendSurfaceActionRoute (pathTo DaysheetDesignerAction)) { actionRouteExtraAttrs = finalActionAttrs })
            [hsx|<button class="btn btn-outline-secondary" type="submit">Configure Daysheets</button>|]
    _ -> mempty

dateNavigation :: Day -> Bool -> Html
dateNavigation date blocked = renderFrontendSurfaceActionForm (Action.viewDaysheetDateAction fields)
    ((defaultFrontendSurfaceActionRoute (pathTo DaysheetsAction)) { actionRouteExtraAttrs = finalActionAttrs <> [("class", "d-flex gap-2 align-items-end")] }) [hsx|
        <div><label for="daysheet-operational-date" class="form-label">Operational date</label>
            <input id="daysheet-operational-date" type="date" class="form-control" name={surfaceFieldNameFrom @Surface.OperationalDate fields} value={tshow date} required="required" /></div>
        <button type="submit" class="btn btn-outline-secondary" disabled={blocked}>Open date</button>
    |]
  where fields = Action.viewDaysheetDateActionFields (Just date)
