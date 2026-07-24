module Application.FwcMapd.Validation where

import Application.FwcMapd.Curation
import Application.FwcMapd.Payload
import Control.Monad (foldM)
import qualified Data.Aeson as Aeson
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Generated.Enums (AwardPenaltyKindEnum (..))
import Generated.Types (StaffEmploymentBasisEnum (..))
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

data ValidatedMapdSnapshot = ValidatedMapdSnapshot
    { validatedAwardFixedId    :: !Int
    , validatedAwards          :: ![(AwardPayload, Aeson.Value)]
    , validatedClassifications :: ![(ClassificationPayload, Aeson.Value)]
    , validatedPayRates        :: ![(PayRatePayload, Aeson.Value)]
    , validatedPenaltyRates    :: ![(PenaltyRatePayload, Aeson.Value)]
    , validatedWageAllowances  :: ![(WageAllowancePayload, Aeson.Value)]
    }
    deriving (Eq, Show)

expectedCoreClassificationFixedIds :: [Int]
expectedCoreClassificationFixedIds = [242, 243, 246, 257, 268, 276, 282]

validateMapdSnapshot :: CuratedMapdAwardData -> Either Text ValidatedMapdSnapshot
validateMapdSnapshot candidate = do
    awards <- normalizeBy "award" (\(payload, _) -> (payload.awardFixedId, payload.publishedYear)) candidate.curatedAwards
    classifications <- normalizeBy "classification" (\(payload, _) -> (payload.classificationFixedId, effectivePeriod payload.operativeFrom payload.operativeTo)) candidate.curatedClassifications
    payRates <- normalizeBy "pay rate" (\(payload, _) -> (payload.basePayRateId, effectivePeriod payload.operativeFrom payload.operativeTo)) candidate.curatedPayRates
    penaltyRates <- normalizeBy "penalty rate" (\(payload, _) -> (payload.penaltyBasePayRateId, payload.penaltyFixedId, effectivePeriod payload.penaltyOperativeFrom payload.penaltyOperativeTo)) candidate.curatedPenaltyRates
    wageAllowances <- normalizeBy "wage allowance" (\(payload, _) -> (payload.wageAllowanceFixedId, effectivePeriod payload.wageAllowanceOperativeFrom payload.wageAllowanceOperativeTo)) candidate.curatedWageAllowances

    when (any (containsAny ["overtime"] . searchablePenaltyRateText . fst) penaltyRates)
        (Left "FWC MAPD snapshot contains out-of-scope overtime source rows")
    validateAwardProvenance candidate.curatedAwardFixedId awards
    validateClassificationSet classifications
    periodsByClassification <- validateCorePayRates classifications payRates
    validateCorePenalties periodsByClassification payRates penaltyRates
    validateTimeAllowances (Set.fromList (Map.elems periodsByClassification)) wageAllowances

    pure
        ValidatedMapdSnapshot
            { validatedAwardFixedId = candidate.curatedAwardFixedId
            , validatedAwards = awards
            , validatedClassifications = classifications
            , validatedPayRates = payRates
            , validatedPenaltyRates = penaltyRates
            , validatedWageAllowances = wageAllowances
            }

normalizeBy :: (Ord key, Show key, Eq payload) => Text -> ((payload, Aeson.Value) -> key) -> [(payload, Aeson.Value)] -> Either Text [(payload, Aeson.Value)]
normalizeBy label identity values =
    Map.elems <$> foldM insertValue Map.empty values
    where
        insertValue accumulated value =
            case Map.lookup (identity value) accumulated of
                Nothing -> Right (Map.insert (identity value) value accumulated)
                Just existing
                    | existing == value -> Right accumulated
                    | otherwise -> Left ("FWC MAPD snapshot conflicting duplicate " <> label <> " identity " <> tshow (identity value))

type EffectivePeriod = (Maybe Day, Maybe Day)

effectivePeriod :: Maybe Day -> Maybe Day -> EffectivePeriod
effectivePeriod = (,)

validateAwardProvenance :: Int -> [(AwardPayload, Aeson.Value)] -> Either Text ()
validateAwardProvenance expectedAwardFixedId = \case
    [] -> Left ("FWC MAPD snapshot incomplete: missing award provenance for award_fixed_id " <> tshow expectedAwardFixedId)
    [(award, _)] -> do
        unless (award.awardFixedId == expectedAwardFixedId)
            (Left ("FWC MAPD snapshot inconsistent: award provenance belongs to award_fixed_id " <> tshow award.awardFixedId <> ", expected " <> tshow expectedAwardFixedId))
        when (award.code == "" || award.name == "")
            (Left ("FWC MAPD snapshot inconsistent: award provenance identity is incomplete for award_fixed_id " <> tshow expectedAwardFixedId))
    _ -> Left ("FWC MAPD snapshot inconsistent: multiple award provenance rows for award_fixed_id " <> tshow expectedAwardFixedId)

