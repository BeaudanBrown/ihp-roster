module Web.Controller.DaysheetDesigner where

import qualified Application.Daysheet.Contract as D
import qualified Application.Daysheet.Designer as Designer
import qualified Application.Daysheet.Designer.Calculation as Calculation
import qualified Web.Daysheets.CalculationEditing as CalculationEditing
import Application.Daysheet.Designer.Controls
import Application.Daysheet.Designer.ReferenceEntry (parseReferenceEntry)
import qualified Application.Daysheet.Evaluation as E
import Application.Daysheet.Designer.ReferenceRetirement (retirementEdit)
import Application.Daysheet.References
import qualified Application.Daysheet.References as References (referenceRecordId)
import qualified Application.Daysheet.Designer.Mutations as Mutations
import qualified Application.Daysheet.Storage as Storage
import Application.Error.Types
import qualified Application.Helper.FrontendContract.Surface.DaysheetDesigner as Surface
import qualified Application.Helper.FrontendContract.Surface.DaysheetDesigner.Action as Action
import Application.Helper.FrontendContract.Surface.DaysheetDesigner.Live (designerLiveScope)
import Application.Helper.LiveUpdate (setActorLiveResourcesRefresh)
import Application.Helper.FrontendContract.Surface.Request (surfaceRequestFieldErrorsMessage)
import Application.Helper.FrontendContract.Surface.Runtime
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.FrontendContract.ClosedScalar (parseClosedScalarLiteral)
import qualified Web.Daysheets.LayoutEditing as Layout
import Application.Helper.SurfaceResource
import Application.Helper.View (ToastOverlayPosition (..), errorToast, renderToastOob)
import qualified Data.ByteString as ByteString
import Data.Traversable (traverse)
import Text.Read (readMaybe)
import qualified Data.UUID as UUID
import qualified Data.Text as Text
import qualified Data.UUID.V4 as UUIDv4
import qualified Network.Wai as Wai
import Network.HTTP.Types.Status (Status, status400, status403, status404, status405)
import Web.Controller.Prelude
import Web.View.Daysheets.Designer

type DesignerRequest = (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond)

