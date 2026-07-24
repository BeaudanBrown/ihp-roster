module Application.FwcMapd.Curation where

import Application.FwcMapd.Payload
import Application.Helper.FwcMapd (searchableTextFields)
import qualified Data.Aeson as Aeson
import Data.Scientific (Scientific)
import qualified Data.Set as Set
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude
import IHP.Prelude

data AwardYearScope
    = AllAwardYears
    | LatestActiveAwardYear
    deriving (Eq, Show)

data MapdCurationProfile = MapdCurationProfile
    { awardYearScope        :: !AwardYearScope
    , employeeRateTypeCodes :: ![Text]
    , requireHourlyRate     :: !Bool
    , excludedKeywords      :: ![Text]
    , includedKeywords      :: ![Text]
    }
    deriving (Eq, Show)

barVenueCurationProfile :: MapdCurationProfile
barVenueCurationProfile =
    MapdCurationProfile
        { awardYearScope = LatestActiveAwardYear
        , employeeRateTypeCodes = ["AD"]
        , requireHourlyRate = True
        , excludedKeywords =
            [ "apprentice"
            , "apprenticeship"
            , "trainee"
            , "training"
            , "junior"
            , "years of age"
            , "casino"
            , "gaming"
            , "surveillance"
            , "airport catering"
            , "loadedrates"
            ]
        , includedKeywords =
            [ "introductory level"
            , "food and beverage attendant"
            , "food and beverage supervisor"
            , "kitchen attendant"
            , "cook"
            , "bar attendant"
            , "bar"
            ]
        }

ordinaryHourlyRate :: FwcMapdPayRate -> Maybe (StaffEmploymentBasisEnum, Scientific, Text)
ordinaryHourlyRate payRate
    | isHourlyRateType payRate.calculatedRateType =
        fmap
            (\hourlyRate -> (basisFromRateType payRate.calculatedRateType, hourlyRate, fromMaybe "Hourly" payRate.calculatedRateType))
            payRate.calculatedRate
    | isHourlyRateType payRate.baseRateType =
        fmap
            (\hourlyRate -> (basisFromRateType payRate.baseRateType, hourlyRate, fromMaybe "Hourly" payRate.baseRateType))
            payRate.baseRate
    | otherwise = Nothing

basisFromRateType :: Maybe Text -> StaffEmploymentBasisEnum
basisFromRateType maybeRateType =
    if maybe False (Text.isInfixOf "casual" . Text.toLower) maybeRateType
        then Casual
        else Permanent

normalisePenaltyKindFromRecord :: FwcMapdPenaltyRate -> Maybe AwardPenaltyKindEnum
normalisePenaltyKindFromRecord penaltyRate =
    normalisePenaltyKindText
        (Text.intercalate " " [fromMaybe "" penaltyRate.penaltyDescription, fromMaybe "" penaltyRate.penaltyText, fromMaybe "" penaltyRate.clauseDescription])

normalisePenaltyKind :: PenaltyRatePayload -> Maybe AwardPenaltyKindEnum
normalisePenaltyKind penaltyRate =
    normalisePenaltyKindText
        (Text.intercalate " " [fromMaybe "" penaltyRate.penaltyDescription, fromMaybe "" penaltyRate.penaltyText])

normaliseTimePenaltyKindFromWageAllowance :: FwcMapdWageAllowance -> Maybe AwardPenaltyKindEnum
normaliseTimePenaltyKindFromWageAllowance wageAllowance =
    case normalisePenaltyKindText (searchableWageAllowanceRecordText wageAllowance) of
        Just EveningAfter7Pm        -> Just EveningAfter7Pm
        Just LateNightAfterMidnight -> Just LateNightAfterMidnight
        _                           -> Nothing

normaliseTimePenaltyKind :: WageAllowancePayload -> Maybe AwardPenaltyKindEnum
normaliseTimePenaltyKind wageAllowance =
    case normalisePenaltyKindText (searchableWageAllowanceText wageAllowance) of
        Just EveningAfter7Pm        -> Just EveningAfter7Pm
        Just LateNightAfterMidnight -> Just LateNightAfterMidnight
        _                           -> Nothing

normalisePenaltyKindText :: Text -> Maybe AwardPenaltyKindEnum
normalisePenaltyKindText rawText
    | containsAny ["public holiday", "public holidays"] text = Just PublicHolidayPenalty
    | containsAny ["saturday"] text = Just SaturdayPenalty
    | containsAny ["sunday"] text = Just SundayPenalty
    | containsAny ["7.00 pm", "7pm", "after 7", "evening"] text = Just EveningAfter7Pm
    | containsAny ["midnight", "after 12", "after midnight"] text = Just LateNightAfterMidnight
    | otherwise = Nothing
    where
        text = Text.toLower rawText

