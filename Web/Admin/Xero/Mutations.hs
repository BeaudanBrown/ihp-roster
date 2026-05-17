module Web.Admin.Xero.Mutations
    ( completeXeroPayItemSyncMutation
    , createRunningXeroPayItemSyncRunMutation
    , failXeroPayItemSyncMutation
    , xeroPayItemsTouchedResources
    ) where

import Application.Helper.LiveResource
import Web.Controller.Admin.Xero.Responses (refreshAdminXeroPayItems)
import Web.Controller.Prelude

createRunningXeroPayItemSyncRunMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => XeroConnection -> UTCTime -> IO (LiveMutationResult XeroSyncRun)
createRunningXeroPayItemSyncRunMutation connection now = do
    syncRun <- newRecord @XeroSyncRun
        |> set #venueId connection.venueId
        |> set #xeroConnectionId (unpackId connection.id)
        |> set #syncStatus ("running" :: Text)
        |> set #syncKind ("pay_item_create" :: Text)
        |> set #startedAt now
        |> createRecord
    refreshAdminXeroPayItems connection.venueId
    pure (liveMutationResult syncRun (xeroPayItemsTouchedResources (Id connection.venueId)))

completeXeroPayItemSyncMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => XeroSyncRun -> Int -> IO (LiveMutationResult XeroSyncRun)
completeXeroPayItemSyncMutation syncRun verifiedCount = do
    now <- getCurrentTime
    updated <- syncRun
        |> set #syncStatus ("succeeded" :: Text)
        |> set #earningsRatesCount verifiedCount
        |> set #finishedAt (Just now)
        |> updateRecord
    refreshAdminXeroPayItems (unpackId currentVenueId)
    pure (liveMutationResult updated (xeroPayItemsTouchedResources currentVenueId))

failXeroPayItemSyncMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => XeroSyncRun -> Int -> Text -> IO (LiveMutationResult XeroSyncRun)
failXeroPayItemSyncMutation syncRun verifiedCount message = do
    now <- getCurrentTime
    updated <- syncRun
        |> set #syncStatus ("failed" :: Text)
        |> set #earningsRatesCount verifiedCount
        |> set #errorMessage (Just message)
        |> set #finishedAt (Just now)
        |> updateRecord
    refreshAdminXeroPayItems (unpackId currentVenueId)
    pure (liveMutationResult updated (xeroPayItemsTouchedResources currentVenueId))

xeroPayItemsTouchedResources :: Id Venue -> [LiveResource]
xeroPayItemsTouchedResources venueId =
    [XeroPayItemsResource (unpackId venueId)]
