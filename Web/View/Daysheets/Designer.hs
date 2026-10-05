module Web.View.Daysheets.Designer
    ( DesignerView (..), DesignerPage (..), renderDesigner, designerSurface, referenceEntryText ) where

import qualified Application.Daysheet.Contract as D
import Application.Daysheet.Designer.Controls
import Application.Daysheet.Storage (DesignerState (..))
import Application.Daysheet.References
import qualified Application.Daysheet.Evaluation as E
import Web.Daysheets.ReadModel (numberText, percentageText)
import qualified Application.Helper.FrontendContract.Surface.DaysheetDesigner as Surface
import qualified Application.Helper.FrontendContract.Surface.DaysheetDesigner.Action as Action
import Application.Helper.FrontendContract.Surface.Attributes (roleAttrs)
import Application.Helper.FrontendContract.Surface.Runtime
import Application.Helper.FrontendContract.Surface.Values
import Web.View.Prelude hiding (referenceRecordId)

-- At most one editable form is mounted on a designer page. Saving it cannot
-- discard unrelated unsaved forms; publication lives on the read-only index.
data DesignerPage
    = DesignerIndexPage
    | DesignerFieldPage (ActionFields Action.SaveDesignerFieldActionOperation)
    | DesignerListPage (ActionFields Action.SaveDesignerListActionOperation)
    | DesignerReferencePage (ActionFields Action.SaveDesignerReferenceValueActionOperation)

data DesignerView = DesignerView
    { venue :: UUID, state :: DesignerState, page :: DesignerPage, problem :: Maybe Text }
instance View DesignerView where
    html DesignerView { .. } = renderDesigner venue state page problem

designerSurface :: UUID -> DesignerPage -> SurfaceImpl Surface.DaysheetDesignerSurface
designerSurface venue page = mkSurfaceImplFromValues @Surface.DaysheetDesignerSurface @Surface.DesignerScope "primary"
    (surfaceField @Surface.VenueId venue &: noSurfaceFields) noSurfaceFields [mounted]
  where
    mounted = case page of
        DesignerIndexPage -> frontendSurfaceMountedFragmentFor @Surface.DaysheetDesignerSurface @Surface.DesignerIndex
            noSurfaceFields noSurfaceFields (pathTo ShowDesignerIndexBodyAction) FrontendSurfaceReplace
        DesignerFieldPage fields -> let
            key = surfaceFieldValue @Surface.DefinitionFieldId fields
            parent = surfaceFieldValue @Surface.ContainerId fields
            params = surfaceOptionalField @Surface.DefinitionFieldId key &: surfaceOptionalField @Surface.ContainerId parent &: noSurfaceFields
            in frontendSurfaceMountedFragmentFor @Surface.DaysheetDesignerSurface @Surface.DesignerFieldEditor params params
                (pathTo (ShowDesignerFieldBodyAction (tshow <$> key) (tshow <$> parent))) FrontendSurfaceDirtyForm
        DesignerReferencePage fields -> frontendSurfaceMountedFragmentFor @Surface.DaysheetDesignerSurface @Surface.DesignerReferenceEditor
            (referenceParams fields) (referenceParams fields)
            (pathTo (ShowDesignerReferenceBodyAction (surfaceFieldValue @Surface.DefinitionListId fields)
                (surfaceFieldValue @Surface.ReferenceRecordId fields) (surfaceFieldValue @Surface.DefinitionFieldId fields))) FrontendSurfaceDirtyForm
        DesignerListPage fields -> let
            key = surfaceFieldValue @Surface.DefinitionListId fields
            params = surfaceOptionalField @Surface.DefinitionListId key &: noSurfaceFields
            in frontendSurfaceMountedFragmentFor @Surface.DaysheetDesignerSurface @Surface.DesignerListEditor params params
                (pathTo (ShowDesignerListBodyAction (tshow <$> key))) FrontendSurfaceDirtyForm