containsAny :: [Text] -> Text -> Bool
containsAny needles haystack =
    any (`Text.isInfixOf` haystack) needles

penaltyEmploymentBasisFromRecord :: FwcMapdPenaltyRate -> StaffEmploymentBasisEnum
penaltyEmploymentBasisFromRecord penaltyRate =
    if containsAny ["casual"] (Text.toLower (Text.intercalate " " [fromMaybe "" penaltyRate.penaltyDescription, fromMaybe "" penaltyRate.penaltyText, fromMaybe "" penaltyRate.clauseDescription]))
        then Casual
        else Permanent

isCasualOrdinaryPenaltyRate :: FwcMapdPenaltyRate -> Bool
isCasualOrdinaryPenaltyRate penaltyRate =
    containsAny ["casual"] searchableText
        && containsAny ["ordinary hours"] searchableText
        && not (containsAny ["overtime"] searchableText)
    where
        searchableText =
            Text.toLower
                (Text.intercalate " " [fromMaybe "" penaltyRate.penaltyDescription, fromMaybe "" penaltyRate.penaltyText, fromMaybe "" penaltyRate.clauseDescription])

penaltyWindowStart :: AwardPenaltyKindEnum -> Maybe TimeOfDay
penaltyWindowStart EveningAfter7Pm        = Just (TimeOfDay 19 0 0)
penaltyWindowStart LateNightAfterMidnight = Just (TimeOfDay 0 0 0)
penaltyWindowStart _                      = Nothing

penaltyWindowEnd :: AwardPenaltyKindEnum -> Maybe TimeOfDay
penaltyWindowEnd EveningAfter7Pm        = Just (TimeOfDay 0 0 0)
penaltyWindowEnd LateNightAfterMidnight = Just (TimeOfDay 7 0 0)
penaltyWindowEnd _                      = Nothing


curateAwardData ::
    MapdCurationProfile ->
    Day ->
    (Int, [(AwardPayload, Aeson.Value)], [(ClassificationPayload, Aeson.Value)], [(PayRatePayload, Aeson.Value)], [(PenaltyRatePayload, Aeson.Value)]) ->
    (Int, [(AwardPayload, Aeson.Value)], [(ClassificationPayload, Aeson.Value)], [(PayRatePayload, Aeson.Value)], [(PenaltyRatePayload, Aeson.Value)])
curateAwardData profile asOfDate (awardFixedId, awards, classifications, payRates, penaltyRates) =
    (awardFixedId, retainedAwards, retainedClassifications, retainedPayRates, retainedPenaltyRates)
    where
        activeAwards = filter (isActiveAwardOn asOfDate . fst) awards
        activeClassifications = filter (isActiveClassificationOn asOfDate . fst) classifications
        activePayRates = filter (isActivePayRateOn asOfDate . fst) payRates
        activePenaltyRates = filter (isActivePenaltyRateOn asOfDate . fst) penaltyRates
        scopedAwards = applyAwardYearScope profile.awardYearScope (.publishedYear) activeAwards
        scopedClassifications = applyAwardYearScope profile.awardYearScope (.publishedYear) activeClassifications
        scopedPayRates = applyAwardYearScope profile.awardYearScope (.publishedYear) activePayRates
        scopedPenaltyRates = applyAwardYearScope profile.awardYearScope (.penaltyPublishedYear) activePenaltyRates
        relevantClassificationIds =
            scopedClassifications
                |> filter (isRelevantClassification profile . fst)
                |> map (classificationPayloadFixedId . fst)
                |> Set.fromList
        retainedPayRates =
            scopedPayRates
                |> filter (\(payload, _) -> maybe False (`Set.member` relevantClassificationIds) (payRatePayloadClassificationFixedId payload))
                |> filter (isRelevantPayRate profile . fst)
        retainedBasePayRateIds =
            retainedPayRates
                |> mapMaybe (\(payload, _) -> payload.basePayRateId)
                |> Set.fromList
        retainedPenaltyRates =
            scopedPenaltyRates
                |> filter (\(payload, _) -> maybe False (`Set.member` retainedBasePayRateIds) payload.penaltyBasePayRateId)
                |> filter (\(payload, _) -> isRelevantPenaltyRate profile payload || isRelevantCasualOrdinaryPenaltyRate profile payload)
        retainedClassificationIds =
            mapMaybe (\(payload, _) -> payRatePayloadClassificationFixedId payload) retainedPayRates
                |> Set.fromList
        retainedClassifications =
            scopedClassifications
                |> filter (\(payload, _) -> Set.member (classificationPayloadFixedId payload) retainedClassificationIds)
        retainedAwards = scopedAwards

