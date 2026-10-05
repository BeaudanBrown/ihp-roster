module Web.View.Daysheets.Deletion (renderRowDeletion) where

import qualified Application.Daysheet.Contract as D
import Application.Daysheet.Daily (CellAddress (..), DeletionPlan (..))
import Application.Daysheet.DailyStorage (DailyState (..))
import Application.Daysheet.Entry (deletionToken)
import qualified Application.Daysheet.Evaluation as E
import Application.Daysheet.References
import qualified Application.Helper.FrontendContract.Surface.Daysheet.Action as Action
import Application.Helper.FrontendContract.Surface.Runtime
import Web.Daysheets.ReadModel
import Web.View.Prelude

renderRowDeletion :: EntryModel -> DeletionPlan -> Maybe Text -> Html
renderRowDeletion model plan message = renderConfirmationDialog
    (defaultConfirmationDialogConfig "Delete this row?" explanation formId form)
        { confirmationDialogApproveLabel = "Delete row"
        , confirmationDialogApproveTone = ConfirmationDanger
        , confirmationDialogLoadingLabel = "Deleting…"
        }
  where
    ReferenceKey source@(D.ListId list) row@(E.RowId key) = deletionTarget plan
    formId = "daysheet-row-deletion-form"
    fields = Action.confirmDaysheetRowDeletionActionFields (deletionToken (E.snapshotKey model.snapshot) plan)
    form = renderFrontendSurfaceActionFormWithHiddenFields (Action.confirmDaysheetRowDeletionAction fields)
        ((defaultFrontendSurfaceActionRoute (pathTo (DeleteDaysheetRowAction model.state.daysheet.id list key)))
            { actionRouteExtraAttrs = [("id", formId)] }) mempty
    explanation = [hsx|
        {forEach message warning}
        <p>Delete <strong>{referenceLabel model source row}</strong>? This removes its entered values.</p>
        <p>{length (incomingCells plan)} incoming links will be cleared. Referencing rows and their other values remain.</p>
        <ul>{forEach (incomingCells plan) incoming}</ul>
    |]
    warning text = [hsx|<p class="alert alert-warning" role="alert">{text}</p>|]
    incoming (address, _) = [hsx|<li>{label address}</li>|]
    fieldLabel fields key = maybe "Saved field" D.fieldLabel (find ((== key) . D.fieldId) fields)
    label = \case
        RootCell key -> fieldLabel (D.rootFields model.state.definition) key
        RowCell (ReferenceKey source row) key -> case find ((== source) . D.listId) (D.recordLists model.state.definition) of
            Nothing -> "Saved row link"
            Just list -> D.listLabel list <> " — " <> referenceLabel model source row <> " — " <> fieldLabel (D.listFields list) key
