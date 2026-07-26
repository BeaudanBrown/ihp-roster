module Application.Support.WageSourceFixtures
    ( ensureFreshWageSourceFacts
    , sealApprovedFixtureCalculation
    ) where

import Application.Helper.Pay (PaySegment (..), TimesheetPayResult (..),
                               fetchTimesheetPayResultsForEntries,
                               timesheetEntryIdKey)
import Application.VenueTime (melbourneTimeZoneName)
import Application.VenueTime.Model (resolveBoundaryInstant,
                                    timesheetEntryWorkedOn)
import Application.WageEngine (WageCalculationVersion (..),
                               currentWageCalculationVersion)
import Control.Monad (void)
import qualified Data.Map.Strict as Map
import qualified Data.Scientific as Scientific
import qualified Data.Text as Text
import Data.Time.Calendar (Day, fromGregorian, toGregorian)
import Data.Time.Clock (addUTCTime)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude
import IHP.Prelude

ensureFreshWageSourceFacts :: (?modelContext :: ModelContext) => Day -> IO ()
ensureFreshWageSourceFacts workedOn = do
    now <- getCurrentTime
    let (year, _, _) = toGregorian workedOn
    _ <- newRecord @FwcMapdSyncRun
        |> set #status ("succeeded" :: Text)
        |> set #requestedAwardFixedIds [9]
        |> set #syncedAwardFixedIds [9]
        |> set #startedAt now
        |> set #finishedAt (Just now)
        |> createRecord
    existingHoliday <- query @PublicHoliday
        |> filterWhere (#jurisdiction, "VIC" :: Text)
        |> filterWhere (#holidayDate, fromGregorian year 1 1)
        |> filterWhere (#isRegional, False)
        |> fetchOneOrNothing
    when (isNothing existingHoliday) do
        void $ newRecord @PublicHoliday
            |> set #jurisdiction ("VIC" :: Text)
            |> set #holidayDate (fromGregorian year 1 1)
            |> set #name ("New Year's Day" :: Text)
            |> set #isRegional False
            |> set #source (Just "DataVic")
            |> set #importedAt (Just now)
            |> createRecord

sealApprovedFixtureCalculation :: (?modelContext :: ModelContext) => TimesheetEntry -> IO TimesheetEntry
sealApprovedFixtureCalculation entry = do
    staffVersionId <- maybe (fail "fixture missing staff pay version") pure entry.staffPayVersionId
    shiftVersionId <- maybe (fail "fixture missing shift pay version") pure entry.shiftTypePayVersionId
    approvedAt <- maybe (fail "fixture missing approval time") pure entry.approvedAt
    approvedBy <- maybe (fail "fixture missing approver") pure entry.approvedByUserId
    staffVersion <- fetch (Id staffVersionId :: Id StaffPayVersion)
    shiftVersion <- fetch (Id shiftVersionId :: Id ShiftTypePayVersion)
    let importedItemId = shiftVersion.importedXeroPayItemId <|> staffVersion.importedXeroPayItemId
        calculationSource = if isJust importedItemId then "external_imported_pay_item" else "hospitality_award" :: Text
        sourceCondition = maybe "ordinary" (\itemId -> "external_imported_pay_item:" <> inputValue itemId) importedItemId
    now <- getCurrentTime
    calculation <- newRecord @TimesheetPayCalculation
        |> set #timesheetEntryId (unpackId entry.id)
        |> set #calculationVersion (let WageCalculationVersion value = currentWageCalculationVersion in value)
        |> set #calculationSource calculationSource
        |> set #venueTimezone ("Australia/Melbourne" :: Text)
        |> set #holidayJurisdiction ("VIC" :: Text)
        |> set #staffPayVersionId staffVersionId
        |> set #shiftTypePayVersionId shiftVersionId
        |> set #approvedAt approvedAt
        |> set #approvedByUserId approvedBy
        |> createRecord
    payResults <- fetchTimesheetPayResultsForEntries [entry]
    let paySegments = maybe [] (.segments) (Map.lookup (timesheetEntryIdKey entry.id) payResults)
    forM_ (zip [0 :: Int ..] (filter ((> 0) . (.minutes)) paySegments)) \(ordinal, segment) -> do
        let segmentDay = fromMaybe (timesheetEntryWorkedOn entry) segment.segmentDate
            segmentHours = toRational segment.minutes / 60
            fallbackRate = if segmentHours == 0 then 0 else toRational segment.amount / segmentHours
            segmentStart = fixtureSegmentStart segmentDay segment.segment
            persistedCondition = fixtureSourceCondition calculationSource sourceCondition segment
        (segmentRate, rateIdentity) <- fixtureComponentRateAndSource staffVersion segment persistedCondition fallbackRate
        void $ newRecord @TimesheetPayTimeSegment
            |> set #timesheetPayCalculationId (unpackId calculation.id)
            |> set #ordinal ordinal
            |> set #paidTimeKind ("worked" :: Text)
            |> set #startsAt segmentStart
            |> set #endsAt (addUTCTime (fromRational (toRational segment.minutes * 60)) segmentStart)
            |> set #localDate segmentDay
            |> set #sourceCondition persistedCondition
            |> createRecord
        void $ newRecord @TimesheetPayEarningsComponent
            |> set #timesheetPayCalculationId (unpackId calculation.id)
            |> set #ordinal ordinal
            |> set #quantity (fst (Scientific.fromRationalRepetendUnlimited segmentHours))
            |> set #unitType ("hours" :: Text)
            |> set #ratePerUnit (fst (Scientific.fromRationalRepetendUnlimited segmentRate))
            |> set #exactAmount (fst (Scientific.fromRationalRepetendUnlimited (segmentHours * segmentRate)))
            |> set #sourceCondition persistedCondition
            |> set #calculationSource calculationSource
            |> set #sourceRateIdentity rateIdentity
            |> createRecord
    sealed <- calculation |> set #sealedAt (Just now) |> updateRecord
    entry
        |> set #activePayCalculationId (Just sealed.id)
        |> set #legacyPayBackfillPending False
        |> updateRecord

fixtureComponentRateAndSource :: (?modelContext :: ModelContext) => StaffPayVersion -> PaySegment -> Text -> Rational -> IO (Rational, Maybe Text)
fixtureComponentRateAndSource staffVersion segment condition fallbackRate
    | Text.isPrefixOf "external_imported_pay_item:" condition = pure (fallbackRate, Nothing)
    | condition == "missed_meal_break_addition" = do
        maybeBaseRate <- fetchBaseRate Permanent
        pure $ case maybeBaseRate of
            Just baseRate -> (toRational baseRate.hourlyRate / 2, Just (baseIdentity baseRate))
            Nothing       -> fallback
    | condition == "saturday" = fetchPenaltyRate SaturdayPenalty
    | condition == "sunday" = fetchPenaltyRate SundayPenalty
    | condition == "public_holiday" = fetchPenaltyRate PublicHolidayPenalty
    | otherwise = do
        maybeBaseRate <- fetchBaseRate staffVersion.employmentBasis
        pure $ case maybeBaseRate of
            Just baseRate -> (toRational baseRate.hourlyRate, Just (baseIdentity baseRate))
            Nothing       -> fallback
  where
    fallback = (fallbackRate, Just "fixture:sealed-approved-calculation")
    payLevelId = fromMaybe (error "fixture segment missing pay level") segment.payLevelId
    fetchBaseRate basis =
        query @AwardLevelBaseRate
            |> filterWhere (#awardLevelId, payLevelId)
            |> filterWhere (#employmentBasis, basis)
            |> orderByDesc #createdAt
            |> fetchOneOrNothing
    fetchPenaltyRate kind = do
        maybeRate <- query @AwardLevelPenaltyRate
            |> filterWhere (#awardLevelId, payLevelId)
            |> filterWhere (#employmentBasis, staffVersion.employmentBasis)
            |> filterWhere (#penaltyKind, kind)
            |> orderByDesc #createdAt
            |> fetchOneOrNothing
        pure $ case maybeRate of
            Just rate -> (toRational rate.hourlyRate, Just (penaltyIdentity rate))
            Nothing   -> fallback
    baseIdentity rate = projectionSourceIdentity "award_level_base_rates" (unpackId rate.id) "fwc_mapd_pay_rates" rate.fwcMapdPayRateId
    penaltyIdentity rate = projectionSourceIdentity "award_level_penalty_rates" (unpackId rate.id) "fwc_mapd_penalty_rates" rate.fwcMapdPenaltyRateId

projectionSourceIdentity :: Text -> UUID -> Text -> UUID -> Text
projectionSourceIdentity projectionTable projectionId sourceTable sourceId =
    "bepis-projection:" <> projectionTable <> ":" <> tshow projectionId <> "/source:" <> sourceTable <> ":" <> tshow sourceId

fixtureSourceCondition :: Text -> Text -> PaySegment -> Text
fixtureSourceCondition calculationSource importedCondition segment
    | calculationSource == "external_imported_pay_item" = importedCondition
    | otherwise = case fromMaybe "ordinary" segment.penaltyKind of
        "saturday_penalty"                  -> "saturday"
        "sunday_penalty"                    -> "sunday"
        "public_holiday_penalty"            -> "public_holiday"
        "delayed_meal_break_weekday"        -> "missed_meal_break_addition"
        "delayed_meal_break_saturday"       -> "missed_meal_break_addition"
        "delayed_meal_break_sunday"         -> "missed_meal_break_addition"
        "delayed_meal_break_public_holiday" -> "missed_meal_break_addition"
        _                                   -> "ordinary"

fixtureSegmentStart :: Day -> Text -> UTCTime
fixtureSegmentStart day segmentName =
    case resolveBoundaryInstant melbourneTimeZoneName day representativeTime Nothing of
        Left err      -> error (show err)
        Right instant -> instant
  where
    representativeTime
        | segmentName == "evening_after_7pm" = TimeOfDay 19 0 0
        | segmentName == "late_night_after_midnight" = TimeOfDay 0 0 0
        | otherwise = TimeOfDay 9 0 0
