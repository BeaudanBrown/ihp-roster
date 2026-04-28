module Application.Helper.XeroPayItems
    ( deriveXeroPayItemRequirements
    , deriveXeroLocalEarningsBuckets
    , deriveXeroUsedAwardPayScopes
    , syncXeroPayItemRequirementRecords
    , xeroManagedPayItemNamePrefix
    , isXeroManagedPayItemName
    ) where

import Application.Helper.XeroAdminTypes
import Control.Monad (void)
import qualified Data.List as List
import qualified Data.Scientific as Scientific
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (inputValue, unpackId)

deriveXeroPayItemRequirements ::
    [XeroUsedAwardPayScope] ->
    [AwardLevel] ->
    [AwardLevelBaseRate] ->
    [AwardLevelPenaltyRate] ->
    [AwardTimePenaltyAllowance] ->
    [XeroEarningsRate] ->
    [XeroPayItemRequirement]
deriveXeroPayItemRequirements usedScopes awardLevels baseRates penaltyRates timeAllowances xeroEarningsRates =
    map attachMatch $
        dedupeRequirementsByKey $
            concatMap ordinaryRequirement baseRows
                ++ map penaltyRequirement penaltyRows
                ++ concatMap timeAllowanceRequirements baseRows
    where
        activeAwardLevels = filter (.isActive) awardLevels
        baseRows = filter rowIsUsed (awardBaseRows activeAwardLevels baseRates)
        penaltyRows = filter rowIsUsed (awardPenaltyRows activeAwardLevels penaltyRates)
        rowIsUsed row =
            XeroUsedAwardPayScope
                { usedAwardLevelId = row.awardLevelId
                , usedEmploymentBasis = row.employmentBasis
                } `elem` usedScopes

        attachMatch requirement =
            let match = findMatchingEarningsRate requirement.payItemRequirementName xeroEarningsRates
             in requirement
                    { payItemRequirementMatch = match
                    , payItemRequirementRecord = Nothing
                    , payItemRequirementStatus =
                        case match of
                            Just _  -> "matched"
                            Nothing -> "proposed"
                    }

        ordinaryRequirement row =
            [ requirement
                (requiredPayItemKey row OrdinaryCondition)
                (requiredPayItemName row OrdinaryCondition)
                Nothing
                "ORDINARYTIMEEARNINGS"
                "RATEPERUNIT"
                Nothing
                (Just row.hourlyRate)
                (Just (formatRate row.hourlyRate))
                "Ordinary hourly rate from FWC award level and employment basis"
            ]

        penaltyRequirement row =
            requirement
                (requiredPayItemKey row row.condition)
                (requiredPayItemName row row.condition)
                (penaltyKindValue row.condition)
                "ORDINARYTIMEEARNINGS"
                "RATEPERUNIT"
                Nothing
                (Just row.hourlyRate)
                (Just (formatRate row.hourlyRate))
                "Full hourly penalty rate from FWC award level and employment basis"

        timeAllowanceRequirements row =
            timeAllowances
                |> filter (\allowance -> allowance.awardFixedId == row.awardFixedId)
                |> filter (\allowance -> allowance.hourlyAmount > 0)
                |> filter (\allowance -> allowance.penaltyKind `elem` timeAllowancePenaltyKinds)
                |> map (\allowance ->
                    requirement
                        (requiredPayItemKey row (PenaltyCondition allowance.penaltyKind))
                        (requiredPayItemName row (PenaltyCondition allowance.penaltyKind))
                        (Just (inputValue allowance.penaltyKind))
                        "ORDINARYTIMEEARNINGS"
                        "RATEPERUNIT"
                        Nothing
                        (Just allowance.hourlyAmount)
                        (Just (formatRate allowance.hourlyAmount))
                        "Flat hourly loading from FWC time allowance"
                )

deriveXeroLocalEarningsBuckets ::
    [XeroUsedAwardPayScope] ->
    [AwardLevel] ->
    [AwardLevelBaseRate] ->
    [AwardLevelPenaltyRate] ->
    [AwardTimePenaltyAllowance] ->
    [XeroLocalEarningsBucket]