instance Controller DaysheetDesignerController where
    beforeAction = bepisBeforeAction BepisAuthenticatedVenueController do
        annotateTelemetryAction
        ensureIsUser
        ensureCurrentVenueOrSupportRedirect
        ensureAdminRole

    action current@DaysheetDesignerAction = runBepis current BepisPageAction (showIndex False)
    action current@ShowDesignerIndexBodyAction = runBepis current BepisFragmentAction (showIndex True)
    action current@ShowDesignerFieldAction { definitionFieldId, containerId } = runBepis current BepisPageAction (showField False definitionFieldId containerId)
    action current@ShowDesignerFieldBodyAction { definitionFieldId, containerId } = runBepis current BepisFragmentAction (showField True definitionFieldId containerId)
    action current@ShowDesignerCalculationAction { calculationFieldId, calculationLocation, calculationGroup, calculationReferencePath } = runBepis current BepisPageAction (showCalculation False calculationFieldId calculationLocation calculationGroup calculationReferencePath)
    action current@ShowDesignerCalculationBodyAction { calculationFieldId, calculationLocation, calculationGroup, calculationReferencePath } = runBepis current BepisFragmentAction (showCalculation True calculationFieldId calculationLocation calculationGroup calculationReferencePath)
    action current@ShowDesignerConstantAction { calculationFieldId, calculationLocation } = runBepis current BepisPageAction (showConstant False calculationFieldId calculationLocation)
    action current@ShowDesignerConstantBodyAction { calculationFieldId, calculationLocation } = runBepis current BepisFragmentAction (showConstant True calculationFieldId calculationLocation)
    action current@ShowDesignerChoiceAction { choiceFieldId, definitionChoiceId } = runBepis current BepisPageAction (showChoice False choiceFieldId definitionChoiceId)
    action current@ShowDesignerChoiceBodyAction { choiceFieldId, definitionChoiceId } = runBepis current BepisFragmentAction (showChoice True choiceFieldId definitionChoiceId)
    action current@ShowDesignerListAction { definitionListId } = runBepis current BepisPageAction (showList False definitionListId)
    action current@ShowDesignerListBodyAction { definitionListId } = runBepis current BepisFragmentAction (showList True definitionListId)

    action current@ShowDesignerReferenceRetirementAction { referenceSourceId, referenceRecordId } = runBepis current BepisPageAction (showRetirement False referenceSourceId referenceRecordId)
    action current@ShowDesignerReferenceRetirementBodyAction { referenceSourceId, referenceRecordId } = runBepis current BepisFragmentAction (showRetirement True referenceSourceId referenceRecordId)

    action current@ShowDesignerReferenceAction { referenceSourceId, referenceRecordId, referenceFieldId } = runBepis current BepisPageAction (showReference False referenceSourceId referenceRecordId referenceFieldId)
    action current@ShowDesignerReferenceBodyAction { referenceSourceId, referenceRecordId, referenceFieldId } = runBepis current BepisFragmentAction (showReference True referenceSourceId referenceRecordId referenceFieldId)

    action current@UseDesignerCalculationPartAction = runBepis current BepisMutationAction do
        ensureWrite
        member <- author
        state <- loadState member
        fields <- either (deny status400 . surfaceRequestFieldErrorsMessage) pure Action.parseUseDesignerCalculationPartActionParams
        let key = D.FieldId (surfaceFieldValue @Surface.DefinitionFieldId fields)
            location = fromMaybe [] (surfaceFieldValue @Surface.ExpressionSlots fields)
            selected = surfaceFieldValue @Surface.CandidateIndex fields
            prepared = CalculationEditing.prepareCalculationEditor state.designerDefinition key location
                (surfaceFieldValue @Surface.CalculationGroup fields) (surfaceFieldValue @Surface.ReferencePath fields)
        case prepared of
            Left message -> failurePage member state DesignerIndexPage message
            Right editor -> case drop selected (Calculation.calculationMenuOptions editor.editorMenu) of
                option : _ | selected >= 0 -> do
                    result <- Mutations.edit member (toInteger (surfaceFieldValue @Surface.ExpectedBase fields))
                        (toInteger <$> surfaceFieldValue @Surface.ExpectedDraft fields) (Calculation.calculationOptionEdit option)
                    finish member state (DesignerCalculationPage editor) result
                _ -> failurePage member state (DesignerCalculationPage editor) "Choose an available calculation part."

    action current@SaveDesignerConstantAction = runBepis current BepisMutationAction do
        ensureWrite
        member <- author
        state <- loadState member
        fields <- either (deny status400 . surfaceRequestFieldErrorsMessage) pure Action.parseSaveDesignerConstantActionParams
        case CalculationEditing.constantEdit state.designerDefinition (D.FieldId (surfaceFieldValue @Surface.DefinitionFieldId fields))
            (fromMaybe [] (surfaceFieldValue @Surface.ExpressionSlots fields)) (surfaceFieldValue @Surface.EnteredValue fields) of
                Left message -> failurePage member state (DesignerConstantPage fields) message
                Right change -> do
                    result <- Mutations.edit member (toInteger (surfaceFieldValue @Surface.ExpectedBase fields))
                        (toInteger <$> surfaceFieldValue @Surface.ExpectedDraft fields) change
                    finish member state (DesignerConstantPage fields) result

    action current@MakeDesignerFieldEnteredAction = runBepis current BepisMutationAction do
        ensureWrite
        member <- author
        state <- loadState member
        fields <- either (deny status400 . surfaceRequestFieldErrorsMessage) pure Action.parseMakeDesignerFieldEnteredActionParams
        field <- findField state.designerDefinition (D.FieldId (surfaceFieldValue @Surface.DefinitionFieldId fields))
        editor <- either (deny status400) pure (CalculationEditing.prepareCalculationEditor state.designerDefinition (D.fieldId field) [] FieldParts Nothing)
        result <- Mutations.edit member (toInteger (surfaceFieldValue @Surface.ExpectedBase fields))
            (toInteger <$> surfaceFieldValue @Surface.ExpectedDraft fields) (Designer.ChangeField (D.fieldId field) (D.fieldLabel field) (D.fieldType field) D.Entered)
        finish member state (DesignerCalculationPage editor) result

    action current@SaveDesignerChoiceAction = runBepis current BepisMutationAction do
        ensureWrite
        member <- author
        state <- loadState member
        fields <- either (deny status400 . surfaceRequestFieldErrorsMessage) pure Action.parseSaveDesignerChoiceActionParams
        let key = D.FieldId (surfaceFieldValue @Surface.DefinitionFieldId fields)
            label = surfaceFieldValue @Surface.Label fields
            choices = [choice | field <- D.rootFields state.designerDefinition <> concatMap D.listFields (D.recordLists state.designerDefinition), D.fieldId field == key, D.ChoiceType values <- [D.fieldType field], choice <- values]
        change <- case surfaceFieldValue @Surface.DefinitionChoiceId fields of
            Just identity -> pure (Designer.RenameChoice key (D.ChoiceId identity) label)
            Nothing -> do
                identity <- D.ChoiceId <$> UUIDv4.nextRandom
                pure (Designer.AddChoice key (length choices) (D.Choice identity label))
        result <- Mutations.edit member (toInteger (surfaceFieldValue @Surface.ExpectedBase fields))
            (toInteger <$> surfaceFieldValue @Surface.ExpectedDraft fields) change
        finish member state (DesignerChoicePage fields) result

    action current@RemoveDesignerChoiceAction = runBepis current BepisMutationAction do
        ensureWrite
        member <- author
        state <- loadState member
        fields <- either (deny status400 . surfaceRequestFieldErrorsMessage) pure Action.parseRemoveDesignerChoiceActionParams
        result <- Mutations.edit member (toInteger (surfaceFieldValue @Surface.ExpectedBase fields))
            (toInteger <$> surfaceFieldValue @Surface.ExpectedDraft fields)
            (Designer.RemoveChoice (D.FieldId (surfaceFieldValue @Surface.DefinitionFieldId fields)) (D.ChoiceId (surfaceFieldValue @Surface.DefinitionChoiceId fields)))
        finish member state DesignerIndexPage result

    action current@MoveDesignerChoiceAction = runBepis current BepisMutationAction do
        ensureWrite
        member <- author
        state <- loadState member
        fields <- either (deny status400 . surfaceRequestFieldErrorsMessage) pure Action.parseMoveDesignerChoiceActionParams
        result <- Mutations.edit member (toInteger (surfaceFieldValue @Surface.ExpectedBase fields))
            (toInteger <$> surfaceFieldValue @Surface.ExpectedDraft fields)
            (Designer.MoveChoice (D.FieldId (surfaceFieldValue @Surface.DefinitionFieldId fields)) (D.ChoiceId (surfaceFieldValue @Surface.DefinitionChoiceId fields)) (surfaceFieldValue @Surface.ToPosition fields))
        finish member state DesignerIndexPage result

    action current@AddDesignerReferenceAction = runBepis current BepisMutationAction do
        ensureWrite
        member <- author
        state <- loadState member
        fields <- either (deny status400 . surfaceRequestFieldErrorsMessage) pure Action.parseAddDesignerReferenceActionParams
        row <- E.RowId <$> UUIDv4.nextRandom
        result <- Mutations.editReferences member (toInteger (surfaceFieldValue @Surface.ExpectedBase fields))
            (toInteger <$> surfaceFieldValue @Surface.ExpectedDraft fields)
            (AddReferenceRecord (D.ListId (surfaceFieldValue @Surface.DefinitionListId fields)) row)
        finish member state DesignerIndexPage result

    action current@RetireDesignerReferenceAction = runBepis current BepisMutationAction do
        ensureWrite
        member <- author
        state <- loadState member
        fields <- either (deny status400 . surfaceRequestFieldErrorsMessage) pure Action.parseRetireDesignerReferenceActionParams
        let key = ReferenceKey (D.ListId (surfaceFieldValue @Surface.DefinitionListId fields)) (E.RowId (surfaceFieldValue @Surface.ReferenceRecordId fields))
            page = DesignerReferenceRetirementPage fields
        case retirementEdit state.designerReferences key (fromMaybe [] (surfaceFieldValue @Surface.ReferenceResolutions fields)) of
            Left _ -> failurePage member state page "Resolve only the listed dependencies. Retire or reassign a dependent record, not both."
            Right change -> do
                result <- Mutations.editReferences member (toInteger (surfaceFieldValue @Surface.ExpectedBase fields))
                    (toInteger <$> surfaceFieldValue @Surface.ExpectedDraft fields) change
                finish member state page result

    action current@SaveDesignerReferenceValueAction = runBepis current BepisMutationAction do
        ensureWrite
        member <- author
        state <- loadState member
        fields <- either (deny status400 . surfaceRequestFieldErrorsMessage) pure Action.parseSaveDesignerReferenceValueActionParams
        let source = D.ListId (surfaceFieldValue @Surface.DefinitionListId fields)
            row = E.RowId (surfaceFieldValue @Surface.ReferenceRecordId fields)
            field = D.FieldId (surfaceFieldValue @Surface.DefinitionFieldId fields)
            raw = fromMaybe "" (surfaceFieldValue @Surface.EnteredValue fields)
            declared = find ((== source) . D.listId) (D.recordLists state.designerDefinition) >>= find ((== field) . D.fieldId) . D.listFields
            parsed = if raw == "" then Right Nothing else case declared of
                Nothing -> Left "This field no longer exists. Clear its obsolete value or discard this edit."
                Just entry -> parseReferenceEntry (D.fieldType entry) raw
            page = DesignerReferencePage fields
        case parsed of
            Left message -> failurePage member state page message
            Right value -> do
                result <- Mutations.editReferences member (toInteger (surfaceFieldValue @Surface.ExpectedBase fields))
                    (toInteger <$> surfaceFieldValue @Surface.ExpectedDraft fields) (SetReferenceValue (ReferenceKey source row) field value)
                finish member state page result

    action current@ShowDesignerReportAction { layoutReportId } = runBepis current BepisPageAction (showReport False layoutReportId)
    action current@ShowDesignerReportBodyAction { layoutReportId } = runBepis current BepisFragmentAction (showReport True layoutReportId)
    action current@ShowDesignerSectionAction { layoutReportId, layoutSectionId } = runBepis current BepisPageAction (showSection False layoutReportId layoutSectionId)
    action current@ShowDesignerSectionBodyAction { layoutReportId, layoutSectionId } = runBepis current BepisFragmentAction (showSection True layoutReportId layoutSectionId)
    action current@ShowDesignerBlockAction { layoutReportId, blockSectionId, layoutBlockIndex, layoutContentKind, layoutSourceId } = runBepis current BepisPageAction (showBlock False layoutReportId blockSectionId layoutBlockIndex layoutContentKind layoutSourceId)
    action current@ShowDesignerBlockBodyAction { layoutReportId, blockSectionId, layoutBlockIndex, layoutContentKind, layoutSourceId } = runBepis current BepisFragmentAction (showBlock True layoutReportId blockSectionId layoutBlockIndex layoutContentKind layoutSourceId)

    action current@MoveDesignerItemAction = runBepis current BepisMutationAction do
        ensureWrite
        member <- author
        state <- loadState member
        fields <- either (deny status400 . surfaceRequestFieldErrorsMessage) pure Action.parseMoveDesignerItemActionParams
        case Layout.moveEdit state.designerDefinition fields of
            Left message -> failurePage member state DesignerIndexPage message
            Right change -> do
                result <- Mutations.edit member (toInteger (surfaceFieldValue @Surface.ExpectedBase fields)) (toInteger <$> surfaceFieldValue @Surface.ExpectedDraft fields) change
                finish member state DesignerIndexPage result

    action current@SaveDesignerReportAction = runBepis current BepisMutationAction do
        ensureWrite
        member <- author
        state <- loadState member
        fields <- either (deny status400 . surfaceRequestFieldErrorsMessage) pure Action.parseSaveDesignerReportActionParams
        let label = surfaceFieldValue @Surface.Label fields
            outputs = reportOutputs (surfaceFieldValue @Surface.Targets fields)
        change <- case surfaceFieldValue @Surface.DefinitionReportId fields of
            Just key -> pure (Designer.ChangeReport (D.ReportId key) label outputs)
            Nothing -> do
                key <- D.ReportId <$> UUIDv4.nextRandom
                pure (Designer.AddReport (length (D.reports state.designerDefinition)) (D.Report key label [] outputs))
        result <- Mutations.edit member (toInteger (surfaceFieldValue @Surface.ExpectedBase fields)) (toInteger <$> surfaceFieldValue @Surface.ExpectedDraft fields) change
        finish member state (DesignerReportPage fields) result

    action current@SaveDesignerSectionAction = runBepis current BepisMutationAction do
        ensureWrite
        member <- author
        state <- loadState member
        fields <- either (deny status400 . surfaceRequestFieldErrorsMessage) pure Action.parseSaveDesignerSectionActionParams
        let report = surfaceFieldValue @Surface.DefinitionReportId fields
            label = surfaceFieldValue @Surface.Label fields
            target = Layout.layoutTarget report
        change <- case surfaceFieldValue @Surface.DefinitionSectionId fields of
            Just key -> pure (Designer.RenameSection target (D.SectionId key) label)
            Nothing -> do
                key <- D.SectionId <$> UUIDv4.nextRandom
                pure (Designer.AddSection target (either (const 0) length (Layout.layoutSections state.designerDefinition report)) (D.Section key label []))
        result <- Mutations.edit member (toInteger (surfaceFieldValue @Surface.ExpectedBase fields)) (toInteger <$> surfaceFieldValue @Surface.ExpectedDraft fields) change
        finish member state (DesignerSectionPage fields) result

    action current@SaveDesignerBlockAction = runBepis current BepisMutationAction do
        ensureWrite
        member <- author
        state <- loadState member
        fields <- either (deny status400 . surfaceRequestFieldErrorsMessage) pure Action.parseSaveDesignerBlockActionParams
        let page = DesignerBlockPage fields
        case Layout.blockEdit state.designerDefinition fields of
            Left message -> failurePage member state page message
            Right change -> do
                result <- Mutations.edit member (toInteger (surfaceFieldValue @Surface.ExpectedBase fields)) (toInteger <$> surfaceFieldValue @Surface.ExpectedDraft fields) change
                finish member state page result

    action current@RemoveDesignerReportAction = runBepis current BepisMutationAction do
        ensureWrite
        member <- author
        state <- loadState member
        fields <- either (deny status400 . surfaceRequestFieldErrorsMessage) pure Action.parseRemoveDesignerReportActionParams
        result <- Mutations.edit member (toInteger (surfaceFieldValue @Surface.ExpectedBase fields)) (toInteger <$> surfaceFieldValue @Surface.ExpectedDraft fields)
            (Designer.RemoveReport (D.ReportId (surfaceFieldValue @Surface.DefinitionReportId fields)))
        finish member state DesignerIndexPage result

    action current@RemoveDesignerSectionAction = runBepis current BepisMutationAction do
        ensureWrite
        member <- author
        state <- loadState member
        fields <- either (deny status400 . surfaceRequestFieldErrorsMessage) pure Action.parseRemoveDesignerSectionActionParams
        result <- Mutations.edit member (toInteger (surfaceFieldValue @Surface.ExpectedBase fields)) (toInteger <$> surfaceFieldValue @Surface.ExpectedDraft fields)
            (Designer.RemoveSection (Layout.layoutTarget (surfaceFieldValue @Surface.DefinitionReportId fields)) (D.SectionId (surfaceFieldValue @Surface.DefinitionSectionId fields)))
        finish member state DesignerIndexPage result

    action current@RemoveDesignerBlockAction = runBepis current BepisMutationAction do
        ensureWrite
        member <- author
        state <- loadState member
        fields <- either (deny status400 . surfaceRequestFieldErrorsMessage) pure Action.parseRemoveDesignerBlockActionParams
        result <- Mutations.edit member (toInteger (surfaceFieldValue @Surface.ExpectedBase fields)) (toInteger <$> surfaceFieldValue @Surface.ExpectedDraft fields)
            (Designer.RemoveBlock (Layout.layoutTarget (surfaceFieldValue @Surface.DefinitionReportId fields)) (D.SectionId (surfaceFieldValue @Surface.DefinitionSectionId fields)) (surfaceFieldValue @Surface.BlockIndex fields))
        finish member state DesignerIndexPage result

    action current@SaveDesignerFieldAction = runBepis current BepisMutationAction do
        ensureWrite
        member <- author
        state <- loadState member
        fields <- either (deny status400 . surfaceRequestFieldErrorsMessage) pure Action.parseSaveDesignerFieldActionParams
        let key = D.FieldId <$> surfaceFieldValue @Surface.DefinitionFieldId fields
            parent = D.ListId <$> surfaceFieldValue @Surface.ContainerId fields
            label = surfaceFieldValue @Surface.Label fields
            kind = surfaceFieldValue @Surface.ValueKind fields
            reference = D.ListId <$> surfaceFieldValue @Surface.ReferenceListId fields
            base = toInteger (surfaceFieldValue @Surface.ExpectedBase fields)
            revision = toInteger <$> surfaceFieldValue @Surface.ExpectedDraft fields
            page = DesignerFieldPage fields
        let existing = key >>= \identity -> find ((== identity) . D.fieldId)
                (D.rootFields state.designerDefinition <> concatMap D.listFields (D.recordLists state.designerDefinition))
        choiceId <- D.ChoiceId <$> UUIDv4.nextRandom
        let choices = case D.fieldType <$> existing of
                Just (D.ChoiceType values) -> values
                _ -> maybe [] (\label -> [D.Choice choiceId label]) (surfaceFieldValue @Surface.InitialChoice fields)
        case fieldKindType kind choices reference of
            Nothing -> failurePage member state page "Choose a reference list for this field."
            Just valueType -> do
                change <- case key of
                    Just identity -> pure (Designer.ChangeField identity label valueType (maybe D.Entered D.fieldSource existing))
                    Nothing -> do
                        identity <- D.FieldId <$> UUIDv4.nextRandom
                        let siblings = case parent of
                                Nothing -> D.rootFields state.designerDefinition
                                Just container -> maybe [] D.listFields (find ((== container) . D.listId) (D.recordLists state.designerDefinition))
                        pure (Designer.AddField parent (length siblings) (D.Field identity label valueType D.Entered))
                result <- Mutations.edit member base revision change
                finish member state page result

    action current@SaveDesignerListAction = runBepis current BepisMutationAction do
        ensureWrite
        member <- author
        state <- loadState member
        fields <- either (deny status400 . surfaceRequestFieldErrorsMessage) pure Action.parseSaveDesignerListActionParams
        let key = D.ListId <$> surfaceFieldValue @Surface.DefinitionListId fields
            label = surfaceFieldValue @Surface.Label fields
            kind = surfaceFieldValue @Surface.CollectionKind fields
            reference = D.ListId <$> surfaceFieldValue @Surface.ReferenceListId fields
            base = toInteger (surfaceFieldValue @Surface.ExpectedBase fields)
            revision = toInteger <$> surfaceFieldValue @Surface.ExpectedDraft fields
            page = DesignerListPage fields
        case listKindMode kind reference of
            Nothing -> failurePage member state page "Choose a venue reference list for this checklist."
            Just mode -> do
                change <- case key of
                    Just identity -> pure (Designer.ChangeList identity label mode)
                    Nothing -> do
                        identity <- D.ListId <$> UUIDv4.nextRandom
                        pure (Designer.AddList (length (D.recordLists state.designerDefinition)) (D.RecordList identity label mode []))
                result <- Mutations.edit member base revision change
                finish member state page result

    action current@RemoveDesignerFieldAction = runBepis current BepisMutationAction do
        ensureWrite
        member <- author
        state <- loadState member
        fields <- either (deny status400 . surfaceRequestFieldErrorsMessage) pure Action.parseRemoveDesignerFieldActionParams
        result <- Mutations.edit member (toInteger (surfaceFieldValue @Surface.ExpectedBase fields))
            (toInteger <$> surfaceFieldValue @Surface.ExpectedDraft fields)
            (Designer.RemoveField (D.FieldId (surfaceFieldValue @Surface.DefinitionFieldId fields)))
        finish member state DesignerIndexPage result

    action current@RemoveDesignerListAction = runBepis current BepisMutationAction do
        ensureWrite
        member <- author
        state <- loadState member
        fields <- either (deny status400 . surfaceRequestFieldErrorsMessage) pure Action.parseRemoveDesignerListActionParams
        result <- Mutations.edit member (toInteger (surfaceFieldValue @Surface.ExpectedBase fields))
            (toInteger <$> surfaceFieldValue @Surface.ExpectedDraft fields)
            (Designer.RemoveList (D.ListId (surfaceFieldValue @Surface.DefinitionListId fields)))
        finish member state DesignerIndexPage result

    action current@StageDesignerStarterAction = runBepis current BepisMutationAction do
        ensureWrite
        member <- author
        state <- loadState member
        fields <- either (deny status400 . surfaceRequestFieldErrorsMessage) pure Action.parseStageDesignerStarterActionParams
        result <- Mutations.stageStarter member (toInteger (surfaceFieldValue @Surface.ExpectedBase fields))
            (toInteger <$> surfaceFieldValue @Surface.ExpectedDraft fields)
        finish member state DesignerIndexPage result

    action current@PublishDesignerDraftAction = runBepis current BepisMutationAction do
        ensureWrite
        member <- author
        state <- loadState member
        fields <- either (deny status400 . surfaceRequestFieldErrorsMessage) pure Action.parsePublishDesignerDraftActionParams
        case surfaceFieldValue @Surface.ExpectedDraft fields of
            Nothing -> failurePage member state DesignerIndexPage "There is no draft to publish."
            Just revision -> do
                result <- Mutations.publish member (toInteger (surfaceFieldValue @Surface.ExpectedBase fields)) (toInteger revision)
                finish member state DesignerIndexPage result

