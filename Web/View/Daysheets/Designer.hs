module Web.View.Daysheets.Designer
    ( DesignerView (..), DesignerPage (..), renderDesigner, designerSurface ) where

import qualified Application.Daysheet.Contract as D
import Application.Daysheet.Designer.Controls
import Application.Daysheet.Storage (DesignerState (..))
import qualified Application.Helper.FrontendContract.Surface.DaysheetDesigner as Surface
import qualified Application.Helper.FrontendContract.Surface.DaysheetDesigner.Action as Action
import Application.Helper.FrontendContract.Surface.Attributes (roleAttrs)
import Application.Helper.FrontendContract.Surface.Runtime
import Application.Helper.FrontendContract.Surface.Values
import Web.View.Prelude

-- At most one editable form is mounted on a designer page. Saving it cannot
-- discard unrelated unsaved forms; publication lives on the read-only index.
data DesignerPage
    = DesignerIndexPage
    | DesignerFieldPage (ActionFields Action.SaveDesignerFieldActionOperation)
    | DesignerListPage (ActionFields Action.SaveDesignerListActionOperation)

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
            <div class="d-flex gap-2"><a class="btn btn-sm btn-outline-primary" href={ShowDesignerFieldAction Nothing (Just (tshow key))}>Add field to list</a>{remove}</div>
        |])
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
