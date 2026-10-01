module Web.Controller.Admin.Xero.SelectionResponse (respondWithPreparationShiftSelection) where

import Application.Helper.TimesheetSelection
import Application.Xero.Timesheets.Selection (fetchPreparationSelectionCandidates)
import qualified Data.Aeson as Aeson
import Web.Controller.Prelude
import Web.TimesheetSelection (fetchTimesheetSelectionRows)
import Web.View.TimesheetSelection (TimesheetSelectionRow (..))
import Web.View.Admin.Xero.ShiftSelection (renderSelection)

-- Both initial period selection and later checklist edits use the same saved
-- identity projection. Callers must first load the run in the authorized venue.
respondWithPreparationShiftSelection ::
    (?context :: ControllerContext, ?request :: Request, ?respond :: Respond, ?modelContext :: ModelContext) =>
    XeroTimesheetPreparationRun -> Maybe [Text] -> Maybe (Maybe Day, Bool) -> Maybe Text -> IO ResponseReceived
respondWithPreparationShiftSelection run draft groupChange errorMessage = do
    entries <- fetchPreparationSelectionCandidates run
    rows <- fetchTimesheetSelectionRows entries
    let saved = case run.selectedEntriesJson of
            Just value -> case Aeson.fromJSON value of
                Aeson.Success identities -> map encodeTimesheetSelectionIdentity identities
                Aeson.Error _ -> []
            Nothing -> []
        available = map (.selectionRowToken) rows
        requested = fromMaybe (if isNothing run.selectedEntriesJson then available else saved) draft
        changed = any (`notElem` available) requested
        groupTokens = case groupChange of
            Nothing -> []
            Just (day, _) -> map (.selectionRowToken) (filter (\row -> maybe True (== row.selectionRowDay) day) rows)
        chosen = case groupChange of
            Nothing -> requested
            Just (_, True) -> requested <> groupTokens
            Just (_, False) -> filter (`notElem` groupTokens) requested
        selected = filter (`elem` chosen) available
        message = errorMessage <|> if changed then Just (renderTimesheetSelectionFailure ChangedTimesheetSelection) else Nothing
    respondHtml (renderSelection run rows selected message)
