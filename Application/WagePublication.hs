module Application.WagePublication
    ( PublishedEarningsLine (..)
    , StaffHoursBucketKind (..)
    , StaffHoursContribution (..)
    , datedEarningsComponents
    , datedEarningsComponentsWithOrdinal
    , derivePublishedEarnings
    , publicationBucketKey
    , staffHoursContributions
    ) where

import Application.Error.Runtime (ExternalRuntimeCategory (..), externalRuntimeInvariantFailure)
import qualified Application.VenueTime.Seconds as Seconds
import Application.VenueTime (resolvedInstantFromUTC, resolvedInstantLocalTime)
import Application.WageEngine
import qualified Data.List as List
import qualified Data.Map.Strict as Map
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
        , staffHoursQuantity = Seconds.toHours (paidTimeDurationSeconds segment)
        }
    | segment <- calculation.paidTimeSegments
    , paidTimeDurationSeconds segment > Seconds.fromSeconds 0
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
datedEarningsComponents =
    map (\(_, componentDate, component) -> (componentDate, component))
        . datedEarningsComponentsWithOrdinal

-- | Retain the immutable ledger ordinal while applying publication date splits.
-- A source component can contribute on multiple dates, but every contribution
-- still belongs to the same sealed component and Xero routing decision.
datedEarningsComponentsWithOrdinal :: WageCalculation -> [(Int, Day, EarningsComponent)]
datedEarningsComponentsWithOrdinal calculation =
    snd (go initialState (zip [0 ..] calculation.earningsComponents))
  where
    paidSegments = calculation.paidTimeSegments
    workedSegments = List.sortOn (.paidTimeStart) (filter ((== Worked) . (.paidTimeKind)) paidSegments)
    hourlyDates = map (.paidTimeLocalDate) paidSegments
    eveningDates = qualifyingDates StaffHoursEvening
    earlyDates = qualifyingDates StaffHoursEarlyMorning
    fallbackDate = maybe (externalRuntimeInvariantFailure PersistedRuntimeInvariant "approved wage calculation has no paid-time date") (.paidTimeLocalDate) (lastMay paidSegments)
    initialState = (hourlyDates, eveningDates, earlyDates)

    go state [] = (state, [])
    go state ((ordinal, component) : rest) =
        let (nextState, contributions) = dateComponent state component
            (finalState, remainingContributions) = go nextState rest
            ordinalContributions = map (\(componentDate, contribution) -> (ordinal, componentDate, contribution)) contributions
         in (finalState, ordinalContributions <> remainingContributions)

    dateComponent state@(remainingHourly, remainingEvening, remainingEarly) component =
        case component.publishedComponentDate of
            Just componentDate -> (state, [(componentDate, component)])
            Nothing            -> undatedComponent
      where
        undatedComponent = case (component.unitType, component.sourceCondition) of
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
                let missedStart = Seconds.addTo (Seconds.fromMinutes 360) firstWorked.paidTimeStart
                    total = Seconds.fromStoredHours component.quantity
                    (remaining, contributions) = allocateMissed total missedStart workedSegments
                    fallback =
                        [ ((resolvedInstantLocalTime (resolvedInstantFromUTC missedStart)).localDay, remaining)
                        | remaining > Seconds.fromSeconds 0
                        ]
                 in if total == Seconds.fromSeconds 0
                    then [(fallbackDate, component)]
                    else map (\(date, duration) -> (date, componentForDuration component total duration)) (contributions <> fallback)

    allocateMissed remaining _ [] = (remaining, [])
    allocateMissed remaining missedStart (segment : segments)
        | remaining <= Seconds.fromSeconds 0 = (Seconds.fromSeconds 0, [])
        | segment.paidTimeEnd <= missedStart = allocateMissed remaining missedStart segments
        | otherwise =
            let contributionStart = max missedStart segment.paidTimeStart
                available = Seconds.between contributionStart segment.paidTimeEnd
                contributionDuration = min remaining available
                contribution =
                    [ (segment.paidTimeLocalDate, contributionDuration)
                    | contributionDuration > Seconds.fromSeconds 0
                    ]
                (left, later) = allocateMissed (Seconds.subtract remaining contributionDuration) missedStart segments
             in (left, contribution <> later)

    componentForDuration component total duration =
        let share = Seconds.toHours duration / Seconds.toHours total
         in component
            { quantity = component.quantity * share
            , amount = component.amount * share
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
                Hours          -> exactQuantity
                CommencedHours -> exactQuantity
            outputAmount = roundToCents (outputQuantity * toRational bucketKey.finalEarningsBucketRatePerUnit)
         in PublishedEarningsLine
                { publishedBucketKey = bucketKey
                , publishedExactQuantity = exactQuantity
                , publishedQuantity = outputQuantity
                , publishedExactAmount = exactAmount
                , publishedAmount = outputAmount
                }

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
    localHour = (resolvedInstantLocalTime (resolvedInstantFromUTC segment.paidTimeStart)).localTimeOfDay.todHour

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
