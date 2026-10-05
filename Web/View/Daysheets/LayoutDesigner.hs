module Web.View.Daysheets.LayoutDesigner (reportForm, sectionForm, blockForm) where

import qualified Application.Daysheet.Contract as D
import Application.Daysheet.Designer.Controls
import qualified Application.Helper.FrontendContract.Surface.DaysheetDesigner as Surface
import qualified Application.Helper.FrontendContract.Surface.DaysheetDesigner.Action as Action
import Application.Helper.FrontendContract.Surface.Runtime
import Application.Helper.FrontendContract.Surface.Values
import Web.View.Prelude

reportForm :: ActionFields Action.SaveDesignerReportActionOperation -> Maybe Text -> Html
reportForm fields problem = renderFrontendSurfaceActionForm (Action.saveDesignerReportAction fields)
    (defaultFrontendSurfaceActionRoute (pathTo SaveDesignerReportAction)) [hsx|
        {hidden (surfaceFieldNameFrom @Surface.ExpectedBase fields) (tshow (surfaceFieldValue @Surface.ExpectedBase fields))}
        {hidden (surfaceFieldNameFrom @Surface.ExpectedDraft fields) (maybe "" tshow (surfaceFieldValue @Surface.ExpectedDraft fields))}
        {hidden (surfaceFieldNameFrom @Surface.DefinitionReportId fields) (maybe "" tshow (surfaceFieldValue @Surface.DefinitionReportId fields))}
        {textControl (surfaceFieldNameFrom @Surface.Label fields) "Report name" (surfaceFieldValue @Surface.Label fields) problem}
        <label class="form-label" for={targetName}>Report targets</label>
        <select class="form-select mb-3" id={targetName} name={targetName}>{forEach [minBound .. maxBound] targetOption}</select>
        <p>Recipients are managed separately. Report content selects existing fields; it does not create another set of calculations.</p>
        {buttons}
    |]
  where
    targetName = surfaceFieldNameFrom @Surface.Targets fields
    targetLabel :: ReportTargets -> Text
    targetLabel FormattedOnly = "Formatted report"
    targetLabel ExcelOnly = "Excel download"
    targetLabel FormattedAndExcel = "Formatted report and Excel download"
    targetOption target = [hsx|<option value={inputValue target} selected={surfaceFieldValue @Surface.Targets fields == target}>{targetLabel target}</option>|]

sectionForm :: ActionFields Action.SaveDesignerSectionActionOperation -> Maybe Text -> Html
sectionForm fields problem = renderFrontendSurfaceActionForm (Action.saveDesignerSectionAction fields)
    (defaultFrontendSurfaceActionRoute (pathTo SaveDesignerSectionAction)) [hsx|
        {hidden (surfaceFieldNameFrom @Surface.ExpectedBase fields) (tshow (surfaceFieldValue @Surface.ExpectedBase fields))}
        {hidden (surfaceFieldNameFrom @Surface.ExpectedDraft fields) (maybe "" tshow (surfaceFieldValue @Surface.ExpectedDraft fields))}
        {hidden (surfaceFieldNameFrom @Surface.DefinitionReportId fields) (maybe "" tshow (surfaceFieldValue @Surface.DefinitionReportId fields))}
        {hidden (surfaceFieldNameFrom @Surface.DefinitionSectionId fields) (maybe "" tshow (surfaceFieldValue @Surface.DefinitionSectionId fields))}
        {textControl (surfaceFieldNameFrom @Surface.Label fields) "Section name" (surfaceFieldValue @Surface.Label fields) problem}
        <p>Renaming keeps the section identity and all its content.</p>{buttons}
    |]

