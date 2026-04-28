module Application.Helper.XeroPayItems
    ( deriveXeroPayItemRequirements
    , syncXeroPayItemRequirementRecords
    ) where

import Application.Helper.XeroAdminTypes
import Control.Monad (guard, void)
import qualified Data.List as List
import qualified Data.Scientific as Scientific
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (inputValue, unpackId)

deriveXeroPayItemRequirements ::
    [AwardLevel] ->
    [AwardLevelBaseRate] ->
    [AwardLevelPenaltyRate] ->
    [AwardTimePenaltyAllowance] ->
    [XeroEarningsRate] ->
    [XeroPayItemRequirement]
deriveXeroPayItemRequirements awardLevels baseRates penaltyRates timeAllowances xeroEarningsRates =
    map attachMatch $
        ordinaryRequirement activeAwardLevels
            ++ concatMap multiplierRequirements multiplierPenaltyKinds
            ++ concatMap timeAllowanceRequirements timeAllowancePenaltyKinds
    where
        activeAwardLevels = filter (.isActive) awardLevels

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

        multiplierRequirements (penaltyKind, keySuffix, displayName) =
            let rows = penaltyMultiplierRows activeAwardLevels baseRates penaltyRates penaltyKind
                distinctMultipliers = stableDistinct (map (.multiplier) rows)
             in case distinctMultipliers of
                    [] -> []
                    [multiplier] ->
                        [ requirement
                            ("xero:pay-item:" <> keySuffix)
                            displayName
                            (Just (inputValue penaltyKind))
                            "ORDINARYTIMEEARNINGS"
                            "MULTIPLE"
                            (Just multiplier)
                            Nothing
                            (Just (formatMultiplier multiplier))
                            ("Stable multiplier from " <> tshow (length rows) <> " award level rates")
                        ]
                    _ ->
                        map
                            (\row ->
                                requirement
                                    ("xero:pay-item:" <> keySuffix <> ":classification:" <> tshow row.classificationFixedId)
                                    (displayName <> " - " <> row.classification)
                                    (Just (inputValue penaltyKind))
                                    "ORDINARYTIMEEARNINGS"
                                    "RATEPERUNIT"
                                    Nothing
                                    (Just row.hourlyRate)
                                    (Just (formatRate row.hourlyRate))
                                    "Classification fallback required; multiplier differs across award levels"
                            )
                            rows

        timeAllowanceRequirements (penaltyKind, keySuffix, displayName) =
            activeAllowances
                |> filter (\allowance -> allowance.penaltyKind == penaltyKind)
                |> List.nubBy (\a b -> a.awardFixedId == b.awardFixedId && a.hourlyAmount == b.hourlyAmount)
                |> map (\allowance ->
                    requirement
                        ("xero:pay-item:" <> keySuffix <> ":award:" <> tshow allowance.awardFixedId <> ":amount:" <> formatRate allowance.hourlyAmount)
                        displayName
                        (Just (inputValue penaltyKind))
                        "ORDINARYTIMEEARNINGS"
                        "RATEPERUNIT"
                        Nothing
                        (Just allowance.hourlyAmount)
                        (Just (formatRate allowance.hourlyAmount))
                        "Flat hourly loading from FWC time allowance"
                )

        activeAllowances =
            filter (\allowance -> allowance.hourlyAmount > 0) timeAllowances

ordinaryRequirement [] = []
ordinaryRequirement _ =
    [ requirement
        "xero:pay-item:ordinary"
        "Ordinary Hours"
        Nothing
        "ORDINARYTIMEEARNINGS"
        "RATEPERUNIT"
        Nothing
        Nothing
        Nothing
        "Base ordinary earnings rate; usually assigned as the employee ordinary earnings rate in Xero"
    ]

data PenaltyMultiplierRow = PenaltyMultiplierRow
    { classificationFixedId :: Int
    , classification        :: Text
    , multiplier            :: Scientific.Scientific
    , hourlyRate            :: Scientific.Scientific
    }