deriveXeroLocalEarningsBuckets usedScopes awardLevels baseRates penaltyRates timeAllowances =
    dedupeBucketsByKey $
        concatMap ordinaryBucket baseRows
            ++ map penaltyBucket penaltyRows
            ++ concatMap timeAllowanceBuckets baseRows
    where
        activeAwardLevels = filter (.isActive) awardLevels
        baseRows = filter rowIsUsed (awardBaseRows activeAwardLevels baseRates)
        penaltyRows = filter rowIsUsed (awardPenaltyRows activeAwardLevels penaltyRates)
        rowIsUsed row =
            XeroUsedAwardPayScope
                { usedAwardLevelId = row.awardLevelId
                , usedEmploymentBasis = row.employmentBasis
                } `elem` usedScopes

        ordinaryBucket row =
            [bucket row OrdinaryCondition]

        penaltyBucket row =
            bucket row row.condition

        timeAllowanceBuckets row =
            timeAllowances
                |> filter (\allowance -> allowance.awardFixedId == row.awardFixedId)
                |> filter (\allowance -> allowance.hourlyAmount > 0)
                |> filter (\allowance -> allowance.penaltyKind `elem` timeAllowancePenaltyKinds)
                |> map (\allowance -> bucket row (PenaltyCondition allowance.penaltyKind))

        bucket row condition =
            XeroLocalEarningsBucket
                { localBucketKey = requiredPayItemKey row condition
                , localBucketLabel = localPayItemLabel row condition
                }

data AwardPayItemRow = AwardPayItemRow
    { awardLevelId         :: UUID
    , awardFixedId          :: Int
    , classificationFixedId :: Int
    , classification        :: Text
    , employmentBasis       :: StaffEmploymentBasisEnum
    , condition             :: PayItemCondition
    , hourlyRate            :: Scientific.Scientific
    }

data PayItemCondition
    = OrdinaryCondition
    | PenaltyCondition AwardPenaltyKindEnum
    deriving (Eq)

awardBaseRows ::
    [AwardLevel] ->
    [AwardLevelBaseRate] ->
    [AwardPayItemRow]
awardBaseRows awardLevels baseRates =
    baseRates
        |> mapMaybe rowForBaseRate
    where
        rowForBaseRate baseRate = do
            awardLevel <- List.find (\level -> unpackId level.id == baseRate.awardLevelId) awardLevels
            pure AwardPayItemRow
                { awardLevelId = baseRate.awardLevelId
                , awardFixedId = awardLevel.awardFixedId
                , classificationFixedId = awardLevel.classificationFixedId
                , classification = awardLevel.classification
                , employmentBasis = baseRate.employmentBasis
                , condition = OrdinaryCondition
                , hourlyRate = baseRate.hourlyRate
                }

awardPenaltyRows ::
    [AwardLevel] ->
    [AwardLevelPenaltyRate] ->
    [AwardPayItemRow]
awardPenaltyRows awardLevels penaltyRates =
    penaltyRates
        |> filter (\penaltyRate -> penaltyRate.penaltyKind `elem` penaltyPayItemKinds)
        |> mapMaybe rowForPenaltyRate
    where
        rowForPenaltyRate penaltyRate = do
            awardLevel <- List.find (\level -> unpackId level.id == penaltyRate.awardLevelId) awardLevels
            pure AwardPayItemRow
                { awardLevelId = penaltyRate.awardLevelId
                , awardFixedId = awardLevel.awardFixedId
                , classificationFixedId = awardLevel.classificationFixedId
                , classification = awardLevel.classification
                , employmentBasis = penaltyRate.employmentBasis
                , condition = PenaltyCondition penaltyRate.penaltyKind
                , hourlyRate = penaltyRate.hourlyRate
                }

penaltyPayItemKinds :: [AwardPenaltyKindEnum]
penaltyPayItemKinds =
    [ SaturdayPenalty
    , SundayPenalty
    , PublicHolidayPenalty
    ]

timeAllowancePenaltyKinds :: [AwardPenaltyKindEnum]
timeAllowancePenaltyKinds =
    [ EveningAfter7Pm
    , LateNightAfterMidnight
    ]

requiredPayItemKey :: AwardPayItemRow -> PayItemCondition -> Text
requiredPayItemKey row condition =
    "xero:pay-item:classification:"
        <> tshow row.classificationFixedId
        <> ":basis:"
        <> inputValue row.employmentBasis
        <> ":"
        <> conditionKey condition

requiredPayItemName :: AwardPayItemRow -> PayItemCondition -> Text
requiredPayItemName row condition =
    xeroManagedPayItemName (localPayItemLabel row condition)

xeroManagedPayItemNamePrefix :: Text
xeroManagedPayItemNamePrefix = "Bepis - "

xeroManagedPayItemName :: Text -> Text
xeroManagedPayItemName label =
    xeroManagedPayItemNamePrefix <> label

isXeroManagedPayItemName :: Text -> Bool
isXeroManagedPayItemName =
    Text.isPrefixOf (Text.toCaseFold xeroManagedPayItemNamePrefix) . Text.toCaseFold

