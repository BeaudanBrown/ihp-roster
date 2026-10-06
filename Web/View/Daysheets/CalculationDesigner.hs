module Web.View.Daysheets.CalculationDesigner
    ( calculationBody, constantForm, calculationCaption ) where

import qualified Application.Daysheet.Contract as D
import qualified Application.Daysheet.Designer as Designer
import Application.Daysheet.Designer.Calculation
import Application.Daysheet.Designer.Controls
import Application.Daysheet.Storage (DesignerState (..))
import qualified Application.Helper.FrontendContract.Surface.DaysheetDesigner as Surface
import qualified Application.Helper.FrontendContract.Surface.DaysheetDesigner.Action as Action
import Application.Helper.FrontendContract.Surface.Runtime
import Application.Helper.FrontendContract.Surface.Values
import Web.Daysheets.CalculationEditing
import Web.Daysheets.ReadModel (numberText, percentageText)
import Web.View.Prelude

calculationBody :: (?context :: ControllerContext) => DesignerState -> CalculationEditor -> Html
calculationBody state editor = [hsx|
    <section aria-label={"Calculation: " <> D.fieldLabel field}>
        <h2 class="h4">Calculation: {D.fieldLabel field}</h2>
        <p>Choosing a part immediately saves a valid draft change. New operations use visible example constants; review and edit their inputs before publishing.</p>
        <p><a href={DaysheetDesignerAction}>Return to designer</a> · <a href={route [] FieldParts Nothing}>Whole calculation</a></p>
        <h3 class="h5">Selected part</h3><p class="text-break" role="status">{calculationCaption definition editor.editorFocus}</p>
        <p>Type: {calculationTypeLabel definition editor.editorType}</p>
        <div class="d-flex gap-2 flex-wrap mb-3">{forEach children childLink}{constantLink}{enteredButton}</div>
        <nav aria-label="Calculation part groups" class="d-flex gap-2 flex-wrap mb-3">{forEach [minBound .. maxBound] groupLink}</nav>
        {directFieldsLink}
        <div class="d-flex flex-column align-items-start gap-2">{forEach (calculationMenuLinks editor.editorMenu) referenceLink}</div>
        <div class="d-flex flex-column align-items-start gap-2 mt-2">{forEach (zip [0 ..] options) optionButton}</div>
        {emptyNotice}
    </section>
|]
  where
    definition = state.designerDefinition
    field = Designer.calculationField editor.editorFocus
    D.FieldId key = editor.editorField
    base = fromInteger state.designerBaseRevision
    revision = fromInteger <$> state.designerDraftRevision
    options = calculationMenuOptions editor.editorMenu
    children = maybe [] Designer.calculationChildren (Designer.calculationExpression editor.editorFocus)
    directFieldsLink = if isJust editor.editorReferencePath then [hsx|<p><a href={route editor.editorLocation FieldParts Nothing}>Read direct fields</a></p>|] else mempty
    emptyNotice = if null options then [hsx|<p>No compatible parts in this group. Choose another group or follow a reference.</p>|] else mempty
    route location group path = ShowDesignerCalculationAction key (renderCalculationLocation location) (inputValue group) (renderReferencePath <$> path)
    groupLink group = [hsx|<a class="btn btn-outline-secondary" href={route editor.editorLocation group Nothing}>{calculationGroupLabel group}</a>|]
    childLink (slot, _) = let
        location = editor.editorLocation <> [slot]
        label = case slot of
            Designer.UnaryInput -> "Edit input"; Designer.BinaryLeft -> "Edit left input"; Designer.BinaryRight -> "Edit right input"
            Designer.Condition -> "Edit condition"; Designer.WhenTrue -> "Edit if-true value"; Designer.WhenFalse -> "Edit otherwise value"
            Designer.FoldFilter -> "Edit row filter"; Designer.FoldValue -> "Edit row value"
        caption = either (const "Unavailable part") (calculationCaption definition) (Designer.calculationFocus editor.editorField location definition)
        in [hsx|<a class="btn btn-outline-primary text-break" href={route location FieldParts Nothing}>{label :: Text}: {caption}</a>|]
    referenceLink link = [hsx|<a class="btn btn-outline-primary text-break" href={route editor.editorLocation FieldParts (Just link.calculationLinkPath)}>{link.calculationLinkLabel}</a>|]
    optionButton (index, option) = let
        fields = Action.useDesignerCalculationPartActionFields base revision key (Just editor.editorLocation) editor.editorGroup (renderReferencePath <$> editor.editorReferencePath) index
        in renderFrontendSurfaceActionFormWithHiddenFields (Action.useDesignerCalculationPartAction fields) (defaultFrontendSurfaceActionRoute (pathTo UseDesignerCalculationPartAction))
            [hsx|<button class="btn btn-outline-primary text-break" type="submit">{"Use " <> calculationOptionLabel option}</button>|]
    constantLink = case constantType definition editor.editorField editor.editorLocation of
        Right _ -> [hsx|<a class="btn btn-outline-primary" href={ShowDesignerConstantAction key (renderCalculationLocation editor.editorLocation)}>Enter constant value</a>|]
        Left _ -> mempty
    enteredButton = case (editor.editorLocation, D.fieldSource field) of
        ([], D.Calculated _) -> let fields = Action.makeDesignerFieldEnteredActionFields base revision key
            in renderFrontendSurfaceActionFormWithHiddenFields (Action.makeDesignerFieldEnteredAction fields) (defaultFrontendSurfaceActionRoute (pathTo MakeDesignerFieldEnteredAction))
                [hsx|<button class="btn btn-outline-danger" type="submit">Make entered field — remove calculation</button>|]
        _ -> mempty

