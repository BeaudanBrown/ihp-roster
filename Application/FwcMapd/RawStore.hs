module Application.FwcMapd.RawStore where

import Application.FwcMapd.Client
import Application.FwcMapd.Config
import Application.FwcMapd.Curation
import Application.FwcMapd.Payload
import Application.FwcMapd.Projection
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Set as Set
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (withTransaction)
import IHP.Prelude

data CuratedMapdAwardData = CuratedMapdAwardData
    { curatedAwardFixedId    :: !Int
    , curatedAwards          :: ![(AwardPayload, Aeson.Value)]
    , curatedClassifications :: ![(ClassificationPayload, Aeson.Value)]
    , curatedPayRates        :: ![(PayRatePayload, Aeson.Value)]
    , curatedPenaltyRates    :: ![(PenaltyRatePayload, Aeson.Value)]
    , curatedWageAllowances  :: ![(WageAllowancePayload, Aeson.Value)]
    }
    deriving (Eq, Show)

fetchAndStore :: (?modelContext :: ModelContext) => MapdConfig -> IO MapdSyncSummary
fetchAndStore config = do
    asOfDate <- utctDay <$> getCurrentTime
    fetchedAwards <- forM config.awardFixedIds \awardFixedId -> do
        awardValues <- liftIO (fetchAwardValues config awardFixedId)
        classificationValues <- liftIO (fetchClassificationValues config awardFixedId)
        payRateValues <- liftIO (fetchPayRateValues config awardFixedId)
        wageAllowanceValues <- liftIO (fetchWageAllowanceValues config awardFixedId)
        awards <- decodePayloads "awards" awardValues :: IO [(AwardPayload, Aeson.Value)]
        classifications <- decodePayloads "classifications" classificationValues :: IO [(ClassificationPayload, Aeson.Value)]
        payRates <- decodePayloads "pay rates" payRateValues :: IO [(PayRatePayload, Aeson.Value)]
        wageAllowances <- decodePayloads "wage allowances" wageAllowanceValues :: IO [(WageAllowancePayload, Aeson.Value)]
        let (_, _, _, retainedPayRatesForPenaltyFetch, _) =
                curateAwardData barVenueCurationProfile asOfDate (awardFixedId, awards, classifications, payRates, [])
            retainedBasePayRateIds =
                retainedPayRatesForPenaltyFetch
                    |> mapMaybe (\(payload, _) -> payload.basePayRateId)
                    |> Set.fromList
                    |> Set.toList
        penaltyRateValues <- liftIO (concat <$> forM retainedBasePayRateIds (fetchPenaltyRateValuesForBasePayRateId config awardFixedId))
        penaltyRates <- decodePayloads "penalty rates" penaltyRateValues :: IO [(PenaltyRatePayload, Aeson.Value)]
        let (curatedAwardFixedId, curatedAwards, curatedClassifications, curatedPayRates, curatedPenaltyRates) =
                curateAwardData barVenueCurationProfile asOfDate (awardFixedId, awards, classifications, payRates, penaltyRates)
            curatedWageAllowances = curateWageAllowances barVenueCurationProfile asOfDate wageAllowances
        pure CuratedMapdAwardData { .. }

    storeCuratedMapdAwardData fetchedAwards

storeCuratedMapdAwardData ::
    (?modelContext :: ModelContext) =>
    [CuratedMapdAwardData] ->
    IO MapdSyncSummary