validateClassificationSet :: [(ClassificationPayload, Aeson.Value)] -> Either Text ()
validateClassificationSet classifications = do
    forM_ expectedCoreClassificationFixedIds \classificationFixedId ->
        case filter ((== classificationFixedId) . (.classificationFixedId) . fst) classifications of
            []  -> Left ("FWC MAPD snapshot incomplete: missing classification_fixed_id " <> tshow classificationFixedId)
            [_] -> Right ()
            _   -> Left ("FWC MAPD snapshot inconsistent: multiple effective classifications for classification_fixed_id " <> tshow classificationFixedId)
    let unexpected = Set.toAscList (Set.fromList (map ((.classificationFixedId) . fst) classifications) `Set.difference` Set.fromList expectedCoreClassificationFixedIds)
    unless (null unexpected) (Left ("FWC MAPD snapshot inconsistent: unsupported core classification ids " <> tshow unexpected))

validateCorePayRates :: [(ClassificationPayload, Aeson.Value)] -> [(PayRatePayload, Aeson.Value)] -> Either Text (Map.Map Int EffectivePeriod)
validateCorePayRates classifications payRates = do
    entries <- forM expectedCoreClassificationFixedIds \classificationFixedId -> do
        classification <- exactlyOne ("classification " <> tshow classificationFixedId) (filter ((== classificationFixedId) . (.classificationFixedId) . fst) classifications)
        payRate <- exactlyOne ("permanent ordinary/base pay rate for classification " <> tshow classificationFixedId) (filter ((== Just classificationFixedId) . (.classificationFixedId) . fst) payRates)
        basePayRateId <- maybe (Left ("FWC MAPD snapshot inconsistent: missing base_pay_rate_id for classification " <> tshow classificationFixedId)) Right (fst payRate).basePayRateId
        unless (isJust (fst payRate).calculatedPayRateId)
            (Left ("FWC MAPD snapshot inconsistent: missing calculated_pay_rate_id for classification " <> tshow classificationFixedId))
        unless (isJust (ordinaryHourlyRateRecord (fst payRate)))
            (Left ("FWC MAPD snapshot incomplete: missing permanent ordinary/base rate for classification " <> tshow classificationFixedId))
        let classificationPeriod = effectivePeriod (fst classification).operativeFrom (fst classification).operativeTo
            payRatePeriod = effectivePeriod (fst payRate).operativeFrom (fst payRate).operativeTo
        unless (classificationPeriod == payRatePeriod)
            (Left ("FWC MAPD snapshot inconsistent: effective dates differ for classification " <> tshow classificationFixedId))
        pure (classificationFixedId, basePayRateId, payRatePeriod)
    let basePayRateIds = map (\(_, basePayRateId, _) -> basePayRateId) entries
    unless (Set.size (Set.fromList basePayRateIds) == length basePayRateIds)
        (Left "FWC MAPD snapshot inconsistent: base_pay_rate_id belongs to multiple core classifications")
    pure (Map.fromList (map (\(classificationFixedId, _, period) -> (classificationFixedId, period)) entries))
  where
    ordinaryHourlyRateRecord payload
        | payload.employeeRateTypeCode == Just "AD" =
            if isJust payload.calculatedRate && payload.calculatedRateType == Just "Hourly"
                then payload.calculatedRate
                else if isJust payload.baseRate && payload.baseRateType == Just "Hourly" then payload.baseRate else Nothing
        | otherwise = Nothing

