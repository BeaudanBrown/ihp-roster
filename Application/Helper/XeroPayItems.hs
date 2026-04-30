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
import Data.Time.Calendar (Day)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (inputValue, unpackId)

deriveXeroPayItemRequirements ::
    Day ->
    [XeroUsedAwardPayScope] ->
    [AwardLevel] ->
    [AwardLevelBaseRate] ->
    [AwardLevelPenaltyRate] ->
    [AwardTimePenaltyAllowance] ->
    [XeroEarningsRate] ->
    [XeroPayItemRequirement]
deriveXeroPayItemRequirements today usedScopes awardLevels baseRates penaltyRates timeAllowances xeroEarningsRates =
    map attachMatch $
        dedupeRequirementsByKey $
            concatMap ordinaryRequirement baseRows
                ++ map penaltyRequirement penaltyRows
                ++ concatMap timeAllowanceRequirements baseRows
                ++ concatMap delayedMealBreakRequirements baseRows
    where
        activeAwardLevels = filter (.isActive) awardLevels
        allBaseRows = awardBaseRows activeAwardLevels baseRates
        baseRows = filter rowIsUsed allBaseRows
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
                today
                row.operativeFrom
                row.operativeTo
                (requiredPayItemKey row)
                (requiredPayItemName row)
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
                today
                row.operativeFrom
                row.operativeTo
                (requiredPayItemKey row)
                (requiredPayItemName row)
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
                    let allowanceRow = row
                            { condition = PenaltyCondition allowance.penaltyKind
                            , hourlyRate = allowance.hourlyAmount
                            , operativeFrom = allowance.operativeFrom
                            , operativeTo = allowance.operativeTo
                            }
                     in
                    requirement
                        today
                        allowanceRow.operativeFrom
                        allowanceRow.operativeTo
                        (requiredPayItemKey allowanceRow)
                        (requiredPayItemName allowanceRow)
                        (Just (inputValue allowance.penaltyKind))
                        "ORDINARYTIMEEARNINGS"
                        "RATEPERUNIT"
                        Nothing
                        (Just allowance.hourlyAmount)
                        (Just (formatRate allowance.hourlyAmount))
                        "Flat hourly loading from FWC time allowance"
                )

        delayedMealBreakRequirements row =
            delayedMealBreakRows allBaseRows penaltyRows row
                |> map (\delayedRow ->
                    requirement
                            today
                            delayedRow.operativeFrom
                            delayedRow.operativeTo
                            (requiredPayItemKey delayedRow)
                            (requiredPayItemName delayedRow)
                            (penaltyKindValue delayedRow.condition)
                            "ORDINARYTIMEEARNINGS"
                            "RATEPERUNIT"
                            Nothing
                            (Just delayedRow.hourlyRate)
                            (Just (formatRate delayedRow.hourlyRate))
                            "HIGA delayed meal break rate: applicable day rate plus 50% of permanent ordinary hourly rate"
                )

deriveXeroLocalEarningsBuckets ::
    Day ->
    [XeroUsedAwardPayScope] ->
    [AwardLevel] ->
    [AwardLevelBaseRate] ->
    [AwardLevelPenaltyRate] ->
    [AwardTimePenaltyAllowance] ->
    [XeroLocalEarningsBucket]