storeCuratedMapdAwardData fetchedAwards =
    withTransaction do
        let requestedAwardIds = map (.curatedAwardFixedId) fetchedAwards
        clearExistingCache requestedAwardIds
        syncedAt <- getCurrentTime
        forM_ fetchedAwards \awardData -> do
            let awardFixedId = awardData.curatedAwardFixedId
                awards = awardData.curatedAwards
                classifications = awardData.curatedClassifications
                payRates = awardData.curatedPayRates
                penaltyRates = awardData.curatedPenaltyRates
                wageAllowances = awardData.curatedWageAllowances
            forM_ awards \(payload, rawValue) ->
                void
                    ( newRecord @FwcMapdAward
                        |> set #awardFixedId payload.awardFixedId
                        |> set #awardId payload.awardId
                        |> set #code payload.code
                        |> set #name payload.name
                        |> set #awardOperativeFrom payload.awardOperativeFrom
                        |> set #awardOperativeTo payload.awardOperativeTo
                        |> set #publishedYear payload.publishedYear
                        |> set #versionNumber payload.versionNumber
                        |> set #lastModifiedDatetime payload.lastModifiedDatetime
                        |> set #rawJson rawValue
                        |> set #syncedAt syncedAt
                        |> createRecord
                    )
            forM_ classifications \(payload, rawValue) ->
                void
                    ( newRecord @FwcMapdClassification
                        |> set #awardFixedId awardFixedId
                        |> set #classificationFixedId payload.classificationFixedId
                        |> set #classification payload.classification
                        |> set #classificationLevel payload.classificationLevel
                        |> set #parentClassificationName payload.parentClassificationName
                        |> set #clauseFixedId payload.clauseFixedId
                        |> set #clauseDescription payload.clauseDescription
                        |> set #clauses payload.clauses
                        |> set #nextDownClassificationFixedId payload.nextDownClassificationFixedId
                        |> set #nextUpClassificationFixedId payload.nextUpClassificationFixedId
                        |> set #operativeFrom payload.operativeFrom
                        |> set #operativeTo payload.operativeTo
                        |> set #publishedYear payload.publishedYear
                        |> set #versionNumber payload.versionNumber
                        |> set #lastModifiedDatetime payload.lastModifiedDatetime
                        |> set #rawJson rawValue
                        |> set #syncedAt syncedAt
                        |> createRecord
                    )
            forM_ payRates \(payload, rawValue) ->
                void
                    ( newRecord @FwcMapdPayRate
                        |> set #awardFixedId awardFixedId
                        |> set #classificationFixedId payload.classificationFixedId
                        |> set #classification payload.classification
                        |> set #classificationLevel payload.classificationLevel
                        |> set #parentClassificationName payload.parentClassificationName
                        |> set #employeeRateTypeCode payload.employeeRateTypeCode
                        |> set #basePayRateId payload.basePayRateId
                        |> set #baseRate payload.baseRate
                        |> set #baseRateType payload.baseRateType
                        |> set #calculatedPayRateId payload.calculatedPayRateId
                        |> set #calculatedRate payload.calculatedRate
                        |> set #calculatedRateType payload.calculatedRateType
                        |> set #operativeFrom payload.operativeFrom
                        |> set #operativeTo payload.operativeTo
                        |> set #publishedYear payload.publishedYear
                        |> set #versionNumber payload.versionNumber
                        |> set #lastModifiedDatetime payload.lastModifiedDatetime
                        |> set #rawJson rawValue
                        |> set #syncedAt syncedAt
                        |> createRecord
                    )
            forM_ penaltyRates \(payload, rawValue) ->
                void
                    ( newRecord @FwcMapdPenaltyRate
                        |> set #awardFixedId awardFixedId
                        |> set #classificationFixedId payload.penaltyClassificationFixedId
                        |> set #classification payload.penaltyClassification
                        |> set #classificationLevel payload.penaltyClassificationLevel
                        |> set #parentClassificationName payload.penaltyParentClassificationName
                        |> set #clauseDescription payload.penaltyClauseDescription
                        |> set #employeeRateTypeCode payload.penaltyEmployeeRateTypeCode
                        |> set #basePayRateId payload.penaltyBasePayRateId
                        |> set #penaltyFixedId payload.penaltyFixedId
                        |> set #penaltyDescription payload.penaltyDescription
                        |> set #penaltyText payload.penaltyText
                        |> set #rate payload.penaltyRate
                        |> set #penaltyRateUnit payload.penaltyRateUnit
                        |> set #penaltyCalculatedValue payload.penaltyCalculatedValue
                        |> set #operativeFrom payload.penaltyOperativeFrom
                        |> set #operativeTo payload.penaltyOperativeTo
                        |> set #publishedYear payload.penaltyPublishedYear
                        |> set #versionNumber payload.penaltyVersionNumber
                        |> set #lastModifiedDatetime payload.penaltyLastModifiedDatetime
                        |> set #rawJson rawValue
                        |> set #syncedAt syncedAt
                        |> createRecord
                    )
            forM_ wageAllowances \(payload, rawValue) ->
                void
                    ( newRecord @FwcMapdWageAllowance
                        |> set #awardFixedId awardFixedId
                        |> set #wageAllowanceFixedId payload.wageAllowanceFixedId
                        |> set #clauseFixedId payload.wageAllowanceClauseFixedId
                        |> set #clauses payload.wageAllowanceClauses
                        |> set #allowance payload.wageAllowance
                        |> set #allowanceType payload.wageAllowanceType
                        |> set #isAllPurpose payload.wageAllowanceIsAllPurpose
                        |> set #rate payload.wageAllowanceRate
                        |> set #baseRate payload.wageAllowanceBaseRate
                        |> set #basePayRateId payload.wageAllowanceBasePayRateId
                        |> set #rateUnit payload.wageAllowanceRateUnit
                        |> set #allowanceAmount payload.wageAllowanceAmount
                        |> set #paymentFrequency payload.wageAllowancePaymentFrequency
                        |> set #operativeFrom payload.wageAllowanceOperativeFrom
                        |> set #operativeTo payload.wageAllowanceOperativeTo
                        |> set #publishedYear payload.wageAllowancePublishedYear
                        |> set #versionNumber payload.wageAllowanceVersionNumber
                        |> set #lastModifiedDatetime payload.wageAllowanceLastModifiedDatetime
                        |> set #rawJson rawValue
                        |> set #syncedAt syncedAt
                        |> createRecord
                    )
            populateAwardLevelProjection awardFixedId syncedAt

        let fetchedAwardCount = sum (map (length . (.curatedAwards)) fetchedAwards)
        let fetchedClassificationCount = sum (map (length . (.curatedClassifications)) fetchedAwards)
        let fetchedPayRateCount = sum (map (length . (.curatedPayRates)) fetchedAwards)
        let fetchedPenaltyRateCount = sum (map (length . (.curatedPenaltyRates)) fetchedAwards)
        let fetchedWageAllowanceCount = sum (map (length . (.curatedWageAllowances)) fetchedAwards)
        pure
            MapdSyncSummary
                { syncedAwardFixedIds = requestedAwardIds
                , fetchedAwardCount = fetchedAwardCount
                , fetchedClassificationCount = fetchedClassificationCount
                , fetchedPayRateCount = fetchedPayRateCount
                , fetchedPenaltyRateCount = fetchedPenaltyRateCount
                , fetchedWageAllowanceCount = fetchedWageAllowanceCount
                }

clearExistingCache :: (?modelContext :: ModelContext) => [Int] -> IO ()
clearExistingCache _awardFixedIds = do
    -- FWC projections reference raw MAPD rows. Keep both append-only so historical
    -- award rates and staff/shift award-level references survive refreshes.
    pure ()

