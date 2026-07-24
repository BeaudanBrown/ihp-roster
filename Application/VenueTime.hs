module Application.VenueTime
    ( melbourneTimeZoneName
    , RepeatedTimeOccurrence (..)
    , MelbourneCivilTime (..)
    , VenueTimeError (..)
    , ResolvedInstant
    , resolveCivilTime
    , resolvedInstantFromUTC
    , resolvedInstantUTC
    , resolvedInstantLocalTime
    , resolvedInstantOccurrence
    , ResolvedInterval
    , resolveInterval
    , resolvedIntervalFromInstants
    , resolvedIntervalStart
    , resolvedIntervalEnd
    , resolvedIntervalElapsedSeconds
    , CopyOccurrenceSelections (..)
    , copyIntervalToDate
    , LocalDayKind (..)
    , LocalTimeWindow (..)
    , AwardSegment
    , awardSegments
    , awardSegmentStart
    , awardSegmentEnd
    , awardSegmentLocalDate
    , awardSegmentLocalDayKind
    , awardSegmentLocalWindow
    , awardSegmentElapsedSeconds
    )
where

import Data.Time.Calendar (addDays, diffDays, fromGregorian, toGregorian)
import Data.Time.Calendar.WeekDate (toWeekDate)
import Data.Time.Clock (NominalDiffTime, UTCTime, addUTCTime, diffUTCTime,
                        utctDay)
import Data.Time.LocalTime (LocalTime (..), TimeOfDay (..), TimeZone,
                            localTimeToUTC, makeTimeOfDayValid, midnight,
                            minutesToTimeZone, utcToLocalTime)
import Data.Time.Zones (LocalToUTCResult (..), TZ, localTimeToUTCFull,
                        utcToLocalTimeTZ)
import Data.Time.Zones.All (TZLabel (Australia__Melbourne), tzByLabel)
import IHP.Prelude

melbourneTimeZoneName :: Text
melbourneTimeZoneName = "Australia/Melbourne"

data RepeatedTimeOccurrence
    = FirstOccurrence
    | SecondOccurrence
    deriving (Eq, Ord, Show)

data MelbourneCivilTime = MelbourneCivilTime
    { civilDate              :: !Day
    , civilTimeOfDay         :: !TimeOfDay
    , repeatedTimeOccurrence :: !(Maybe RepeatedTimeOccurrence)
    }
    deriving (Eq, Show)

data VenueTimeError
    = InvalidCivilTimeOfDay !TimeOfDay
    | NonexistentCivilTime !LocalTime
    | RepeatedCivilTimeRequiresOccurrence !LocalTime
    | RepeatedTimeOccurrenceNotApplicable !LocalTime !RepeatedTimeOccurrence
    | NonPositiveResolvedInterval !UTCTime !UTCTime
    deriving (Eq, Show)

newtype ResolvedInstant = ResolvedInstant UTCTime
    deriving (Eq, Ord, Show)

resolveCivilTime :: MelbourneCivilTime -> Either VenueTimeError ResolvedInstant
resolveCivilTime civilTime = do
    validateTimeOfDay civilTime.civilTimeOfDay
    let localTime = LocalTime civilTime.civilDate civilTime.civilTimeOfDay
    case civilTimeResolution localTime of
        CivilTimeGap -> Left (NonexistentCivilTime localTime)
        CivilTimeUnique utc -> case civilTime.repeatedTimeOccurrence of
            Nothing         -> Right (ResolvedInstant utc)
            Just occurrence -> Left (RepeatedTimeOccurrenceNotApplicable localTime occurrence)
        CivilTimeRepeated first second -> case civilTime.repeatedTimeOccurrence of
            Nothing               -> Left (RepeatedCivilTimeRequiresOccurrence localTime)
            Just FirstOccurrence  -> Right (ResolvedInstant first)
            Just SecondOccurrence -> Right (ResolvedInstant second)

resolvedInstantFromUTC :: UTCTime -> ResolvedInstant
resolvedInstantFromUTC = ResolvedInstant

