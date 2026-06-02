module Application.Xero.Admin.PayItems
    ( CreatePayItemsVerificationResult (..)
    , XeroPayItemSubmissionFailure (..)
    , createProposedXeroPayItems
    , selectedXeroPayItemAccountCode
    , xeroPayItemSubmissionFailurePayload
    , xeroPayItemVerificationFailureMessage
    ) where

import Application.Helper.ControllerContext
import Application.Helper.Xero
import Application.Helper.XeroAdminTypes (XeroPayItemAccountCodeOption (..), XeroPayItemRequirement (..), xeroPayItemAccountCodeOptionValues)
import Application.Helper.XeroPayItems (xeroManagedPayItemNamePrefix)
import Application.Xero.Admin.ReferenceData
import Application.Xero.Connection (xeroClientErrorText)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Char as Char
import qualified Data.List as List
import qualified Data.Maybe as Maybe
import Data.Scientific (Scientific)
import qualified Data.Text as Text
import Data.Time.Format (defaultTimeLocale, formatTime)
import Generated.Types
import IHP.ControllerPrelude

selectedXeroPayItemAccountCode :: [XeroPayItemAccountCodeOption] -> Maybe XeroPayItemAccountCodeSelection -> Maybe Text
selectedXeroPayItemAccountCode accountCodeOptions maybeSelection =
    case maybeSelection of
        Just selection | selection.selectionStatus == "verified" -> do
            accountCode <- Text.strip <$> selection.accountCode
            if Text.null accountCode || accountCode `List.notElem` xeroPayItemAccountCodeOptionValues accountCodeOptions then Nothing else Just accountCode
        _ -> Nothing

data CreatePayItemsVerificationResult = CreatePayItemsVerificationResult
    { submittedCount     :: !Int
    , failedCount        :: !Int
    , verifiedCount      :: !Int
    , missingCount       :: !Int
    , missingNames       :: ![Text]
    , submissionFailures :: ![XeroPayItemSubmissionFailure]
    }
    deriving (Eq, Show)

data XeroPayItemSubmissionFailure = XeroPayItemSubmissionFailure
    { failureRequirementKey :: !Text
    , failurePayItemName    :: !Text
    , failureIdempotencyKey :: !Text
    , failureRateType       :: !Text
    , failureRatePerUnit    :: !(Maybe Scientific)
    , failureError          :: !Text
    }
    deriving (Eq, Show)

createProposedXeroPayItems ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroClient ->
    XeroConnection ->
    Text ->
    UTCTime ->
    Text ->
    [XeroPayItemRequirement] ->
    IO (Either Text CreatePayItemsVerificationResult)
createProposedXeroPayItems xeroClient connection accessToken now accountCode requirements = do
    let batchKey = xeroPayItemIdempotencyBatchKey now
    initialFetchResult <- fetchEarningsRates xeroClient accessToken connection.tenantId
    case initialFetchResult of
        Left err -> pure (Left ("Xero pay item preflight pull failed before creating pay items: " <> xeroClientErrorText err))
        Right initialRates -> do
            upsertFetchedXeroEarningsRates connection now initialRates
            let initiallyVerifiedPairs = Maybe.mapMaybe (verifiedRequirementRate initialRates) requirements
                initiallyVerifiedRequirementKeys = map (.payItemRequirementKey) (map fst initiallyVerifiedPairs)
                requirementsToCreate = filter (\requirement -> requirement.payItemRequirementKey `List.notElem` initiallyVerifiedRequirementKeys) requirements
            mapM_ (uncurry (persistCreatedXeroPayItem connection now)) initiallyVerifiedPairs
            maybeExpenseAccountId <- selectedXeroPayItemExpenseAccountId connection accountCode
            (submittedCount, submissionFailures) <- submitCreates batchKey (1 :: Int) 0 [] maybeExpenseAccountId requirementsToCreate
            verifySubmittedCreates submittedCount submissionFailures
    where
        verifySubmittedCreates submittedCount submissionFailures = do
            fetchResult <- fetchEarningsRates xeroClient accessToken connection.tenantId
            case fetchResult of
                Left err -> pure (Left ("Xero pay item verification failed after submitting " <> tshow submittedCount <> " pay items and receiving " <> tshow (length submissionFailures) <> " create errors: " <> xeroClientErrorText err))
                Right fetchedRates -> do
                    upsertFetchedXeroEarningsRates connection now fetchedRates
                    let verifiedPairs = Maybe.mapMaybe (verifiedRequirementRate fetchedRates) requirements
                    mapM_ (uncurry (persistCreatedXeroPayItem connection now)) verifiedPairs
                    let verifiedNames = map (.payItemRequirementName) (map fst verifiedPairs)
                    let missingNames = filter (`List.notElem` verifiedNames) (map (.payItemRequirementName) requirements)
                    pure $
                        Right
                            CreatePayItemsVerificationResult
                                { submittedCount = submittedCount
                                , failedCount = length submissionFailures
                                , verifiedCount = length verifiedPairs
                                , missingCount = length missingNames
                                , missingNames = missingNames
                                , submissionFailures = submissionFailures
                                }

        submitCreates _ _ submittedCount failures _ [] = pure (submittedCount, reverse failures)
        submitCreates batchKey itemIndex submittedCount failures maybeExpenseAccountId (requirement : rest) = do
            let idempotencyKey = xeroPayItemIdempotencyKey batchKey itemIndex requirement
            let body = xeroPayItemRequestPayload maybeExpenseAccountId accountCode requirement
            createResult <-
                createPayItem
                    xeroClient
                    accessToken
                    connection.tenantId
                    idempotencyKey
                    body
            case createResult of
                Left err ->
                    submitCreates
                        batchKey
                        (itemIndex + 1)
                        submittedCount
                        ( xeroPayItemSubmissionFailure requirement idempotencyKey err : failures
                        )
                        maybeExpenseAccountId
                        rest
                Right _ ->
                    submitCreates
                        batchKey
                        (itemIndex + 1)
                        (submittedCount + 1)
                        failures
                        maybeExpenseAccountId
                        rest

