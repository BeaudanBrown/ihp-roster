module Application.WageEngine.Rules
    ( calculateTimesheetPay
    )
where

import Application.VenueTime (AwardSegment, LocalDayKind (..), ResolvedInstant,
                              ResolvedInterval, awardSegmentElapsedSeconds,
                              awardSegmentEnd, awardSegmentLocalDate,
                              awardSegmentLocalDayKind, awardSegmentStart,
                              awardSegments, resolvedInstantFromUTC,
                              resolvedInstantUTC,
                              resolvedIntervalElapsedSeconds,
                              resolvedIntervalEnd, resolvedIntervalFromInstants,
                              resolvedIntervalStart)
import Application.WageEngine.Components (awardHourlyComponent,
                                          commencedHourAdditionComponents,
                                          importedHourlyComponent,
                                          missedMealBreakAdditionComponent,
                                          paidSegment, paidSegmentWithKind)
import Application.WageEngine.RateBook (AwardRateContext (awardRateBook, awardRateLevel),
                                        BaseRateKind (..), EmploymentBasis (..),
                                        ResolvedAwardLevel (resolvedAwardClassification),
                                        ValidatedRateKey (ClassificationRate),
                                        lookupValidatedRateWithSource,
                                        validatedRateBookVersion)
import Application.WageEngine.Types
import qualified Data.List as List
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import Data.Time.Clock (NominalDiffTime, addUTCTime, diffUTCTime)
import Data.Traversable (traverse)
import IHP.Prelude

calculateTimesheetPay :: WageCalculationInput -> Either WageCalculationError WageCalculation
calculateTimesheetPay calculationInput = do
    validateCalculationContext calculationInput
    (shiftSegments, shiftBounds) <- validateShiftSegments calculationInput.calculationShiftSegments
    paidIntervals <- subtractUnpaidMealBreak shiftBounds calculationInput.calculationUnpaidMealBreak shiftSegments
    case selectedImportedPayItem calculationInput.calculationImportedOverrides of
        Just importedPayItem -> calculateImportedPay importedPayItem paidIntervals
        Nothing              -> calculateAwardPay shiftBounds paidIntervals
  where
    calculateAwardPay shiftBounds intervals = do
        basis <- case calculationInput.calculationArrangement of
            AwardHourlyEmployment employmentBasis -> Right employmentBasis
            UnsupportedEmployment unsupportedEmployment ->
                Left (UnsupportedCalculationInput (UnsupportedEmploymentArrangement unsupportedEmployment))
        awardRateContext <- maybe (Left (UnsupportedCalculationInput MissingAwardRateContext)) Right calculationInput.calculationAwardRateContext
        missedInterval <- missedMealBreakInterval shiftBounds calculationInput.calculationUnpaidMealBreak
        let selectedMinimum =
                selectMinimumPayment
                    basis
                    calculationInput.calculationStatewidePublicHolidayDates
                    intervals
        minimumIntervals <-
            maybe
                (Right [])
                (\minimumPayment ->
                    hypotheticalContinuationSegments
                        shiftBounds
                        (minimumPaymentRequiredSeconds basis minimumPayment - paidIntervalElapsedSeconds intervals)
                )
                selectedMinimum
        let intervalResults = map (calculateAwardInterval Worked awardRateContext basis) intervals
            minimumResults =
                case selectedMinimum of
                    Nothing -> []
                    Just CasualMinimumPayment ->
                        map (calculateAwardInterval CasualMinimumEngagementTopUp awardRateContext basis) minimumIntervals
                    Just PublicHolidayMinimumPayment ->
                        map (calculatePublicHolidayMinimumInterval awardRateContext basis) minimumIntervals
            additionComponents =
                commencedHourAdditionComponents
                    awardRateContext.awardRateBook
                    calculationInput.calculationStatewidePublicHolidayDates
                    intervals
            missedMealBreakComponents =
                maybe []
                    (pure . missedMealBreakAdditionComponent awardRateContext.awardRateBook awardRateContext.awardRateLevel.resolvedAwardClassification)
                    missedInterval
        pure
            WageCalculation
                { calculatedEntryId = calculationInput.calculationEntryId
                , calculationVersion = currentWageCalculationVersion
                , calculationRateBookVersion = Just (validatedRateBookVersion awardRateContext.awardRateBook)
                , paidTimeSegments = map fst intervalResults <> map fst minimumResults
                , earningsComponents = map snd intervalResults <> map snd minimumResults <> additionComponents <> missedMealBreakComponents
                }

    calculateImportedPay importedPayItem intervals = do
        unless
            ( not (Text.null (Text.strip importedPayItem.importedPayItemId))
                && not (Text.null (Text.strip importedPayItem.importedPayItemName))
                && importedPayItem.importedHourlyRate > 0
            )
            (Left (UnsupportedCalculationInput (InvalidImportedPayItem importedPayItem.importedPayItemId)))
        let condition = ImportedFlatRateCondition importedPayItem.importedPayItemId
        pure
            WageCalculation
                { calculatedEntryId = calculationInput.calculationEntryId
                , calculationVersion = currentWageCalculationVersion
                , calculationRateBookVersion = Nothing
                , paidTimeSegments = map (paidSegment condition) intervals
                , earningsComponents = map (importedHourlyComponent importedPayItem condition) intervals
                }

    calculateAwardInterval paidKind awardRateContext basis interval =
        calculateAwardIntervalForCondition
            paidKind
            awardRateContext
            basis
            (awardCondition calculationInput.calculationStatewidePublicHolidayDates interval)
            interval

    calculatePublicHolidayMinimumInterval awardRateContext basis =
        calculateAwardIntervalForCondition
            PublicHolidayMinimumTopUp
            awardRateContext
            basis
            (PublicHolidayRate, PublicHolidayCondition)

    calculateAwardIntervalForCondition paidKind awardRateContext basis (rateKind, condition) interval =
        let
            key = ClassificationRate awardRateContext.awardRateLevel.resolvedAwardClassification basis rateKind
            validatedRate = lookupValidatedRateWithSource key awardRateContext.awardRateBook
         in
            ( paidSegmentWithKind paidKind condition interval
            , awardHourlyComponent validatedRate condition interval
            )

