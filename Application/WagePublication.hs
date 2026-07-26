module Application.WagePublication
    ( PublishedEarningsLine (..)
    , StaffHoursBucketKind (..)
    , StaffHoursContribution (..)
    , datedEarningsComponents
    , derivePublishedEarnings
    , publicationBucketKey
    , roundHourlyQuantity
    , staffHoursContributions
    ) where

import Application.VenueTime.Model (storedInstantLocalTime)
import Application.WageEngine
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Data.Time.Clock (addUTCTime, diffUTCTime)
import Data.Time.LocalTime (TimeOfDay (..))
import IHP.Prelude

data PublishedEarningsLine = PublishedEarningsLine
    { publishedBucketKey     :: !FinalEarningsBucketKey
    , publishedExactQuantity :: !Rational
    , publishedQuantity      :: !Rational
    , publishedExactAmount   :: !Rational
    , publishedAmount        :: !Rational
    }
    deriving (Eq, Show)

data StaffHoursBucketKind
    = StaffHoursOrdinary
    | StaffHoursEvening
    | StaffHoursEarlyMorning
    deriving (Eq, Ord, Show)

data StaffHoursContribution = StaffHoursContribution
    { staffHoursDate       :: !Day
    , staffHoursBucketKind :: !StaffHoursBucketKind
    , staffHoursQuantity   :: !Rational
    }
    deriving (Eq, Show)

-- | Staff Hours is a paid-time report, not an earnings-component report.
-- Worked segments follow their Melbourne local clock bucket; non-worked minimum
-- top-ups deliberately fall back to the day's ordinary bucket.
staffHoursContributions :: WageCalculation -> [StaffHoursContribution]
staffHoursContributions calculation =
    [ StaffHoursContribution
        { staffHoursDate = segment.paidTimeLocalDate
        , staffHoursBucketKind = bucketFor segment
        , staffHoursQuantity = paidTimeDurationSeconds segment / 3600
        }
    | segment <- calculation.paidTimeSegments
    , paidTimeDurationSeconds segment > 0
    ]
  where
    bucketFor segment
        | segment.paidTimeKind /= Worked = StaffHoursOrdinary
        | otherwise = bucketForWorkedSegment segment

-- | Attach local output days omitted from the provider-neutral component.
-- Base hourly components follow paid-segment order. Fixed additions follow
-- their qualifying date/window. A missed-break interval starts six elapsed
-- hours after the first worked instant; allocate its exact quantity across the
-- same paid segment boundaries so a late break or midnight cannot move it to a
-- later local day. Split publication contributions still sum to the unchanged
-- approved component quantity and amount.
datedEarningsComponents :: WageCalculation -> [(Day, EarningsComponent)]
datedEarningsComponents calculation =
    snd (go initialState calculation.earningsComponents)
  where
    paidSegments = calculation.paidTimeSegments
    workedSegments = List.sortOn (.paidTimeStart) (filter ((== Worked) . (.paidTimeKind)) paidSegments)
    hourlyDates = map (.paidTimeLocalDate) paidSegments
    eveningDates = qualifyingDates StaffHoursEvening
    earlyDates = qualifyingDates StaffHoursEarlyMorning
    fallbackDate = maybe (error "approved wage calculation has no paid-time date") (.paidTimeLocalDate) (lastMay paidSegments)
    initialState = (hourlyDates, eveningDates, earlyDates)

    go state [] = (state, [])
    go state (component : rest) =
        let (nextState, contributions) = dateComponent state component
            (finalState, remainingContributions) = go nextState rest
         in (finalState, contributions <> remainingContributions)

    dateComponent state@(remainingHourly, remainingEvening, remainingEarly) component =
        case (component.unitType, component.sourceCondition) of
            (Hours, MissedMealBreakAdditionCondition) ->
                (state, missedMealBreakContributions component)
            (Hours, _) ->
                let (date, dates) = takeDate fallbackDate remainingHourly
                 in ((dates, remainingEvening, remainingEarly), [(date, component)])
            (CommencedHours, EveningAdditionCondition) ->
                let (date, dates) = takeDate fallbackDate remainingEvening
                 in ((remainingHourly, dates, remainingEarly), [(date, component)])
            (CommencedHours, EarlyMorningAdditionCondition) ->
                let (date, dates) = takeDate fallbackDate remainingEarly
                 in ((remainingHourly, remainingEvening, dates), [(date, component)])
            _ -> (state, [(fallbackDate, component)])

    missedMealBreakContributions component =
        case listToMaybe workedSegments of
            Nothing -> [(fallbackDate, component)]
            Just firstWorked ->
                let missedStart = addUTCTime (6 * 60 * 60) firstWorked.paidTimeStart
                    (remaining, contributions) = allocateMissed component component.quantity missedStart workedSegments
                    fallback =
                        [ ( (storedInstantLocalTime "Australia/Melbourne" missedStart).localDay
                          , componentForQuantity component remaining
                          )
                        | remaining > 0
                        ]
                 in contributions <> fallback

    allocateMissed _ remaining _ [] = (remaining, [])
    allocateMissed component remaining missedStart (segment : segments)
        | remaining <= 0 = (0, [])
        | segment.paidTimeEnd <= missedStart = allocateMissed component remaining missedStart segments
        | otherwise =
            let contributionStart = max missedStart segment.paidTimeStart
                available = toRational (diffUTCTime segment.paidTimeEnd contributionStart) / 3600
                contributionQuantity = min remaining available
                contribution =
                    [ (segment.paidTimeLocalDate, componentForQuantity component contributionQuantity)
                    | contributionQuantity > 0
                    ]
                (left, later) = allocateMissed component (remaining - contributionQuantity) missedStart segments
             in (left, contribution <> later)

    componentForQuantity component contributionQuantity =
        component
            { quantity = contributionQuantity
            , amount = contributionQuantity * toRational component.ratePerUnit
            }

    qualifyingDates wanted =
        workedSegments
            |> filter ((== wanted) . bucketForWorkedSegment)
            |> map (.paidTimeLocalDate)
            |> List.nub
            |> List.sort

    takeDate fallback = \case
        date : dates -> (date, dates)
        []           -> (fallback, [])