resolvedInstantUTC :: ResolvedInstant -> UTCTime
resolvedInstantUTC (ResolvedInstant utc) = utc

resolvedInstantLocalTime :: ResolvedInstant -> LocalTime
resolvedInstantLocalTime instant
    | usesRecurringFutureRule utc = recurringFutureUTCToLocalTime utc
    | otherwise = utcToLocalTimeTZ melbourneZone utc
  where
    utc = resolvedInstantUTC instant

resolvedInstantOccurrence :: ResolvedInstant -> Maybe RepeatedTimeOccurrence
resolvedInstantOccurrence instant =
    case civilTimeResolution (resolvedInstantLocalTime instant) of
        CivilTimeRepeated first second
            | resolvedInstantUTC instant == first -> Just FirstOccurrence
            | resolvedInstantUTC instant == second -> Just SecondOccurrence
        _ -> Nothing

data ResolvedInterval = ResolvedInterval
    { intervalStart :: !ResolvedInstant
    , intervalEnd   :: !ResolvedInstant
    }
    deriving (Eq, Show)

resolveInterval :: MelbourneCivilTime -> MelbourneCivilTime -> Either VenueTimeError ResolvedInterval
resolveInterval start end = do
    resolvedStart <- resolveCivilTime start
    resolvedEnd <- resolveCivilTime end
    resolvedIntervalFromInstants resolvedStart resolvedEnd

resolvedIntervalFromInstants :: ResolvedInstant -> ResolvedInstant -> Either VenueTimeError ResolvedInterval
resolvedIntervalFromInstants start end
    | resolvedInstantUTC end <= resolvedInstantUTC start =
        Left (NonPositiveResolvedInterval (resolvedInstantUTC start) (resolvedInstantUTC end))
    | otherwise = Right (ResolvedInterval start end)

resolvedIntervalStart :: ResolvedInterval -> ResolvedInstant
resolvedIntervalStart = (.intervalStart)

resolvedIntervalEnd :: ResolvedInterval -> ResolvedInstant
resolvedIntervalEnd = (.intervalEnd)

resolvedIntervalElapsedSeconds :: ResolvedInterval -> NominalDiffTime
resolvedIntervalElapsedSeconds interval =
    diffUTCTime
        (resolvedInstantUTC (resolvedIntervalEnd interval))
        (resolvedInstantUTC (resolvedIntervalStart interval))

data CopyOccurrenceSelections = CopyOccurrenceSelections
    { copiedStartOccurrence :: !(Maybe RepeatedTimeOccurrence)
    , copiedEndOccurrence   :: !(Maybe RepeatedTimeOccurrence)
    }
    deriving (Eq, Show)

copyIntervalToDate :: Day -> CopyOccurrenceSelections -> ResolvedInterval -> Either VenueTimeError ResolvedInterval
copyIntervalToDate targetStartDate selections source =
    resolveInterval copiedStart copiedEnd
  where
    sourceStartLocal = resolvedInstantLocalTime (resolvedIntervalStart source)
    sourceEndLocal = resolvedInstantLocalTime (resolvedIntervalEnd source)
    endDayOffset = diffDays sourceEndLocal.localDay sourceStartLocal.localDay
    copiedStart =
        MelbourneCivilTime
            { civilDate = targetStartDate
            , civilTimeOfDay = sourceStartLocal.localTimeOfDay
            , repeatedTimeOccurrence = selections.copiedStartOccurrence
            }
    copiedEnd =
        MelbourneCivilTime
            { civilDate = addDays endDayOffset targetStartDate
            , civilTimeOfDay = sourceEndLocal.localTimeOfDay
            , repeatedTimeOccurrence = selections.copiedEndOccurrence
            }

data LocalDayKind
    = LocalWeekday
    | LocalSaturday
    | LocalSunday
    deriving (Eq, Ord, Show)