xeroPayItemSubmissionFailurePayload :: XeroPayItemSubmissionFailure -> Aeson.Value
xeroPayItemSubmissionFailurePayload failure =
    Aeson.object
        [ "requirementKey" Aeson..= failure.failureRequirementKey
        , "payItemName" Aeson..= failure.failurePayItemName
        , "idempotencyKey" Aeson..= failure.failureIdempotencyKey
        , "rateType" Aeson..= failure.failureRateType
        , "ratePerUnit" Aeson..= failure.failureRatePerUnit
        , "error" Aeson..= failure.failureError
        ]

xeroPayItemVerificationFailureMessage :: CreatePayItemsVerificationResult -> Text
xeroPayItemVerificationFailureMessage verification =
    Text.intercalate
        " "
        (filter (not . Text.null) [failureSummary, verificationSummary, missingSummary])
    where
        failureSummary =
            if verification.failedCount == 0
                then ""
                else
                    "Xero rejected "
                        <> tshow verification.failedCount
                        <> " pay item creates. First error for "
                        <> maybe "unknown pay item" (.failurePayItemName) (listToMaybe verification.submissionFailures)
                        <> ": "
                        <> maybe "unknown error" (.failureError) (listToMaybe verification.submissionFailures)
        verificationSummary =
            "Submitted "
                <> tshow verification.submittedCount
                <> " Xero pay item creates and verified "
                <> tshow verification.verifiedCount
                <> " after pulling Xero pay items."
        missingSummary =
            if verification.missingCount == 0
                then ""
                else
                    "Still missing: "
                        <> Text.intercalate ", " (take 5 verification.missingNames)
                        <> if verification.missingCount > 5 then " and " <> tshow (verification.missingCount - 5) <> " more." else "."

xeroPayItemSubmissionFailure :: XeroPayItemRequirement -> Text -> XeroClientError -> XeroPayItemSubmissionFailure
xeroPayItemSubmissionFailure requirement idempotencyKey err =
    XeroPayItemSubmissionFailure
        { failureRequirementKey = requirement.payItemRequirementKey
        , failurePayItemName = requirement.payItemRequirementName
        , failureIdempotencyKey = idempotencyKey
        , failureRateType = requirement.payItemRequirementRateType
        , failureRatePerUnit = requirement.payItemRequirementRatePerUnit
        , failureError = xeroClientErrorText err
        }

verifiedRequirementRate :: [XeroEarningsRateRef] -> XeroPayItemRequirement -> Maybe (XeroPayItemRequirement, XeroEarningsRateRef)
verifiedRequirementRate fetchedRates requirement =
    fmap (\rate -> (requirement, rate)) (List.find isMatchingActiveRate fetchedRates)
    where
        isMatchingActiveRate rate =
            rate.xeroEarningsRateName == requirement.payItemRequirementName
                && rate.xeroEarningsRateIsActive

xeroPayItemIdempotencyBatchKey :: UTCTime -> Text
xeroPayItemIdempotencyBatchKey now =
    cs (formatTime defaultTimeLocale "%Y%m%d%H%M%S%q" now)

xeroPayItemIdempotencyKey :: Text -> Int -> XeroPayItemRequirement -> Text
xeroPayItemIdempotencyKey batchKey itemIndex requirement =
    "bepis-pay-item-"
        <> batchKey
        <> "-"
        <> Text.justifyRight 3 '0' (tshow itemIndex)
        <> "-"
        <> Text.take 76 (xeroPayItemIdempotencySlug requirement.payItemRequirementKey)

xeroPayItemIdempotencySlug :: Text -> Text
xeroPayItemIdempotencySlug =
    Text.map \char ->
        if Char.isAlphaNum char
            then Char.toLower char
            else '-'

