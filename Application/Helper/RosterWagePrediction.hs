{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Application.Helper.RosterWagePrediction
    ( RosterWagePrediction (..)
    , RosterWagePredictionDay (..)
    , fetchRosterWagePrediction
    , lookupRosterWagePredictionDay
    , lookupRosterWagePredictionDayByDate
    , rosterSlotPredictedAutomaticBreakWindow
    , formatMoneyAmount
    ) where

import Application.Helper.Pay (latestVenueEffectiveRate)
import Application.Helper.TimeRules (automaticMealBreakMinutes,
                                     automaticMealBreakStartOffsetMinutes,
                                     automaticMealBreakThresholdMinutes,
                                     validRosterShiftDurationMinutes)
import Application.VenueTime (AwardSegment, LocalDayKind (..),
                              LocalTimeWindow (..), awardSegmentElapsedSeconds,
                              awardSegmentEnd, awardSegmentLocalDate,
                              awardSegmentLocalDayKind, awardSegmentLocalWindow,
                              awardSegmentStart, resolvedInstantUTC)
import Application.VenueTime.Model
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Data.Scientific (Scientific)
import qualified Data.Scientific as Scientific
import Data.Time.Calendar (Day, addDays)
import Data.Time.Clock (NominalDiffTime, UTCTime, addUTCTime, diffUTCTime)
import Data.UUID (UUID)
import Generated.Types
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
            , predictionBreakMinutes = automaticMealBreakMinutes
            }
    where
        rosterDaysById = Map.fromList [(unpackId rosterDay.id, rosterDay) | rosterDay <- rosterDays]

lookupRosterWagePredictionDay :: RosterWagePrediction -> RosterDay -> Maybe RosterWagePredictionDay
lookupRosterWagePredictionDay prediction rosterDay =
    List.find (\day -> day.predictionDayOffset == rosterDay.dayOffset) prediction.predictionDays

lookupRosterWagePredictionDayByDate :: RosterWagePrediction -> Day -> Maybe RosterWagePredictionDay
lookupRosterWagePredictionDayByDate prediction date =
    List.find (\day -> day.predictionDayDate == date) prediction.predictionDays

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
        Just (staffId, shiftTypeId, boundaries, segments) -> do
            staff <- fetch (Id staffId :: Id Staff)
            shiftType <- fetch (Id shiftTypeId :: Id ShiftType)
            let workedOn = addDays (toInteger rosterDay.dayOffset) (weekStartDate venueConfig rosterWeek)
            amount <- predictShiftAmount venueConfig staff shiftType workedOn boundaries segments
            pure (Just PredictedShift { predictedShiftDayOffset = rosterDay.dayOffset, predictedShiftAmount = amount })

predictShiftAmount ::
    (?modelContext :: ModelContext) =>
    VenueConfig ->
    Staff ->
    ShiftType ->
    Day ->
    AuthoritativeBoundaries ->
    [AwardSegment] ->
    IO Scientific
predictShiftAmount venueConfig staff shiftType workedOn boundaries segments = do
    case shiftType.overrideAwardLevelId <|> staff.defaultAwardLevelId of
        Nothing -> pure 0
        Just awardLevelId -> do
            awardLevel <- fetch awardLevelId
            baseRate <- fetchBaseRate venueConfig awardLevel staff.employmentBasis workedOn
            segmentAmounts <- forM segments \segment -> do
                let segmentDate = awardSegmentLocalDate segment
                penaltyKind <- resolveSegmentPenaltyKind venueConfig segment
                hourlyRate <- segmentHourlyRate venueConfig awardLevel staff.employmentBasis workedOn segmentDate baseRate penaltyKind
                let paidHours = nominalDiffTimeHours (paidSecondsInSegment automaticBreakWindow segment)
                pure (roundMoney (paidHours * hourlyRate))
            pure (roundMoney (sum segmentAmounts))
  where
    automaticBreakWindow = predictedAutomaticMealBreakWindow boundaries

