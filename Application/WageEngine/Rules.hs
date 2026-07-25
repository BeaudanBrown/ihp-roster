module Application.WageEngine.Rules
    ( calculateTimesheetPay
    )
where

import Application.VenueTime (AwardSegment, LocalDayKind (..), awardSegmentEnd,
                              awardSegmentLocalDate, awardSegmentLocalDayKind,
                              awardSegmentStart, resolvedInstantUTC)
import Application.WageEngine.Components (awardHourlyComponent,
                                          commencedHourAdditionComponents,
                                          importedHourlyComponent, paidSegment)
import Application.WageEngine.RateBook (AwardRateContext (awardRateBook, awardRateLevel),
                                        BaseRateKind (..),
                                        ResolvedAwardLevel (resolvedAwardClassification),
                                        ValidatedRateKey (ClassificationRate),
                                        lookupValidatedRateWithSource,
                                        validatedRateBookVersion)
import Application.WageEngine.Types
import qualified Data.List as List
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import IHP.Prelude

calculateTimesheetPay :: WageCalculationInput -> Either WageCalculationError WageCalculation
calculateTimesheetPay calculationInput = do
    validateCalculationContext calculationInput
    intervals <- validatePaidIntervals calculationInput.calculationPaidIntervals
    case selectedImportedPayItem calculationInput.calculationImportedOverrides of
        Just importedPayItem -> calculateImportedPay importedPayItem intervals
        Nothing              -> calculateAwardPay intervals
  where
    calculateAwardPay intervals = do
        basis <- case calculationInput.calculationArrangement of
            AwardHourlyEmployment employmentBasis -> Right employmentBasis
            UnsupportedEmployment unsupportedEmployment ->
                Left (UnsupportedCalculationInput (UnsupportedEmploymentArrangement unsupportedEmployment))
        awardRateContext <- maybe (Left (UnsupportedCalculationInput MissingAwardRateContext)) Right calculationInput.calculationAwardRateContext
        let intervalResults = map (calculateAwardInterval awardRateContext basis) intervals
            additionComponents =
                commencedHourAdditionComponents
                    awardRateContext.awardRateBook
                    calculationInput.calculationStatewidePublicHolidayDates
                    intervals
        pure
            WageCalculation
                { calculatedEntryId = calculationInput.calculationEntryId
                , calculationVersion = currentWageCalculationVersion
                , calculationRateBookVersion = Just (validatedRateBookVersion awardRateContext.awardRateBook)
                , paidTimeSegments = map fst intervalResults
                , earningsComponents = map snd intervalResults <> additionComponents
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

    calculateAwardInterval awardRateContext basis interval =
        let
            (rateKind, condition) = awardCondition calculationInput.calculationStatewidePublicHolidayDates interval
            key = ClassificationRate awardRateContext.awardRateLevel.resolvedAwardClassification basis rateKind
            validatedRate = lookupValidatedRateWithSource key awardRateContext.awardRateBook
         in
            ( paidSegment condition interval
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

validatePaidIntervals :: [AwardSegment] -> Either WageCalculationError [AwardSegment]
validatePaidIntervals [] = Left (InvalidPaidInterval NoPaidIntervals)
validatePaidIntervals rawIntervals = do
    let intervals = List.sortOn (resolvedInstantUTC . awardSegmentStart) rawIntervals
        adjacent = zip intervals (drop 1 intervals)
    when
        ( any
            ( \(left, right) ->
                resolvedInstantUTC (awardSegmentEnd left)
                    > resolvedInstantUTC (awardSegmentStart right)
            )
            adjacent
        )
        (Left (InvalidPaidInterval OverlappingPaidIntervals))
    pure intervals

awardCondition :: Set.Set Day -> AwardSegment -> (BaseRateKind, SourceCondition)
awardCondition statewidePublicHolidayDates interval
    | Set.member (awardSegmentLocalDate interval) statewidePublicHolidayDates = (PublicHolidayRate, PublicHolidayCondition)
    | otherwise = case awardSegmentLocalDayKind interval of
        LocalWeekday  -> (OrdinaryRate, OrdinaryCondition)
        LocalSaturday -> (SaturdayRate, SaturdayCondition)
        LocalSunday   -> (SundayRate, SundayCondition)