classificationPayloadFixedId :: ClassificationPayload -> Int
classificationPayloadFixedId payload = payload.classificationFixedId

payRatePayloadClassificationFixedId :: PayRatePayload -> Maybe Int
payRatePayloadClassificationFixedId payload = payload.classificationFixedId

applyAwardYearScope :: AwardYearScope -> (a -> Maybe Int) -> [(a, Aeson.Value)] -> [(a, Aeson.Value)]
applyAwardYearScope AllAwardYears _ values = values
applyAwardYearScope LatestActiveAwardYear yearOf values =
    case maximumMaybe (mapMaybe (yearOf . fst) values) of
        Nothing -> values
        Just latestYear ->
            filter (\(payload, _) -> yearOf payload == Just latestYear) values

maximumMaybe :: Ord a => [a] -> Maybe a
maximumMaybe []     = Nothing
maximumMaybe values = Just (maximum values)

isRelevantPayRate :: MapdCurationProfile -> PayRatePayload -> Bool
isRelevantPayRate profile payRate =
    isIncludedRateType
        && hourlyOk
        && matchesCurationText profile searchableText
    where
        isIncludedRateType = payRate.employeeRateTypeCode `elem` map Just profile.employeeRateTypeCodes
        hourlyOk = not profile.requireHourlyRate || hasHourlyAmount payRate
        searchableText = searchablePayRateText payRate

isRelevantPenaltyRate :: MapdCurationProfile -> PenaltyRatePayload -> Bool
isRelevantPenaltyRate profile penaltyRate =
    isIncludedRateType
        && hasPayablePenaltyAmount penaltyRate
        && not (containsAny ["overtime"] searchableText)
        && not (hasAnyKeyword profile.excludedKeywords searchableText)
        && isJust (normalisePenaltyKind penaltyRate)
    where
        isIncludedRateType = penaltyRate.penaltyEmployeeRateTypeCode `elem` map Just profile.employeeRateTypeCodes
        searchableText = searchablePenaltyRateText penaltyRate

isRelevantCasualOrdinaryPenaltyRate :: MapdCurationProfile -> PenaltyRatePayload -> Bool
isRelevantCasualOrdinaryPenaltyRate profile penaltyRate =
    isIncludedRateType
        && hasPayablePenaltyAmount penaltyRate
        && containsAny ["casual"] searchableText
        && containsAny ["ordinary hours"] searchableText
        && not (containsAny ["overtime"] searchableText)
        && not (hasAnyKeyword profile.excludedKeywords searchableText)
    where
        isIncludedRateType = penaltyRate.penaltyEmployeeRateTypeCode `elem` map Just profile.employeeRateTypeCodes
        searchableText = searchablePenaltyRateText penaltyRate

curateWageAllowances :: MapdCurationProfile -> Day -> [(WageAllowancePayload, Aeson.Value)] -> [(WageAllowancePayload, Aeson.Value)]
curateWageAllowances profile asOfDate wageAllowances =
    wageAllowances
        |> filter (isActiveWageAllowanceOn asOfDate . fst)
        |> applyAwardYearScope profile.awardYearScope (.wageAllowancePublishedYear)
        |> filter (isRelevantWageAllowance profile . fst)

isRelevantWageAllowance :: MapdCurationProfile -> WageAllowancePayload -> Bool
isRelevantWageAllowance profile wageAllowance =
    hasPayableWageAllowanceAmount wageAllowance
        && not (hasAnyKeyword profile.excludedKeywords searchableText)
        && isJust (normaliseTimePenaltyKind wageAllowance)
    where
        searchableText = searchableWageAllowanceText wageAllowance

isRelevantClassification :: MapdCurationProfile -> ClassificationPayload -> Bool
isRelevantClassification profile classification =
    matchesCurationText profile (searchableClassificationText classification)

matchesCurationText :: MapdCurationProfile -> Text -> Bool
matchesCurationText profile searchableText =
    not (hasAnyKeyword profile.excludedKeywords searchableText)
        && hasAnyKeyword profile.includedKeywords searchableText

hasHourlyAmount :: PayRatePayload -> Bool
hasHourlyAmount payRate =
    (isHourlyRateType payRate.calculatedRateType && isJust payRate.calculatedRate)
        || (isHourlyRateType payRate.baseRateType && isJust payRate.baseRate)

isHourlyRateType :: Maybe Text -> Bool
isHourlyRateType =
    maybe False (\rateType -> Text.toLower rateType `elem` ["hourly", "casual hourly"])