showIndex :: DesignerRequest => Bool -> IO ResponseReceived
showIndex fragment = do
    ensureRead
    member <- author
    state <- loadState member
    if isHtmxRequest && not fragment
        then setHeader ("HX-Redirect", cs (pathTo DaysheetDesignerAction)) >> respondHtml mempty
        else display fragment member state DesignerIndexPage Nothing

showField :: DesignerRequest => Bool -> Maybe Text -> Maybe Text -> IO ResponseReceived
showField fragment rawKey rawParent = do
    ensureRead
    member <- author
    state <- loadState member
    key <- parseKey rawKey
    suppliedParent <- parseKey rawParent
    field <- traverse (findField state.designerDefinition . D.FieldId) key
    let parent = case field of
            Just value -> (\source -> let D.ListId identity = D.listId source in identity) <$> find (any ((== D.fieldId value) . D.fieldId) . D.listFields) (D.recordLists state.designerDefinition)
            Nothing -> suppliedParent
    _ <- fieldsIn state.designerDefinition (D.ListId <$> parent)
    let valueType = maybe D.TextType D.fieldType field
        reference = case valueType of D.ReferenceType (D.ListId identity) -> Just identity; _ -> Nothing
        fields = Action.saveDesignerFieldActionFields (fromInteger state.designerBaseRevision) (fromInteger <$> state.designerDraftRevision)
            key parent (maybe "" D.fieldLabel field) (fieldKind valueType) reference Nothing
    display fragment member state (DesignerFieldPage fields) Nothing