completeRosterSlot :: RosterSlot -> Maybe (UUID, UUID, AuthoritativeBoundaries, [AwardSegment])
completeRosterSlot slot = do
    staffId <- slot.staffId
    shiftTypeId <- slot.shiftTypeId
    startTime <- rosterSlotStartTime slot
    endTime <- rosterSlotEndTime slot
    _ <- validRosterShiftDurationMinutes startTime endTime
    boundaries <- rosterSlotPredictionBoundaries slot
    segments <- either (const Nothing) Just (authoritativeAwardSegments boundaries)
    pure (staffId, shiftTypeId, boundaries, segments)

staffedIncomplete :: RosterSlot -> Bool
staffedIncomplete slot =
    isJust slot.staffId && isNothing (completeRosterSlot slot)

rosterSlotPredictedAutomaticBreakWindow :: RosterSlot -> Maybe (UTCTime, UTCTime)
rosterSlotPredictedAutomaticBreakWindow slot = do
    boundaries <- rosterSlotPredictionBoundaries slot
    predictedAutomaticMealBreakWindow boundaries

rosterSlotPredictionBoundaries :: RosterSlot -> Maybe AuthoritativeBoundaries
rosterSlotPredictionBoundaries slot = do
    startsAt <- slot.startsAt
    endsAt <- slot.endsAt
    either (const Nothing) Just (authoritativeBoundariesFromInstants slot.timezone startsAt endsAt Nothing Nothing)

predictedAutomaticMealBreakWindow :: AuthoritativeBoundaries -> Maybe (UTCTime, UTCTime)
predictedAutomaticMealBreakWindow boundaries
    | authoritativeElapsedSeconds boundaries >= minutesToNominalDiffTime automaticMealBreakThresholdMinutes =
        let breakStart = addUTCTime (minutesToNominalDiffTime automaticMealBreakStartOffsetMinutes) (authoritativeStartsAt boundaries)
         in Just (breakStart, addUTCTime (minutesToNominalDiffTime automaticMealBreakMinutes) breakStart)
    | otherwise = Nothing

paidSecondsInSegment :: Maybe (UTCTime, UTCTime) -> AwardSegment -> NominalDiffTime
paidSecondsInSegment maybeBreakWindow segment =
    max 0 (awardSegmentElapsedSeconds segment - breakOverlapSeconds)
  where
    segmentStart = resolvedInstantUTC (awardSegmentStart segment)
    segmentEnd = resolvedInstantUTC (awardSegmentEnd segment)
    breakOverlapSeconds =
        case maybeBreakWindow of
            Nothing -> 0
            Just (breakStart, breakEnd) ->
                max 0 (diffUTCTime (min segmentEnd breakEnd) (max segmentStart breakStart))

minutesToNominalDiffTime :: Int -> NominalDiffTime
minutesToNominalDiffTime minutes = fromIntegral (minutes * 60)

nominalDiffTimeHours :: NominalDiffTime -> Scientific
nominalDiffTimeHours seconds = fromRational (toRational seconds) / 3600

resolveSegmentPenaltyKind ::
    (?modelContext :: ModelContext) =>
    VenueConfig ->
    AwardSegment ->
    IO (Maybe AwardPenaltyKindEnum)
resolveSegmentPenaltyKind venueConfig segment = do
    publicHoliday <- isPublicHolidayForVenue venueConfig (awardSegmentLocalDate segment)
    pure $
        if publicHoliday
            then Just PublicHolidayPenalty
            else case awardSegmentLocalDayKind segment of
                LocalSaturday -> Just SaturdayPenalty
                LocalSunday -> Just SundayPenalty
                LocalWeekday -> case awardSegmentLocalWindow segment of
                    EarlyMorningWindow -> Just LateNightAfterMidnight
                    OrdinaryWindow     -> Nothing
                    EveningWindow      -> Just EveningAfter7Pm