publicationBucketKey :: EarningsComponent -> FinalEarningsBucketKey
publicationBucketKey = finalEarningsBucketKey

-- | Aggregate exact ledger components by the final output bucket, then apply
-- the one defensive output transform. The approved components remain unchanged.
derivePublishedEarnings :: [EarningsComponent] -> [PublishedEarningsLine]
derivePublishedEarnings components =
    map publish (Map.toAscList grouped)
  where
    grouped =
        Map.fromListWith addExact
            [ (publicationBucketKey component, (component.quantity, component.amount))
            | component <- components
            , component.quantity > 0
            ]

    addExact (newQuantity, newAmount) (oldQuantity, oldAmount) =
        (newQuantity + oldQuantity, newAmount + oldAmount)

    publish (bucketKey, (exactQuantity, exactAmount)) =
        let outputQuantity = case bucketKey.finalEarningsBucketUnitType of
                Hours          -> roundHourlyQuantity exactQuantity
                CommencedHours -> exactQuantity
            outputAmount = roundToCents (outputQuantity * toRational bucketKey.finalEarningsBucketRatePerUnit)
         in PublishedEarningsLine
                { publishedBucketKey = bucketKey
                , publishedExactQuantity = exactQuantity
                , publishedQuantity = outputQuantity
                , publishedExactAmount = exactAmount
                , publishedAmount = outputAmount
                }

-- | Nearest quarter hour with exact half-quarter ties away from zero. Payroll
-- quantities are positive; the symmetric negative branch keeps the helper total.
roundHourlyQuantity :: Rational -> Rational
roundHourlyQuantity value
    | value < 0 = negate (roundHourlyQuantity (negate value))
    | otherwise = fromInteger (floor (value * 4 + 1 / 2)) / 4

roundToCents :: Rational -> Rational
roundToCents value
    | value < 0 = negate (roundToCents (negate value))
    | otherwise = fromInteger (floor (value * 100 + 1 / 2)) / 100

bucketForWorkedSegment :: PaidTimeSegment -> StaffHoursBucketKind
bucketForWorkedSegment segment =
    case dayOfWeekIndex segment.paidTimeLocalDate of
        6 | localHour < 7 -> StaffHoursEarlyMorning
        6                 -> StaffHoursOrdinary
        7                 -> StaffHoursOrdinary
        _ | localHour < 7 -> StaffHoursEarlyMorning
          | localHour >= 19 -> StaffHoursEvening
          | otherwise -> StaffHoursOrdinary
  where
    localHour = (storedInstantLocalTime "Australia/Melbourne" segment.paidTimeStart).localTimeOfDay.todHour

dayOfWeekIndex :: Day -> Int
dayOfWeekIndex day =
    case dayOfWeek day of
        Monday    -> 1
        Tuesday   -> 2
        Wednesday -> 3
        Thursday  -> 4
        Friday    -> 5
        Saturday  -> 6
        Sunday    -> 7
