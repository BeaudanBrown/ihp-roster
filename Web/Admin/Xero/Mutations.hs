module Web.Admin.Xero.Mutations
    ( completeXeroPayItemSyncMutation
    , completeXeroReferenceSyncMutation
    , createRunningXeroPayItemSyncRunMutation
    , failXeroPayItemSyncMutation
    , failXeroReferenceSyncMutation
    , startXeroReferenceSyncMutation
    , xeroPayItemsTouchedResources
    , xeroReferenceSyncTouchedResources
    ) where

import Application.Helper.LiveResource
import Application.Helper.Xero
import Application.Xero.Admin.ReferenceData
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Web.Controller.Prelude
import Web.LiveResourceInvalidation (invalidateTouchedResources)

createRunningXeroPayItemSyncRunMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => XeroConnection -> UTCTime -> IO (LiveMutationResult XeroSyncRun)
createRunningXeroPayItemSyncRunMutation connection now = do
    syncRun <- newRecord @XeroSyncRun
        |> set #venueId connection.venueId
        |> set #xeroConnectionId (unpackId connection.id)
        |> set #syncStatus ("running" :: Text)
        |> set #syncKind ("pay_item_create" :: Text)
        |> set #startedAt now
        |> createRecord
    invalidateTouchedResources "xero.pay_items.sync.start" (liveMutationResult syncRun (xeroPayItemsTouchedResources (Id connection.venueId)))

completeXeroPayItemSyncMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => XeroSyncRun -> Int -> IO (LiveMutationResult XeroSyncRun)
completeXeroPayItemSyncMutation syncRun verifiedCount = do
    now <- getCurrentTime
    updated <- syncRun
        |> set #syncStatus ("succeeded" :: Text)
        |> set #earningsRatesCount verifiedCount
        |> set #finishedAt (Just now)
        |> updateRecord
    invalidateTouchedResources "xero.pay_items.sync.complete" (liveMutationResult updated (xeroPayItemsTouchedResources currentVenueId))

failXeroPayItemSyncMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => XeroSyncRun -> Int -> Text -> IO (LiveMutationResult XeroSyncRun)
failXeroPayItemSyncMutation syncRun verifiedCount message = do
    now <- getCurrentTime
    updated <- syncRun
        |> set #syncStatus ("failed" :: Text)
        |> set #earningsRatesCount verifiedCount
        |> set #errorMessage (Just message)
        |> set #finishedAt (Just now)
        |> updateRecord
    invalidateTouchedResources "xero.pay_items.sync.fail" (liveMutationResult updated (xeroPayItemsTouchedResources currentVenueId))

startXeroReferenceSyncMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => XeroConnection -> UTCTime -> IO (LiveMutationResult XeroSyncRun)
startXeroReferenceSyncMutation connection now = do
    syncRun <-
        newRecord @XeroSyncRun
            |> set #venueId connection.venueId
            |> set #xeroConnectionId (unpackId connection.id)
            |> set #syncStatus ("running" :: Text)
            |> set #syncKind ("payroll_reference_data" :: Text)
            |> set #startedAt now
            |> createRecord
    invalidateTouchedResources "xero.reference_sync.start" $
        liveMutationResult syncRun (xeroReferenceSyncTouchedResources (Id connection.venueId))

completeXeroReferenceSyncMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => XeroSyncRun -> XeroConnection -> [XeroEmployeeRef] -> [XeroEarningsRateRef] -> [XeroPayrollCalendarRef] -> IO (LiveMutationResult XeroSyncRun)
completeXeroReferenceSyncMutation syncRun connection employees earningsRates payrollCalendars = do
    now <- getCurrentTime
    updated <- withTransaction do
        mapM_ (upsertXeroEmployee connection now) employees
        mapM_ (upsertXeroEarningsRate connection now) earningsRates
        mapM_ (upsertXeroPayrollCalendar connection now) payrollCalendars
        markStaleXeroStaffMappings connection employees
        markStaleXeroEarningsRateMappings connection earningsRates
        reconcileXeroPayItemAccountCodeSelection connection earningsRates
        reconcileXeroPayrollCalendarSelection connection payrollCalendars
        updatedSyncRun <-
            syncRun
                |> set #syncStatus ("succeeded" :: Text)
                |> set #employeesCount (length employees)
                |> set #earningsRatesCount (length earningsRates)
                |> set #payrollCalendarsCount (length payrollCalendars)
                |> set #finishedAt (Just now)
                |> updateRecord
        _ <-
            connection
                |> set #lastSyncAt (Just now)
                |> set #lastError Nothing
                |> updateRecord
        void $
            recordCurrentUserAuditEvent
                "xero_reference_sync_succeeded"
                "xero_sync_runs"
                (unpackId syncRun.id)
                ( Aeson.object
                    [ "tenantId" Aeson..= connection.tenantId
                    , "employeesCount" Aeson..= length employees
                    , "earningsRatesCount" Aeson..= length earningsRates
                    , "payrollCalendarsCount" Aeson..= length payrollCalendars
                    ]
                )
        pure updatedSyncRun
    invalidateTouchedResources "xero.reference_sync.complete" $
        liveMutationResult updated (xeroReferenceSyncTouchedResources currentVenueId)

failXeroReferenceSyncMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => XeroSyncRun -> XeroConnection -> Text -> IO (LiveMutationResult XeroSyncRun)
failXeroReferenceSyncMutation syncRun connection message = do
    now <- getCurrentTime
    updated <- withTransaction do
        latestConnection <- fetch connection.id
        updatedSyncRun <-
            syncRun
                |> set #syncStatus ("failed" :: Text)
                |> set #errorMessage (Just message)
                |> set #finishedAt (Just now)
                |> updateRecord
        _ <-
            latestConnection
                |> set #lastError (Just message)
                |> updateRecord
        void $
            recordCurrentUserAuditEvent
                "xero_reference_sync_failed"
                "xero_sync_runs"
                (unpackId syncRun.id)
                ( Aeson.object
                    [ "tenantId" Aeson..= connection.tenantId
                    , "failure" Aeson..= message
                    ]
                )
        pure updatedSyncRun
    invalidateTouchedResources "xero.reference_sync.fail" $
        liveMutationResult updated (xeroReferenceSyncTouchedResources currentVenueId)

xeroPayItemsTouchedResources :: Id Venue -> [LiveResource]
xeroPayItemsTouchedResources venueId =
    [XeroPayItemsResource (unpackId venueId)]

xeroReferenceSyncTouchedResources :: Id Venue -> [LiveResource]
xeroReferenceSyncTouchedResources venueId =
    [ XeroConnectionResource (unpackId venueId)
    , XeroMappingsResource (unpackId venueId)
    ]
