{-# LANGUAGE RankNTypes #-}
-- | Membership-scoped lifecycle. Callers pass the current authenticated venue
-- membership, never a request-selected actor. Authority is re-read under lock;
-- ordinary venue authority cannot be synthesized from a platform user role.
module Application.Daysheet.Storage
    ( saveDraft, publishDraft, captureDefinition, retireCurrentReferences, updateCurrentReferences
    ) where

import qualified Application.Daysheet.Contract as D
import Application.Daysheet.DefinitionCodec
import Application.Daysheet.ReferenceCodec
import Application.Daysheet.References
import qualified Application.Daysheet.Evaluation as E
import Application.Daysheet.Authority (withAuthority)
import Application.Daysheet.StorageError
import Application.Error.Domain (projectDomainError)
import Application.Error.Types
import Application.Helper.Audit (recordAuditEvent)
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

checked :: StorageError -> Either error a -> StoreM a
checked errorValue = either (const (failure errorValue)) pure

configuration :: (?modelContext :: ModelContext) => VenueMembership -> StoreM (Maybe DaysheetConfiguration)
configuration member = liftIO (query @DaysheetConfiguration |> filterWhere (#venueId, member.venueId) |> fetchOneOrNothing)

draft :: (?modelContext :: ModelContext) => VenueMembership -> StoreM (Maybe DaysheetDefinitionDraft)
draft member = liftIO (query @DaysheetDefinitionDraft |> filterWhere (#venueId, member.venueId) |> fetchOneOrNothing)

owner :: VenueMembership -> E.SnapshotKey
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

-- Staging permits old reference values incompatible with the new definition;
-- only publication demands their correction. Saving never touches live data.
saveDraft :: (?modelContext :: ModelContext) => VenueMembership -> Integer -> Maybe Integer -> D.Definition -> ReferenceData -> IO (AppResult DaysheetDefinitionDraft)
saveDraft member expectedBase expectedDraft definition references = withAuthority member [VenueAdmin, VenueOwner] do
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

publication :: (?modelContext :: ModelContext) => VenueMembership -> DaysheetConfiguration -> StoreM DaysheetDefinitionVersion
publication member config = do
    versionId <- maybe (failure NotPublished) pure config.publishedVersionId
    value <- liftIO (query @DaysheetDefinitionVersion |> filterWhere (#id, Id versionId) |> filterWhere (#venueId, member.venueId) |> fetchOneOrNothing)
    maybe (failure StoredDocumentInvalid) pure value

publishDraft :: (?modelContext :: ModelContext) => VenueMembership -> Integer -> Integer -> IO (AppResult DaysheetDefinitionVersion)
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
    _ <- liftIO (recordAuditEvent member.venueId member.userId DaysheetDefinitionPublishedAudit "daysheet_definition_versions" (unpackId version.id) (Aeson.object ["version" Aeson..= version.versionNumber]) ApplicationAuditSource)
    pure version

-- One explicit venue/day creation captures one immutable meaning. Repeated or
-- concurrent creation returns the existing capture, never a newer definition.
captureDefinition :: (?modelContext :: ModelContext) => VenueMembership -> Day -> IO (AppResult DaysheetDefinitionCapture)
captureDefinition member day = withAuthority member [Manager, VenueAdmin, VenueOwner] do
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
updateCurrentReferences :: (?modelContext :: ModelContext) => VenueMembership -> Integer -> ReferenceData -> IO (AppResult DaysheetConfiguration)
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

retireCurrentReferences :: (?modelContext :: ModelContext) => VenueMembership -> Integer -> ReferenceKey -> [ReferenceChange] -> IO (AppResult DaysheetConfiguration)
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
    _ <- liftIO (recordAuditEvent member.venueId member.userId DaysheetReferencesRetiredAudit "daysheet_configurations" (unpackId config.id) (Aeson.object ["revision" Aeson..= next]) ApplicationAuditSource)
    pure updated