showCalculation :: DesignerRequest => Bool -> UUID -> Maybe Text -> Text -> Maybe Text -> IO ResponseReceived
showCalculation fragment key rawLocation rawGroup path = do
    ensureRead
    member <- author
    state <- loadState member
    location <- either (deny status400) pure (CalculationEditing.parseCalculationLocation rawLocation)
    group <- maybe (deny status400 "Choose an available calculation group.") pure (parseClosedScalarLiteral @CalculationGroup rawGroup)
    editor <- either (deny status404) pure (CalculationEditing.prepareCalculationEditor state.designerDefinition (D.FieldId key) location group path)
    display fragment member state (DesignerCalculationPage editor) Nothing

showConstant :: DesignerRequest => Bool -> UUID -> Maybe Text -> IO ResponseReceived
showConstant fragment key rawLocation = do
    ensureRead
    member <- author
    state <- loadState member
    location <- either (deny status400) pure (CalculationEditing.parseCalculationLocation rawLocation)
    _ <- either (deny status404) pure (CalculationEditing.constantType state.designerDefinition (D.FieldId key) location)
    let fields = Action.saveDesignerConstantActionFields (fromInteger state.designerBaseRevision) (fromInteger <$> state.designerDraftRevision) key (Just location) ""
    display fragment member state (DesignerConstantPage fields) Nothing