constantForm :: (?context :: ControllerContext) => DesignerState -> ActionFields Action.SaveDesignerConstantActionOperation -> Maybe Text -> Html
constantForm state fields problem = renderFrontendSurfaceActionForm (Action.saveDesignerConstantAction fields) (defaultFrontendSurfaceActionRoute (pathTo SaveDesignerConstantAction)) [hsx|
    {hidden (surfaceFieldNameFrom @Surface.ExpectedBase fields) (tshow (surfaceFieldValue @Surface.ExpectedBase fields))}
    {hidden (surfaceFieldNameFrom @Surface.ExpectedDraft fields) (maybe "" tshow (surfaceFieldValue @Surface.ExpectedDraft fields))}
    {hidden (surfaceFieldNameFrom @Surface.DefinitionFieldId fields) (tshow key)}
    {forEach location (\slot -> hidden (surfaceFieldNameFrom @Surface.ExpressionSlots fields) (inputValue slot))}
    <p class="text-break">Current part: {caption}</p>
    <label class="form-label" for={name}>New constant value</label>{control}
    <p class="form-text">{maybe "Unavailable type" (calculationTypeLabel state.designerDefinition) kind}. Money is AUD; percentages use human units such as 1.6 for 1.6%. Dates use YYYY-MM-DD; times use HH:MM. Numeric values do not accept expressions or exponent notation.</p>
    <div class="d-flex gap-2 mt-3"><button class="btn btn-primary" type="submit">Save constant</button><a class="btn btn-outline-secondary" href={DaysheetDesignerAction}>Discard edit and return</a></div>
|]
  where
    key = surfaceFieldValue @Surface.DefinitionFieldId fields
    location = fromMaybe [] (surfaceFieldValue @Surface.ExpressionSlots fields)
    kind = either (const Nothing) Just (constantType state.designerDefinition (D.FieldId key) location)
    caption = either (const "The saved calculation changed.") (calculationCaption state.designerDefinition) (Designer.calculationFocus (D.FieldId key) location state.designerDefinition)
    name = surfaceFieldNameFrom @Surface.EnteredValue fields
    raw = surfaceFieldValue @Surface.EnteredValue fields
    invalid :: Text
    invalid = if isJust problem then "true" else "false"
    control = case kind of
        Just D.BooleanType -> select [("true", "Yes"), ("false", "No")]
        Just (D.ChoiceType choices) -> select [(let D.ChoiceId identity = D.choiceId choice in tshow identity, D.choiceLabel choice) | choice <- choices]
        _ -> [hsx|<textarea class="form-control" id={name} name={name} rows="3" maxlength="10000" required={kind /= Just D.TextType} aria-invalid={invalid}>{raw}</textarea>|]
    select values = let option (value, label) = [hsx|<option value={value} selected={raw == value}>{label}</option>|]
        in [hsx|<select class="form-select" id={name} name={name} required="required" aria-invalid={invalid}><option value="" selected={raw == ""}>Choose a value</option>{forEach values option}</select>|]

calculationCaption :: D.Definition -> Designer.CalculationFocus -> Text
calculationCaption definition focus = case Designer.calculationExpression focus of
    Nothing -> "Entered value"
    Just expression -> case expression of
        D.Constant literal -> case literal of
            D.TextLiteral "" -> "Text — empty"
            D.TextLiteral value -> "Text — " <> value
            D.BooleanLiteral value -> if value then "Yes" else "No"
            D.ChoiceLiteral key -> "Choice — " <> fromMaybe "Unavailable option" (headMay [D.choiceLabel choice | field <- D.rootFields definition <> concatMap D.listFields (D.recordLists definition), D.ChoiceType choices <- [D.fieldType field], choice <- choices, D.choiceId choice == key])
            D.WholeLiteral value -> tshow value
            D.DecimalLiteral value -> numberText value
            D.MoneyLiteral value -> numberText value <> " AUD"
            D.PercentageLiteral value -> percentageText value <> "%"
            D.DateLiteral value -> tshow value
            D.OperationalTimeLiteral value -> tshow value
        D.ReadField (D.FieldPath context path) -> contextLabel context <> pathLabel (contextFields context) path
        D.ChecklistReference context -> contextLabel context <> "paired checklist reference"
        D.Unary operation _ -> unaryLabel operation
        D.Binary operation _ _ -> binaryLabel operation
        D.If {} -> "If / otherwise"
        D.Fold operation source _ _ -> (if operation == D.Sum then "Sum rows — " else "Count rows — ") <> maybe "Unavailable list" D.listLabel (find ((== source) . D.listId) (D.recordLists definition))
  where
    contextLabel D.Root = "Whole Daysheet — "
    contextLabel D.Current = "This row — "
    contextLabel D.Item = "Included row — "
    contextFields D.Root = D.rootFields definition
    contextFields context = fromMaybe [] do
        key <- if context == D.Current then Designer.calculationCurrent focus else Designer.calculationItem focus
        D.listFields <$> find ((== key) . D.listId) (D.recordLists definition)
    pathLabel _ [] = "Unavailable field"
    pathLabel fields (key : rest) = case find ((== key) . D.fieldId) fields of
        Nothing -> "Unavailable field"
        Just field | null rest -> D.fieldLabel field
        Just field -> D.fieldLabel field <> " → " <> case D.fieldType field of
            D.ReferenceType source -> pathLabel (maybe [] D.listFields (find ((== source) . D.listId) (D.recordLists definition))) rest
            _ -> "Unavailable field"

hidden :: Text -> Text -> Html
hidden name value = [hsx|<input type="hidden" name={name} value={value}/>|]
