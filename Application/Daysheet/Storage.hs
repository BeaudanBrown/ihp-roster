{-# LANGUAGE RankNTypes #-}
-- | Venue-scoped lifecycle. Callers pass explicit Daysheet authority derived
-- from authenticated context, never a request-selected actor. Live membership
-- or separate founder support authority is re-read under lock.
module Application.Daysheet.Storage
    ( saveDraft, publishDraft, captureDefinition, withDefinitionCapture, retireCurrentReferences, updateCurrentReferences
    , DesignerState (..), readDesignerState, editDraft, editDraftReferences
    ) where

import qualified Application.Daysheet.Contract as D
import qualified Application.Daysheet.Designer as Designer
import Application.Daysheet.DefinitionCodec
import Application.Daysheet.ReferenceCodec
import Application.Daysheet.References
import qualified Application.Daysheet.Evaluation as E
import Application.Daysheet.Authority (DaysheetAccess, venueId, userId, withAuthority, recordDaysheetAuditEvent)
import Application.Daysheet.StorageError
import Application.Error.Domain (projectDomainError)
import Application.Error.Types
import Application.Helper.Audit.Vocabulary
import Application.VenueTime (melbourneTimeZoneName)
import Control.Monad.Trans.Except (ExceptT, throwE)
import qualified Data.Aeson as Aeson
import qualified Data.UUID as UUID
import Generated.Types
import IHP.ModelSupport
import IHP.Fetch (fetchOneOrNothing)
import IHP.Prelude
import IHP.QueryBuilder

-- Helpers use the transaction-bound implicit context, not a captured pool.
type StoreM = ExceptT AppError IO

failure :: StorageError -> StoreM a
failure = throwE . projectDomainError

checked :: StorageError -> Either rejection a -> StoreM a
checked errorValue = either (const (failure errorValue)) pure

configuration :: (?modelContext :: ModelContext) => DaysheetAccess -> StoreM (Maybe DaysheetConfiguration)
configuration member = liftIO (query @DaysheetConfiguration |> filterWhere (#venueId, member.venueId) |> fetchOneOrNothing)

draft :: (?modelContext :: ModelContext) => DaysheetAccess -> StoreM (Maybe DaysheetDefinitionDraft)
draft member = liftIO (query @DaysheetDefinitionDraft |> filterWhere (#venueId, member.venueId) |> fetchOneOrNothing)

owner :: DaysheetAccess -> E.SnapshotKey
owner member = E.SnapshotKey member.venueId UUID.nil

revisionAfter :: Integer -> StoreM Integer
revisionAfter revision
    | revision < 0 || revision >= 2147483647 = failure RevisionLimit
    | otherwise = pure (revision + 1)

liveReferences :: Maybe DaysheetConfiguration -> StoreM ReferenceData
liveReferences Nothing = pure (ReferenceData [])
liveReferences (Just config) = case config.publishedVersionId of
    Nothing -> pure (ReferenceData [])
    Just _ -> checked StoredDocumentInvalid (decodeReferenceData config.referenceData)

-- A read is observational: an unpublished venue has an empty valid definition,
-- but neither its configuration nor its draft is created until an explicit edit.
-- Keep a stale draft's base separate from the live configuration revision; no
-- ordinary edit silently rebases it after live reference changes.
data DesignerState = DesignerState
    { designerDefinition :: D.Definition
    , designerReferences :: ReferenceData
    , designerBaseRevision :: Integer
    , designerCurrentRevision :: Integer
    , designerDraftRevision :: Maybe Integer
    , designerPublishedVersionId :: Maybe UUID
    } deriving (Eq, Show)

readDesignerState :: (?modelContext :: ModelContext) => DaysheetAccess -> IO (AppResult DesignerState)
readDesignerState member = withAuthority member [VenueAdmin, VenueOwner] (designerState member)

designerState :: (?modelContext :: ModelContext) => DaysheetAccess -> StoreM DesignerState
designerState member = do
    config <- configuration member
    saved <- draft member
    let currentRevision = maybe 0 (.revision) config
        published = config >>= (.publishedVersionId)
    (definition, references, base) <- case saved of
        Just value -> do
            definition <- checked StoredDocumentInvalid (decodeDefinition value.definition)
            references <- checked StoredDocumentInvalid (decodeReferenceData value.referenceData)
            pure (definition, references, value.baseRevision)
        Nothing -> case config of
            Just value | isJust value.publishedVersionId -> do
                version <- publication member value
                definition <- checked StoredDocumentInvalid (decodeDefinition version.definition)
                references <- liveReferences config
                pure (definition, references, currentRevision)
            _ -> pure (D.Definition 2 [] [] [] [], ReferenceData [], currentRevision)
    pure DesignerState
        { designerDefinition = definition, designerReferences = references
        , designerBaseRevision = base, designerCurrentRevision = currentRevision
        , designerDraftRevision = (.revision) <$> saved, designerPublishedVersionId = published
        }

editDraft :: (?modelContext :: ModelContext) => DaysheetAccess -> Integer -> Maybe Integer -> Designer.Edit -> IO (AppResult DaysheetDefinitionDraft)
editDraft member expectedBase expectedDraft edit = withAuthority member [VenueAdmin, VenueOwner] do
    state <- designerState member
    checkDesignerRevision expectedBase expectedDraft state
    changed <- checked InvalidDefinitionDocument (Designer.applyEdit edit state.designerDefinition)
    let ReferenceData lists = state.designerReferences
        retiringList = case edit of
            Designer.RemoveList key -> Just key
            Designer.ChangeList key _ mode | mode /= D.VenueReference -> Just key
            _ -> Nothing
    forM_ retiringList \key -> when (any (\list -> referenceListId list == key && any (not . referenceRetired) (referenceRecords list)) lists)
        (failure ReferenceRemovalRequiresRetirement)
    saveDraftLocked member expectedBase expectedDraft changed state.designerReferences

editDraftReferences :: (?modelContext :: ModelContext) => DaysheetAccess -> Integer -> Maybe Integer -> ReferenceEdit -> IO (AppResult DaysheetDefinitionDraft)
editDraftReferences member expectedBase expectedDraft edit = withAuthority member [VenueAdmin, VenueOwner] do
    state <- designerState member
    checkDesignerRevision expectedBase expectedDraft state
    changed <- checked InvalidReferenceDocument (editReferenceData state.designerDefinition (owner member) state.designerReferences edit)
    saveDraftLocked member expectedBase expectedDraft state.designerDefinition changed

checkDesignerRevision :: Integer -> Maybe Integer -> DesignerState -> StoreM ()
checkDesignerRevision expectedBase expectedDraft state =
    unless (state.designerBaseRevision == expectedBase && state.designerCurrentRevision == expectedBase
        && state.designerDraftRevision == expectedDraft) (failure RevisionConflict)

-- Staging permits old reference values incompatible with the new definition;
-- only publication demands their correction. Saving never touches live data.
saveDraft :: (?modelContext :: ModelContext) => DaysheetAccess -> Integer -> Maybe Integer -> D.Definition -> ReferenceData -> IO (AppResult DaysheetDefinitionDraft)
saveDraft member expectedBase expectedDraft definition references = withAuthority member [VenueAdmin, VenueOwner] $
    saveDraftLocked member expectedBase expectedDraft definition references

saveDraftLocked :: (?modelContext :: ModelContext) => DaysheetAccess -> Integer -> Maybe Integer -> D.Definition -> ReferenceData -> StoreM DaysheetDefinitionDraft
saveDraftLocked member expectedBase expectedDraft definition references = do
    config <- configuration member
    saved <- draft member
    unless (maybe 0 (.revision) config == expectedBase && fmap (.revision) saved == expectedDraft) (failure RevisionConflict)
    definitionJson <- checked InvalidDefinitionDocument (encodeDefinition definition)
    referencesJson <- checked InvalidReferenceDocument (encodeReferenceData references)
    previous <- liveReferences config
    unless (preservesReferences previous references) (failure ReferenceRemovalRequiresRetirement)
    next <- maybe (pure 0) (revisionAfter . (.revision)) saved
    now <- liftIO getCurrentTime
    when (isNothing config) do
        _ <- liftIO (newRecord @DaysheetConfiguration |> set #venueId member.venueId |> createRecord)
        pure ()
    let value = fromMaybe (newRecord @DaysheetDefinitionDraft |> set #venueId member.venueId) saved
            |> set #baseRevision expectedBase
            |> set #revision next
            |> set #definition definitionJson
            |> set #referenceData referencesJson
            |> set #updatedBy member.userId
            |> set #updatedAt now
    liftIO (if isNothing saved then createRecord value else updateRecord value)

publication :: (?modelContext :: ModelContext) => DaysheetAccess -> DaysheetConfiguration -> StoreM DaysheetDefinitionVersion
publication member config = do
    versionId <- maybe (failure NotPublished) pure config.publishedVersionId
    value <- liftIO (query @DaysheetDefinitionVersion |> filterWhere (#id, Id versionId) |> filterWhere (#venueId, member.venueId) |> fetchOneOrNothing)
    maybe (failure StoredDocumentInvalid) pure value

publishDraft :: (?modelContext :: ModelContext) => DaysheetAccess -> Integer -> Integer -> IO (AppResult DaysheetDefinitionVersion)
publishDraft member expectedBase expectedDraft = withAuthority member [VenueAdmin, VenueOwner] do
    config <- configuration member >>= maybe (failure MissingDraft) pure
    saved <- draft member >>= maybe (failure MissingDraft) pure
    unless (config.revision == expectedBase && saved.baseRevision == expectedBase && saved.revision == expectedDraft) (failure RevisionConflict)
    definition <- checked StoredDocumentInvalid (decodeDefinition saved.definition)
    references <- checked StoredDocumentInvalid (decodeReferenceData saved.referenceData)
    _ <- checked InvalidReferenceDocument (validateReferences definition (owner member) references)
    previous <- liveReferences (Just config)
    unless (preservesReferences previous references) (failure ReferenceRemovalRequiresRetirement)
    next <- revisionAfter config.revision
    now <- liftIO getCurrentTime
    version <- liftIO (newRecord @DaysheetDefinitionVersion
        |> set #venueId member.venueId
        |> set #versionNumber (fromIntegral next)
        |> set #definition saved.definition
        |> set #referenceData saved.referenceData
        |> set #publishedBy member.userId
        |> createRecord)
    _ <- liftIO (config |> set #publishedVersionId (Just (unpackId version.id)) |> set #referenceData saved.referenceData |> set #revision next |> set #updatedAt now |> updateRecord)
    liftIO (deleteRecord saved)
    _ <- liftIO (recordDaysheetAuditEvent member DaysheetDefinitionPublishedAudit "daysheet_definition_versions" (unpackId version.id) (Aeson.object ["version" Aeson..= version.versionNumber]) ApplicationAuditSource)
    pure version

-- One explicit venue/day creation captures one immutable meaning. Repeated or
-- concurrent creation returns the existing capture, never a newer definition.
captureDefinition :: (?modelContext :: ModelContext) => DaysheetAccess -> Day -> IO (AppResult DaysheetDefinitionCapture)
captureDefinition member day = withDefinitionCapture member day pure

-- Daily creation and its captured meaning commit together. The continuation
-- receives the transaction-bound model context; no nested transaction or
-- captured outer pool may split this atomic boundary.
withDefinitionCapture :: (?modelContext :: ModelContext) => DaysheetAccess -> Day -> ((?modelContext :: ModelContext) => DaysheetDefinitionCapture -> StoreM a) -> IO (AppResult a)
withDefinitionCapture member day action = withAuthority member [Manager, VenueAdmin, VenueOwner] do
    captured <- captureDefinitionLocked member day
    action captured

captureDefinitionLocked :: (?modelContext :: ModelContext) => DaysheetAccess -> Day -> StoreM DaysheetDefinitionCapture
captureDefinitionLocked member day = do
    existing <- liftIO (query @DaysheetDefinitionCapture |> filterWhere (#venueId, member.venueId) |> filterWhere (#operationalDate, day) |> fetchOneOrNothing)
    case existing of
        Just captured -> pure captured
        Nothing -> do
            config <- configuration member >>= maybe (failure NotPublished) pure
            version <- publication member config
            definition <- checked StoredDocumentInvalid (decodeDefinition version.definition)
            references <- liveReferences (Just config)
            _ <- checked InvalidReferenceDocument (validateReferences definition (owner member) references)
            referenceJson <- checked InvalidReferenceDocument (encodeReferenceData (activeReferenceData references))
            liftIO (newRecord @DaysheetDefinitionCapture
                |> set #venueId member.venueId
                |> set #operationalDate day
                |> set #timezone melbourneTimeZoneName
                |> set #definitionVersionId (unpackId version.id)
                |> set #referenceData referenceJson
                |> set #capturedBy member.userId
                |> createRecord)

-- Ordinary reference edits/additions do not require a definition publication.
-- Retirement/restoration cannot be smuggled through this replacement interface.
updateCurrentReferences :: (?modelContext :: ModelContext) => DaysheetAccess -> Integer -> ReferenceData -> IO (AppResult DaysheetConfiguration)
updateCurrentReferences member expectedRevision references = withAuthority member [VenueAdmin, VenueOwner] do
    config <- configuration member >>= maybe (failure NotPublished) pure
    unless (config.revision == expectedRevision) (failure RevisionConflict)
    version <- publication member config
    definition <- checked StoredDocumentInvalid (decodeDefinition version.definition)
    previous <- liveReferences (Just config)
    unless (preservesRetirementState previous references) (failure ReferenceRemovalRequiresRetirement)
    _ <- checked InvalidReferenceDocument (validateReferences definition (owner member) references)
    referenceJson <- checked InvalidReferenceDocument (encodeReferenceData references)
    next <- revisionAfter config.revision
    now <- liftIO getCurrentTime
    liftIO (config |> set #referenceData referenceJson |> set #revision next |> set #updatedAt now |> updateRecord)

retireCurrentReferences :: (?modelContext :: ModelContext) => DaysheetAccess -> Integer -> ReferenceKey -> [ReferenceChange] -> IO (AppResult DaysheetConfiguration)
retireCurrentReferences member expectedRevision target choices = withAuthority member [VenueAdmin, VenueOwner] do
    config <- configuration member >>= maybe (failure NotPublished) pure
    unless (config.revision == expectedRevision) (failure RevisionConflict)
    version <- publication member config
    definition <- checked StoredDocumentInvalid (decodeDefinition version.definition)
    references <- liveReferences (Just config)
    corrected <- checked InvalidReferenceDocument (retireReferences definition (owner member) references target choices)
    referenceJson <- checked InvalidReferenceDocument (encodeReferenceData corrected)
    next <- revisionAfter config.revision
    now <- liftIO getCurrentTime
    updated <- liftIO (config |> set #referenceData referenceJson |> set #revision next |> set #updatedAt now |> updateRecord)
    _ <- liftIO (recordDaysheetAuditEvent member DaysheetReferencesRetiredAudit "daysheet_configurations" (unpackId config.id) (Aeson.object ["revision" Aeson..= next]) ApplicationAuditSource)
    pure updated
