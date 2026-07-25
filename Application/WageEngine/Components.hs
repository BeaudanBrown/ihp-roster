module Application.WageEngine.Components
    ( paidSegment
    , awardHourlyComponent
    , importedHourlyComponent
    , commencedHourAdditionComponents
    )
where

import Application.VenueTime (AwardSegment, LocalDayKind (..),
                              LocalTimeWindow (..), awardSegmentEnd,
                              awardSegmentLocalDate, awardSegmentLocalDayKind,
                              awardSegmentLocalWindow, awardSegmentStart,
                              resolvedInstantUTC)
import Application.WageEngine.RateBook (RateSourceIdentity,
                                        TimeAdditionKind (..),
                                        ValidatedRateBook,
                                        ValidatedRateKey (AwardAddition),
                                        lookupValidatedRateWithSource)
import Application.WageEngine.Types
import qualified Data.Map.Strict as Map
import Data.Scientific (Scientific)
import qualified Data.Set as Set
import Data.Time.Calendar (Day)
import Data.Time.Clock (diffUTCTime)
import IHP.Prelude

paidSegment :: SourceCondition -> AwardSegment -> PaidTimeSegment
paidSegment condition interval =
    PaidTimeSegment
        { paidTimeKind = Worked
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

commencedHourAdditionComponents :: ValidatedRateBook -> Set.Set Day -> [AwardSegment] -> [EarningsComponent]
commencedHourAdditionComponents rateBook statewidePublicHolidayDates intervals =
    map componentFor (Map.toAscList qualifyingDurations)
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

    componentFor (CommencedAdditionKey _ additionKind, durationHours) =
        let (rate, sourceIdentity) = lookupValidatedRateWithSource (AwardAddition additionKind) rateBook
            units = fromInteger (ceiling durationHours :: Integer)
         in EarningsComponent
                { quantity = units
                , unitType = CommencedHours
                , ratePerUnit = rate
                , amount = units * toRational rate
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
