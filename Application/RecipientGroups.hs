module Application.RecipientGroups
    ( RecipientGroupInput (..)
    , RecipientGroupError (..)
    , listRecipientGroups
    , fetchRecipientGroup
    , saveRecipientGroup
    , deleteRecipientGroup
    ) where

import Application.Helper.ControllerAccess (hasRole)
import Application.Helper.ControllerContext (authenticatedCurrentUser, currentVenueId, currentVenueOrNothing)
import Application.PayrollReports.Settings (withPayrollReportVenueLock, clearPayrollReportRecipientGroupInCurrentTransaction)
import Application.RecipientGroups.Validation (validateRecipientAddresses)
import Control.Monad (void)
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude

-- Addresses are private: never derive Show for request inputs.
data RecipientGroupInput = RecipientGroupInput
    { name :: !Text
    , recipients :: ![Text]
    , expectedRevision :: !(Maybe Int)
    }

data RecipientGroupError
    = RecipientGroupAccessDenied
    | RecipientGroupInvalid !Text
    | RecipientGroupNotFound
    | RecipientGroupStale
    | RecipientGroupNameConflict
    | RecipientGroupScheduleConfirmationRequired
    deriving (Eq, Show)

canManage :: (?context :: ControllerContext) => Bool
canManage = isJust currentVenueOrNothing && hasRole VenueAdmin

listRecipientGroups :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO (Either RecipientGroupError [RecipientGroup])
listRecipientGroups
    | not canManage = pure (Left RecipientGroupAccessDenied)
    | otherwise = Right <$> (query @RecipientGroup
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#archivedAt, Nothing)
        |> orderByAsc #name |> fetch)

fetchRecipientGroup :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RecipientGroup -> IO (Either RecipientGroupError RecipientGroup)
fetchRecipientGroup groupId
    | not canManage = pure (Left RecipientGroupAccessDenied)
    | otherwise = maybe (Left RecipientGroupNotFound) Right <$> (query @RecipientGroup
        |> filterWhere (#id, groupId)
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#archivedAt, Nothing) |> fetchOneOrNothing)

-- Venue-first serialization also protects first creation and case-insensitive
-- name uniqueness. No group edit mutates a schedule or a prepared run.
saveRecipientGroup :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe (Id RecipientGroup) -> RecipientGroupInput -> IO (Either RecipientGroupError RecipientGroup)
saveRecipientGroup groupId input
    | not canManage = pure (Left RecipientGroupAccessDenied)
    | Text.null normalizedName || Text.length normalizedName > 100 =
        pure (Left (RecipientGroupInvalid "Use a group name of 1–100 characters."))
    | otherwise = case validateRecipientAddresses input.recipients of
        Left message -> pure (Left (RecipientGroupInvalid message))
        Right [] -> pure (Left (RecipientGroupInvalid "Add at least one recipient."))
        Right addresses -> withTransaction do
            withPayrollReportVenueLock (unpackId currentVenueId)
            existing <- case groupId of
                Nothing -> pure (Right Nothing)
                Just identifier -> fmap Just <$> fetchRecipientGroup identifier
            case existing of
                Left failure -> pure (Left failure)
                Right record
                    | fmap (.revision) record /= input.expectedRevision -> pure (Left RecipientGroupStale)
                    | otherwise -> do
                        conflict <- query @RecipientGroup
                            |> filterWhere (#venueId, unpackId currentVenueId)
                            |> filterWhere (#archivedAt, Nothing)
                            |> filterWhereCaseInsensitive (#name, normalizedName)
                            |> fetchOneOrNothing
                        if maybe False (\other -> Just other.id /= groupId) conflict
                            then pure (Left RecipientGroupNameConflict)
                            else do
                                now <- getCurrentTime
                                let actorId = unpackId authenticatedCurrentUser.id
                                let initial = newRecord @RecipientGroup
                                        |> set #venueId (unpackId currentVenueId)
                                        |> set #createdByUserId actorId
                                let updated = fromMaybe initial record
                                        |> set #name normalizedName
                                        |> set #recipients addresses
                                        |> set #revision (maybe 0 ((+ 1) . (.revision)) record)
                                        |> set #updatedByUserId actorId
                                        |> set #updatedAt now
                                Right <$> (if isNothing record then createRecord updated else updateRecord updated)
  where
    normalizedName = Text.unwords (Text.words input.name)

deleteRecipientGroup :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RecipientGroup -> Int -> Bool -> IO (Either RecipientGroupError ())
deleteRecipientGroup groupId expectedRevision confirmScheduleDisable
    | not canManage = pure (Left RecipientGroupAccessDenied)
    | otherwise = withTransaction do
        withPayrollReportVenueLock (unpackId currentVenueId)
        fetchRecipientGroup groupId >>= \case
            Left failure -> pure (Left failure)
            Right record
                | record.revision /= expectedRevision -> pure (Left RecipientGroupStale)
                | otherwise -> do
                    linked <- query @PayrollReportSetting
                        |> filterWhere (#venueId, unpackId currentVenueId)
                        |> filterWhere (#recipientGroupId, Just (unpackId groupId)) |> fetchExists
                    if linked && not confirmScheduleDisable
                        then pure (Left RecipientGroupScheduleConfirmationRequired)
                        else do
                            now <- getCurrentTime
                            let actorId = unpackId authenticatedCurrentUser.id
                            clearPayrollReportRecipientGroupInCurrentTransaction (unpackId currentVenueId) (unpackId groupId) actorId
                            record |> set #archivedAt (Just now) |> set #revision (record.revision + 1)
                                |> set #updatedAt now |> set #updatedByUserId actorId |> updateRecord |> void
                            pure (Right ())
