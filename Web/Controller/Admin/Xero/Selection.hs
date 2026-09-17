module Web.Controller.Admin.Xero.Selection
    ( openXeroShiftSelectionAction
    , refreshXeroShiftSelectionAction
    , changeXeroShiftSelectionGroupAction
    , saveXeroShiftSelectionAction
    , submitXeroShiftSelectionAction
    ) where

import Application.Helper.TimesheetSelection
import qualified Application.Helper.FrontendContract.AppShell as Shell
import Application.Helper.FrontendContract.AppShell.Request
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.FrontendContract.Surface.Request (surfaceRequestFieldErrorsMessage)
import Application.Xero.Timesheets.Selection
import Application.Xero.Timesheets.Prepare (refreshXeroTimesheetPreparation, submitSelectedXeroTimesheetPreparation)
import Application.Helper.XeroAdminTypes (XeroTimesheetPreparationView (..))
import qualified Data.Text as Text
import qualified Text.Read as Read
import Web.Controller.Admin.Xero.Timesheets (respondWithPreparationDialog, resolvePreparationResult, respondToXeroTimesheetSubmission)
import Web.View.Admin.Xero.TimesheetPreparation (needsPayItemStep)
import Web.Controller.Prelude
import Web.Controller.Admin.Xero.SelectionResponse (respondWithPreparationShiftSelection)

type SelectionContext = (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond)

openXeroShiftSelectionAction :: SelectionContext => Id XeroTimesheetPreparationRun -> IO ResponseReceived
openXeroShiftSelectionAction runId = showSelection runId Nothing Nothing Nothing

refreshXeroShiftSelectionAction :: SelectionContext => Id XeroTimesheetPreparationRun -> IO ResponseReceived
refreshXeroShiftSelectionAction runId = case parseAppShellActionParams @Shell.RefreshXeroShiftSelection of
    Left errors -> respondHtml [hsx|{surfaceRequestFieldErrorsMessage errors}|]
    Right fields -> showSelection runId (Just (filter (not . Text.null) (surfaceFieldValue @Shell.SelectedTimesheetEntriesField fields))) Nothing Nothing

changeXeroShiftSelectionGroupAction :: SelectionContext => Id XeroTimesheetPreparationRun -> Maybe Day -> Bool -> IO ResponseReceived
changeXeroShiftSelectionGroupAction runId day selected = case parseAppShellActionParams @Shell.ChangeXeroShiftSelectionGroup of
    Left errors -> respondHtml [hsx|{surfaceRequestFieldErrorsMessage errors}|]
    Right fields -> showSelection runId (Just (filter (not . Text.null) (surfaceFieldValue @Shell.SelectedTimesheetEntriesField fields))) (Just (day, selected)) Nothing

saveXeroShiftSelectionAction :: SelectionContext => Id XeroTimesheetPreparationRun -> IO ResponseReceived
saveXeroShiftSelectionAction runId = case parseAppShellActionParams @Shell.SaveXeroShiftSelection of
    Left errors -> respondHtml [hsx|{surfaceRequestFieldErrorsMessage errors}|]
    Right fields -> persistSelection runId
        (surfaceFieldValue @Shell.SelectedTimesheetEntriesField fields)
        (surfaceFieldValue @Shell.SelectionRunUpdatedAtField fields)
        (\run -> resolvePreparationResult (refreshXeroTimesheetPreparation run.id) >>= respondWithPreparationDialog)

-- A separate action keeps old, already-open Continue forms save-only. Only the
-- new checklist's explicit Confirm and submit control authorizes provider writes.
submitXeroShiftSelectionAction :: SelectionContext => Id XeroTimesheetPreparationRun -> IO ResponseReceived
submitXeroShiftSelectionAction runId = case parseAppShellActionParams @Shell.SubmitXeroShiftSelection of
    Left errors -> respondHtml [hsx|{surfaceRequestFieldErrorsMessage errors}|]
    Right fields -> persistSelection runId
        (surfaceFieldValue @Shell.SelectedTimesheetEntriesField fields)
        (surfaceFieldValue @Shell.SelectionRunUpdatedAtField fields)
        submitSavedSelection
  where
    submitSavedSelection run = resolvePreparationResult (refreshXeroTimesheetPreparation run.id) >>= \case
        Right view
            | view.preparationRun.selectedEntriesJson /= run.selectedEntriesJson ->
                respondWithPreparationShiftSelection view.preparationRun Nothing Nothing (Just "Approvals changed during preparation. Review the updated shifts and confirm again.")
            | view.preparationCanSubmit && not (needsPayItemStep view) ->
                resolvePreparationResult (submitSelectedXeroTimesheetPreparation run.id run.selectedEntriesJson) >>= respondToXeroTimesheetSubmission run.id
        result -> respondWithPreparationDialog result

persistSelection :: SelectionContext => Id XeroTimesheetPreparationRun -> [Text] -> Text -> (XeroTimesheetPreparationRun -> IO ResponseReceived) -> IO ResponseReceived
persistSelection runId submittedTokens expectedTimestamp afterSave = do
    let tokens = filter (not . Text.null) submittedTokens
        expected = Read.readMaybe @UTCTime (cs expectedTimestamp)
    case (expected, parseExplicitTimesheetSelection tokens) of
        (Nothing, _) -> showSelection runId (Just tokens) Nothing (Just "Preparation changed. Review your selection again.")
        (_, Left failure) -> showSelection runId (Just tokens) Nothing (Just (renderTimesheetSelectionFailure failure))
        (Just updatedAt, Right selection) -> savePreparationSelection currentVenueId runId updatedAt selection >>= \case
            Left message -> showSelection runId (Just tokens) Nothing (Just message)
            Right run -> afterSave run

showSelection :: SelectionContext => Id XeroTimesheetPreparationRun -> Maybe [Text] -> Maybe (Maybe Day, Bool) -> Maybe Text -> IO ResponseReceived
showSelection runId draft groupChange errorMessage = do
    maybeRun <- query @XeroTimesheetPreparationRun |> filterWhere (#id, runId) |> filterWhere (#venueId, unpackId currentVenueId) |> fetchOneOrNothing
    case maybeRun of
        Nothing -> respondHtml [hsx|Preparation was not found for this venue.|]
        Just run -> respondWithPreparationShiftSelection run draft groupChange errorMessage