localPayItemLabel :: AwardPayItemRow -> PayItemCondition -> Text
localPayItemLabel row condition =
    row.classification
        <> " ("
        <> inputValue row.employmentBasis
        <> ") - "
        <> conditionLabel condition

conditionKey :: PayItemCondition -> Text
conditionKey OrdinaryCondition = "ordinary"
conditionKey (PenaltyCondition penaltyKind) = "penalty:" <> inputValue penaltyKind

conditionLabel :: PayItemCondition -> Text
conditionLabel OrdinaryCondition = "Ordinary"
conditionLabel (PenaltyCondition SaturdayPenalty) = "Saturday Penalty"
conditionLabel (PenaltyCondition SundayPenalty) = "Sunday Penalty"
conditionLabel (PenaltyCondition PublicHolidayPenalty) = "Public Holiday Penalty"
conditionLabel (PenaltyCondition EveningAfter7Pm) = "Evening After 7pm Loading"
conditionLabel (PenaltyCondition LateNightAfterMidnight) = "Late Night After Midnight Loading"

penaltyKindValue :: PayItemCondition -> Maybe Text
penaltyKindValue OrdinaryCondition = Nothing
penaltyKindValue (PenaltyCondition penaltyKind) = Just (inputValue penaltyKind)

deriveXeroUsedAwardPayScopes :: [Staff] -> [ShiftType] -> [XeroUsedAwardPayScope]
deriveXeroUsedAwardPayScopes staffMembers shiftTypes =
    List.nub (staffScopes ++ shiftOverrideScopes)
    where
        activeStaff =
            staffMembers
                |> filter (.isActive)
                |> filter (isNothing . (.archivedAt))
        activeShiftTypes =
            shiftTypes
                |> filter (.isActive)
                |> filter (isNothing . (.archivedAt))
        activeStaffEmploymentBases =
            List.nub (map (.employmentBasis) activeStaff)
        staffScopes =
            activeStaff
                |> mapMaybe \staff -> do
                    awardLevelId <- staff.defaultAwardLevelId
                    pure XeroUsedAwardPayScope
                        { usedAwardLevelId = unpackId awardLevelId
                        , usedEmploymentBasis = staff.employmentBasis
                        }
        shiftOverrideScopes =
            activeShiftTypes
                |> concatMap \shiftType ->
                    case shiftType.overrideAwardLevelId of
                        Nothing -> []
                        Just awardLevelId ->
                            activeStaffEmploymentBases
                                |> map \employmentBasis ->
                                    XeroUsedAwardPayScope
                                        { usedAwardLevelId = unpackId awardLevelId
                                        , usedEmploymentBasis = employmentBasis
                                        }

syncXeroPayItemRequirementRecords ::
    (?modelContext :: ModelContext) =>
    Id XeroConnection ->
    Id Venue ->
    Maybe (Id User) ->
    [XeroPayItemRequirement] ->
    IO [XeroPayItemRequirement]
