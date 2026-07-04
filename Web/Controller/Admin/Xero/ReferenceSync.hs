module Web.Controller.Admin.Xero.ReferenceSync
    ( syncXeroPayrollReferenceDataAction
    ) where

import Application.Helper.SurfaceResource (LiveMutationResult (..))
import Application.Helper.Xero
import Application.Xero.Admin.ReadModel
import Application.Xero.Connection
import qualified Data.Text as Text
import Web.Admin.Xero.Mutations (completeXeroReferenceSyncMutation,
                                 failXeroReferenceSyncMutation,
                                 startXeroReferenceSyncMutation)
import Web.Controller.Admin.Xero.Connection (redirectToXeroAuthorizationForReferenceSync)
import Web.Controller.Admin.Xero.Responses (currentUserCanManageXeroIntegration,
                                            respondWithXeroSectionFragment)
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
    syncRun <- liveMutationValue <$> startXeroReferenceSyncMutation connection now
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
                    accountsResult <- fetchAccounts xeroClient accessToken refreshedConnection.tenantId
                    payrollSettingsAccountsResult <- fetchPayrollSettingsAccounts xeroClient accessToken refreshedConnection.tenantId
                    case (employeesResult, earningsRatesResult, payrollCalendarsResult, accountsResult, payrollSettingsAccountsResult) of
                        (Right employees, Right earningsRates, Right payrollCalendars, Right accounts, Right payrollSettingsAccounts) -> do
                            completeXeroReferenceSync syncRun refreshedConnection employees earningsRates payrollCalendars accounts payrollSettingsAccounts
                        (Left err, _, _, _, _) ->
                            failXeroReferenceSync syncRun refreshedConnection ("Xero employee sync failed: " <> xeroClientErrorText err)
                        (_, Left err, _, _, _) ->
                            failXeroReferenceSync syncRun refreshedConnection ("Xero earnings-rate sync failed: " <> xeroClientErrorText err)
                        (_, _, Left err, _, _) ->
                            failXeroReferenceSync syncRun refreshedConnection ("Xero payroll-calendar sync failed: " <> xeroClientErrorText err)
                        (_, _, _, Left err, _) ->
                            failXeroReferenceSync syncRun refreshedConnection ("Xero account sync failed: " <> xeroClientErrorText err)
                        (_, _, _, _, Left err) ->
                            failXeroReferenceSync syncRun refreshedConnection ("Xero payroll-settings sync failed: " <> xeroClientErrorText err)

completeXeroReferenceSync ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroSyncRun ->
    XeroConnection ->
    [XeroEmployeeRef] ->
    [XeroEarningsRateRef] ->
    [XeroPayrollCalendarRef] ->
    [XeroAccountRef] ->
    [XeroAccountRef] ->
    IO ()
completeXeroReferenceSync syncRun connection employees earningsRates payrollCalendars accounts payrollSettingsAccounts = do
    _ <- completeXeroReferenceSyncMutation syncRun connection employees earningsRates payrollCalendars accounts payrollSettingsAccounts
    setSuccessMessage ("Synced Xero payroll reference data: " <> tshow (length employees) <> " employees, " <> tshow (length earningsRates) <> " earnings rates, " <> tshow (length payrollCalendars) <> " payroll calendars, " <> tshow (length accounts) <> " accounts.")
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
    _ <- failXeroReferenceSyncMutation syncRun connection message
    setErrorMessage message
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
        _ <- failXeroReferenceSyncMutation syncRun connection message
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