validateCalculationContext :: WageCalculationInput -> Either WageCalculationError ()
validateCalculationContext calculationInput = do
    case calculationInput.calculationArrangement of
        UnsupportedEmployment unsupportedEmployment ->
            Left (UnsupportedCalculationInput (UnsupportedEmploymentArrangement unsupportedEmployment))
        AwardHourlyEmployment _ -> Right ()
    case Set.lookupMin calculationInput.calculationUnsupportedFeatures of
        Nothing -> Right ()
        Just unsupportedFeature -> Left (UnsupportedCalculationInput (UnsupportedFeatureRequested unsupportedFeature))

data ShiftBounds = ShiftBounds
    { shiftBoundsStart :: !ResolvedInstant
    , shiftBoundsEnd   :: !ResolvedInstant
    }

data MinimumPayment
    = CasualMinimumPayment
    | PublicHolidayMinimumPayment

selectMinimumPayment :: EmploymentBasis -> Set.Set Day -> [AwardSegment] -> Maybe MinimumPayment
selectMinimumPayment basis statewidePublicHolidayDates intervals
    | any (\interval -> Set.member (awardSegmentLocalDate interval) statewidePublicHolidayDates) intervals = Just PublicHolidayMinimumPayment
    | basis == CasualEmployment = Just CasualMinimumPayment
    | otherwise = Nothing

minimumPaymentRequiredSeconds :: EmploymentBasis -> MinimumPayment -> NominalDiffTime
minimumPaymentRequiredSeconds basis = \case
    CasualMinimumPayment -> twoHours
    PublicHolidayMinimumPayment -> case basis of
        CasualEmployment  -> twoHours
        PermanentPartTime -> fourHours

validateShiftSegments :: [AwardSegment] -> Either WageCalculationError ([AwardSegment], ShiftBounds)
validateShiftSegments rawSegments =
    case List.sortOn (resolvedInstantUTC . awardSegmentStart) rawSegments of
        [] -> Left (InvalidShiftSegments NoShiftSegments)
        firstSegment : remainingSegments -> do
            let segments = firstSegment : remainingSegments
                lastSegment = foldl' (\_ segment -> segment) firstSegment remainingSegments
                adjacent = zip segments (drop 1 segments)
            when
                ( any
                    ( \(left, right) ->
                        resolvedInstantUTC (awardSegmentEnd left)
                            > resolvedInstantUTC (awardSegmentStart right)
                    )
                    adjacent
                )
                (Left (InvalidShiftSegments OverlappingShiftSegments))
            when
                ( any
                    ( \(left, right) ->
                        resolvedInstantUTC (awardSegmentEnd left)
                            < resolvedInstantUTC (awardSegmentStart right)
                    )
                    adjacent
                )
                (Left (InvalidShiftSegments NonContiguousShiftSegments))
            pure
                ( segments
                , ShiftBounds
                    { shiftBoundsStart = awardSegmentStart firstSegment
                    , shiftBoundsEnd = awardSegmentEnd lastSegment
                    }
                )

subtractUnpaidMealBreak :: ShiftBounds -> Maybe ResolvedInterval -> [AwardSegment] -> Either WageCalculationError [AwardSegment]
subtractUnpaidMealBreak _ Nothing segments = Right segments
subtractUnpaidMealBreak shiftBounds (Just mealBreak) segments = do
    unless (mealBreakIsWithinShift shiftBounds mealBreak)
        (Left (InvalidShiftSegments UnpaidMealBreakOutsideShift))
    concat <$> traverse (subtractFromSegment mealBreak) segments

mealBreakIsWithinShift :: ShiftBounds -> ResolvedInterval -> Bool
mealBreakIsWithinShift shiftBounds mealBreak =
    resolvedIntervalStart mealBreak >= shiftBounds.shiftBoundsStart
        && resolvedIntervalEnd mealBreak <= shiftBounds.shiftBoundsEnd

