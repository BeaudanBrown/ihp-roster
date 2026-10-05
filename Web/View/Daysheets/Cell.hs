module Web.View.Daysheets.Cell
    ( CellFeedback (..), renderEntryCell, renderDeletedEntryCell, cellInputText ) where

import qualified Application.Daysheet.Contract as D
import qualified Application.Daysheet.Daily as Daily
import Application.Daysheet.EntryLayout
import Application.Daysheet.DailyStorage (DailyState (..))
import qualified Application.Daysheet.Evaluation as E
import Application.Daysheet.References
import qualified Application.Helper.FrontendContract.Surface.Daysheet as Surface
import qualified Application.Helper.FrontendContract.Surface.Daysheet.Action as Action
import Application.Helper.FrontendContract.Surface.Request.Runtime (FrontendSurfaceAction)
import Application.Helper.FrontendContract.Surface.Runtime
import Application.Helper.FrontendContract.Surface.Values
import qualified Data.Map.Strict as Map
import Web.Daysheets.LiveUpdates
import Web.Daysheets.ReadModel
import Web.View.Prelude

data CellFeedback = InvalidInput Text Text | ConflictingInput Text Text

renderEntryCell :: EntryModel -> EntryCell -> Maybe CellFeedback -> Html
renderEntryCell model binding feedback = case entrySavedCell binding of
    Nothing -> [hsx|<div class="mb-3"><span class="form-label">{D.fieldLabel field}</span><div>{readOnlyValue}</div></div>|]
    Just saved -> [hsx|
        <div id={target} class={surfaceDomTokenValue @Surface.DaysheetSurface @Surface.DaysheetCellFormTarget <> " mb-3"}>
            {renderForm saved}
            {if isJust feedback then keepSaved else mempty}
        </div>
    |]
  where
    placement = entryOccurrence binding
    field = occurrenceField placement
    index = occurrenceIndex placement
    rowKey = (\(E.RowId value) -> value) <$> entryRow binding
    row = tshow <$> rowKey
    target = cellTargetId index rowKey
    inputId = target <> "-value"
    sheet = model.state.daysheet.id
    route action = defaultFrontendSurfaceActionRoute (pathTo action)
    readOnlyValue = case resultFor model (entryTarget binding) of
        D.Known value -> [hsx|<output>{valueText model field value}</output>|]
        D.Unavailable reason -> [hsx|<span class="text-muted">Unavailable: {E.explainUnavailable model.evaluation reason}</span>|]
    keepSaved = renderFrontendSurfaceActionLink
        (Action.keepSavedDaysheetCellAction Action.keepSavedDaysheetCellActionFields)
        ((route (KeepSavedDaysheetCellAction sheet index row)) { actionRouteExtraAttrs = [("class", "btn btn-sm btn-outline-secondary")] })
        [hsx|Keep saved value|]
    renderForm saved = renderFrontendSurfaceActionForm contract
        ((route action) { actionRouteExtraAttrs = [("aria-invalid", "true") | isJust feedback] }) [hsx|
        <label class="form-label" for={inputId}>{D.fieldLabel field}</label>
        <input type="hidden" name={revisionName} value={Daily.cellRevision saved} />
        {formControls saved valueName raw}
    |]
      where
        raw = case feedback of
            Just (InvalidInput submitted _) -> submitted
            Just (ConflictingInput submitted _) -> submitted
            Nothing -> cellInputText (Daily.cellValue saved)
        revision = fromInteger (Daily.cellRevision saved)
        (contract, revisionName, valueName, action) = formContract revision
    formControls saved valueName raw = case feedback of
        Just (ConflictingInput submitted message) -> [hsx|
            <div class="alert alert-warning" role="alert">
                <p>{message}</p>
                <p>Your unsaved value: <strong class="text-break">{blankLabel submitted}</strong></p>
                <p>Saved value: <strong class="text-break">{savedLabel saved}</strong></p>
            </div>
            <input id={inputId} type="hidden" name={valueName} value={submitted} />
            <button class="btn btn-sm btn-warning" type="submit">Replace saved value</button>
        |]
        _ -> [hsx|
            {inputControl valueName raw}
            {validationMessage}
            <button class="btn btn-sm btn-outline-secondary mt-1" type="submit">Save</button>
        |]
    validationMessage = case feedback of
        Just (InvalidInput _ message) -> [hsx|<div class="text-danger" role="alert">{message}</div>|]
        _ -> mempty
    savedLabel saved = case Daily.cellValue saved of
        Nothing -> "Blank"
        Just (ReferenceScalar literal) -> valueText model field (E.Scalar literal)
        Just (ReferenceLink (ReferenceKey source key)) -> referenceLabel model source key
    blankLabel value = if isEmpty value then "Blank" else value
    inputControl name value = case D.fieldType field of
        D.TextType -> [hsx|<textarea id={inputId} class="form-control" name={name} maxlength="10000" rows="2">{value}</textarea>|]
        D.BooleanType -> select name value [("true", "Yes"), ("false", "No")]
        D.ChoiceType choices -> select name value [(tshow key, D.choiceLabel choice) | choice <- choices, D.ChoiceId key <- [D.choiceId choice]]
        D.ReferenceType source -> select name value [(tshow key, referenceLabel model source record) | record@(E.RowId key) <- Map.findWithDefault [] source model.rows]
        D.DateType -> [hsx|<input id={inputId} class="form-control" type="date" name={name} value={value} />|]
        D.OperationalTimeType -> [hsx|<input id={inputId} class="form-control" type="time" step="1" name={name} value={value} />|]
        _ -> [hsx|<input id={inputId} class="form-control" type="text" {...decimalInputAttrs} maxlength="80" name={name} value={value} />|]
    decimalInputAttrs :: [(Text, Text)]
    decimalInputAttrs = [("inputmode", "decimal")]
    select name value options = [hsx|
        <select id={inputId} class="form-select" name={name}>
            <option value="" selected={value == ""}>Not entered</option>
            {forEach options (renderOption value)}
        </select>
    |]
    renderOption value (key, label) = [hsx|<option value={key} selected={value == key}>{label}</option>|]
    formContract :: Int -> (FrontendSurfaceAction, Text, Text, DaysheetsController)
    formContract revision = case D.fieldType field of
        D.TextType -> let fields = Action.saveDaysheetTextActionFields revision Nothing in
            (Action.saveDaysheetTextAction fields, surfaceFieldNameFrom @Surface.ExpectedRevision fields, surfaceFieldNameFrom @Surface.EnteredText fields, SaveDaysheetTextAction sheet index row)
        D.BooleanType -> let fields = Action.saveDaysheetBooleanActionFields revision Nothing in
            (Action.saveDaysheetBooleanAction fields, surfaceFieldNameFrom @Surface.ExpectedRevision fields, surfaceFieldNameFrom @Surface.EnteredBoolean fields, SaveDaysheetBooleanAction sheet index row)
        D.DateType -> let fields = Action.saveDaysheetDateActionFields revision Nothing in
            (Action.saveDaysheetDateAction fields, surfaceFieldNameFrom @Surface.ExpectedRevision fields, surfaceFieldNameFrom @Surface.EnteredDate fields, SaveDaysheetDateAction sheet index row)
        D.OperationalTimeType -> let fields = Action.saveDaysheetClockActionFields revision Nothing in
            (Action.saveDaysheetClockAction fields, surfaceFieldNameFrom @Surface.ExpectedRevision fields, surfaceFieldNameFrom @Surface.EnteredClock fields, SaveDaysheetClockAction sheet index row)
        D.ChoiceType _ -> selection revision
        D.ReferenceType _ -> selection revision
        _ -> let fields = Action.saveDaysheetNumberActionFields revision Nothing in
            (Action.saveDaysheetNumberAction fields, surfaceFieldNameFrom @Surface.ExpectedRevision fields, surfaceFieldNameFrom @Surface.EnteredNumber fields, SaveDaysheetNumberAction sheet index row)
    selection revision = let fields = Action.saveDaysheetSelectionActionFields revision Nothing in
        (Action.saveDaysheetSelectionAction fields, surfaceFieldNameFrom @Surface.ExpectedRevision fields, surfaceFieldNameFrom @Surface.EnteredSelection fields, SaveDaysheetSelectionAction sheet index row)