upsertFetchedXeroEarningsRates ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    XeroConnection ->
    UTCTime ->
    [XeroEarningsRateRef] ->
    IO ()
upsertFetchedXeroEarningsRates connection now fetchedRates =
    withTransaction do
        mapM_ (upsertXeroEarningsRate connection now) fetchedRates
        markStaleXeroEarningsRateMappings connection fetchedRates

selectedXeroPayItemExpenseAccountId :: (?modelContext :: ModelContext) => XeroConnection -> Text -> IO (Maybe Text)
selectedXeroPayItemExpenseAccountId connection accountCode = do
    accounts <-
        query @XeroAccount
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#code, Just accountCode)
            |> filterWhere (#accountType, Just ("EXPENSE" :: Text))
            |> filterWhere (#status, Just ("ACTIVE" :: Text))
            |> fetch
    pure (fmap (.xeroAccountId) (listToMaybe accounts))

xeroPayItemRequestPayload :: Maybe Text -> Text -> XeroPayItemRequirement -> Aeson.Value
xeroPayItemRequestPayload maybeExpenseAccountId accountCode requirement =
    xeroEarningsRatePayload maybeExpenseAccountId accountCode requirement

xeroEarningsRatePayload :: Maybe Text -> Text -> XeroPayItemRequirement -> Aeson.Value
xeroEarningsRatePayload maybeExpenseAccountId accountCode requirement =
    Aeson.object $
        [ "Name" Aeson..= requirement.payItemRequirementName
        , "TypeOfUnits" Aeson..= ("Hours" :: Text)
        , "EarningsType" Aeson..= requirement.payItemRequirementEarningsType
        , "RateType" Aeson..= requirement.payItemRequirementRateType
        , "RatePerUnit" Aeson..= requirement.payItemRequirementRatePerUnit
        , "IsSubjectToTax" Aeson..= True
        , "IsSubjectToSuper" Aeson..= True
        , "IsReportableAsW1" Aeson..= True
        , "IsQualifyingEarnings" Aeson..= True
        ]
            <> maybe ["AccountCode" Aeson..= accountCode] (\expenseAccountId -> ["ExpenseAccountID" Aeson..= expenseAccountId]) maybeExpenseAccountId

persistCreatedXeroPayItem ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    UTCTime ->
    XeroPayItemRequirement ->
    XeroEarningsRateRef ->
    IO ()
persistCreatedXeroPayItem connection now requirement createdRate = do
    earningsRate <- upsertXeroEarningsRate connection now createdRate
    withTransaction do
        maybeRequirementRecord <-
            query @XeroPayItemRequirementRecord
                |> filterWhere (#xeroConnectionId, unpackId connection.id)
                |> filterWhere (#requirementKey, requirement.payItemRequirementKey)
                |> fetchOneOrNothing
        forM_ maybeRequirementRecord \record ->
            record
                |> set #requirementStatus ("created" :: Text)
                |> set #xeroEarningsRateId (Just earningsRate.xeroEarningsRateId)
                |> set #xeroEarningsRateName (Just earningsRate.name)
                |> set #xeroEarningsRateRateType earningsRate.rateType
                |> set #lastVerifiedAt (Just now)
                |> set #updatedByUserId (Just (unpackId currentUser.id))
                |> updateRecord
                |> void
        upsertCreatedXeroEarningsRateMapping connection now requirement earningsRate

upsertCreatedXeroEarningsRateMapping ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    UTCTime ->
    XeroPayItemRequirement ->
    XeroEarningsRate ->
    IO ()
upsertCreatedXeroEarningsRateMapping connection now requirement earningsRate = do
    existingMapping <-
        query @XeroEarningsRateMapping
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#localBucketKey, requirement.payItemRequirementKey)
            |> fetchOneOrNothing
    let localBucketLabel = fromMaybe requirement.payItemRequirementName (Text.stripPrefix xeroManagedPayItemNamePrefix requirement.payItemRequirementName)
    let prepared record =
            record
                |> set #venueId (unpackId currentVenueId)
                |> set #xeroConnectionId (unpackId connection.id)
                |> set #localBucketKey requirement.payItemRequirementKey
                |> set #localBucketLabel localBucketLabel
                |> set #xeroEarningsRateId (Just earningsRate.xeroEarningsRateId)
                |> set #xeroEarningsRateName (Just earningsRate.name)
                |> set #mappingStatus ("verified" :: Text)
                |> set #lastVerifiedAt (Just now)
                |> set #updatedByUserId (Just (unpackId currentUser.id))
    case existingMapping of
        Just existing -> prepared existing |> updateRecord |> void
        Nothing ->
            prepared (newRecord @XeroEarningsRateMapping)
                |> set #createdByUserId (Just (unpackId currentUser.id))
                |> createRecord
                |> void
