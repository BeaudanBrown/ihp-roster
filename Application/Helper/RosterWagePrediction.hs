{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Application.Helper.RosterWagePrediction
    ( RosterWagePrediction (..)
    , RosterWagePredictionDay (..)
    , fetchRosterWagePrediction
    , formatMoneyAmount
    ) where

import Application.Helper.TimeRules (shiftDurationMinutes, timeOfDayToMinutes)
import Application.Helper.WeekBoundaries (weekdayIndexForDay)
import Control.Monad (guard)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Data.Ord (Down (..))
import Data.Scientific (Scientific)
import qualified Data.Scientific as Scientific
import Data.Time.Calendar (Day, addDays)
import Data.Time.Clock (UTCTime)
import Data.Time.LocalTime (TimeOfDay)
import Data.UUID (UUID)
import Generated.Types
import GHC.Records (HasField)
import IHP.ControllerPrelude

data RosterWagePrediction = RosterWagePrediction
    { predictionDays                 :: ![RosterWagePredictionDay]
    , predictionWeekTotal            :: !Scientific
    , predictionCompleteShiftCount   :: !Int
    , predictionIncompleteShiftCount :: !Int
    , predictionBreakMinutes         :: !Int
    }
    deriving (Eq, Show)

data RosterWagePredictionDay = RosterWagePredictionDay
    { predictionDayDate       :: !Day
    , predictionDayOffset     :: !Int
    , predictionDayTotal      :: !Scientific
    , predictionDayShiftCount :: !Int
    }
    deriving (Eq, Show)

data PredictedShift = PredictedShift
    { predictedShiftDayOffset :: !Int
    , predictedShiftAmount    :: !Scientific
    }
    deriving (Eq, Show)

data PayWindow = PayWindow
    { windowStartMinute :: !Int
    , windowEndMinute   :: !Int
    , windowPenaltyKind :: !(Maybe AwardPenaltyKindEnum)
    }

fetchRosterWagePrediction ::
    (?modelContext :: ModelContext) =>
    VenueConfig ->
    RosterWeek ->
    [RosterDay] ->
    [RosterSlot] ->
    IO RosterWagePrediction
fetchRosterWagePrediction venueConfig rosterWeek rosterDays rosterSlots = do
    predictedShifts <- catMaybes <$>
        forM rosterSlots \slot ->
            case Map.lookup slot.rosterDayId rosterDaysById of
                Nothing -> pure Nothing
                Just rosterDay -> predictRosterSlot venueConfig rosterWeek rosterDay slot
    let predictionDays =
            [ predictionDay (weekStartDate venueConfig rosterWeek) rosterDay predictedShifts
            | rosterDay <- rosterDays
            ]
    pure
        RosterWagePrediction
            { predictionDays
            , predictionWeekTotal = roundMoney (sum (map (.predictionDayTotal) predictionDays))
            , predictionCompleteShiftCount = length predictedShifts
            , predictionIncompleteShiftCount = length (filter staffedIncomplete rosterSlots)
            , predictionBreakMinutes = assumedBreakMinutes
            }
    where
        rosterDaysById = Map.fromList [(unpackId rosterDay.id, rosterDay) | rosterDay <- rosterDays]

predictionDay :: Day -> RosterDay -> [PredictedShift] -> RosterWagePredictionDay
predictionDay weekStart rosterDay predictedShifts =
    let dayShifts = filter (\shift -> shift.predictedShiftDayOffset == rosterDay.dayOffset) predictedShifts
     in RosterWagePredictionDay
            { predictionDayDate = addDays (toInteger rosterDay.dayOffset) weekStart
            , predictionDayOffset = rosterDay.dayOffset
            , predictionDayTotal = roundMoney (sum (map (.predictedShiftAmount) dayShifts))
            , predictionDayShiftCount = length dayShifts
            }

predictRosterSlot ::
    (?modelContext :: ModelContext) =>
    VenueConfig ->
    RosterWeek ->
    RosterDay ->
    RosterSlot ->
    IO (Maybe PredictedShift)
predictRosterSlot venueConfig rosterWeek rosterDay slot =
    case completeRosterSlot slot of
        Nothing -> pure Nothing
        Just (staffId, shiftTypeId, startTime, endTime) -> do
            staff <- fetch (Id staffId :: Id Staff)
            shiftType <- fetch (Id shiftTypeId :: Id ShiftType)
            let workedOn = addDays (toInteger rosterDay.dayOffset) (weekStartDate venueConfig rosterWeek)
            amount <- predictShiftAmount venueConfig staff shiftType workedOn startTime endTime
            pure (Just PredictedShift { predictedShiftDayOffset = rosterDay.dayOffset, predictedShiftAmount = amount })

predictShiftAmount ::
    (?modelContext :: ModelContext) =>
    VenueConfig ->
    Staff ->
    ShiftType ->
    Day ->
    TimeOfDay ->
    TimeOfDay ->
    IO Scientific
predictShiftAmount venueConfig staff shiftType workedOn startTime endTime = do
    case shiftType.overrideAwardLevelId <|> staff.defaultAwardLevelId of
        Nothing -> pure 0
        Just awardLevelId -> do
            awardLevel <- fetch awardLevelId
            baseRate <- fetchBaseRate awardLevel staff.employmentBasis workedOn
            segmentAmounts <- forM (payWindowsForShift startTime endTime) \window -> do
                let segmentDate = segmentDateForWindow workedOn window
                penaltyKind <- resolveWindowPenaltyKind venueConfig segmentDate window
                hourlyRate <- segmentHourlyRate awardLevel staff.employmentBasis workedOn segmentDate baseRate penaltyKind
                pure (roundMoney (fromIntegral (paidMinutesInWindow startTime endTime window) / 60 * hourlyRate))
            pure (roundMoney (sum segmentAmounts))

completeRosterSlot :: RosterSlot -> Maybe (UUID, UUID, TimeOfDay, TimeOfDay)
completeRosterSlot slot = do
    staffId <- slot.staffId
    shiftTypeId <- slot.shiftTypeId
    startTime <- slot.startTime
    endTime <- slot.endTime
    guard (shiftDurationMinutes startTime endTime > 0)
    pure (staffId, shiftTypeId, startTime, endTime)

staffedIncomplete :: RosterSlot -> Bool
staffedIncomplete slot =
    isJust slot.staffId && isNothing (completeRosterSlot slot)

payWindowsForShift :: TimeOfDay -> TimeOfDay -> [PayWindow]
payWindowsForShift startTime endTime =
    filter ((> 0) . paidMinutesInWindow startTime endTime)
        [ PayWindow 0 420 (Just LateNightAfterMidnight)
        , PayWindow 420 1140 Nothing
        , PayWindow 1140 1440 (Just EveningAfter7Pm)
        , PayWindow 1440 1860 (Just LateNightAfterMidnight)
        ]

paidMinutesInWindow :: TimeOfDay -> TimeOfDay -> PayWindow -> Int
paidMinutesInWindow startTime endTime PayWindow { windowStartMinute, windowEndMinute } =
    max 0 (min paidEnd windowEndMinute - max startMinute windowStartMinute)
    where
        startMinute = normalizeShiftMinute startTime
        endMinute = normalizeShiftMinute endTime
        paidEnd = max startMinute (endMinute - predictedBreakMinutes startTime endTime)

predictedBreakMinutes :: TimeOfDay -> TimeOfDay -> Int
predictedBreakMinutes startTime endTime =
    if shiftDurationMinutes startTime endTime > 360
        then assumedBreakMinutes
        else 0

assumedBreakMinutes :: Int
assumedBreakMinutes = 30

normalizeShiftMinute :: TimeOfDay -> Int
normalizeShiftMinute timeOfDay =
    let minute = timeOfDayToMinutes timeOfDay
     in if minute < 360 then minute + 1440 else minute

segmentDateForWindow :: Day -> PayWindow -> Day
segmentDateForWindow workedOn window =
    addDays (if window.windowStartMinute >= 1440 then 1 else 0) workedOn

resolveWindowPenaltyKind ::
    (?modelContext :: ModelContext) =>
    VenueConfig ->
    Day ->
    PayWindow ->
    IO (Maybe AwardPenaltyKindEnum)
resolveWindowPenaltyKind venueConfig segmentDate window = do
    publicHoliday <- isPublicHolidayForVenue venueConfig segmentDate
    pure $
        if publicHoliday
            then Just PublicHolidayPenalty
            else case weekdayIndexForDay segmentDate of
                6 -> Just SaturdayPenalty
                0 -> Just SundayPenalty
                _ -> window.windowPenaltyKind

isPublicHolidayForVenue :: (?modelContext :: ModelContext) => VenueConfig -> Day -> IO Bool
isPublicHolidayForVenue venueConfig day =
    query @PublicHoliday
        |> filterWhere (#jurisdiction, venueConfig.publicHolidayJurisdiction)
        |> filterWhere (#holidayDate, day)
        |> filterWhere (#isRegional, False)
        |> fetchExists

segmentHourlyRate ::
    (?modelContext :: ModelContext) =>
    AwardLevel ->
    StaffEmploymentBasisEnum ->
    Day ->
    Day ->
    Scientific ->
    Maybe AwardPenaltyKindEnum ->
    IO Scientific
segmentHourlyRate _ _ _ _ baseRate Nothing =
    pure baseRate
segmentHourlyRate awardLevel employmentBasis workedOn segmentDate baseRate (Just penaltyKind)
    | penaltyKind `elem` [SaturdayPenalty, SundayPenalty, PublicHolidayPenalty] =
        fromMaybe baseRate <$> fetchPenaltyRate awardLevel employmentBasis segmentDate penaltyKind
    | penaltyKind `elem` [EveningAfter7Pm, LateNightAfterMidnight] = do
        maybeAllowance <- fetchTimeAllowance awardLevel segmentDate penaltyKind
        case maybeAllowance of
            Just allowance -> pure (baseRate + allowance)
            Nothing -> do
                maybePenaltyRate <- fetchPenaltyRate awardLevel employmentBasis segmentDate penaltyKind
                pure (maybe baseRate (\penaltyRate -> baseRate + max 0 (penaltyRate - baseRate)) maybePenaltyRate)
    | otherwise =
        fromMaybe baseRate <$> fetchPenaltyRate awardLevel employmentBasis workedOn penaltyKind

fetchBaseRate ::
    (?modelContext :: ModelContext) =>
    AwardLevel ->
    StaffEmploymentBasisEnum ->
    Day ->
    IO Scientific
fetchBaseRate awardLevel employmentBasis workedOn = do
    rates <- query @AwardLevelBaseRate
        |> filterWhere (#awardLevelId, unpackId awardLevel.id)
        |> filterWhere (#employmentBasis, employmentBasis)
        |> fetch
    pure (maybe 0 (.hourlyRate) (latestEffective workedOn rates))

fetchPenaltyRate ::
    (?modelContext :: ModelContext) =>
    AwardLevel ->
    StaffEmploymentBasisEnum ->
    Day ->
    AwardPenaltyKindEnum ->
    IO (Maybe Scientific)
fetchPenaltyRate awardLevel employmentBasis segmentDate penaltyKind = do
    rates <- query @AwardLevelPenaltyRate
        |> filterWhere (#awardLevelId, unpackId awardLevel.id)
        |> filterWhere (#employmentBasis, employmentBasis)
        |> filterWhere (#penaltyKind, penaltyKind)
        |> fetch
    pure ((.hourlyRate) <$> latestEffective segmentDate rates)

fetchTimeAllowance ::
    (?modelContext :: ModelContext) =>
    AwardLevel ->
    Day ->
    AwardPenaltyKindEnum ->
    IO (Maybe Scientific)
fetchTimeAllowance awardLevel segmentDate penaltyKind = do
    allowances <- query @AwardTimePenaltyAllowance
        |> filterWhere (#awardFixedId, awardLevel.awardFixedId)
        |> filterWhere (#penaltyKind, penaltyKind)
        |> fetch
    pure ((.hourlyAmount) <$> latestEffective segmentDate allowances)

latestEffective :: (HasField "operativeFrom" record (Maybe Day), HasField "operativeTo" record (Maybe Day), HasField "createdAt" record UTCTime) => Day -> [record] -> Maybe record
latestEffective day =
    List.find (effectiveOn day)
        . List.sortOn (\record -> (Down record.operativeFrom, Down record.createdAt))

effectiveOn :: (HasField "operativeFrom" record (Maybe Day), HasField "operativeTo" record (Maybe Day)) => Day -> record -> Bool
effectiveOn day record =
    maybe True (<= day) record.operativeFrom
        && maybe True (>= day) record.operativeTo

weekStartDate :: VenueConfig -> RosterWeek -> Day
weekStartDate venueConfig rosterWeek =
    addDays (toInteger (rosterWeek.weekOffset * 7)) venueConfig.weekOffsetEpoch

roundMoney :: Scientific -> Scientific
roundMoney value =
    fromInteger (round (value * 100) :: Integer) / 100

formatMoneyAmount :: Scientific -> Text
formatMoneyAmount value =
    "$" <> cs (Scientific.formatScientific Scientific.Fixed (Just 2) (roundMoney value))
