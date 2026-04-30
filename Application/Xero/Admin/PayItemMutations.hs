module Application.Xero.Admin.PayItemMutations
    ( createMissingXeroPayItemsAction
    ) where

import Application.Helper.Xero
import Application.Helper.XeroAdminTypes
import Application.Helper.XeroPayItems
import Application.Xero.Admin.PayItems
import Application.Xero.Admin.ReadModel
import Application.Xero.Admin.Responses
import Application.Xero.Connection
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Web.Controller.Prelude

createMissingXeroPayItemsAction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
createMissingXeroPayItemsAction =
    if not currentUserCanManageXeroIntegration
        then respondWithXeroMappingMutationError "Only the venue owner or a super admin can create pay items in Xero."
        else do
            maybeConnection <- fetchActiveCurrentVenueXeroConnection
            case maybeConnection of
                Nothing -> respondWithXeroMappingMutationError "Connect Xero before creating pay items."
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
        Nothing -> respondWithXeroMappingMutationError "Choose a Xero pay item account code before creating pay items."
        Just accountCode ->
            if null proposedRequirements
                then respondToXeroMappingMutationSuccess "No missing Xero pay items need to be created."
                else do
                    readXeroConfig >>= \case
                        Left message -> respondWithXeroMappingMutationError message
                        Right xeroConfig -> do
                            refreshResult <- refreshXeroConnectionAccess xeroConfig connection
                            case refreshResult of
                                Left message -> respondWithXeroMappingMutationError message
                                Right (refreshedConnection, accessToken) -> do
                                    xeroClient <- currentXeroClient
                                    now <- getCurrentTime
                                    createResult <- createProposedXeroPayItems xeroClient refreshedConnection accessToken now accountCode proposedRequirements
                                    case createResult of
                                        Left message -> respondWithXeroMappingMutationError message
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
                                            broadcastAdminXeroInvalidation currentVenueId
                                            if verification.failedCount == 0 && verification.missingCount == 0
                                                then respondToXeroMappingMutationSuccess ("Created and verified " <> tshow verification.verifiedCount <> " missing Xero pay items.")
                                                else respondWithXeroMappingMutationError (xeroPayItemVerificationFailureMessage verification)
