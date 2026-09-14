-- Provider-catalogue projection only. This module may describe Xero pay-item
-- keys and rates, but must never calculate per-entry quantities or totals;
-- those belong exclusively to Application.WageEvaluation and sealed ledgers.
module Application.Helper.XeroPayItems
    ( deriveXeroPayItemRequirements
    , deriveXeroUsedAwardPayScopes
    , syncXeroPayItemRequirementRecords
    , xeroManagedPayItemNamePrefix
    , isXeroManagedPayItemName
    ) where

import Application.Helper.Pay (venueEffectiveRateDate,
                               venueEffectiveRateEndDate)
import Application.Helper.WeekBoundaries (WeekdayIndex)
import Application.Helper.XeroAdminTypes
import Application.WageEngine (ProjectionRateSource (..), RateSourceIdentity,
                               projectionRateSourceIdentity)
import Application.Xero.PayrollSourceKey (sourceRateSuffix)
import Application.Xero.WorkflowState (xeroPayItemRequirementIsIgnored,
                                       xeroPayItemRequirementIsUsable)
import Control.Monad (void, zipWithM_)
import qualified Data.List as List
import qualified Data.Scientific as Scientific
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude

deriveXeroPayItemRequirements ::
    WeekdayIndex ->
    Day ->
    [XeroUsedAwardPayScope] ->
    [AwardLevel] ->
    [AwardLevelBaseRate] ->
    [AwardLevelPenaltyRate] ->
    [AwardTimePenaltyAllowance] ->
    [XeroEarningsRate] ->
    [XeroPayItemRequirement]
deriveXeroPayItemRequirements weekStartsOn today usedScopes awardLevels baseRates penaltyRates timeAllowances xeroEarningsRates =
    map attachMatch $
        dedupeRequirementsByKey $
            concatMap ordinaryRequirement baseRows
                ++ map penaltyRequirement penaltyRows
                ++ concatMap timeAllowanceRequirements baseRows
                ++ map missedMealBreakRequirement baseRows
    where
        activeAwardLevels = filter (.isActive) awardLevels
        allBaseRows = awardBaseRows weekStartsOn activeAwardLevels baseRates
        baseRows = filter rowIsUsed allBaseRows
        penaltyRows = filter rowIsUsed (awardPenaltyRows weekStartsOn activeAwardLevels penaltyRates)
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
                            Just _  -> Matched
                            Nothing -> XeroPayItemRequirementStatusEnumProposed
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
                            , operativeFrom = venueEffectiveRateDate weekStartsOn <$> allowance.operativeFrom
                            , operativeTo = venueEffectiveRateEndDate weekStartsOn allowance.operativeTo
                            , sourceIdentity = projectionRateSourceIdentity (AwardTimePenaltyAllowanceSource (unpackId allowance.id) allowance.fwcMapdWageAllowanceId)
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
                        (Just (formatCommencedHourRate allowance.hourlyAmount))
                        "Fixed commenced-hour addition from FWC clause 29.2 time allowance"
                )

        missedMealBreakRequirement row =
            let permanentRow = permanentBaseRowFor allBaseRows row
                missedRate = permanentRow.hourlyRate * 0.5
             in requirement
                    today
                    permanentRow.operativeFrom
                    permanentRow.operativeTo
                    (missedMealBreakKey permanentRow missedRate)
                    ("Missed Meal Break 50% Addition - " <> row.classification <> " - " <> xeroManagedPayItemNameBrand <> " - " <> effectiveDateLabel row.operativeFrom)
                    (Just "missed_meal_break_addition")
                    "ORDINARYTIMEEARNINGS"
                    "RATEPERUNIT"
                    Nothing
                    (Just missedRate)
                    (Just (formatRate missedRate))
                    "HIGA missed meal break addition: 50% of the permanent ordinary classification rate"

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
    , sourceIdentity        :: RateSourceIdentity
    }

data PayItemCondition
    = OrdinaryCondition
    | PenaltyCondition AwardPenaltyKindEnum
    deriving (Eq)

awardBaseRows ::
    WeekdayIndex ->
    [AwardLevel] ->
    [AwardLevelBaseRate] ->
    [AwardPayItemRow]