hasPayablePenaltyAmount :: PenaltyRatePayload -> Bool
hasPayablePenaltyAmount penaltyRate =
    isJust penaltyRate.penaltyCalculatedValue

hasPayableWageAllowanceAmount :: WageAllowancePayload -> Bool
hasPayableWageAllowanceAmount wageAllowance =
    isJust wageAllowance.wageAllowanceAmount

isActiveAwardOn :: Day -> AwardPayload -> Bool
isActiveAwardOn asOfDate award =
    startsOnOrBefore asOfDate award.awardOperativeFrom && endsOnOrAfter asOfDate award.awardOperativeTo

isActiveClassificationOn :: Day -> ClassificationPayload -> Bool
isActiveClassificationOn asOfDate classification =
    startsOnOrBefore asOfDate classification.operativeFrom && endsOnOrAfter asOfDate classification.operativeTo

isActivePayRateOn :: Day -> PayRatePayload -> Bool
isActivePayRateOn asOfDate payRate =
    startsOnOrBefore asOfDate payRate.operativeFrom && endsOnOrAfter asOfDate payRate.operativeTo

isActivePenaltyRateOn :: Day -> PenaltyRatePayload -> Bool
isActivePenaltyRateOn asOfDate penaltyRate =
    startsOnOrBefore asOfDate penaltyRate.penaltyOperativeFrom && endsOnOrAfter asOfDate penaltyRate.penaltyOperativeTo

isActiveWageAllowanceOn :: Day -> WageAllowancePayload -> Bool
isActiveWageAllowanceOn asOfDate wageAllowance =
    startsOnOrBefore asOfDate wageAllowance.wageAllowanceOperativeFrom && endsOnOrAfter asOfDate wageAllowance.wageAllowanceOperativeTo

startsOnOrBefore :: Day -> Maybe Day -> Bool
startsOnOrBefore asOfDate = maybe True (<= asOfDate)

endsOnOrAfter :: Day -> Maybe Day -> Bool
endsOnOrAfter asOfDate = maybe True (>= asOfDate)

searchablePayRateText :: PayRatePayload -> Text
searchablePayRateText payRate =
    searchableTextFields
        [ payRate.classification
        , fromMaybe "" payRate.classificationLevel
        , fromMaybe "" payRate.parentClassificationName
        , fromMaybe "" payRate.employeeRateTypeCode
        , fromMaybe "" payRate.baseRateType
        , fromMaybe "" payRate.calculatedRateType
        ]

searchableClassificationText :: ClassificationPayload -> Text
searchableClassificationText classification =
    searchableTextFields
        [ classification.classification
        , fromMaybe "" classification.classificationLevel
        , fromMaybe "" classification.parentClassificationName
        , fromMaybe "" classification.clauseDescription
        ]

searchablePenaltyRateText :: PenaltyRatePayload -> Text
searchablePenaltyRateText penaltyRate =
    searchableTextFields
        [ penaltyRate.penaltyClassification
        , fromMaybe "" penaltyRate.penaltyClassificationLevel
        , fromMaybe "" penaltyRate.penaltyParentClassificationName
        , fromMaybe "" penaltyRate.penaltyClauseDescription
        , fromMaybe "" penaltyRate.penaltyEmployeeRateTypeCode
        , fromMaybe "" penaltyRate.penaltyDescription
        , fromMaybe "" penaltyRate.penaltyText
        ]

searchableWageAllowanceText :: WageAllowancePayload -> Text
searchableWageAllowanceText wageAllowance =
    searchableTextFields
        [ fromMaybe "" wageAllowance.wageAllowanceClauses
        , fromMaybe "" wageAllowance.wageAllowance
        , fromMaybe "" wageAllowance.wageAllowanceType
        , fromMaybe "" wageAllowance.wageAllowanceRateUnit
        , fromMaybe "" wageAllowance.wageAllowancePaymentFrequency
        ]

searchableWageAllowanceRecordText :: FwcMapdWageAllowance -> Text
searchableWageAllowanceRecordText wageAllowance =
    searchableTextFields
        [ fromMaybe "" wageAllowance.clauses
        , fromMaybe "" wageAllowance.allowance
        , fromMaybe "" wageAllowance.allowanceType
        , fromMaybe "" wageAllowance.rateUnit
        , fromMaybe "" wageAllowance.paymentFrequency
        ]

hasAnyKeyword :: [Text] -> Text -> Bool
hasAnyKeyword keywords searchableText =
    any (`Text.isInfixOf` searchableText) (map Text.toLower keywords)