subtractFromSegment :: ResolvedInterval -> AwardSegment -> Either WageCalculationError [AwardSegment]
subtractFromSegment mealBreak segment
    | mealBreakEnd <= segmentStart || mealBreakStart >= segmentEnd = Right [segment]
    | otherwise = do
        before <- segmentPieces segmentStart (min mealBreakStart segmentEnd)
        after <- segmentPieces (max mealBreakEnd segmentStart) segmentEnd
        pure (before <> after)
  where
    segmentStart = awardSegmentStart segment
    segmentEnd = awardSegmentEnd segment
    mealBreakStart = resolvedIntervalStart mealBreak
    mealBreakEnd = resolvedIntervalEnd mealBreak

segmentPieces :: ResolvedInstant -> ResolvedInstant -> Either WageCalculationError [AwardSegment]
segmentPieces start end
    | start >= end = Right []
    | otherwise =
        case resolvedIntervalFromInstants start end >>= awardSegments of
            Left failure   -> Left (AuthoritativeSegmentationFailure failure)
            Right segments -> Right segments

hypotheticalContinuationSegments :: ShiftBounds -> NominalDiffTime -> Either WageCalculationError [AwardSegment]
hypotheticalContinuationSegments _ duration
    | duration <= 0 = Right []
hypotheticalContinuationSegments shiftBounds duration =
    case
        resolvedIntervalFromInstants
            shiftBounds.shiftBoundsEnd
            (resolvedInstantFromUTC (addUTCTime duration (resolvedInstantUTC shiftBounds.shiftBoundsEnd)))
            >>= awardSegments
        of
            Left failure   -> Left (AuthoritativeSegmentationFailure failure)
            Right segments -> Right segments

paidIntervalElapsedSeconds :: [AwardSegment] -> NominalDiffTime
paidIntervalElapsedSeconds = sum . map awardSegmentElapsedSeconds

missedMealBreakInterval :: ShiftBounds -> Maybe ResolvedInterval -> Either WageCalculationError (Maybe ResolvedInterval)
missedMealBreakInterval shiftBounds maybeMealBreak
    | shiftDuration <= sixHours = Right Nothing
    | maybe False (timelyMealBreak shiftBounds) maybeMealBreak = Right Nothing
    | otherwise =
        case resolvedIntervalFromInstants sixHourThreshold delayedMealBreakEnd of
            Left failure   -> Left (AuthoritativeSegmentationFailure failure)
            Right interval -> Right (Just interval)
  where
    shiftDuration = diffUTCTime (resolvedInstantUTC shiftBounds.shiftBoundsEnd) (resolvedInstantUTC shiftBounds.shiftBoundsStart)
    sixHourThreshold = offsetFromShiftStart sixHours shiftBounds
    delayedMealBreakEnd =
        case maybeMealBreak of
            Just mealBreak
                | mealBreakHasMinimumDuration mealBreak
                    && resolvedIntervalStart mealBreak > sixHourThreshold ->
                    resolvedIntervalStart mealBreak
            _ -> shiftBounds.shiftBoundsEnd

timelyMealBreak :: ShiftBounds -> ResolvedInterval -> Bool
timelyMealBreak shiftBounds mealBreak =
    mealBreakHasMinimumDuration mealBreak
        && resolvedIntervalStart mealBreak >= offsetFromShiftStart twoHours shiftBounds
        && resolvedIntervalStart mealBreak <= offsetFromShiftStart sixHours shiftBounds

mealBreakHasMinimumDuration :: ResolvedInterval -> Bool
mealBreakHasMinimumDuration mealBreak =
    resolvedIntervalElapsedSeconds mealBreak >= mealBreakMinimumDuration

offsetFromShiftStart :: NominalDiffTime -> ShiftBounds -> ResolvedInstant
offsetFromShiftStart offset shiftBounds =
    resolvedInstantFromUTC (addUTCTime offset (resolvedInstantUTC shiftBounds.shiftBoundsStart))

twoHours :: NominalDiffTime
twoHours = 2 * 60 * 60

fourHours :: NominalDiffTime
fourHours = 4 * 60 * 60

sixHours :: NominalDiffTime
sixHours = 6 * 60 * 60

mealBreakMinimumDuration :: NominalDiffTime
mealBreakMinimumDuration = 30 * 60

awardCondition :: Set.Set Day -> AwardSegment -> (BaseRateKind, SourceCondition)
awardCondition statewidePublicHolidayDates interval
    | Set.member (awardSegmentLocalDate interval) statewidePublicHolidayDates = (PublicHolidayRate, PublicHolidayCondition)
    | otherwise = case awardSegmentLocalDayKind interval of
        LocalWeekday  -> (OrdinaryRate, OrdinaryCondition)
        LocalSaturday -> (SaturdayRate, SaturdayCondition)
        LocalSunday   -> (SundayRate, SundayCondition)