renderDesigner :: (?context :: ControllerContext) => UUID -> DesignerState -> DesignerPage -> Maybe Text -> Html
renderDesigner venue state page problem = case page of
    DesignerIndexPage -> renderFrontendSurfaceFragmentMount @Surface.DaysheetDesignerSurface @Surface.DesignerIndex noSurfaceFields impl content
    DesignerFieldPage fields -> renderFrontendSurfaceFragmentMount @Surface.DaysheetDesignerSurface @Surface.DesignerFieldEditor
        (surfaceOptionalField @Surface.DefinitionFieldId (surfaceFieldValue @Surface.DefinitionFieldId fields)
            &: surfaceOptionalField @Surface.ContainerId (surfaceFieldValue @Surface.ContainerId fields) &: noSurfaceFields) impl content
    DesignerReferencePage fields -> renderFrontendSurfaceFragmentMount @Surface.DaysheetDesignerSurface @Surface.DesignerReferenceEditor
        (referenceParams fields) impl content
    DesignerListPage fields -> renderFrontendSurfaceFragmentMount @Surface.DaysheetDesignerSurface @Surface.DesignerListEditor
        (surfaceOptionalField @Surface.DefinitionListId (surfaceFieldValue @Surface.DefinitionListId fields) &: noSurfaceFields) impl content
  where
    impl = designerSurface venue page
    definition = state.designerDefinition
    base = fromInteger state.designerBaseRevision
    revision = fromInteger <$> state.designerDraftRevision
    finalAttrs = roleAttrs (surfaceBrowserRoleValue @Surface.DaysheetDesignerSurface @Surface.DesignerFinalAction)
    pendingAttrs = roleAttrs (surfaceBrowserRoleValue @Surface.DaysheetDesignerSurface @Surface.DesignerPendingNotice)
    invalidValue :: Text
    invalidValue = if isJust problem then "true" else "false"
    content = renderAppPage AppPageConfig
        { appPageTitle = "Daysheet designer", appPageDescription = Nothing, appPageHelpTopic = Nothing
        , appPageWidthClass = "", appPageActions = mempty
        , appPageBody = [hsx|
            <div class="app-page-stack">
                <p>Changes are staged. Publish explicitly to use them for new Daysheets. Existing Daysheets, including drafts, keep their captured definitions.</p>
                <p>Configuration revision: {state.designerCurrentRevision}. Draft base: {state.designerBaseRevision}.</p>
                {staleNotice}
                {forEach problem renderProblem}
                <p {...pendingAttrs} class="alert alert-warning" role="status" hidden="hidden">Save or resolve your pending edit before continuing.</p>
                {body}
            </div>
        |]
        }
    renderProblem :: Text -> Html
    renderProblem text = [hsx|<div class="alert alert-warning" role="alert">{text}</div>|]
    staleNotice = if state.designerBaseRevision == state.designerCurrentRevision then mempty
        else renderProblem "Live reference data changed after this draft began. This draft cannot be saved or published against the old base. Your staged changes have not been discarded."
    body = case page of
        DesignerIndexPage -> [hsx|
            <div class="d-flex gap-2 flex-wrap">
                <a class="btn btn-outline-primary" href={ShowDesignerFieldAction Nothing Nothing}>Add root field</a>
                <a class="btn btn-outline-primary" href={ShowDesignerListAction Nothing}>Add list</a>
                {publishButton}
            </div>
            <section><h2 class="h4">Root fields</h2>{forEach (D.rootFields definition) fieldSummary}</section>
            {forEach (D.recordLists definition) listSummary}
        |]
        DesignerFieldPage fields -> fieldForm fields
        DesignerListPage fields -> listForm fields
        DesignerReferencePage fields -> referenceForm fields
    publishButton = case state.designerDraftRevision of
        Nothing -> [hsx|<p class="text-muted">No unpublished changes.</p>|]
        Just _ -> let fields = Action.publishDesignerDraftActionFields base revision
            in renderFrontendSurfaceActionFormWithHiddenFields (Action.publishDesignerDraftAction fields)
                ((defaultFrontendSurfaceActionRoute (pathTo PublishDesignerDraftAction)) { actionRouteExtraAttrs = finalAttrs })
                [hsx|<button class="btn btn-primary" type="submit">Publish draft</button>|]
    fieldSummary field = let
        D.FieldId key = D.fieldId field
        fields = Action.removeDesignerFieldActionFields base revision key
        remove = renderFrontendSurfaceActionFormWithHiddenFields (Action.removeDesignerFieldAction fields)
            (defaultFrontendSurfaceActionRoute (pathTo RemoveDesignerFieldAction)) [hsx|<button class="btn btn-sm btn-outline-danger" type="submit">Remove field</button>|]
        in [hsx|<div class="d-flex gap-2 align-items-center flex-wrap mb-2"><a href={ShowDesignerFieldAction (Just (tshow key)) Nothing}>{D.fieldLabel field}</a><span class="text-muted">{fieldKindLabel (fieldKind (D.fieldType field))}</span>{remove}</div>|]
    listSummary source = let
        D.ListId key = D.listId source
        fields = Action.removeDesignerListActionFields base revision key
        remove = renderFrontendSurfaceActionFormWithHiddenFields (Action.removeDesignerListAction fields)
            (defaultFrontendSurfaceActionRoute (pathTo RemoveDesignerListAction)) [hsx|<button class="btn btn-sm btn-outline-danger" type="submit">Remove list</button>|]
        in renderAppPanel (defaultAppPanelConfig [hsx|
            <h2 class="h4"><a href={ShowDesignerListAction (Just (tshow key))}>{D.listLabel source}</a></h2>
            <p>{listKindLabel (listKind (D.listMode source))}</p>
            {forEach (D.listFields source) fieldSummary}
            {referenceRows source}
            <div class="d-flex gap-2"><a class="btn btn-sm btn-outline-primary" href={ShowDesignerFieldAction Nothing (Just (tshow key))}>Add field to list</a>{remove}</div>
        |])
    referenceRows source = case D.listMode source of
        D.VenueReference -> let
            D.ListId key = D.listId source
            fields = Action.addDesignerReferenceActionFields base revision key
            add = renderFrontendSurfaceActionFormWithHiddenFields (Action.addDesignerReferenceAction fields)
                (defaultFrontendSurfaceActionRoute (pathTo AddDesignerReferenceAction)) [hsx|<button class="btn btn-sm btn-outline-primary" type="submit">Add reference record</button>|]
            rows = activeRows state.designerReferences (D.listId source)
            in [hsx|<section aria-label={"Reference records: " <> D.listLabel source}><h3 class="h5">Reference records</h3>{forEach rows (referenceRow source)}{add}</section>|]
        _ -> mempty
    referenceRow source row = let
        D.ListId sourceId = D.listId source
        E.RowId rowId = referenceRecordId row
        key = ReferenceKey (D.listId source) (referenceRecordId row)
        dependencies = retirementDependencies state.designerReferences key
        fields = Action.retireDesignerReferenceActionFields base revision sourceId rowId
        retire = renderFrontendSurfaceActionFormWithHiddenFields (Action.retireDesignerReferenceAction fields)
            (defaultFrontendSurfaceActionRoute (pathTo RetireDesignerReferenceAction)) [hsx|<button class="btn btn-sm btn-outline-danger" type="submit" disabled={not (null dependencies)}>Retire reference record</button>|]
        cell field = let D.FieldId fieldId = D.fieldId field in [hsx|
            <p><a href={ShowDesignerReferenceAction sourceId rowId fieldId}>{D.fieldLabel field}</a>: {maybe "Blank" referenceEntryText (lookup (D.fieldId field) (referenceValues row))}</p>
        |]
        obsolete = filter (\(field, _) -> not (any (\declared -> D.fieldId declared == field && D.fieldSource declared == D.Entered) (D.listFields source))) (referenceValues row)
        clearOld (D.FieldId fieldId, value) = let
            request = Action.saveDesignerReferenceValueActionFields base revision sourceId rowId fieldId Nothing
            in renderFrontendSurfaceActionFormWithHiddenFields (Action.saveDesignerReferenceValueAction request)
                (defaultFrontendSurfaceActionRoute (pathTo SaveDesignerReferenceValueAction)) [hsx|<p>Obsolete stored value: {referenceEntryText value} <button class="btn btn-sm btn-outline-secondary" type="submit">Clear obsolete value</button></p>|]
        in [hsx|<div role="group" aria-label={referenceRowLabel source row} class="mb-3 text-break"><h4 class="h6">{referenceRowLabel source row}</h4>
            {forEach (filter ((== D.Entered) . D.fieldSource) (D.listFields source)) cell}
            {forEach obsolete clearOld}
            {if null dependencies then mempty else dependencyNotice dependencies}
            {retire}
        </div>|]
    dependencyNotice dependencies = [hsx|<p class="form-text">Reassign or explicitly clear these links before retiring this record: {forEach dependencies dependencyLink}</p>|]
    dependencyLink (Dependency (ReferenceKey (D.ListId source) (E.RowId row)) (D.FieldId field)) =
        [hsx|<a class="me-2" href={ShowDesignerReferenceAction source row field}>Edit dependent link</a>|]
    referenceForm fields = let
        source = D.ListId (surfaceFieldValue @Surface.DefinitionListId fields)
        field = D.FieldId (surfaceFieldValue @Surface.DefinitionFieldId fields)
        declared = find ((== source) . D.listId) (D.recordLists definition) >>= find ((== field) . D.fieldId) . D.listFields
        name = surfaceFieldNameFrom @Surface.EnteredValue fields
        raw = fromMaybe "" (surfaceFieldValue @Surface.EnteredValue fields)
        control = case D.fieldType <$> declared of
            Just D.BooleanType -> selection name raw [("true", "Yes"), ("false", "No")]
            Just (D.ChoiceType choices) -> selection name raw [(let D.ChoiceId key = D.choiceId choice in tshow key, D.choiceLabel choice) | choice <- choices]
            Just (D.ReferenceType target) -> let targetSource = find ((== target) . D.listId) (D.recordLists definition)
                in selection name raw [(let E.RowId key = referenceRecordId row in tshow key, maybe (referenceEntryText (ReferenceLink (ReferenceKey target (referenceRecordId row)))) (\list -> referenceRowLabel list row) targetSource) | row <- activeRows state.designerReferences target]
            _ -> [hsx|<textarea class="form-control" id={name} name={name} rows="3" aria-invalid={invalidValue}>{raw}</textarea>|]
        in renderFrontendSurfaceActionForm (Action.saveDesignerReferenceValueAction fields) (defaultFrontendSurfaceActionRoute (pathTo SaveDesignerReferenceValueAction)) [hsx|
            {hidden (surfaceFieldNameFrom @Surface.ExpectedBase fields) (tshow (surfaceFieldValue @Surface.ExpectedBase fields))}
            {hidden (surfaceFieldNameFrom @Surface.ExpectedDraft fields) (maybe "" tshow (surfaceFieldValue @Surface.ExpectedDraft fields))}
            {hidden (surfaceFieldNameFrom @Surface.DefinitionListId fields) (tshow (surfaceFieldValue @Surface.DefinitionListId fields))}
            {hidden (surfaceFieldNameFrom @Surface.ReferenceRecordId fields) (tshow (surfaceFieldValue @Surface.ReferenceRecordId fields))}
            {hidden (surfaceFieldNameFrom @Surface.DefinitionFieldId fields) (tshow (surfaceFieldValue @Surface.DefinitionFieldId fields))}
            <label class="form-label" for={name}>{maybe "Reference value" D.fieldLabel declared}</label>{control}
            <p class="form-text">{maybe "This field no longer exists. Clear its obsolete stored value from the designer." (fieldKindLabel . fieldKind . D.fieldType) declared}. Blank explicitly clears this value. Money is AUD; percentages use human units such as 1.6. Dates use YYYY-MM-DD; times use HH:MM.</p>
            {buttons}
        |]
    selection name raw options = let
        option (value, label) = [hsx|<option value={value} selected={raw == value}>{label}</option>|]
        retained = if raw == "" || any ((== raw) . fst) options then mempty else option (raw, "Previous value — choose a correction: " <> raw)
        in [hsx|<select class="form-select" id={name} name={name} aria-invalid={invalidValue}><option value="" selected={raw == ""}>Blank</option>{retained}{forEach options option}</select>|]
    fieldForm fields = let
        name = surfaceFieldNameFrom @Surface.Label fields
        kindName = surfaceFieldNameFrom @Surface.ValueKind fields
        sourceName = surfaceFieldNameFrom @Surface.ReferenceListId fields
        choiceName = surfaceFieldNameFrom @Surface.InitialChoice fields
        selected = surfaceFieldValue @Surface.ValueKind fields
        option kind = [hsx|<option value={inputValue kind} selected={kind == selected}>{fieldKindLabel kind}</option>|]
        in renderFrontendSurfaceActionForm (Action.saveDesignerFieldAction fields) (defaultFrontendSurfaceActionRoute (pathTo SaveDesignerFieldAction)) [hsx|
            {hidden (surfaceFieldNameFrom @Surface.ExpectedBase fields) (tshow (surfaceFieldValue @Surface.ExpectedBase fields))}
            {hidden (surfaceFieldNameFrom @Surface.ExpectedDraft fields) (maybe "" tshow (surfaceFieldValue @Surface.ExpectedDraft fields))}
            {hidden (surfaceFieldNameFrom @Surface.DefinitionFieldId fields) (maybe "" tshow (surfaceFieldValue @Surface.DefinitionFieldId fields))}
            {hidden (surfaceFieldNameFrom @Surface.ContainerId fields) (maybe "" tshow (surfaceFieldValue @Surface.ContainerId fields))}
            <div class="mb-3"><label class="form-label" for={name}>Field name</label><input class="form-control" id={name} name={name} value={surfaceFieldValue @Surface.Label fields} required="required" aria-invalid={invalidValue}/></div>
            <div class="mb-3"><label class="form-label" for={kindName}>Field type</label><select class="form-select" id={kindName} name={kindName}>{forEach [minBound .. maxBound] option}</select></div>
            {referenceSelect sourceName (surfaceFieldValue @Surface.ReferenceListId fields) (D.recordLists definition)}
            <div class="mb-3"><label class="form-label" for={choiceName}>First option (new choice fields only)</label><input class="form-control" id={choiceName} name={choiceName} value={fromMaybe "" (surfaceFieldValue @Surface.InitialChoice fields)}/></div>
            <p class="form-text">Renaming keeps the field identity and any existing calculation. Changes that break dependent fields or layouts are rejected.</p>
            {buttons}
        |]
    listForm fields = let
        name = surfaceFieldNameFrom @Surface.Label fields
        kindName = surfaceFieldNameFrom @Surface.CollectionKind fields
        sourceName = surfaceFieldNameFrom @Surface.ReferenceListId fields
        selected = surfaceFieldValue @Surface.CollectionKind fields
        option kind = [hsx|<option value={inputValue kind} selected={kind == selected}>{listKindLabel kind}</option>|]
        in renderFrontendSurfaceActionForm (Action.saveDesignerListAction fields) (defaultFrontendSurfaceActionRoute (pathTo SaveDesignerListAction)) [hsx|
            {hidden (surfaceFieldNameFrom @Surface.ExpectedBase fields) (tshow (surfaceFieldValue @Surface.ExpectedBase fields))}
            {hidden (surfaceFieldNameFrom @Surface.ExpectedDraft fields) (maybe "" tshow (surfaceFieldValue @Surface.ExpectedDraft fields))}
            {hidden (surfaceFieldNameFrom @Surface.DefinitionListId fields) (maybe "" tshow (surfaceFieldValue @Surface.DefinitionListId fields))}
            <div class="mb-3"><label class="form-label" for={name}>List name</label><input class="form-control" id={name} name={name} value={surfaceFieldValue @Surface.Label fields} required="required" aria-invalid={invalidValue}/></div>
            <div class="mb-3"><label class="form-label" for={kindName}>List mode</label><select class="form-select" id={kindName} name={kindName}>{forEach [minBound .. maxBound] option}</select></div>
            {referenceSelect sourceName (surfaceFieldValue @Surface.ReferenceListId fields) (filter ((== D.VenueReference) . D.listMode) (D.recordLists definition))}
            <p class="form-text">A checklist requires a venue reference list. Existing list fields and identities are retained.</p>
            {buttons}
        |]
    buttons = [hsx|<div class="d-flex gap-2"><button class="btn btn-primary" type="submit">Save draft</button><a class="btn btn-outline-secondary" href={DaysheetDesignerAction}>Discard edit and return</a></div>|]

