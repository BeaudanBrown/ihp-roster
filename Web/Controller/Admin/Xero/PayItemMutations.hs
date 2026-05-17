module Web.Controller.Admin.Xero.PayItemMutations
    ( createMissingXeroPayItemsAction
    ) where

import Application.Helper.Xero
import Application.Helper.XeroAdminTypes
import Application.Helper.XeroPayItems
import Application.Helper.LiveResource (LiveMutationResult (..))
import Application.Xero.Admin.PayItems
import Application.Xero.Admin.ReadModel
import Application.Xero.Connection
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Web.Admin.Xero.Mutations
import Web.Controller.Admin.Xero.Responses
import Web.Controller.Prelude

createMissingXeroPayItemsAction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
createMissingXeroPayItemsAction =
    if not currentUserCanManageXeroIntegration
        then respondWithXeroPayItemsMutationError "Only the venue owner or a super admin can create pay items in Xero."
        else do
            maybeConnection <- fetchActiveCurrentVenueXeroConnection
            case maybeConnection of
                Nothing -> respondWithXeroPayItemsMutationError "Connect Xero before creating pay items."
                Just connection -> createMissingXeroPayItems connection

createMissingXeroPayItems ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    IO ()
createMissingXeroPayItems connection = do
    xeroEarningsRates <- fetchCurrentVenueXeroEarningsRates (Just connection)
    requirements <- fetchCurrentVenueXeroPayItemRequirements (Just connection) xeroEarningsRates
    maybeAccountCodeSelection <- fetchCurrentVenueXeroPayItemAccountCodeSelection (Just connection)
    accountCodeOptions <- fetchCurrentVenueXeroPayItemAccountCodeOptions (Just connection)
    let proposedRequirements = filter (\requirement -> requirement.payItemRequirementStatus == "proposed" && requirement.payItemRequirementIsActive) requirements
    case selectedXeroPayItemAccountCode accountCodeOptions maybeAccountCodeSelection of
        Nothing -> respondWithXeroPayItemsMutationError "Choose a Xero pay item account code before creating pay items."
        Just accountCode ->
            if null proposedRequirements
                then respondToXeroPayItemsMutationSuccess "No missing Xero pay items need to be created."
                else do
                    now <- getCurrentTime
                    LiveMutationResult { liveMutationValue = syncRun } <- createRunningXeroPayItemSyncRunMutation connection now
                    readXeroConfig >>= \case
                        Left message -> failXeroPayItemSync syncRun message
                        Right xeroConfig -> do
                            refreshResult <- refreshXeroConnectionAccess xeroConfig connection
                            case refreshResult of
                                Left message -> failXeroPayItemSync syncRun message
                                Right (refreshedConnection, accessToken) -> do
                                    xeroClient <- currentXeroClient
                                    createResult <- createProposedXeroPayItems xeroClient refreshedConnection accessToken now accountCode proposedRequirements
                                    case createResult of
                                        Left message -> failXeroPayItemSync syncRun message
                                        Right verification -> do
                                            void $ recordCurrentUserAuditEvent
                                                "xero_pay_items_created"
                                                "xero_pay_item_requirement_records"
                                                (unpackId refreshedConnection.id)
                                                (Aeson.object
                                                    [ "tenantId" Aeson..= refreshedConnection.tenantId
                                                    , "submittedCount" Aeson..= verification.submittedCount
                                                    , "failedCount" Aeson..= verification.failedCount
                                                    , "verifiedCount" Aeson..= verification.verifiedCount
                                                    , "missingCount" Aeson..= verification.missingCount
                                                    , "missingNames" Aeson..= verification.missingNames
                                                    , "submissionFailures" Aeson..= map xeroPayItemSubmissionFailurePayload verification.submissionFailures
                                                    ]
                                                )
                                            if verification.failedCount == 0 && verification.missingCount == 0
                                                then completeXeroPayItemSync syncRun verification.verifiedCount ("Created and verified " <> tshow verification.verifiedCount <> " missing Xero pay items.")
                                                else failXeroPayItemSyncWithVerifiedCount syncRun verification.verifiedCount (xeroPayItemVerificationFailureMessage verification)

completeXeroPayItemSync ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroSyncRun ->
    Int ->
    Text ->
    IO ()
completeXeroPayItemSync syncRun verifiedCount message = do
    _ <- completeXeroPayItemSyncMutation syncRun verifiedCount
    respondToXeroPayItemsMutationSuccess message

failXeroPayItemSync ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroSyncRun ->
    Text ->
    IO ()
failXeroPayItemSync syncRun =
    failXeroPayItemSyncWithVerifiedCount syncRun 0

failXeroPayItemSyncWithVerifiedCount ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroSyncRun ->
    Int ->
    Text ->
    IO ()
failXeroPayItemSyncWithVerifiedCount syncRun verifiedCount message = do
    _ <- failXeroPayItemSyncMutation syncRun verifiedCount message
    respondWithXeroPayItemsMutationError message