syncXeroPayItemRequirementRecords connectionId venueId maybeActorUserId requirements = do
    now <- getCurrentTime
    let dedupedRequirements = dedupeRequirementsByKey requirements
    existingRecords <-
        query @XeroPayItemRequirementRecord
            |> filterWhere (#venueId, unpackId venueId)
            |> filterWhere (#xeroConnectionId, unpackId connectionId)
            |> fetch
    savedRecords <- mapM (upsertRequirementRecord now existingRecords) dedupedRequirements
    let activeKeys = map (.payItemRequirementKey) dedupedRequirements
    mapM_ (markStaleIfMissing now activeKeys) existingRecords
    pure (zipWith attachRecord dedupedRequirements savedRecords)
    where
        upsertRequirementRecord now existingRecords requirement = do
            let existing = List.find (\record -> record.requirementKey == requirement.payItemRequirementKey) existingRecords
            let prepared record =
                    record
                        |> set #venueId (unpackId venueId)
                        |> set #xeroConnectionId (unpackId connectionId)
                        |> set #requirementKey requirement.payItemRequirementKey
                        |> set #displayName requirement.payItemRequirementName
                        |> set #penaltyKind requirement.payItemRequirementPenaltyKind
                        |> set #earningsType requirement.payItemRequirementEarningsType
                        |> set #rateType requirement.payItemRequirementRateType
                        |> set #multiplier requirement.payItemRequirementMultiplier
                        |> set #ratePerUnit requirement.payItemRequirementRatePerUnit
                        |> set #sourceDescription requirement.payItemRequirementSource
                        |> set #requirementStatus (statusFor requirement existing)
                        |> set #xeroEarningsRateId ((.xeroEarningsRateId) <$> requirement.payItemRequirementMatch)
                        |> set #xeroEarningsRateName ((.name) <$> requirement.payItemRequirementMatch)
                        |> set #xeroEarningsRateRateType (requirement.payItemRequirementMatch >>= (.rateType))
                        |> set #lastVerifiedAt (if hasXeroMatch requirement then Just now else Nothing)
                        |> set #updatedByUserId (unpackId <$> maybeActorUserId)
            case existing of
                Just record -> prepared record |> updateRecord
                Nothing ->
                    prepared (newRecord @XeroPayItemRequirementRecord)
                        |> set #createdByUserId (unpackId <$> maybeActorUserId)
                        |> createRecord

        markStaleIfMissing now activeKeys record =
            when (record.requirementKey `notElem` activeKeys && record.requirementStatus /= "stale") do
                void $
                    record
                        |> set #requirementStatus "stale"
                        |> set #updatedByUserId (unpackId <$> maybeActorUserId)
                        |> set #updatedAt now
                        |> updateRecord

        attachRecord requirement record =
            requirement
                { payItemRequirementRecord = Just record
                , payItemRequirementStatus = record.requirementStatus
                }

statusFor :: XeroPayItemRequirement -> Maybe XeroPayItemRequirementRecord -> Text
statusFor requirement existing
    | hasXeroMatch requirement && maybe False (existingExpectedValueChanged requirement) existing = "rate_changed"
    | hasXeroMatch requirement && maybe False (xeroRateTypeChanged requirement) requirement.payItemRequirementMatch = "rate_changed"
    | hasXeroMatch requirement && maybe False (\record -> record.requirementStatus == "created") existing = "created"
    | hasXeroMatch requirement = "matched"
    | maybe False (\record -> record.requirementStatus == "ignored") existing = "ignored"
    | otherwise = "proposed"

hasXeroMatch :: XeroPayItemRequirement -> Bool
hasXeroMatch requirement =
    isJust requirement.payItemRequirementMatch

existingExpectedValueChanged :: XeroPayItemRequirement -> XeroPayItemRequirementRecord -> Bool
existingExpectedValueChanged requirement record =
    record.requirementStatus `elem` ["matched", "created", "rate_changed"]
        && ( record.rateType /= requirement.payItemRequirementRateType
            || record.multiplier /= requirement.payItemRequirementMultiplier
            || record.ratePerUnit /= requirement.payItemRequirementRatePerUnit
           )

xeroRateTypeChanged :: XeroPayItemRequirement -> XeroEarningsRate -> Bool
xeroRateTypeChanged requirement earningsRate =
    maybe False (\rateType -> Text.toCaseFold rateType /= Text.toCaseFold requirement.payItemRequirementRateType) earningsRate.rateType

requirement :: Text -> Text -> Maybe Text -> Text -> Text -> Maybe Scientific.Scientific -> Maybe Scientific.Scientific -> Maybe Text -> Text -> XeroPayItemRequirement
requirement key name penaltyKind earningsType rateType multiplier ratePerUnit value source =
    XeroPayItemRequirement
        { payItemRequirementKey = key
        , payItemRequirementName = name
        , payItemRequirementPenaltyKind = penaltyKind
        , payItemRequirementEarningsType = earningsType
        , payItemRequirementRateType = rateType
        , payItemRequirementMultiplier = multiplier
        , payItemRequirementRatePerUnit = ratePerUnit
        , payItemRequirementValue = value
        , payItemRequirementSource = source
        , payItemRequirementMatch = Nothing
        , payItemRequirementRecord = Nothing
        , payItemRequirementStatus = "proposed"
        }

findMatchingEarningsRate :: Text -> [XeroEarningsRate] -> Maybe XeroEarningsRate
findMatchingEarningsRate requirementName
    | isXeroManagedPayItemName requirementName =
        List.find
            (\earningsRate ->
                isXeroManagedPayItemName earningsRate.name
                    && Text.toCaseFold earningsRate.name == Text.toCaseFold requirementName
            )
    | otherwise = const Nothing

dedupeRequirementsByKey :: [XeroPayItemRequirement] -> [XeroPayItemRequirement]
dedupeRequirementsByKey =
    List.nubBy (\left right -> left.payItemRequirementKey == right.payItemRequirementKey)

dedupeBucketsByKey :: [XeroLocalEarningsBucket] -> [XeroLocalEarningsBucket]
dedupeBucketsByKey =
    List.nubBy (\left right -> left.localBucketKey == right.localBucketKey)

formatRate :: Scientific.Scientific -> Text
formatRate value =
    "$" <> Text.pack (Scientific.formatScientific Scientific.Fixed (Just 4) value) <> "/hr"