blockForm :: D.Definition -> ActionFields Action.SaveDesignerBlockActionOperation -> Maybe Text -> Html
blockForm definition fields problem = renderFrontendSurfaceActionForm (Action.saveDesignerBlockAction fields)
    (defaultFrontendSurfaceActionRoute (pathTo SaveDesignerBlockAction)) [hsx|
        {hidden (surfaceFieldNameFrom @Surface.ExpectedBase fields) (tshow (surfaceFieldValue @Surface.ExpectedBase fields))}
        {hidden (surfaceFieldNameFrom @Surface.ExpectedDraft fields) (maybe "" tshow (surfaceFieldValue @Surface.ExpectedDraft fields))}
        {hidden (surfaceFieldNameFrom @Surface.DefinitionReportId fields) (maybe "" tshow (surfaceFieldValue @Surface.DefinitionReportId fields))}
        {hidden (surfaceFieldNameFrom @Surface.DefinitionSectionId fields) (tshow (surfaceFieldValue @Surface.DefinitionSectionId fields))}
        {hidden (surfaceFieldNameFrom @Surface.BlockIndex fields) (maybe "" tshow (surfaceFieldValue @Surface.BlockIndex fields))}
        {hidden (surfaceFieldNameFrom @Surface.ContentKind fields) (inputValue kind)}
        {hidden (surfaceFieldNameFrom @Surface.DefinitionListId fields) (maybe "" tshow source)}
        <h2 class="h4">{blockKindLabel kind}</h2>{controls}{buttons}
    |]
  where
    kind = surfaceFieldValue @Surface.ContentKind fields
    source = surfaceFieldValue @Surface.DefinitionListId fields
    rowFields = maybe [] D.listFields (find (\list -> let D.ListId key = D.listId list in source == Just key) (D.recordLists definition))
    scoped = case kind of RowAdvisoryContent -> rowFields; TableContent -> rowFields; _ -> D.rootFields definition
    options selected = [(let D.FieldId key = D.fieldId field in key, D.fieldLabel field) | field <- selected]
    conditionFields = filter ((== D.BooleanType) . D.fieldType) scoped
    controls = case kind of
        InstructionsContent -> textControl (surfaceFieldNameFrom @Surface.TextContent fields) "Plain-text instructions" (fromMaybe "" (surfaceFieldValue @Surface.TextContent fields)) problem
        FieldContent -> oneChoice (surfaceFieldNameFrom @Surface.DefinitionFieldId fields) "Field or summary" "Choose a root field" (surfaceFieldValue @Surface.DefinitionFieldId fields) (options scoped)
        TableContent -> [hsx|
            {manyChoices (surfaceFieldNameFrom @Surface.ColumnIds fields) "Columns" (fromMaybe [] (surfaceFieldValue @Surface.ColumnIds fields)) (options scoped)}
            {oneChoice (surfaceFieldNameFrom @Surface.GroupingFieldId fields) "Group rows by" "No grouping" (surfaceFieldValue @Surface.GroupingFieldId fields) (options scoped)}
            {manyChoices (surfaceFieldNameFrom @Surface.SortingFieldIds fields) "Sort rows by" (fromMaybe [] (surfaceFieldValue @Surface.SortingFieldIds fields)) (options scoped)}
            {manyChoices (surfaceFieldNameFrom @Surface.DescendingFieldIds fields) "Descending sort fields" (fromMaybe [] (surfaceFieldValue @Surface.DescendingFieldIds fields)) (options scoped)}
            <p class="form-text">Use multiple selection for columns and sorting. Saved order is retained; new selections append. Descending applies only to selected sort fields.</p>
        |]
        AdvisoryContent -> advisoryControls
        RowAdvisoryContent -> advisoryControls
    advisoryControls = [hsx|
        {oneChoice (surfaceFieldNameFrom @Surface.DefinitionFieldId fields) "Boolean condition" "Keep existing condition (or choose a boolean field)" (surfaceFieldValue @Surface.DefinitionFieldId fields) (options conditionFields)}
        {textControl (surfaceFieldNameFrom @Surface.PassedText fields) "Pass message" (fromMaybe "" (surfaceFieldValue @Surface.PassedText fields)) problem}
        {textControl (surfaceFieldNameFrom @Surface.ConcernText fields) "Concern message" (fromMaybe "" (surfaceFieldValue @Surface.ConcernText fields)) problem}
        <p class="form-text">Blank inputs yield Not evaluated, not a pass. These checks do not prevent submission.</p>
    |]

hidden :: Text -> Text -> Html
hidden name value = [hsx|<input type="hidden" name={name} value={value}/>|]
textControl :: Text -> Text -> Text -> Maybe Text -> Html
textControl name label value problem = let invalid :: Text; invalid = if isJust problem then "true" else "false"
    in [hsx|<div class="mb-3"><label class="form-label" for={name}>{label}</label><textarea class="form-control" id={name} name={name} rows="2" required="required" aria-invalid={invalid}>{value}</textarea></div>|]

oneChoice :: Text -> Text -> Text -> Maybe UUID -> [(UUID, Text)] -> Html
oneChoice name label empty selected options = [hsx|<div class="mb-3"><label class="form-label" for={name}>{label}</label><select class="form-select" id={name} name={name}><option value="" selected={isNothing selected}>{empty}</option>{forEach retained option}</select></div>|]
  where
    retained = options <> [(key, "Unavailable field") | key <- maybeToList selected, key `notElem` map fst options]
    option (key, caption) = [hsx|<option value={tshow key} selected={selected == Just key}>{caption}</option>|]

manyChoices :: Text -> Text -> [UUID] -> [(UUID, Text)] -> Html
manyChoices name label selected options = [hsx|<div class="mb-3"><label class="form-label" for={name}>{label}</label><select class="form-select" id={name} name={name} multiple="multiple" size="5">{forEach ordered option}</select></div>|]
  where
    ordered = selected <> [key | (key, _) <- options, key `notElem` selected]
    option key = [hsx|<option value={tshow key} selected={key `elem` selected}>{fromMaybe "Unavailable field" (lookup key options)}</option>|]

buttons :: Html
buttons = [hsx|<div class="d-flex gap-2"><button class="btn btn-primary" type="submit">Save draft</button><a class="btn btn-outline-secondary" href={DaysheetDesignerAction}>Discard edit and return</a></div>|]