showChoice :: DesignerRequest => Bool -> UUID -> Maybe Text -> IO ResponseReceived
showChoice fragment key rawChoice = do
    ensureRead
    member <- author
    state <- loadState member
    choice <- parseKey rawChoice
    field <- findField state.designerDefinition (D.FieldId key)
    choices <- case D.fieldType field of
        D.ChoiceType values -> pure values
        _ -> deny status400 "This field does not have choice options."
    previous <- traverse (\identity -> maybe (deny status404 "This choice no longer exists.") pure (find ((== D.ChoiceId identity) . D.choiceId) choices)) choice
    let fields = Action.saveDesignerChoiceActionFields (fromInteger state.designerBaseRevision) (fromInteger <$> state.designerDraftRevision)
            key choice (maybe "" D.choiceLabel previous)
    display fragment member state (DesignerChoicePage fields) Nothing

showList :: DesignerRequest => Bool -> Maybe Text -> IO ResponseReceived
showList fragment rawKey = do
    ensureRead
    member <- author
    state <- loadState member
    key <- parseKey rawKey
    source <- traverse (findList state.designerDefinition . D.ListId) key
    let mode = maybe D.OpenDaily D.listMode source
        reference = case mode of D.ReferenceChecklist (D.ListId identity) -> Just identity; _ -> Nothing
        fields = Action.saveDesignerListActionFields (fromInteger state.designerBaseRevision) (fromInteger <$> state.designerDraftRevision)
            key (maybe "" D.listLabel source) (listKind mode) reference
    display fragment member state (DesignerListPage fields) Nothing