data LocalTimeWindow
    = OrdinaryWindow
    | EveningWindow
    | EarlyMorningWindow
    deriving (Eq, Ord, Show)

data AwardSegment = AwardSegment
    { segmentStart        :: !ResolvedInstant
    , segmentEnd          :: !ResolvedInstant
    , segmentLocalDate    :: !Day
    , segmentLocalDayKind :: !LocalDayKind
    , segmentLocalWindow  :: !LocalTimeWindow
    }
    deriving (Eq, Show)

awardSegments :: ResolvedInterval -> Either VenueTimeError [AwardSegment]
awardSegments interval = go (resolvedIntervalStart interval)
  where
    finalEnd = resolvedIntervalEnd interval

    go start
        | start >= finalEnd = Right []
        | otherwise = do
            let localStart = resolvedInstantLocalTime start
            boundary <- resolveCivilTime (civilInput (nextAwardBoundary localStart) Nothing)
            let end = min finalEnd boundary
                segment =
                    AwardSegment
                        { segmentStart = start
                        , segmentEnd = end
                        , segmentLocalDate = localStart.localDay
                        , segmentLocalDayKind = localDayKind localStart.localDay
                        , segmentLocalWindow = localTimeWindow localStart.localTimeOfDay
                        }
            remaining <- go end
            pure (segment : remaining)

awardSegmentStart :: AwardSegment -> ResolvedInstant
awardSegmentStart = (.segmentStart)

awardSegmentEnd :: AwardSegment -> ResolvedInstant
awardSegmentEnd = (.segmentEnd)

awardSegmentLocalDate :: AwardSegment -> Day
awardSegmentLocalDate = (.segmentLocalDate)

awardSegmentLocalDayKind :: AwardSegment -> LocalDayKind
awardSegmentLocalDayKind = (.segmentLocalDayKind)

awardSegmentLocalWindow :: AwardSegment -> LocalTimeWindow
awardSegmentLocalWindow = (.segmentLocalWindow)

awardSegmentElapsedSeconds :: AwardSegment -> NominalDiffTime
awardSegmentElapsedSeconds segment =
    diffUTCTime
        (resolvedInstantUTC (awardSegmentEnd segment))
        (resolvedInstantUTC (awardSegmentStart segment))

nextAwardBoundary :: LocalTime -> LocalTime
nextAwardBoundary localTime
    | localTime.localTimeOfDay < ordinaryStart = LocalTime localTime.localDay ordinaryStart
    | localTime.localTimeOfDay < eveningStart = LocalTime localTime.localDay eveningStart
    | otherwise = LocalTime (addDays 1 localTime.localDay) midnight
  where
    ordinaryStart = TimeOfDay 7 0 0
    eveningStart = TimeOfDay 19 0 0

localDayKind :: Day -> LocalDayKind
localDayKind day =
    case let (_, _, weekday) = toWeekDate day in weekday of
        6 -> LocalSaturday
        7 -> LocalSunday
        _ -> LocalWeekday

localTimeWindow :: TimeOfDay -> LocalTimeWindow
localTimeWindow timeOfDay
    | timeOfDay < TimeOfDay 7 0 0 = EarlyMorningWindow
    | timeOfDay < TimeOfDay 19 0 0 = OrdinaryWindow
    | otherwise = EveningWindow

civilInput :: LocalTime -> Maybe RepeatedTimeOccurrence -> MelbourneCivilTime
civilInput localTime occurrence =
    MelbourneCivilTime
        { civilDate = localTime.localDay
        , civilTimeOfDay = localTime.localTimeOfDay
        , repeatedTimeOccurrence = occurrence
        }

data CivilTimeResolution
    = CivilTimeGap
    | CivilTimeUnique !UTCTime
    | CivilTimeRepeated !UTCTime !UTCTime

civilTimeResolution :: LocalTime -> CivilTimeResolution
civilTimeResolution localTime
    | localTime.localDay >= recurringFutureRuleStart = recurringFutureCivilTimeResolution localTime
    | otherwise =
        case localTimeToUTCFull melbourneZone localTime of
            LTUNone _ _                   -> CivilTimeGap
            LTUUnique utc _               -> CivilTimeUnique utc
            LTUAmbiguous first second _ _ -> CivilTimeRepeated first second