deriveXeroLocalEarningsBuckets today usedScopes awardLevels baseRates penaltyRates timeAllowances =
    dedupeBucketsByKey $
        concatMap ordinaryBucket baseRows
            ++ map penaltyBucket penaltyRows
            ++ concatMap timeAllowanceBuckets baseRows
            ++ concatMap delayedMealBreakBuckets baseRows
    where
        activeAwardLevels = filter (.isActive) awardLevels
        allBaseRows = awardBaseRows activeAwardLevels baseRates
        baseRows = filter rowIsUsed (filter (rowIsActiveOn today) allBaseRows)
        penaltyRows = filter rowIsUsed (filter (rowIsActiveOn today) (awardPenaltyRows activeAwardLevels penaltyRates))
        rowIsUsed row =
            XeroUsedAwardPayScope
                { usedAwardLevelId = row.awardLevelId
                , usedEmploymentBasis = row.employmentBasis
                } `elem` usedScopes

        ordinaryBucket row =
            [bucket row]

        penaltyBucket row =
            bucket row

        timeAllowanceBuckets row =
            timeAllowances
                |> filter (\allowance -> allowance.awardFixedId == row.awardFixedId)
                |> filter (\allowance -> allowance.hourlyAmount > 0)
                |> filter (\allowance -> allowance.penaltyKind `elem` timeAllowancePenaltyKinds)
                |> filter (allowanceIsActiveOn today)
                |> map (\allowance ->
                    bucket row
                        { condition = PenaltyCondition allowance.penaltyKind
                        , operativeFrom = allowance.operativeFrom
                        , operativeTo = allowance.operativeTo
                        }
                )

        delayedMealBreakBuckets row =
            delayedMealBreakRows allBaseRows penaltyRows row
                |> filter (rowIsActiveOn today)
                |> map bucket

        bucket row =
            XeroLocalEarningsBucket
                { localBucketKey = requiredPayItemKey row
                , localBucketLabel = localPayItemLabel row
                }