awardBaseRows weekStartsOn awardLevels baseRates =
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
                , operativeFrom = venueEffectiveRateDate weekStartsOn <$> baseRate.operativeFrom
                , operativeTo = venueEffectiveRateEndDate weekStartsOn baseRate.operativeTo
                , sourceIdentity = projectionRateSourceIdentity (AwardLevelBaseRateSource (unpackId baseRate.id) baseRate.fwcMapdPayRateId)
                }

awardPenaltyRows ::
    WeekdayIndex ->
    [AwardLevel] ->
    [AwardLevelPenaltyRate] ->
    [AwardPayItemRow]
awardPenaltyRows weekStartsOn awardLevels penaltyRates =
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
                , operativeFrom = venueEffectiveRateDate weekStartsOn <$> penaltyRate.operativeFrom
                , operativeTo = venueEffectiveRateEndDate weekStartsOn penaltyRate.operativeTo
                , sourceIdentity = projectionRateSourceIdentity (AwardLevelPenaltyRateSource (unpackId penaltyRate.id) penaltyRate.fwcMapdPenaltyRateId)
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

permanentBaseRowFor :: [AwardPayItemRow] -> AwardPayItemRow -> AwardPayItemRow
permanentBaseRowFor allBaseRows row =
    allBaseRows
        |> List.find exactPermanentMatch
        |> (<|> List.find anyPermanentMatch allBaseRows)
        |> fromMaybe row
    where
        exactPermanentMatch baseRow =
            anyPermanentMatch baseRow
                && baseRow.operativeFrom == row.operativeFrom
                && baseRow.operativeTo == row.operativeTo
        anyPermanentMatch baseRow =
            baseRow.awardLevelId == row.awardLevelId
                && baseRow.employmentBasis == Permanent

missedMealBreakKey :: AwardPayItemRow -> Scientific.Scientific -> Text
missedMealBreakKey row missedRate =
    "xero:pay-item:classification:"
        <> tshow row.classificationFixedId
        <> ":effective:"
        <> effectiveDateKey row.operativeFrom
        <> ":penalty:missed_meal_break_addition"
        <> sourceRateSuffix (Just row.sourceIdentity) missedRate

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
        <> sourceRateSuffix (Just row.sourceIdentity) row.hourlyRate

requiredPayItemName :: AwardPayItemRow -> Text
requiredPayItemName row =
    xeroManagedPayItemName (localPayItemLabel row)

xeroManagedPayItemNamePrefix :: Text
xeroManagedPayItemNamePrefix = xeroManagedPayItemNameBrand <> " - "

xeroManagedPayItemNameBrand :: Text
xeroManagedPayItemNameBrand = "Bepis"

xeroManagedPayItemName :: Text -> Text
xeroManagedPayItemName label = label

isXeroManagedPayItemName :: Text -> Bool
isXeroManagedPayItemName name =
    let foldedName = Text.toCaseFold name
        foldedLegacyPrefix = Text.toCaseFold xeroManagedPayItemNamePrefix
        foldedBrandSegment = Text.toCaseFold (" - " <> xeroManagedPayItemNameBrand <> " - ")
     in Text.isPrefixOf foldedLegacyPrefix foldedName || foldedBrandSegment `Text.isInfixOf` foldedName