referenceParams :: ActionFields Action.SaveDesignerReferenceValueActionOperation -> SurfaceFields Surface.ReferenceEditorParams
referenceParams fields = surfaceField @Surface.DefinitionListId (surfaceFieldValue @Surface.DefinitionListId fields)
    &: surfaceField @Surface.ReferenceRecordId (surfaceFieldValue @Surface.ReferenceRecordId fields)
    &: surfaceField @Surface.DefinitionFieldId (surfaceFieldValue @Surface.DefinitionFieldId fields) &: noSurfaceFields

activeRows :: ReferenceData -> D.ListId -> [ReferenceRecord]
activeRows (ReferenceData lists) source = [row | list <- lists, referenceListId list == source, row <- referenceRecords list, not (referenceRetired row)]

referenceRowLabel :: D.RecordList -> ReferenceRecord -> Text
referenceRowLabel source row = fromMaybe ("Record " <> tshow (referenceRecordId row)) (headMay
    [text | field <- D.listFields source, Just (ReferenceScalar (D.TextLiteral text)) <- [lookup (D.fieldId field) (referenceValues row)], not (null text)])

referenceEntryText :: ReferenceValue -> Text
referenceEntryText (ReferenceLink (ReferenceKey _ (E.RowId key))) = tshow key
referenceEntryText (ReferenceScalar literal) = case literal of
    D.TextLiteral text -> text
    D.BooleanLiteral value -> if value then "true" else "false"
    D.ChoiceLiteral (D.ChoiceId key) -> tshow key
    D.WholeLiteral value -> tshow value
    D.DecimalLiteral value -> numberText value
    D.MoneyLiteral value -> numberText value
    D.PercentageLiteral value -> percentageText value
    D.DateLiteral value -> tshow value
    D.OperationalTimeLiteral value -> tshow value

hidden :: Text -> Text -> Html
hidden name value = [hsx|<input type="hidden" name={name} value={value}/>|]

referenceSelect :: Text -> Maybe UUID -> [D.RecordList] -> Html
referenceSelect name selected sources = [hsx|
    <div class="mb-3"><label class="form-label" for={name}>Reference list (reference fields / checklists only)</label>
        <select class="form-select" id={name} name={name}><option value="">Not applicable</option>{forEach sources option}</select>
    </div>
|]
  where
    option source = let D.ListId key = D.listId source
        in [hsx|<option value={tshow key} selected={selected == Just key}>{D.listLabel source}</option>|]