data AwardPayItemRow = AwardPayItemRow
    { awardLevelId          :: UUID
    , awardFixedId          :: Int
    , classificationFixedId :: Int
    , classification        :: Text
    , employmentBasis       :: StaffEmploymentBasisEnum
    , condition             :: PayItemCondition
    , hourlyRate            :: Scientific.Scientific
    , operativeFrom         :: Maybe Day
    , operativeTo           :: Maybe Day
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
                , operativeFrom = baseRate.operativeFrom
                , operativeTo = baseRate.operativeTo
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
                , operativeFrom = penaltyRate.operativeFrom
                , operativeTo = penaltyRate.operativeTo
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

delayedMealBreakPenaltyKinds :: [AwardPenaltyKindEnum]
delayedMealBreakPenaltyKinds =
    [ DelayedMealBreakWeekday
    , DelayedMealBreakSaturday
    , DelayedMealBreakSunday
    , DelayedMealBreakPublicHoliday
    ]

delayedMealBreakRows :: [AwardPayItemRow] -> [AwardPayItemRow] -> AwardPayItemRow -> [AwardPayItemRow]
delayedMealBreakRows allBaseRows penaltyRows row =
    weekdayRow : weekendRows
    where
        weekdayRow =
            row
                { condition = PenaltyCondition DelayedMealBreakWeekday
                , hourlyRate = row.hourlyRate + permanentBaseRateFor allBaseRows row * 0.5
                }
        weekendRows =
            delayedMealBreakDayPairs
                |> mapMaybe \(sourceKind, delayedKind) -> do
                    sourceRow <-
                        penaltyRows
                            |> List.find
                                ( \penaltyRow ->
                                    penaltyRow.awardLevelId == row.awardLevelId
                                        && penaltyRow.employmentBasis == row.employmentBasis
                                        && penaltyRow.condition == PenaltyCondition sourceKind
                                        && penaltyRow.operativeFrom == row.operativeFrom
                                )
                    pure sourceRow
                        { condition = PenaltyCondition delayedKind
                        , hourlyRate = sourceRow.hourlyRate + permanentBaseRateFor allBaseRows sourceRow * 0.5
                        }

delayedMealBreakDayPairs :: [(AwardPenaltyKindEnum, AwardPenaltyKindEnum)]
delayedMealBreakDayPairs =
    [ (SaturdayPenalty, DelayedMealBreakSaturday)
    , (SundayPenalty, DelayedMealBreakSunday)
    , (PublicHolidayPenalty, DelayedMealBreakPublicHoliday)
    ]

permanentBaseRateFor :: [AwardPayItemRow] -> AwardPayItemRow -> Scientific.Scientific
permanentBaseRateFor allBaseRows row =
    allBaseRows
        |> List.find exactPermanentMatch
        |> (<|> List.find anyPermanentMatch allBaseRows)
        |> maybe row.hourlyRate (.hourlyRate)
    where
        exactPermanentMatch baseRow =
            anyPermanentMatch baseRow
                && baseRow.operativeFrom == row.operativeFrom
                && baseRow.operativeTo == row.operativeTo
        anyPermanentMatch baseRow =
            baseRow.awardLevelId == row.awardLevelId
                && baseRow.employmentBasis == Permanent

rowIsActiveOn :: Day -> AwardPayItemRow -> Bool
rowIsActiveOn today row =
    maybe True (<= today) row.operativeFrom
        && maybe True (>= today) row.operativeTo

allowanceIsActiveOn :: Day -> AwardTimePenaltyAllowance -> Bool
allowanceIsActiveOn today allowance =
    maybe True (<= today) allowance.operativeFrom
        && maybe True (>= today) allowance.operativeTo

requiredPayItemKey :: AwardPayItemRow -> Text
requiredPayItemKey row =
    "xero:pay-item:classification:"
        <> tshow row.classificationFixedId
        <> ":basis:"
        <> inputValue row.employmentBasis
        <> ":effective:"
        <> effectiveDateKey row.operativeFrom
        <> ":"
        <> conditionKey row.condition

requiredPayItemName :: AwardPayItemRow -> Text
requiredPayItemName row =
    xeroManagedPayItemName (localPayItemLabel row)

xeroManagedPayItemNamePrefix :: Text
xeroManagedPayItemNamePrefix = "Bepis - "

xeroManagedPayItemName :: Text -> Text
xeroManagedPayItemName label =
    xeroManagedPayItemNamePrefix <> label

isXeroManagedPayItemName :: Text -> Bool
isXeroManagedPayItemName =
    Text.isPrefixOf (Text.toCaseFold xeroManagedPayItemNamePrefix) . Text.toCaseFold

localPayItemLabel :: AwardPayItemRow -> Text
localPayItemLabel row =
    awardLabel row.awardFixedId
        <> " - "
        <> employmentBasisLabel row.employmentBasis
        <> " - "
        <> effectiveDateLabel row.operativeFrom
        <> " - "
        <> row.classification
        <> " - "
        <> conditionLabel row.condition

awardLabel :: Int -> Text
awardLabel 9            = "HIGA"
awardLabel awardFixedId = "Award " <> tshow awardFixedId

employmentBasisLabel :: StaffEmploymentBasisEnum -> Text
employmentBasisLabel Permanent = "PERM"
employmentBasisLabel Casual    = "CAS"

effectiveDateKey :: Maybe Day -> Text
effectiveDateKey Nothing    = "undated"
effectiveDateKey (Just day) = tshow day

effectiveDateLabel :: Maybe Day -> Text
effectiveDateLabel Nothing    = "Undated"
effectiveDateLabel (Just day) = Text.strip (Text.pack (formatTime defaultTimeLocale "%e-%B-%Y" day))

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
conditionLabel (PenaltyCondition DelayedMealBreakWeekday) = "M-F Delayed Meal Break"
conditionLabel (PenaltyCondition DelayedMealBreakSaturday) = "Saturday Delayed Meal Break"
conditionLabel (PenaltyCondition DelayedMealBreakSunday) = "Sunday Delayed Meal Break"
conditionLabel (PenaltyCondition DelayedMealBreakPublicHoliday) = "Public Holiday Delayed Meal Break"

penaltyKindValue :: PayItemCondition -> Maybe Text
penaltyKindValue OrdinaryCondition              = Nothing
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

requirement :: Day -> Maybe Day -> Maybe Day -> Text -> Text -> Maybe Text -> Text -> Text -> Maybe Scientific.Scientific -> Maybe Scientific.Scientific -> Maybe Text -> Text -> XeroPayItemRequirement
requirement today effectiveFrom effectiveTo key name penaltyKind earningsType rateType multiplier ratePerUnit value source =
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
        , payItemRequirementEffectiveFrom = effectiveFrom
        , payItemRequirementEffectiveTo = effectiveTo
        , payItemRequirementIsActive =
            maybe True (<= today) effectiveFrom
                && maybe True (>= today) effectiveTo
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