localPayItemLabel :: AwardPayItemRow -> Text
localPayItemLabel row =
    conditionLabel row.condition
        <> " - "
        <> row.classification
        <> " - "
        <> employmentBasisLabel row.employmentBasis
        <> " - "
        <> xeroManagedPayItemNameBrand
        <> " - "
        <> effectiveDateLabel row.operativeFrom

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
    zipWithM_ (upsertMatchedEarningsRateMapping now) dedupedRequirements savedRecords
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
            when (record.requirementKey `notElem` activeKeys && record.requirementStatus /= XeroPayItemRequirementStatusEnumStale) do
                void $
                    record
                        |> set #requirementStatus XeroPayItemRequirementStatusEnumStale
                        |> set #updatedByUserId (unpackId <$> maybeActorUserId)
                        |> set #updatedAt now
                        |> updateRecord

        attachRecord requirement record =
            requirement
                { payItemRequirementRecord = Just record
                , payItemRequirementStatus = record.requirementStatus
                }

        upsertMatchedEarningsRateMapping now requirement record =
            case requirement.payItemRequirementMatch of
                Just earningsRate
                    | xeroPayItemRequirementIsUsable record.requirementStatus -> do
                        existingMapping <-
                            query @XeroEarningsRateMapping
                                |> filterWhere (#venueId, unpackId venueId)
                                |> filterWhere (#xeroConnectionId, unpackId connectionId)
                                |> filterWhere (#localBucketKey, requirement.payItemRequirementKey)
                                |> fetchOneOrNothing
                        let localBucketLabel = fromMaybe requirement.payItemRequirementName (Text.stripPrefix xeroManagedPayItemNamePrefix requirement.payItemRequirementName)
                        let prepared mapping =
                                mapping
                                    |> set #venueId (unpackId venueId)
                                    |> set #xeroConnectionId (unpackId connectionId)
                                    |> set #localBucketKey requirement.payItemRequirementKey
                                    |> set #localBucketLabel localBucketLabel
                                    |> set #xeroEarningsRateId (Just earningsRate.xeroEarningsRateId)
                                    |> set #xeroEarningsRateName (Just earningsRate.name)
                                    |> set #mappingStatus XeroEarningsRateMappingStatusEnumVerified
                                    |> set #lastVerifiedAt (Just now)
                                    |> set #updatedByUserId (unpackId <$> maybeActorUserId)
                        case existingMapping of
                            Just mapping -> prepared mapping |> updateRecord |> void
                            Nothing ->
                                prepared (newRecord @XeroEarningsRateMapping)
                                    |> set #createdByUserId (unpackId <$> maybeActorUserId)
                                    |> createRecord
                                    |> void
                _ -> pure ()

statusFor :: XeroPayItemRequirement -> Maybe XeroPayItemRequirementRecord -> XeroPayItemRequirementStatusEnum
statusFor requirement existing
    | hasXeroMatch requirement && maybe False (existingExpectedValueChanged requirement) existing = RateChanged
    | hasXeroMatch requirement && maybe False (xeroRateTypeChanged requirement) requirement.payItemRequirementMatch = RateChanged
    | hasXeroMatch requirement && maybe False (\record -> record.requirementStatus == XeroPayItemRequirementStatusEnumCreated) existing = XeroPayItemRequirementStatusEnumCreated
    | hasXeroMatch requirement = Matched
    | maybe False (\record -> xeroPayItemRequirementIsIgnored record.requirementStatus) existing = Ignored
    | otherwise = XeroPayItemRequirementStatusEnumProposed

hasXeroMatch :: XeroPayItemRequirement -> Bool
hasXeroMatch requirement =
    isJust requirement.payItemRequirementMatch

existingExpectedValueChanged :: XeroPayItemRequirement -> XeroPayItemRequirementRecord -> Bool
existingExpectedValueChanged requirement record =
    xeroPayItemRequirementIsUsable record.requirementStatus || record.requirementStatus == RateChanged
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
        , payItemRequirementStatus = XeroPayItemRequirementStatusEnumProposed
        }

findMatchingEarningsRate :: Text -> [XeroEarningsRate] -> Maybe XeroEarningsRate
findMatchingEarningsRate requirementName
    | isXeroManagedPayItemName requirementName =
        List.find
            (\earningsRate ->
                isXeroManagedPayItemName earningsRate.name
                    && Text.toCaseFold earningsRate.name `elem` candidateNames
            )
    | otherwise = const Nothing
    where
        candidateNames = map Text.toCaseFold (requirementName : legacyManagedPayItemNames requirementName)

legacyManagedPayItemNames :: Text -> [Text]
legacyManagedPayItemNames requirementName =
    case Text.splitOn " - " requirementName of
        [condition, classification, basis, brand, effectiveDate]
            | Text.toCaseFold brand == Text.toCaseFold xeroManagedPayItemNameBrand ->
                [ xeroManagedPayItemNamePrefix
                    <> "HIGA - "
                    <> basis
                    <> " - "
                    <> effectiveDate
                    <> " - "
                    <> classification
                    <> " - "
                    <> condition
                ]
        _ -> []

dedupeRequirementsByKey :: [XeroPayItemRequirement] -> [XeroPayItemRequirement]
dedupeRequirementsByKey =
    List.nubBy (\left right -> left.payItemRequirementKey == right.payItemRequirementKey)

formatRate :: Scientific.Scientific -> Text
formatRate value =
    "$" <> Text.pack (Scientific.formatScientific Scientific.Fixed (Just 4) value) <> "/hr"

formatCommencedHourRate :: Scientific.Scientific -> Text
formatCommencedHourRate value =
    "$" <> Text.pack (Scientific.formatScientific Scientific.Fixed (Just 4) value) <> "/commenced hour"