validateCorePenalties :: Map.Map Int EffectivePeriod -> [(PayRatePayload, Aeson.Value)] -> [(PenaltyRatePayload, Aeson.Value)] -> Either Text ()
validateCorePenalties periodsByClassification payRates penalties =
    forM_ expectedCoreClassificationFixedIds \classificationFixedId -> do
        payRate <- exactlyOne ("pay rate for classification " <> tshow classificationFixedId) (filter ((== Just classificationFixedId) . (.classificationFixedId) . fst) payRates)
        basePayRateId <- maybe (Left ("FWC MAPD snapshot inconsistent: missing base_pay_rate_id for classification " <> tshow classificationFixedId)) Right (fst payRate).basePayRateId
        expectedPeriod <- maybe (Left "FWC MAPD snapshot internal validation error") Right (Map.lookup classificationFixedId periodsByClassification)
        let owned = filter ((== Just basePayRateId) . (.penaltyBasePayRateId) . fst) penalties
            requiredCategories =
                [ (Casual, Nothing)
                , (Permanent, Just SaturdayPenalty)
                , (Permanent, Just SundayPenalty)
                , (Permanent, Just PublicHolidayPenalty)
                , (Casual, Just SaturdayPenalty)
                , (Casual, Just SundayPenalty)
                , (Casual, Just PublicHolidayPenalty)
                ]
        forM_ requiredCategories \category -> do
            penalty <- exactlyOne ("required " <> categoryLabel category <> " row for classification " <> tshow classificationFixedId) (filter ((== category) . penaltyCategory . fst) owned)
            unless (isJust (fst penalty).penaltyFixedId && isJust (fst penalty).penaltyCalculatedValue)
                (Left ("FWC MAPD snapshot inconsistent: required penalty source identity/value missing for classification " <> tshow classificationFixedId <> " (" <> categoryLabel category <> ")"))
            unless (effectivePeriod (fst penalty).penaltyOperativeFrom (fst penalty).penaltyOperativeTo == expectedPeriod)
                (Left ("FWC MAPD snapshot inconsistent: effective dates differ for classification " <> tshow classificationFixedId <> " (" <> categoryLabel category <> ")"))
            case (fst penalty).penaltyClassificationFixedId of
                Just owner | owner /= classificationFixedId -> Left ("FWC MAPD snapshot inconsistent: penalty category ownership differs for classification " <> tshow classificationFixedId)
                _ -> Right ()

penaltyCategory :: PenaltyRatePayload -> (StaffEmploymentBasisEnum, Maybe AwardPenaltyKindEnum)
penaltyCategory penalty
    | isRelevantCasualOrdinaryPenaltyRate barVenueCurationProfile penalty = (Casual, Nothing)
    | otherwise = (if containsAny ["casual"] searchable then Casual else Permanent, normalisePenaltyKind penalty)
    where searchable = searchablePenaltyRateText penalty

categoryLabel :: (StaffEmploymentBasisEnum, Maybe AwardPenaltyKindEnum) -> Text
categoryLabel (basis, kind) = tshow basis <> " " <> maybe "ordinary/base" tshow kind

validateTimeAllowances :: Set.Set EffectivePeriod -> [(WageAllowancePayload, Aeson.Value)] -> Either Text ()
validateTimeAllowances effectivePeriods wageAllowances = do
    unless (Set.size effectivePeriods == 1)
        (Left "FWC MAPD snapshot inconsistent: core classifications have different effective periods")
    expectedPeriod <- maybe (Left "FWC MAPD snapshot incomplete: no effective period") Right (Set.lookupMin effectivePeriods)
    forM_ [EveningAfter7Pm, LateNightAfterMidnight] \kind -> do
        allowance <- exactlyOne ("award-wide " <> tshow kind <> " clause 29.2 addition") (filter ((== Just kind) . normaliseTimePenaltyKind . fst) wageAllowances)
        unless (containsAny ["29.2"] (fromMaybe "" (fst allowance).wageAllowanceClauses))
            (Left ("FWC MAPD snapshot inconsistent: " <> tshow kind <> " addition is not owned by clause 29.2"))
        unless (containsAny ["per hour or part"] (fromMaybe "" (fst allowance).wageAllowancePaymentFrequency))
            (Left ("FWC MAPD snapshot inconsistent: " <> tshow kind <> " is not a commenced-hour addition"))
        unless (isJust (fst allowance).wageAllowanceFixedId && isJust (fst allowance).wageAllowanceAmount)
            (Left ("FWC MAPD snapshot inconsistent: source identity/value missing for " <> tshow kind <> " clause 29.2 addition"))
        unless (effectivePeriod (fst allowance).wageAllowanceOperativeFrom (fst allowance).wageAllowanceOperativeTo == expectedPeriod)
            (Left ("FWC MAPD snapshot inconsistent: effective dates differ for " <> tshow kind <> " clause 29.2 addition"))

exactlyOne :: Text -> [a] -> Either Text a
exactlyOne label = \case
    [value] -> Right value
    []      -> Left ("FWC MAPD snapshot incomplete: missing " <> label)
    _       -> Left ("FWC MAPD snapshot inconsistent: multiple " <> label <> " rows")