showReport :: DesignerRequest => Bool -> Maybe Text -> IO ResponseReceived
showReport fragment rawKey = do
    ensureRead
    member <- author
    state <- loadState member
    key <- parseKey rawKey
    previous <- traverse (\identity -> maybe (deny status404 "This report no longer exists.") pure (find (\(D.Report (D.ReportId value) _ _ _) -> value == identity) (D.reports state.designerDefinition))) key
    let label = case previous of Just (D.Report _ value _ _) -> value; _ -> ""
        targets = case previous of Just (D.Report _ _ _ values) -> reportTargets values; _ -> FormattedAndExcel
        fields = Action.saveDesignerReportActionFields (fromInteger state.designerBaseRevision) (fromInteger <$> state.designerDraftRevision) key label targets
    display fragment member state (DesignerReportPage fields) Nothing

showSection :: DesignerRequest => Bool -> Maybe Text -> Maybe Text -> IO ResponseReceived
showSection fragment rawReport rawKey = do
    ensureRead
    member <- author
    state <- loadState member
    report <- parseKey rawReport
    key <- parseKey rawKey
    sections <- either (deny status404) pure (Layout.layoutSections state.designerDefinition report)
    previous <- traverse (either (deny status404) pure . (`Layout.sectionById` sections)) key
    let label = case previous of Just (D.Section _ value _) -> value; _ -> ""
        fields = Action.saveDesignerSectionActionFields (fromInteger state.designerBaseRevision) (fromInteger <$> state.designerDraftRevision) report key label
    display fragment member state (DesignerSectionPage fields) Nothing

