module Application.Xero.Admin.ImportedPayItems
    ( XeroImportedPayItemCandidate (..)
    , fetchActiveImportedXeroPayItems
    , importXeroEarningsRates
    , viableImportedPayItemCandidates
    , xeroEarningsRateIsBepisGenerated
    , xeroEarningsRateIsSupportedImportedPayItem
    ) where

import Application.Helper.ControllerContext
import Application.Helper.Xero
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude

newtype XeroImportedPayItemCandidate = XeroImportedPayItemCandidate
    { candidateEarningsRate :: XeroEarningsRateRef
    }
    deriving (Eq, Show)

fetchActiveImportedXeroPayItems :: (?context :: ControllerContext, ?modelContext :: ModelContext) => XeroConnection -> IO [XeroImportedPayItem]
fetchActiveImportedXeroPayItems connection =
    query @XeroImportedPayItem
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#xeroConnectionId, unpackId connection.id)
        |> filterWhere (#archivedAt, Nothing :: Maybe UTCTime)
        |> filterWhere (#providerAvailable, True)
        |> orderBy #name
        |> fetch

viableImportedPayItemCandidates :: [XeroImportedPayItem] -> [XeroEarningsRateRef] -> [XeroImportedPayItemCandidate]
viableImportedPayItemCandidates activeImports fetchedRates =
    fetchedRates
        |> filter xeroEarningsRateIsSupportedImportedPayItem
        |> filter (not . xeroEarningsRateIsBepisGenerated)
        |> filter (not . alreadyImported)
        |> map XeroImportedPayItemCandidate
    where
        importedRateIds = map (.xeroEarningsRateId) activeImports
        alreadyImported rate = rate.xeroEarningsRateId `elem` importedRateIds

xeroEarningsRateIsSupportedImportedPayItem :: XeroEarningsRateRef -> Bool
xeroEarningsRateIsSupportedImportedPayItem rate =
    rate.xeroEarningsRateIsActive
        && normalized rate.xeroEarningsRateType == Just "ordinarytimeearnings"
        && normalized rate.xeroEarningsRateRateType == Just "rateperunit"
        && normalized rate.xeroEarningsRateTypeOfUnits == Just "hours"
        && maybe False (> 0) rate.xeroEarningsRateRatePerUnit

xeroEarningsRateIsBepisGenerated :: XeroEarningsRateRef -> Bool
xeroEarningsRateIsBepisGenerated rate =
    "bepis" `Text.isInfixOf` Text.toLower rate.xeroEarningsRateName

normalized :: Maybe Text -> Maybe Text
normalized = fmap (Text.toLower . Text.strip)

importXeroEarningsRates :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => XeroConnection -> UTCTime -> [XeroEarningsRateRef] -> [Text] -> IO [XeroImportedPayItem]
importXeroEarningsRates connection now fetchedRates selectedRateIds = do
    let selectedRates =
            fetchedRates
                |> filter (\rate -> rate.xeroEarningsRateId `elem` selectedRateIds)
                |> filter xeroEarningsRateIsSupportedImportedPayItem
                |> filter (not . xeroEarningsRateIsBepisGenerated)
    mapM (upsertImportedXeroPayItem connection now) selectedRates

upsertImportedXeroPayItem :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => XeroConnection -> UTCTime -> XeroEarningsRateRef -> IO XeroImportedPayItem
upsertImportedXeroPayItem connection now rate = do
    existing <-
        query @XeroImportedPayItem
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#xeroEarningsRateId, rate.xeroEarningsRateId)
            |> orderByDesc #createdAt
            |> fetchOneOrNothing
    let fillRecord record =
            record
                |> set #venueId (unpackId currentVenueId)
                |> set #xeroConnectionId (unpackId connection.id)
                |> set #xeroEarningsRateId rate.xeroEarningsRateId
                |> set #name rate.xeroEarningsRateName
                |> set #accountCode rate.xeroEarningsRateAccountCode
                |> set #earningsType (fromMaybe "ORDINARYTIMEEARNINGS" rate.xeroEarningsRateType)
                |> set #rateType (fromMaybe "RATEPERUNIT" rate.xeroEarningsRateRateType)
                |> set #typeOfUnits (fromMaybe "Hours" rate.xeroEarningsRateTypeOfUnits)
                |> set #ratePerUnit (fromMaybe 0 rate.xeroEarningsRateRatePerUnit)
                |> set #rawPayload rate.xeroEarningsRateRaw
                |> set #lastSeenAt now
                |> set #providerAvailable True
                |> set #providerUnavailableAt Nothing
                |> set #archivedAt Nothing
                |> set #archivedByUserId Nothing
                |> set #archiveReason Nothing
    case existing of
        Just record -> fillRecord record |> updateRecord
        Nothing ->
            fillRecord (newRecord @XeroImportedPayItem)
                |> set #importedByUserId (unpackId currentUser.id)
                |> set #importedAt now
                |> createRecord