penaltyMultiplierRows ::
    [AwardLevel] ->
    [AwardLevelBaseRate] ->
    [AwardLevelPenaltyRate] ->
    AwardPenaltyKindEnum ->
    [PenaltyMultiplierRow]
penaltyMultiplierRows awardLevels baseRates penaltyRates penaltyKind =
    penaltyRates
        |> filter (\penaltyRate -> penaltyRate.penaltyKind == penaltyKind)
        |> mapMaybe rowForPenaltyRate
    where
        rowForPenaltyRate penaltyRate = do
            awardLevel <- List.find (\level -> unpackId level.id == penaltyRate.awardLevelId) awardLevels
            baseRate <-
                List.find
                    (\base ->
                        base.awardLevelId == penaltyRate.awardLevelId
                            && base.employmentBasis == penaltyRate.employmentBasis
                    )
                    baseRates
            guard (baseRate.hourlyRate > 0)
            pure PenaltyMultiplierRow
                { classificationFixedId = awardLevel.classificationFixedId
                , classification = awardLevel.classification
                , multiplier = penaltyRate.hourlyRate / baseRate.hourlyRate
                , hourlyRate = penaltyRate.hourlyRate
                }

multiplierPenaltyKinds :: [(AwardPenaltyKindEnum, Text, Text)]
multiplierPenaltyKinds =
    [ (SaturdayPenalty, "saturday", "Saturday Penalty")
    , (SundayPenalty, "sunday", "Sunday Penalty")
    , (PublicHolidayPenalty, "public-holiday", "Public Holiday Penalty")
    ]

timeAllowancePenaltyKinds :: [(AwardPenaltyKindEnum, Text, Text)]
timeAllowancePenaltyKinds =
    [ (EveningAfter7Pm, "evening-after-7pm", "Evening After 7pm Loading")
    , (LateNightAfterMidnight, "late-night-after-midnight", "Late Night After Midnight Loading")
    ]

syncXeroPayItemRequirementRecords ::
    (?modelContext :: ModelContext) =>
    Id XeroConnection ->
    Id Venue ->
    Maybe (Id User) ->
    [XeroPayItemRequirement] ->
    IO [XeroPayItemRequirement]
syncXeroPayItemRequirementRecords connectionId venueId maybeActorUserId requirements = do
    now <- getCurrentTime
    existingRecords <-
        query @XeroPayItemRequirementRecord
            |> filterWhere (#venueId, unpackId venueId)
            |> filterWhere (#xeroConnectionId, unpackId connectionId)
            |> fetch
    savedRecords <- mapM (upsertRequirementRecord now existingRecords) requirements
    let activeKeys = map (.payItemRequirementKey) requirements
    mapM_ (markStaleIfMissing now activeKeys) existingRecords
    pure (zipWith attachRecord requirements savedRecords)
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
    | hasXeroMatch requirement = "matched"
    | maybe False (\record -> record.requirementStatus == "ignored") existing = "ignored"
    | otherwise = "proposed"

hasXeroMatch :: XeroPayItemRequirement -> Bool
hasXeroMatch requirement =
    isJust requirement.payItemRequirementMatch

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
findMatchingEarningsRate requirementName =
    List.find (\earningsRate -> Text.toCaseFold earningsRate.name == Text.toCaseFold requirementName)

stableDistinct :: [Scientific.Scientific] -> [Scientific.Scientific]
stableDistinct =
    List.nub

formatMultiplier :: Scientific.Scientific -> Text
formatMultiplier value =
    Text.pack (Scientific.formatScientific Scientific.Fixed (Just 4) value) <> "x"

formatRate :: Scientific.Scientific -> Text
formatRate value =
    "$" <> Text.pack (Scientific.formatScientific Scientific.Fixed (Just 4) value) <> "/hr"