-- A deletion never resurrects the row or silently drops the submitted value.
-- The invalid form keeps the shared pending-edit gate closed until explicit
-- discard. The pristine replacement allows a pending whole-body resync even
-- when this was the sheet's last editable row.
renderDeletedEntryCell :: EntryModel -> Int -> Maybe UUID -> Maybe Text -> Html
renderDeletedEntryCell model index row submitted = [hsx|
    <div id={target} class={surfaceDomTokenValue @Surface.DaysheetSurface @Surface.DaysheetCellFormTarget <> " mb-3"}>
        {form}
        {discardControl}
    </div>
|]
  where
    target = cellTargetId index row
    inputId = target <> "-unsaved"
    form = renderFrontendSurfaceActionForm action (route { actionRouteExtraAttrs = [("aria-invalid", "true") | isJust submitted] }) contents
    discardControl = if isJust submitted then renderFrontendSurfaceActionLink action route [hsx|Discard this unsaved value|] else mempty
    action = Action.keepSavedDaysheetCellAction Action.keepSavedDaysheetCellActionFields
    route = defaultFrontendSurfaceActionRoute (pathTo (KeepSavedDaysheetCellAction model.state.daysheet.id index (tshow <$> row)))
    label = maybe "Unsaved value" (("Unsaved value — " <>) . D.fieldLabel . occurrenceField) (Map.lookup index (entryOccurrences model.layout))
    contents = case submitted of
        Just raw -> [hsx|
            <p class="alert alert-warning" role="alert">This row was deleted. Copy your unsaved value if needed, then discard it to continue. Saving cannot recreate the row.</p>
            <label class="form-label" for={inputId}>{label}</label>
            <textarea id={inputId} class="form-control" readonly="readonly" rows="2">{raw}</textarea>
        |]
        Nothing -> [hsx|<p>This row was deleted.</p>|]

cellInputText :: Maybe ReferenceValue -> Text
cellInputText = \case
    Nothing -> ""
    Just (ReferenceLink (ReferenceKey _ (E.RowId key))) -> tshow key
    Just (ReferenceScalar literal) -> case literal of
        D.TextLiteral value -> value
        D.BooleanLiteral value -> if value then "true" else "false"
        D.ChoiceLiteral (D.ChoiceId value) -> tshow value
        D.WholeLiteral value -> tshow value
        D.DecimalLiteral value -> numberText value
        D.MoneyLiteral value -> numberText value
        D.PercentageLiteral value -> percentageText value
        D.DateLiteral value -> tshow value
        D.OperationalTimeLiteral value -> tshow value
