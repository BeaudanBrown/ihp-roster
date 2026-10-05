module Web.Controller.DaysheetDesigner where

import qualified Application.Daysheet.Contract as D
import qualified Application.Daysheet.Designer as Designer
import Application.Daysheet.Designer.Controls
import qualified Application.Daysheet.Designer.Mutations as Mutations
import qualified Application.Daysheet.Storage as Storage
import Application.Error.Types
import qualified Application.Helper.FrontendContract.Surface.DaysheetDesigner as Surface
import qualified Application.Helper.FrontendContract.Surface.DaysheetDesigner.Action as Action
import Application.Helper.FrontendContract.Surface.Request (surfaceRequestFieldErrorsMessage)
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.SurfaceResource
import Application.Helper.View (ToastOverlayPosition (..), errorToast, renderToastOob)
import qualified Data.ByteString as ByteString
import Data.Traversable (traverse)
import qualified Data.UUID as UUID
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
    action current@ShowDesignerListAction { definitionListId } = runBepis current BepisPageAction (showList False definitionListId)
    action current@ShowDesignerListBodyAction { definitionListId } = runBepis current BepisFragmentAction (showList True definitionListId)

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
        if isHtmxRequest then setHeader ("HX-Redirect", cs (pathTo DaysheetDesignerAction)) >> respondHtml mempty
            else redirectTo DaysheetDesignerAction

ensureRead :: DesignerRequest => IO ()
ensureRead = ensureMethods ["GET", "HEAD"]
ensureWrite :: DesignerRequest => IO ()
ensureWrite = ensureMethods ["POST"] >> ensureVenueWritable
ensureMethods :: DesignerRequest => [ByteString] -> IO ()
ensureMethods methods = unless (Wai.requestMethod ?request `elem` methods)
    (respondAndExit (Wai.responseLBS status405 [("Allow", ByteString.intercalate ", " methods), ("Content-Type", "text/plain")] "Method not permitted."))
deny :: DesignerRequest => Status -> Text -> IO a
deny status message = respondAndExit (Wai.responseLBS status [("Content-Type", "text/plain; charset=utf-8")] (cs message))
