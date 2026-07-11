module Web.Controller.Admin.Xero.ReferenceSync
    ( syncXeroPayrollReferenceDataAction
    ) where

import Application.Helper.SurfaceResource (LiveMutationResult (..))
import Application.Xero.Admin.ReadModel (fetchCurrentVenueXeroConnection)
import Application.Xero.Admin.ReferenceData (XeroReferenceDataSyncResult (..))
import qualified Data.Text as Text
import Web.Admin.Xero.Mutations (syncXeroReferenceDataMutation)
import Web.Controller.Admin.Xero.Connection (redirectToXeroAuthorizationForReferenceSync)
import Web.Controller.Admin.Xero.Responses
import Web.Controller.Prelude

syncXeroPayrollReferenceDataAction ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO ()
syncXeroPayrollReferenceDataAction = do
    maybeConnection <- fetchCurrentVenueXeroConnection
    case maybeConnection of
        Nothing -> respondReferenceSyncFailure "Connect Xero before syncing payroll reference data."
        Just connection -> do
            syncResult <- syncXeroReferenceDataMutation connection
            case liveMutationValue syncResult of
                Left message
                    | shouldStartReconnectAfterSyncFailure message && currentUserCanManageXeroIntegration ->
                        redirectToXeroAuthorizationForReferenceSync
                    | otherwise -> respondReferenceSyncFailure message
                Right result ->
                    respondReferenceSyncSuccess $
                        "Synced Xero payroll reference data: "
                            <> tshow result.referenceDataSyncEmployeeCount
                            <> " employees, "
                            <> tshow result.referenceDataSyncEarningsRateCount
                            <> " earnings rates, "
                            <> tshow result.referenceDataSyncPayrollCalendarCount
                            <> " payroll calendars, and "
                            <> tshow result.referenceDataSyncAccountCount
                            <> " accounts from Xero."

shouldStartReconnectAfterSyncFailure :: Text -> Bool
shouldStartReconnectAfterSyncFailure message =
    let normalized = Text.toLower message
     in "reconnect xero" `Text.isInfixOf` normalized
        || "needs to be reconnected" `Text.isInfixOf` normalized
        || "refresh token expired" `Text.isInfixOf` normalized
        || "refresh token expired or was revoked" `Text.isInfixOf` normalized

respondReferenceSyncSuccess ::
    (?context :: ControllerContext, ?request :: Request) =>
    Text ->
    IO ()
respondReferenceSyncSuccess message =
    if isHtmxRequest
        then respondWithXeroSectionActorInvalidationAndToast (Just (xeroSuccessToast message))
        else do
            setSuccessMessage message
            redirectTo XeroAction

respondReferenceSyncFailure ::
    (?context :: ControllerContext, ?request :: Request) =>
    Text ->
    IO ()
respondReferenceSyncFailure message =
    if isHtmxRequest
        then respondWithXeroSectionActorInvalidationAndToast (Just (xeroErrorToast message))
        else do
            setErrorMessage message
            redirectTo XeroAction