recurringFutureCivilTimeResolution :: LocalTime -> CivilTimeResolution
recurringFutureCivilTimeResolution localTime
    | localTime.localDay == daylightStartDay
        && localTime.localTimeOfDay >= TimeOfDay 2 0 0
        && localTime.localTimeOfDay < TimeOfDay 3 0 0 = CivilTimeGap
    | localTime.localDay == daylightEndDay
        && localTime.localTimeOfDay >= TimeOfDay 2 0 0
        && localTime.localTimeOfDay < TimeOfDay 3 0 0 =
            CivilTimeRepeated
                (localTimeToUTC melbourneDaylightTimeZone localTime)
                (localTimeToUTC melbourneStandardTimeZone localTime)
    | otherwise = CivilTimeUnique (localTimeToUTC applicableTimeZone localTime)
  where
    (year, _, _) = toGregorian localTime.localDay
    daylightEndDay = firstSundayOfMonth year 4
    daylightStartDay = firstSundayOfMonth year 10
    applicableTimeZone
        | localTime.localDay < daylightEndDay = melbourneDaylightTimeZone
        | localTime.localDay == daylightEndDay
            && localTime.localTimeOfDay < TimeOfDay 2 0 0 = melbourneDaylightTimeZone
        | localTime.localDay < daylightStartDay = melbourneStandardTimeZone
        | localTime.localDay == daylightStartDay
            && localTime.localTimeOfDay < TimeOfDay 2 0 0 = melbourneStandardTimeZone
        | otherwise = melbourneDaylightTimeZone

usesRecurringFutureRule :: UTCTime -> Bool
usesRecurringFutureRule utc =
    utctDay (addUTCTime (11 * 60 * 60) utc) >= recurringFutureRuleStart

recurringFutureUTCToLocalTime :: UTCTime -> LocalTime
recurringFutureUTCToLocalTime utc = utcToLocalTime applicableTimeZone utc
  where
    approximateLocalDay = utctDay (addUTCTime (11 * 60 * 60) utc)
    (year, _, _) = toGregorian approximateLocalDay
    daylightEndUTC =
        localTimeToUTC
            melbourneDaylightTimeZone
            (LocalTime (firstSundayOfMonth year 4) (TimeOfDay 3 0 0))
    daylightStartUTC =
        localTimeToUTC
            melbourneStandardTimeZone
            (LocalTime (firstSundayOfMonth year 10) (TimeOfDay 2 0 0))
    applicableTimeZone
        | utc >= daylightEndUTC && utc < daylightStartUTC = melbourneStandardTimeZone
        | otherwise = melbourneDaylightTimeZone

firstSundayOfMonth :: Integer -> Int -> Day
firstSundayOfMonth year month =
    addDays (fromIntegral ((7 - weekday) `mod` 7)) firstDay
  where
    firstDay = fromGregorian year month 1
    (_, _, weekday) = toWeekDate firstDay

recurringFutureRuleStart :: Day
recurringFutureRuleStart = fromGregorian 2038 1 1

melbourneStandardTimeZone :: TimeZone
melbourneStandardTimeZone = minutesToTimeZone (10 * 60)

melbourneDaylightTimeZone :: TimeZone
melbourneDaylightTimeZone = minutesToTimeZone (11 * 60)

validateTimeOfDay :: TimeOfDay -> Either VenueTimeError ()
validateTimeOfDay timeOfDay =
    case makeTimeOfDayValid timeOfDay.todHour timeOfDay.todMin timeOfDay.todSec of
        Just validated | validated == timeOfDay -> Right ()
        _ -> Left (InvalidCivilTimeOfDay timeOfDay)

melbourneZone :: TZ
melbourneZone = tzByLabel Australia__Melbourne