showBlock :: DesignerRequest => Bool -> Maybe Text -> UUID -> Maybe Text -> Text -> Maybe Text -> IO ResponseReceived
showBlock fragment rawReport section rawIndex rawKind rawSource = do
    ensureRead
    member <- author
    state <- loadState member
    report <- parseKey rawReport
    source <- parseKey rawSource
    index <- traverse (\value -> if Text.length value > 18 then deny status400 "Invalid content position."
        else maybe (deny status400 "Invalid content position.") pure (readMaybe @Int (cs value))) rawIndex
    kind <- maybe (deny status400 "Invalid content type.") pure (parseClosedScalarLiteral @BlockKind rawKind)
    sections <- either (deny status404) pure (Layout.layoutSections state.designerDefinition report)
    D.Section _ _ blocks <- either (deny status404) pure (Layout.sectionById section sections)
    previous <- traverse (either (deny status404) pure . (`Layout.blockAt` blocks)) index
    let fields = Layout.blockFormFields state report section index kind source previous
    display fragment member state (DesignerBlockPage fields) Nothing

showRetirement :: DesignerRequest => Bool -> UUID -> UUID -> IO ResponseReceived
showRetirement fragment sourceId rowId = do
    ensureRead
    member <- author
    state <- loadState member
    source <- findList state.designerDefinition (D.ListId sourceId)
    unless (D.listMode source == D.VenueReference) (deny status404 "This is not a venue reference list.")
    let ReferenceData lists = state.designerReferences
    unless (any (\list -> referenceListId list == D.ListId sourceId && any (\row -> References.referenceRecordId row == E.RowId rowId && not (referenceRetired row)) (referenceRecords list)) lists)
        (deny status404 "This reference record is no longer active.")
    let fields = Action.retireDesignerReferenceActionFields (fromInteger state.designerBaseRevision) (fromInteger <$> state.designerDraftRevision) sourceId rowId Nothing
    display fragment member state (DesignerReferenceRetirementPage fields) Nothing

