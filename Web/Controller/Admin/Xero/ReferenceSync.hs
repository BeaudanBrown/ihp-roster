module Web.Controller.Admin.Xero.ReferenceSync
    ( syncXeroPayrollReferenceDataAction
    ) where

import Application.Helper.Xero
import Application.Xero.Admin.ReadModel
import Application.Xero.Admin.ReferenceData
import Application.Xero.Connection
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import Web.Controller.Admin.Xero.Connection (redirectToXeroAuthorizationForReferenceSync)
import Web.Controller.Admin.Xero.Responses
import Web.Controller.Prelude

syncXeroPayrollReferenceDataAction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
syncXeroPayrollReferenceDataAction = do
    maybeConnection <- fetchActiveCurrentVenueXeroConnection
    case maybeConnection of
        Nothing -> do
            setErrorMessage "Connect Xero before syncing payroll reference data."
            if isHtmxRequest
                then respondWithXeroSectionFragment
                else redirectTo XeroAction
        Just connection -> syncXeroPayrollReferenceData connection

syncXeroPayrollReferenceData ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    IO ()
syncXeroPayrollReferenceData connection = do
    now <- getCurrentTime
    syncRun <-
        newRecord @XeroSyncRun
            |> set #venueId (unpackId currentVenueId)
            |> set #xeroConnectionId (unpackId connection.id)
            |> set #syncStatus ("running" :: Text)
            |> set #syncKind ("payroll_reference_data" :: Text)
            |> set #startedAt now
            |> createRecord
    broadcastAdminXeroInvalidation currentVenueId
    readXeroConfig >>= \case
        Left message -> failXeroReferenceSync syncRun connection message
        Right xeroConfig -> do
            refreshResult <- refreshXeroConnectionAccessWithoutBroadcast xeroConfig connection
            case refreshResult of
                Left message -> failXeroReferenceSyncOrReconnect syncRun connection message
                Right (refreshedConnection, accessToken) -> do
                    xeroClient <- currentXeroClient
                    employeesResult <- fetchPayrollEmployees xeroClient accessToken refreshedConnection.tenantId
                    earningsRatesResult <- fetchEarningsRates xeroClient accessToken refreshedConnection.tenantId
                    payrollCalendarsResult <- fetchPayrollCalendars xeroClient accessToken refreshedConnection.tenantId
                    case (employeesResult, earningsRatesResult, payrollCalendarsResult) of
                        (Right employees, Right earningsRates, Right payrollCalendars) -> do
                            completeXeroReferenceSync syncRun refreshedConnection employees earningsRates payrollCalendars
                        (Left err, _, _) ->
                            failXeroReferenceSync syncRun refreshedConnection ("Xero employee sync failed: " <> xeroClientErrorText err)
                        (_, Left err, _) ->
                            failXeroReferenceSync syncRun refreshedConnection ("Xero earnings-rate sync failed: " <> xeroClientErrorText err)
                        (_, _, Left err) ->
                            failXeroReferenceSync syncRun refreshedConnection ("Xero payroll-calendar sync failed: " <> xeroClientErrorText err)

completeXeroReferenceSync ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroSyncRun ->
    XeroConnection ->
    [XeroEmployeeRef] ->
    [XeroEarningsRateRef] ->
    [XeroPayrollCalendarRef] ->
    IO ()
completeXeroReferenceSync syncRun connection employees earningsRates payrollCalendars = do
    now <- getCurrentTime
    withTransaction do
        mapM_ (upsertXeroEmployee connection now) employees
        mapM_ (upsertXeroEarningsRate connection now) earningsRates
        mapM_ (upsertXeroPayrollCalendar connection now) payrollCalendars
        markStaleXeroStaffMappings connection employees
        markStaleXeroEarningsRateMappings connection earningsRates
        reconcileXeroPayItemAccountCodeSelection connection earningsRates
        reconcileXeroPayrollCalendarSelection connection payrollCalendars
        _ <- syncRun
            |> set #syncStatus ("succeeded" :: Text)
            |> set #employeesCount (length employees)
            |> set #earningsRatesCount (length earningsRates)
            |> set #payrollCalendarsCount (length payrollCalendars)
            |> set #finishedAt (Just now)
            |> updateRecord
        _ <- connection
            |> set #lastSyncAt (Just now)
            |> set #lastError Nothing
            |> updateRecord
        void $ recordCurrentUserAuditEvent
            "xero_reference_sync_succeeded"
            "xero_sync_runs"
            (unpackId syncRun.id)
            (Aeson.object
                [ "tenantId" Aeson..= connection.tenantId
                , "employeesCount" Aeson..= length employees
                , "earningsRatesCount" Aeson..= length earningsRates
                , "payrollCalendarsCount" Aeson..= length payrollCalendars
                ]
            )
    setSuccessMessage ("Synced Xero payroll reference data: " <> tshow (length employees) <> " employees, " <> tshow (length earningsRates) <> " earnings rates, " <> tshow (length payrollCalendars) <> " payroll calendars.")
    broadcastAdminXeroInvalidation currentVenueId
    if isHtmxRequest
        then respondWithXeroSectionFragment
        else redirectTo XeroAction

failXeroReferenceSync ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroSyncRun ->
    XeroConnection ->
    Text ->
    IO ()
failXeroReferenceSync syncRun connection message = do
    recordFailedXeroReferenceSync syncRun connection message
    setErrorMessage message
    broadcastAdminXeroInvalidation currentVenueId
    if isHtmxRequest
        then respondWithXeroSectionFragment
        else redirectTo XeroAction

failXeroReferenceSyncOrReconnect ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroSyncRun ->
    XeroConnection ->
    Text ->
    IO ()
failXeroReferenceSyncOrReconnect syncRun connection message
    | shouldStartReconnectAfterSyncFailure message && currentUserCanManageXeroIntegration = do
        recordFailedXeroReferenceSync syncRun connection message
        redirectToXeroAuthorizationForReferenceSync
    | otherwise =
        failXeroReferenceSync syncRun connection message

shouldStartReconnectAfterSyncFailure :: Text -> Bool
shouldStartReconnectAfterSyncFailure message =
    let normalized = Text.toLower message
     in "reconnect xero" `Text.isInfixOf` normalized
        || "needs to be reconnected" `Text.isInfixOf` normalized
        || "refresh token expired" `Text.isInfixOf` normalized
        || "refresh token expired or was revoked" `Text.isInfixOf` normalized

recordFailedXeroReferenceSync ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroSyncRun ->
    XeroConnection ->
    Text ->
    IO ()
recordFailedXeroReferenceSync syncRun connection message = do
    now <- getCurrentTime
    withTransaction do
        latestConnection <- fetch connection.id
        _ <- syncRun
            |> set #syncStatus ("failed" :: Text)
            |> set #errorMessage (Just message)
            |> set #finishedAt (Just now)
            |> updateRecord
        _ <- latestConnection
            |> set #lastError (Just message)
            |> updateRecord
        void $ recordCurrentUserAuditEvent
            "xero_reference_sync_failed"
            "xero_sync_runs"
            (unpackId syncRun.id)
            (Aeson.object
                [ "tenantId" Aeson..= connection.tenantId
                , "failure" Aeson..= message
                ]
            )
