module Application.WageEngine.Components
    ( paidSegment
    , paidSegmentWithKind
    , awardHourlyComponent
    , importedHourlyComponent
    , missedMealBreakAdditionComponent
    , commencedHourAdditionComponents
    )
where

import Application.VenueTime (AwardSegment, LocalDayKind (..),
                              LocalTimeWindow (..), ResolvedInterval,
                              awardSegmentEnd, awardSegmentLocalDate,
                              awardSegmentLocalDayKind, awardSegmentLocalWindow,
                              awardSegmentStart, resolvedInstantUTC,
                              resolvedIntervalElapsedSeconds)
import Application.WageEngine.RateBook (AwardClassification,
                                        BaseRateKind (OrdinaryRate),
                                        EmploymentBasis (PermanentPartTime),
                                        RateSourceIdentity,
                                        TimeAdditionKind (..),
                                        ValidatedRateBook,
                                        ValidatedRateKey (AwardAddition, ClassificationRate),
                                        ValidatedRateLookupError (ValidatedRateMissing),
                                        lookupValidatedRateWithSource)
import Application.WageEngine.Types
import qualified Data.Bifunctor as Bifunctor
import qualified Data.Map.Strict as Map
import Data.Scientific (Scientific)
import qualified Data.Set as Set
import Data.Time.Calendar (Day)
import Data.Time.Clock (diffUTCTime)
import Data.Traversable (traverse)
import IHP.Prelude

paidSegment :: SourceCondition -> AwardSegment -> PaidTimeSegment
paidSegment = paidSegmentWithKind Worked

paidSegmentWithKind :: PaidTimeKind -> SourceCondition -> AwardSegment -> PaidTimeSegment
paidSegmentWithKind kind condition interval =
    PaidTimeSegment
        { paidTimeKind = kind
        , paidTimeStart = resolvedInstantUTC (awardSegmentStart interval)
        , paidTimeEnd = resolvedInstantUTC (awardSegmentEnd interval)
        , paidTimeLocalDate = awardSegmentLocalDate interval
        , paidTimeSourceCondition = condition
        }

awardHourlyComponent :: (Scientific, RateSourceIdentity) -> SourceCondition -> AwardSegment -> EarningsComponent
awardHourlyComponent (rate, sourceIdentity) condition interval =
    hourlyComponent
        (intervalDurationHours interval)
        rate
        condition
        HospitalityAward
        (Just sourceIdentity)

importedHourlyComponent :: ImportedPayItem -> SourceCondition -> AwardSegment -> EarningsComponent
importedHourlyComponent importedPayItem condition interval =
    hourlyComponent
        (intervalDurationHours interval)
        importedPayItem.importedHourlyRate
        condition
        ExternalImportedPayItem
        Nothing

missedMealBreakAdditionComponent :: ValidatedRateBook -> AwardClassification -> ResolvedInterval -> Either WageCalculationError EarningsComponent
missedMealBreakAdditionComponent rateBook classification delayedInterval = do
    (ordinaryRate, ordinaryRateIdentity) <-
        lookupValidatedRateWithSource
            (ClassificationRate classification PermanentPartTime OrdinaryRate)
            rateBook
            |> Bifunctor.first (\(ValidatedRateMissing key) -> MissingValidatedRate key)
    pure $
        hourlyComponent
            (toRational (resolvedIntervalElapsedSeconds delayedInterval) / 3600)
            (ordinaryRate / 2)
            MissedMealBreakAdditionCondition
            HospitalityAward
            (Just ordinaryRateIdentity)

commencedHourAdditionComponents :: ValidatedRateBook -> Set.Set Day -> [AwardSegment] -> Either WageCalculationError [EarningsComponent]
commencedHourAdditionComponents rateBook statewidePublicHolidayDates intervals =
    traverse componentFor (Map.toAscList qualifyingDurations)
  where
    qualifyingDurations =
        Map.fromListWith (+)
            (mapMaybe qualifyingDuration intervals)

    qualifyingDuration interval = do
        additionKind <- qualifyingAdditionKind interval
        pure
            ( CommencedAdditionKey
                { commencedAdditionDate = awardSegmentLocalDate interval
                , commencedAdditionKind = additionKind
                }
            , intervalDurationHours interval
            )

    qualifyingAdditionKind interval
        | Set.member (awardSegmentLocalDate interval) statewidePublicHolidayDates = Nothing
        | awardSegmentLocalDayKind interval /= LocalWeekday = Nothing
        | otherwise = case awardSegmentLocalWindow interval of
            EveningWindow      -> Just EveningAddition
            EarlyMorningWindow -> Just EarlyMorningAddition
            OrdinaryWindow     -> Nothing

    componentFor (CommencedAdditionKey _ additionKind, durationHours) = do
        (rate, sourceIdentity) <-
            lookupValidatedRateWithSource (AwardAddition additionKind) rateBook
                |> Bifunctor.first (\(ValidatedRateMissing key) -> MissingValidatedRate key)
        let units = fromInteger (ceiling durationHours :: Integer)
        pure EarningsComponent
            { quantity = units
            , unitType = CommencedHours
            , ratePerUnit = rate
            , amount = units * toRational rate
            , publishedComponentDate = Nothing
            , publishedRateBoundaryDate = Nothing
            , publishedXeroLocalBucketKey = Nothing
            , publishedXeroEarningsRateId = Nothing
            , publishedXeroMappingLegacyFallback = False
            , sourceCondition = additionCondition additionKind
            , calculationSource = HospitalityAward
            , sourceRateIdentity = Just sourceIdentity
            }

data CommencedAdditionKey = CommencedAdditionKey
    { commencedAdditionDate :: !Day
    , commencedAdditionKind :: !TimeAdditionKind
    }
    deriving (Eq, Ord, Show)

hourlyComponent :: Rational -> Scientific -> SourceCondition -> CalculationSource -> Maybe RateSourceIdentity -> EarningsComponent
hourlyComponent hours rate condition source rateIdentity =
    EarningsComponent
        { quantity = hours
        , unitType = Hours
        , ratePerUnit = rate
        , amount = hours * toRational rate
        , publishedComponentDate = Nothing
        , publishedRateBoundaryDate = Nothing
        , publishedXeroLocalBucketKey = Nothing
        , publishedXeroEarningsRateId = Nothing
        , publishedXeroMappingLegacyFallback = False
        , sourceCondition = condition
        , calculationSource = source
        , sourceRateIdentity = rateIdentity
        }

additionCondition :: TimeAdditionKind -> SourceCondition
additionCondition = \case
    EveningAddition      -> EveningAdditionCondition
    EarlyMorningAddition -> EarlyMorningAdditionCondition

intervalDurationHours :: AwardSegment -> Rational
intervalDurationHours interval =
    toRational
        ( diffUTCTime
            (resolvedInstantUTC (awardSegmentEnd interval))
            (resolvedInstantUTC (awardSegmentStart interval))
        )
        / 3600