showReference :: DesignerRequest => Bool -> UUID -> UUID -> UUID -> IO ResponseReceived
showReference fragment sourceId rowId fieldId = do
    ensureRead
    member <- author
    state <- loadState member
    source <- findList state.designerDefinition (D.ListId sourceId)
    unless (D.listMode source == D.VenueReference) (deny status404 "This is not a venue reference list.")
    _ <- maybe (deny status404 "This reference field is not editable.") pure
        (find (\field -> D.fieldId field == D.FieldId fieldId && D.fieldSource field == D.Entered) (D.listFields source))
    let ReferenceData lists = state.designerReferences
    row <- case [row | list <- lists, referenceListId list == D.ListId sourceId, row <- referenceRecords list, References.referenceRecordId row == E.RowId rowId, not (referenceRetired row)] of
        [value] -> pure value
        _ -> deny status404 "This reference record is no longer active."
    let fields = Action.saveDesignerReferenceValueActionFields (fromInteger state.designerBaseRevision) (fromInteger <$> state.designerDraftRevision)
            sourceId rowId fieldId (referenceEntryText <$> lookup (D.FieldId fieldId) (referenceValues row))
    display fragment member state (DesignerReferencePage fields) Nothing

findField :: DesignerRequest => D.Definition -> D.FieldId -> IO D.Field
findField definition key = maybe (deny status404 "This field no longer exists in the draft.") pure
    (find ((== key) . D.fieldId) (D.rootFields definition <> concatMap D.listFields (D.recordLists definition)))
findList :: DesignerRequest => D.Definition -> D.ListId -> IO D.RecordList
findList definition key = maybe (deny status404 "This list no longer exists in the draft.") pure (find ((== key) . D.listId) (D.recordLists definition))
fieldsIn :: DesignerRequest => D.Definition -> Maybe D.ListId -> IO [D.Field]
fieldsIn definition Nothing = pure (D.rootFields definition)
fieldsIn definition (Just key) = D.listFields <$> findList definition key
parseKey :: DesignerRequest => Maybe Text -> IO (Maybe UUID)
parseKey = traverse (maybe (deny status400 "Invalid designer identity.") pure . UUID.fromText)

author :: DesignerRequest => IO VenueMembership
author = maybe (deny status403 "The designer requires an active admin or owner venue membership.") pure currentVenueMembershipOrNothing
loadState :: DesignerRequest => VenueMembership -> IO Storage.DesignerState
loadState member = Storage.readDesignerState member >>= either (deny status403 . appErrorSafeMessage) pure

display :: DesignerRequest => Bool -> VenueMembership -> Storage.DesignerState -> DesignerPage -> Maybe Text -> IO ResponseReceived
display fragment member state page problem = if fragment
    then respondHtml (renderDesigner member.venueId state page problem)
    else render DesignerView { venue = member.venueId, state, page, problem }

failurePage :: DesignerRequest => VenueMembership -> Storage.DesignerState -> DesignerPage -> Text -> IO ResponseReceived
failurePage member state page message = if isHtmxRequest
    then respondHtml (renderToastOob ToastBottomCenter (errorToast message))
    else display False member state page (Just message)

finish :: DesignerRequest => VenueMembership -> Storage.DesignerState -> DesignerPage -> LiveMutationResult (AppResult a) -> IO ResponseReceived
finish member state page result = case result.liveMutationValue of
    Left failure -> failurePage member state page (appErrorSafeMessage failure)
    Right _ -> do
        setHeader ("X-Bepis-Form-Saved", "true")
        let target = case page of
                DesignerCalculationPage editor -> let D.FieldId key = editor.editorField in
                    ShowDesignerCalculationAction key (CalculationEditing.renderCalculationLocation editor.editorLocation) (inputValue editor.editorGroup) (CalculationEditing.renderReferencePath <$> editor.editorReferencePath)
                DesignerConstantPage fields -> ShowDesignerCalculationAction (surfaceFieldValue @Surface.DefinitionFieldId fields)
                    (CalculationEditing.renderCalculationLocation (fromMaybe [] (surfaceFieldValue @Surface.ExpressionSlots fields))) (inputValue ValueParts) Nothing
                _ -> DaysheetDesignerAction
            refresh = do
                let impl = designerSurface member.venueId page
                setActorLiveResourcesRefresh (designerLiveScope member.venueId) result.liveMutationTouchedResources impl.surfaceImplMountConfig.mountFragments
                setHeader ("HX-Reswap", "none")
        if isHtmxRequest then do
            case page of
                DesignerIndexPage -> refresh
                DesignerCalculationPage _ -> refresh
                _ -> setHeader ("HX-Redirect", cs (pathTo target))
            respondHtml mempty
        else redirectTo target

ensureRead :: DesignerRequest => IO ()
ensureRead = ensureMethods ["GET", "HEAD"]
ensureWrite :: DesignerRequest => IO ()
ensureWrite = ensureMethods ["POST"] >> ensureVenueWritable
ensureMethods :: DesignerRequest => [ByteString] -> IO ()
ensureMethods methods = unless (Wai.requestMethod ?request `elem` methods)
    (respondAndExit (Wai.responseLBS status405 [("Allow", ByteString.intercalate ", " methods), ("Content-Type", "text/plain")] "Method not permitted."))
deny :: DesignerRequest => Status -> Text -> IO a
deny status message = respondAndExit (Wai.responseLBS status [("Content-Type", "text/plain; charset=utf-8")] (cs message))