isPublicHolidayForVenue :: (?modelContext :: ModelContext) => VenueConfig -> Day -> IO Bool
isPublicHolidayForVenue venueConfig day =
    query @PublicHoliday
        |> filterWhere (#jurisdiction, venueConfig.publicHolidayJurisdiction)
        |> filterWhere (#holidayDate, day)
        |> filterWhere (#isRegional, False)
        |> fetchExists

segmentHourlyRate ::
    (?modelContext :: ModelContext) =>
    VenueConfig ->
    AwardLevel ->
    StaffEmploymentBasisEnum ->
    Day ->
    Day ->
    Scientific ->
    Maybe AwardPenaltyKindEnum ->
    IO Scientific
segmentHourlyRate _ _ _ _ _ baseRate Nothing =
    pure baseRate
segmentHourlyRate venueConfig awardLevel employmentBasis workedOn segmentDate baseRate (Just penaltyKind)
    | penaltyKind `elem` [SaturdayPenalty, SundayPenalty, PublicHolidayPenalty] =
        fromMaybe baseRate <$> fetchPenaltyRate venueConfig awardLevel employmentBasis segmentDate penaltyKind
    | penaltyKind `elem` [EveningAfter7Pm, LateNightAfterMidnight] = do
        maybeAllowance <- fetchTimeAllowance venueConfig awardLevel segmentDate penaltyKind
        case maybeAllowance of
            Just allowance -> pure (baseRate + allowance)
            Nothing -> do
                maybePenaltyRate <- fetchPenaltyRate venueConfig awardLevel employmentBasis segmentDate penaltyKind
                pure (maybe baseRate (\penaltyRate -> baseRate + max 0 (penaltyRate - baseRate)) maybePenaltyRate)
    | otherwise =
        fromMaybe baseRate <$> fetchPenaltyRate venueConfig awardLevel employmentBasis workedOn penaltyKind

fetchBaseRate ::
    (?modelContext :: ModelContext) =>
    VenueConfig ->
    AwardLevel ->
    StaffEmploymentBasisEnum ->
    Day ->
    IO Scientific
fetchBaseRate venueConfig awardLevel employmentBasis workedOn = do
    rates <- query @AwardLevelBaseRate
        |> filterWhere (#awardLevelId, unpackId awardLevel.id)
        |> filterWhere (#employmentBasis, employmentBasis)
        |> fetch
    pure (maybe 0 (.hourlyRate) (latestVenueEffectiveRate venueConfig.rosterWeekStartsOn workedOn rates))

fetchPenaltyRate ::
    (?modelContext :: ModelContext) =>
    VenueConfig ->
    AwardLevel ->
    StaffEmploymentBasisEnum ->
    Day ->
    AwardPenaltyKindEnum ->
    IO (Maybe Scientific)
fetchPenaltyRate venueConfig awardLevel employmentBasis segmentDate penaltyKind = do
    rates <- query @AwardLevelPenaltyRate
        |> filterWhere (#awardLevelId, unpackId awardLevel.id)
        |> filterWhere (#employmentBasis, employmentBasis)
        |> filterWhere (#penaltyKind, penaltyKind)
        |> fetch
    pure ((.hourlyRate) <$> latestVenueEffectiveRate venueConfig.rosterWeekStartsOn segmentDate rates)

fetchTimeAllowance ::
    (?modelContext :: ModelContext) =>
    VenueConfig ->
    AwardLevel ->
    Day ->
    AwardPenaltyKindEnum ->
    IO (Maybe Scientific)
fetchTimeAllowance venueConfig awardLevel segmentDate penaltyKind = do
    allowances <- query @AwardTimePenaltyAllowance
        |> filterWhere (#awardFixedId, awardLevel.awardFixedId)
        |> filterWhere (#penaltyKind, penaltyKind)
        |> fetch
    pure ((.hourlyAmount) <$> latestVenueEffectiveRate venueConfig.rosterWeekStartsOn segmentDate allowances)

weekStartDate :: VenueConfig -> RosterWeek -> Day
weekStartDate venueConfig rosterWeek =
    addDays (toInteger (rosterWeek.weekOffset * 7)) venueConfig.weekOffsetEpoch

roundMoney :: Scientific -> Scientific
roundMoney value =
    fromInteger (round (value * 100) :: Integer) / 100

formatMoneyAmount :: Scientific -> Text
formatMoneyAmount value =
    "$" <> cs (Scientific.formatScientific Scientific.Fixed (Just 2) (roundMoney value))
