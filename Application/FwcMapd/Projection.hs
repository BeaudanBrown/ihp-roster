module Application.FwcMapd.Projection where

import Application.FwcMapd.Curation
import Control.Monad (foldM, void)
import qualified Data.Map.Strict as Map
import Data.Scientific (Scientific)
import qualified Data.Set as Set
import Generated.Types
import IHP.ControllerPrelude

populateAwardLevelProjection :: (?modelContext :: ModelContext) => Int -> UTCTime -> IO ()
populateAwardLevelProjection awardFixedId syncedAt = do
    classifications <-
        query @FwcMapdClassification
            |> filterWhere (#awardFixedId, awardFixedId)
            |> filterWhere (#syncedAt, syncedAt)
            |> orderByAsc #classification
            |> fetch
    markMissingAwardLevelsInactive awardFixedId (Set.fromList (map (.classificationFixedId) classifications))
    awardLevels <- forM classifications (upsertAwardLevel syncedAt)

    let awardLevelByClassificationFixedId =
            Map.fromList
                (map (\awardLevel -> (awardLevel.classificationFixedId, awardLevel)) awardLevels)

    payRates <-
        query @FwcMapdPayRate
            |> filterWhere (#awardFixedId, awardFixedId)
            |> filterWhere (#syncedAt, syncedAt)
            |> orderByAsc #classification
            |> fetch
    let awardLevelByBasePayRateId =
            payRates
                |> mapMaybe
                    ( \payRate -> do
                        basePayRateId <- payRate.basePayRateId
                        awardLevel <- payRate.classificationFixedId >>= (`Map.lookup` awardLevelByClassificationFixedId)
                        pure (basePayRateId, awardLevel)
                    )
                |> Map.fromList
        payRateByBasePayRateId =
            payRates
                |> mapMaybe
                    ( \payRate -> do
                        basePayRateId <- payRate.basePayRateId
                        pure (basePayRateId, payRate)
                    )
                |> Map.fromList
    baseRateSeen <-
        foldM
            (createBaseRateIfNew awardLevelByClassificationFixedId)
            Set.empty
            payRates

    penaltyRates <-
        query @FwcMapdPenaltyRate
            |> filterWhere (#awardFixedId, awardFixedId)
            |> filterWhere (#syncedAt, syncedAt)
            |> orderByAsc #classification
            |> fetch
    void $
        foldM
            (createCasualBaseRateIfNew awardLevelByBasePayRateId payRateByBasePayRateId)
            baseRateSeen
            penaltyRates
    void $
        foldM
            (createPenaltyRateIfNew awardLevelByClassificationFixedId awardLevelByBasePayRateId)
            Set.empty
            penaltyRates
    populateTimePenaltyAllowances awardFixedId syncedAt

markMissingAwardLevelsInactive :: (?modelContext :: ModelContext) => Int -> Set.Set Int -> IO ()
markMissingAwardLevelsInactive awardFixedId currentClassificationFixedIds = do
    existingAwardLevels <-
        query @AwardLevel
            |> filterWhere (#awardFixedId, awardFixedId)
            |> fetch
    forM_ existingAwardLevels \awardLevel ->
        when (awardLevel.isActive && not (Set.member awardLevel.classificationFixedId currentClassificationFixedIds)) do
            void (awardLevel |> set #isActive False |> updateRecord)

upsertAwardLevel :: (?modelContext :: ModelContext) => UTCTime -> FwcMapdClassification -> IO AwardLevel
upsertAwardLevel syncedAt classification = do
    existingAwardLevel <-
        query @AwardLevel
            |> filterWhere (#awardFixedId, classification.awardFixedId)
            |> filterWhere (#classificationFixedId, classification.classificationFixedId)
            |> fetchOneOrNothing
    case existingAwardLevel of
        Just awardLevel ->
            awardLevel
                |> set #classification classification.classification
                |> set #classificationLevel classification.classificationLevel
                |> set #parentClassificationName classification.parentClassificationName
                |> set #clauseDescription classification.clauseDescription
                |> set #operativeFrom classification.operativeFrom
                |> set #operativeTo classification.operativeTo
                |> set #publishedYear classification.publishedYear
                |> set #isActive True
                |> set #rawJson classification.rawJson
                |> set #syncedAt syncedAt
                |> updateRecord
        Nothing ->
            newRecord @AwardLevel
                |> set #awardFixedId classification.awardFixedId
                |> set #classificationFixedId classification.classificationFixedId
                |> set #classification classification.classification
                |> set #classificationLevel classification.classificationLevel
                |> set #parentClassificationName classification.parentClassificationName
                |> set #clauseDescription classification.clauseDescription
                |> set #operativeFrom classification.operativeFrom
                |> set #operativeTo classification.operativeTo
                |> set #publishedYear classification.publishedYear
                |> set #isActive True
                |> set #rawJson classification.rawJson
                |> set #syncedAt syncedAt
                |> createRecord

createBaseRateIfNew ::
    (?modelContext :: ModelContext) =>
    Map.Map Int AwardLevel ->
    Set.Set (UUID, StaffEmploymentBasisEnum, Maybe Day, Maybe Day) ->
    FwcMapdPayRate ->
    IO (Set.Set (UUID, StaffEmploymentBasisEnum, Maybe Day, Maybe Day))
createBaseRateIfNew awardLevelByClassificationFixedId seen payRate =
    case (payRate.classificationFixedId >>= (`Map.lookup` awardLevelByClassificationFixedId), ordinaryHourlyRate payRate) of
        (Just awardLevel, Just (employmentBasis, hourlyRate, rateLabel)) -> do
            let key = (unpackId awardLevel.id, employmentBasis, payRate.operativeFrom, payRate.operativeTo)
            if Set.member key seen
                then pure seen
                else do
                    upsertBaseRate
                        awardLevel
                        employmentBasis
                        (unpackId payRate.id)
                        hourlyRate
                        rateLabel
                        payRate.operativeFrom
                        payRate.operativeTo
                        payRate.publishedYear
                    pure (Set.insert key seen)
        _ -> pure seen

createCasualBaseRateIfNew ::
    (?modelContext :: ModelContext) =>
    Map.Map Text AwardLevel ->
    Map.Map Text FwcMapdPayRate ->
    Set.Set (UUID, StaffEmploymentBasisEnum, Maybe Day, Maybe Day) ->
    FwcMapdPenaltyRate ->
    IO (Set.Set (UUID, StaffEmploymentBasisEnum, Maybe Day, Maybe Day))
createCasualBaseRateIfNew awardLevelByBasePayRateId payRateByBasePayRateId seen penaltyRate =
    case (penaltyRate.basePayRateId, penaltyRate.penaltyCalculatedValue) of
        (Just basePayRateId, Just hourlyRate)
            | isCasualOrdinaryPenaltyRate penaltyRate ->
                case (Map.lookup basePayRateId awardLevelByBasePayRateId, Map.lookup basePayRateId payRateByBasePayRateId) of
                    (Just awardLevel, Just sourcePayRate) -> do
                        let key = (unpackId awardLevel.id, Casual, penaltyRate.operativeFrom, penaltyRate.operativeTo)
                        if Set.member key seen
                            then pure seen
                            else do
                                upsertBaseRate
                                    awardLevel
                                    Casual
                                    (unpackId sourcePayRate.id)
                                    hourlyRate
                                    "Casual ordinary hours"
                                    penaltyRate.operativeFrom
                                    penaltyRate.operativeTo
                                    penaltyRate.publishedYear
                                pure (Set.insert key seen)
                    _ -> pure seen
        _ -> pure seen

createPenaltyRateIfNew ::
    (?modelContext :: ModelContext) =>
    Map.Map Int AwardLevel ->
    Map.Map Text AwardLevel ->
    Set.Set (UUID, StaffEmploymentBasisEnum, AwardPenaltyKindEnum, Maybe Day, Maybe Day) ->
    FwcMapdPenaltyRate ->
    IO (Set.Set (UUID, StaffEmploymentBasisEnum, AwardPenaltyKindEnum, Maybe Day, Maybe Day))
createPenaltyRateIfNew awardLevelByClassificationFixedId awardLevelByBasePayRateId seen penaltyRate =
    case (resolvePenaltyAwardLevel awardLevelByClassificationFixedId awardLevelByBasePayRateId penaltyRate, normalisePenaltyKindFromRecord penaltyRate, penaltyRate.penaltyCalculatedValue) of
        (Just awardLevel, Just penaltyKind, Just hourlyRate) -> do
            let employmentBasis = penaltyEmploymentBasisFromRecord penaltyRate
                key = (unpackId awardLevel.id, employmentBasis, penaltyKind, penaltyRate.operativeFrom, penaltyRate.operativeTo)
            if Set.member key seen
                then pure seen
                else do
                    upsertPenaltyRate
                        awardLevel
                        employmentBasis
                        penaltyKind
                        (unpackId penaltyRate.id)
                        hourlyRate
                        penaltyRate.operativeFrom
                        penaltyRate.operativeTo
                        penaltyRate.publishedYear
                    pure (Set.insert key seen)
        _ -> pure seen

upsertBaseRate ::
    (?modelContext :: ModelContext) =>
    AwardLevel ->
    StaffEmploymentBasisEnum ->
    UUID ->
    Scientific ->
    Text ->
    Maybe Day ->
    Maybe Day ->
    Maybe Int ->
    IO ()
upsertBaseRate awardLevel employmentBasis fwcMapdPayRateId hourlyRate rateLabel operativeFrom operativeTo publishedYear = do
    existingBaseRate <-
        query @AwardLevelBaseRate
            |> filterWhere (#awardLevelId, unpackId awardLevel.id)
            |> filterWhere (#employmentBasis, employmentBasis)
            |> filterWhere (#operativeFrom, operativeFrom)
            |> filterWhere (#operativeTo, operativeTo)
            |> fetchOneOrNothing
    void case existingBaseRate of
        Just baseRate ->
            baseRate
                |> set #fwcMapdPayRateId fwcMapdPayRateId
                |> set #hourlyRate hourlyRate
                |> set #rateLabel rateLabel
                |> set #publishedYear publishedYear
                |> updateRecord
        Nothing ->
            newRecord @AwardLevelBaseRate
                |> set #awardLevelId (unpackId awardLevel.id)
                |> set #employmentBasis employmentBasis
                |> set #fwcMapdPayRateId fwcMapdPayRateId
                |> set #hourlyRate hourlyRate
                |> set #rateLabel rateLabel
                |> set #operativeFrom operativeFrom
                |> set #operativeTo operativeTo
                |> set #publishedYear publishedYear
                |> createRecord

upsertPenaltyRate ::
    (?modelContext :: ModelContext) =>
    AwardLevel ->
    StaffEmploymentBasisEnum ->
    AwardPenaltyKindEnum ->
    UUID ->
    Scientific ->
    Maybe Day ->
    Maybe Day ->
    Maybe Int ->
    IO ()
upsertPenaltyRate awardLevel employmentBasis penaltyKind fwcMapdPenaltyRateId hourlyRate operativeFrom operativeTo publishedYear = do
    existingPenaltyRate <-
        query @AwardLevelPenaltyRate
            |> filterWhere (#awardLevelId, unpackId awardLevel.id)
            |> filterWhere (#employmentBasis, employmentBasis)
            |> filterWhere (#penaltyKind, penaltyKind)
            |> filterWhere (#operativeFrom, operativeFrom)
            |> filterWhere (#operativeTo, operativeTo)
            |> fetchOneOrNothing
    void case existingPenaltyRate of
        Just penaltyRate ->
            penaltyRate
                |> set #fwcMapdPenaltyRateId fwcMapdPenaltyRateId
                |> set #hourlyRate hourlyRate
                |> set #startsAtTime (penaltyWindowStart penaltyKind)
                |> set #endsAtTime (penaltyWindowEnd penaltyKind)
                |> set #publishedYear publishedYear
                |> updateRecord
        Nothing ->
            newRecord @AwardLevelPenaltyRate
                |> set #awardLevelId (unpackId awardLevel.id)
                |> set #employmentBasis employmentBasis
                |> set #penaltyKind penaltyKind
                |> set #fwcMapdPenaltyRateId fwcMapdPenaltyRateId
                |> set #hourlyRate hourlyRate
                |> set #startsAtTime (penaltyWindowStart penaltyKind)
                |> set #endsAtTime (penaltyWindowEnd penaltyKind)
                |> set #operativeFrom operativeFrom
                |> set #operativeTo operativeTo
                |> set #publishedYear publishedYear
                |> createRecord

populateTimePenaltyAllowances :: (?modelContext :: ModelContext) => Int -> UTCTime -> IO ()
populateTimePenaltyAllowances awardFixedId syncedAt = do
    wageAllowances <-
        query @FwcMapdWageAllowance
            |> filterWhere (#awardFixedId, awardFixedId)
            |> filterWhere (#syncedAt, syncedAt)
            |> orderByAsc #createdAt
            |> fetch
    void $
        foldM
            createTimePenaltyAllowanceIfNew
            Set.empty
            wageAllowances

createTimePenaltyAllowanceIfNew ::
    (?modelContext :: ModelContext) =>
    Set.Set (Int, AwardPenaltyKindEnum, Maybe Day, Maybe Day) ->
    FwcMapdWageAllowance ->
    IO (Set.Set (Int, AwardPenaltyKindEnum, Maybe Day, Maybe Day))
createTimePenaltyAllowanceIfNew seen wageAllowance =
    case (normaliseTimePenaltyKindFromWageAllowance wageAllowance, wageAllowance.allowanceAmount) of
        (Just penaltyKind, Just hourlyAmount) -> do
            let key = (wageAllowance.awardFixedId, penaltyKind, wageAllowance.operativeFrom, wageAllowance.operativeTo)
            if Set.member key seen
                then pure seen
                else do
                    upsertTimePenaltyAllowance wageAllowance penaltyKind hourlyAmount
                    pure (Set.insert key seen)
        _ -> pure seen

upsertTimePenaltyAllowance ::
    (?modelContext :: ModelContext) =>
    FwcMapdWageAllowance ->
    AwardPenaltyKindEnum ->
    Scientific ->
    IO ()
upsertTimePenaltyAllowance wageAllowance penaltyKind hourlyAmount = do
    existingAllowance <-
        query @AwardTimePenaltyAllowance
            |> filterWhere (#awardFixedId, wageAllowance.awardFixedId)
            |> filterWhere (#penaltyKind, penaltyKind)
            |> filterWhere (#operativeFrom, wageAllowance.operativeFrom)
            |> filterWhere (#operativeTo, wageAllowance.operativeTo)
            |> fetchOneOrNothing
    void case existingAllowance of
        Just allowance ->
            allowance
                |> set #fwcMapdWageAllowanceId (unpackId wageAllowance.id)
                |> set #ratePercent wageAllowance.rate
                |> set #hourlyAmount hourlyAmount
                |> set #startsAtTime (penaltyWindowStart penaltyKind)
                |> set #endsAtTime (penaltyWindowEnd penaltyKind)
                |> set #publishedYear wageAllowance.publishedYear
                |> updateRecord
        Nothing ->
            newRecord @AwardTimePenaltyAllowance
                |> set #awardFixedId wageAllowance.awardFixedId
                |> set #penaltyKind penaltyKind
                |> set #fwcMapdWageAllowanceId (unpackId wageAllowance.id)
                |> set #ratePercent wageAllowance.rate
                |> set #hourlyAmount hourlyAmount
                |> set #startsAtTime (penaltyWindowStart penaltyKind)
                |> set #endsAtTime (penaltyWindowEnd penaltyKind)
                |> set #operativeFrom wageAllowance.operativeFrom
                |> set #operativeTo wageAllowance.operativeTo
                |> set #publishedYear wageAllowance.publishedYear
                |> createRecord

resolvePenaltyAwardLevel :: Map.Map Int AwardLevel -> Map.Map Text AwardLevel -> FwcMapdPenaltyRate -> Maybe AwardLevel
resolvePenaltyAwardLevel awardLevelByClassificationFixedId awardLevelByBasePayRateId penaltyRate =
    case penaltyRate.basePayRateId >>= (`Map.lookup` awardLevelByBasePayRateId) of
        Just awardLevel -> Just awardLevel
        Nothing         -> penaltyRate.classificationFixedId >>= (`Map.lookup` awardLevelByClassificationFixedId)

