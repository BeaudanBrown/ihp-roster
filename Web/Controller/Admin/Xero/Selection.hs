module Web.Controller.Admin.Xero.Selection
    ( openXeroShiftSelectionAction
    , refreshXeroShiftSelectionAction
    , changeXeroShiftSelectionGroupAction
    , saveXeroShiftSelectionAction
    ) where

import Application.Helper.TimesheetSelection
import qualified Application.Helper.FrontendContract.AppShell as Shell
import Application.Helper.FrontendContract.AppShell.Request
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.FrontendContract.Surface.Request (surfaceRequestFieldErrorsMessage)
import Application.Xero.Timesheets.Selection
import Application.Xero.Timesheets.Prepare (refreshXeroTimesheetPreparation)
import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import qualified Text.Read as Read
import Web.Controller.Admin.Xero.Timesheets (respondWithPreparationDialog, resolvePreparationResult)
import Web.Controller.Prelude
import Web.TimesheetSelection (fetchTimesheetSelectionRows)
import Web.View.TimesheetSelection
import Web.View.Admin.Xero.ShiftSelection (renderSelection)
import IHP.ViewPrelude (hsx)

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
    Right fields -> do
        let tokens = filter (not . Text.null) (surfaceFieldValue @Shell.SelectedTimesheetEntriesField fields)
            expected = Read.readMaybe @UTCTime (cs (surfaceFieldValue @Shell.SelectionRunUpdatedAtField fields))
        case (expected, parseExplicitTimesheetSelection tokens) of
            (Nothing, _) -> showSelection runId (Just tokens) Nothing (Just "Preparation changed. Review your selection again.")
            (_, Left failure) -> showSelection runId (Just tokens) Nothing (Just (renderTimesheetSelectionFailure failure))
            (Just updatedAt, Right selection) -> savePreparationSelection currentVenueId runId updatedAt selection >>= \case
                Left message -> showSelection runId (Just tokens) Nothing (Just message)
                Right run -> resolvePreparationResult (refreshXeroTimesheetPreparation run.id) >>= respondWithPreparationDialog

showSelection :: SelectionContext => Id XeroTimesheetPreparationRun -> Maybe [Text] -> Maybe (Maybe Day, Bool) -> Maybe Text -> IO ResponseReceived
showSelection runId draft groupChange errorMessage = do
    maybeRun <- query @XeroTimesheetPreparationRun |> filterWhere (#id, runId) |> filterWhere (#venueId, unpackId currentVenueId) |> fetchOneOrNothing
    case maybeRun of
        Nothing -> respondHtml [hsx|Preparation was not found for this venue.|]
        Just run -> do
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
