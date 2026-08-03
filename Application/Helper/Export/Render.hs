module Application.Helper.Export.Render where

import Application.Helper.Controller
import Application.Helper.Export.Types
import Application.VenueTime (RepeatedTimeOccurrence (..))
import Application.VenueTime.Model (civilBoundaryIsRepeated,
                                    resolveBoundaryInstant,
                                    storedInstantLocalTime,
                                    timesheetEntryBreakElapsedSeconds,
                                    timesheetEntryBreakEndTime,
                                    timesheetEntryBreakStartTime,
                                    timesheetEntryEndTime,
                                    timesheetEntryHadBreak,
                                    timesheetEntryStartTime,
                                    timesheetEntryWorkedOn)
import Application.WagePublication (StaffHoursBucketKind (..),
                                    StaffHoursContribution (..))
import qualified Codec.Archive.Zip as Zip
import qualified Data.ByteString.Base64 as Base64
import qualified Data.ByteString.Lazy as LBS
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Data.Ratio (denominator, numerator)
import qualified Data.Scientific as Scientific
import qualified Data.Text as Text
import Data.Text.Encoding (decodeUtf8, encodeUtf8)
import Data.Time.Calendar (Day, addDays)
import Data.Time.Clock (NominalDiffTime, UTCTime, diffUTCTime)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Data.Time.LocalTime (LocalTime (..), TimeOfDay (..), addLocalTime)
import Generated.Types
import IHP.ControllerPrelude
import Text.Printf (printf)
import Text.Read (readMaybe)

renderTextZipBase64 :: [(Text, Text)] -> Text
renderTextZipBase64 files =
    decodeUtf8
        (Base64.encode (LBS.toStrict (Zip.fromArchive archive)))
    where
        archive =
            foldr
                (\(fileName, fileContents) currentArchive ->
                    let entry = Zip.toEntry (Text.unpack fileName) 0 (LBS.fromStrict (encodeUtf8 fileContents))
                     in Zip.addEntryToArchive entry currentArchive
                )
                Zip.emptyArchive
                files

renderStaffPayCsv :: ReportWeekSelection -> [StaffPayCsvRecord] -> Text
renderStaffPayCsv reportWeekSelection records =
    Text.unlines (csvHeader : map renderRow records)
    where
        bucketLabels = staffPayBucketLabels reportWeekSelection
        csvHeader =
            Text.intercalate ","
                (map csvCell (["Employee"] <> bucketLabels))

        renderRow record =
            Text.intercalate ","
                ( [csvCell (staffPayNameType record)]
                    <> map formatStaffPayHours record.bucketHours
                )

renderPayrollEarningsCsv :: [PayrollEarningsCsvRecord] -> Text
renderPayrollEarningsCsv records =
    Text.unlines (csvHeader : map renderRow records)
    where
        csvHeader =
            Text.intercalate ","
                [ "staff_first_name"
                , "staff_last_name"
                , "work_date"
                , "earnings_rate_name"
                , "exact_quantity"
                , "quantity"
                , "unit"
                , "rate_per_unit"
                , "exact_amount"
                , "amount"
                , "tracking_code"
                , "description"
                , "staff_id"
                , "timesheet_entry_ids"
                , "pay_config_version_manifest"
                , "calculation_source"
                , "calculation_version"
                , "rate_book_version"
                , "source_condition"
                , "source_rate_identity"
                , "source_pay_level_name"
                , "source_shift_type_name"
                , "approved_at"
                , "approved_by_user_ids"
                , "active_pay_calculation_ids"
                ]

        renderRow record =
            Text.intercalate ","
                [ csvCell record.staffFirstName
                , csvCell record.staffLastName
                , csvCell (tshow record.workDate)
                , csvCell record.earningsRateName
                , csvCell (renderExactRational record.exactQuantity)
                , formatStaffPayHours record.quantity
                , csvCell record.unit
                , formatRationalDecimal 4 record.ratePerUnit
                , csvCell (renderExactRational record.exactAmount)
                , formatRationalDecimal 2 record.amount
                , csvCell (fromMaybe "" record.trackingCode)
                , csvCell record.description
                , csvCell (tshow record.staffId)
                , csvCell (Text.intercalate " " (map tshow record.timesheetEntryIds))
                , csvCell (fromMaybe "" record.payConfigVersionManifest)
                , csvCell record.calculationSource
                , csvCell record.calculationVersion
                , csvCell (fromMaybe "" record.rateBookVersion)
                , csvCell record.sourceCondition
                , csvCell (fromMaybe "" record.sourceRateIdentity)
                , csvCell (fromMaybe "" record.sourcePayLevelName)
                , csvCell (fromMaybe "" record.sourceShiftTypeName)
                , csvCell (Text.intercalate " " (map formatUtc record.approvedAt))
                , csvCell (Text.intercalate " " (map tshow record.approvedByUserIds))
                , csvCell (Text.intercalate " " (map tshow record.activePayCalculationIds))
                ]

staffPayNameType :: StaffPayCsvRecord -> Text
staffPayNameType record =
    record.staffLastName
        <> ", "
        <> record.staffFirstName
        <> maybe "" (" " <>) record.label

data StaffPayBucket = StaffPayBucket
    { bucketDate  :: !Day
    , bucketKind  :: !Text
    , bucketLabel :: !Text
    }
    deriving (Eq, Show)

staffPayBuckets :: ReportWeekSelection -> [StaffPayBucket]
staffPayBuckets reportWeekSelection =
    concatMap bucketsForDay [0 .. 6]
    where
        bucketsForDay dayOffset =
            let date = addDays (toInteger dayOffset) reportWeekSelection.weekStart
                dayLabel = fromMaybe (fallbackReportDayLabel reportWeekSelection.weekStart dayOffset) (safeIndex reportWeekSelection.dayLabels dayOffset)
             in map
                    (\(kind, suffix) ->
                        StaffPayBucket
                            { bucketDate = date
                            , bucketKind = kind
                            , bucketLabel = shortDayLabel dayLabel <> " " <> suffix
                            }
                    )
                    (bucketKindsForDate date)

staffPayBucketLabels :: ReportWeekSelection -> [Text]
staffPayBucketLabels reportWeekSelection =
    map (.bucketLabel) (staffPayBuckets reportWeekSelection)

staffPayContributionBucketIndex :: [StaffPayBucket] -> StaffHoursContribution -> Maybe Int
staffPayContributionBucketIndex buckets contribution =
    List.findIndex
        (\bucket -> bucket.bucketDate == contribution.staffHoursDate && bucket.bucketKind == contributionKind)
        buckets
  where
    contributionKind = case contribution.staffHoursBucketKind of
        StaffHoursOrdinary     -> "ordinary"
        StaffHoursEvening      -> "evening_after_7pm"
        StaffHoursEarlyMorning -> "late_night_after_midnight"

bucketKindsForDate :: Day -> [(Text, Text)]
bucketKindsForDate date =
    case formatTime defaultTimeLocale "%u" date :: String of
        "6" -> [("ordinary", "Ord"), ("late_night_after_midnight", "12+")]
        "7" -> [("ordinary", "Ord")]
        _   -> [("ordinary", "Ord"), ("evening_after_7pm", "7-12"), ("late_night_after_midnight", "12+")]

shortDayLabel :: Text -> Text
shortDayLabel dayLabel =
    case Text.toCaseFold dayLabel of
        "monday"    -> "Mon"
        "tuesday"   -> "Tues"
        "wednesday" -> "Wed"
        "thursday"  -> "Thurs"
        "friday"    -> "Fri"
        "saturday"  -> "Sat"
        "sunday"    -> "Sun"
        _           -> Text.take 4 dayLabel

safeIndex :: [a] -> Int -> Maybe a
safeIndex values index
    | index < 0 = Nothing
    | otherwise =
        case drop index values of
            value : _ -> Just value
            []        -> Nothing

addDayHours :: Int -> Rational -> [Rational] -> [Rational]
addDayHours dayIndex hours existingDayHours =
    [ if index == dayIndex then currentHours + hours else currentHours
    | (index, currentHours) <- zip [0 ..] existingDayHours
    ]

formatStaffPayHours :: Rational -> Text
formatStaffPayHours = formatRationalDecimal 6

formatRationalDecimal :: Int -> Rational -> Text
formatRationalDecimal decimalPlaces value =
    cs (Scientific.formatScientific Scientific.Fixed (Just decimalPlaces) (rationalToScientificAt decimalPlaces value))

renderExactRational :: Rational -> Text
renderExactRational value =
    tshow (numerator value) <> "/" <> tshow (denominator value)

rationalToScientificAt :: Int -> Rational -> Scientific.Scientific
rationalToScientificAt decimalPlaces value =
    Scientific.scientific (round (value * fromInteger scale)) (negate decimalPlaces)
    where
        scale :: Integer
        scale = 10 ^ decimalPlaces

renderHourlyBreakdownDateCsv :: Day -> [ShiftType] -> [TimesheetEntry] -> Text
renderHourlyBreakdownDateCsv date shiftTypes entries =
    Text.unlines (csvHeader : map renderHourRow [8 .. 27])
    where
        csvHeader =
            Text.intercalate ","
                (map csvCell ("Time" : map (.name) shiftTypes))

        dayEntries =
            filter ((== date) . timesheetEntryWorkedOn) entries

        renderHourRow hourOfWindow =
            let windowLabel = formatHourlyWindow hourOfWindow
                hourValues =
                    map
                        (\shiftType ->
                            let hours = sum (map (entryHoursForHourlyWindow hourOfWindow shiftType) dayEntries)
                             in if hours <= 0
                                    then ""
                                    else formatHourlyBreakdownHours hours
                        )
                        shiftTypes
             in Text.intercalate "," (csvCell windowLabel : map csvCell hourValues)

entryHoursForHourlyWindow :: Int -> ShiftType -> TimesheetEntry -> Rational
entryHoursForHourlyWindow hourOfWindow shiftType entry
    | entry.shiftTypeId /= unpackId (get #id shiftType) = 0
    | otherwise =
        let targetDate = addDays (toInteger (hourOfWindow `div` 24)) (timesheetEntryWorkedOn entry)
            targetHour = hourOfWindow `mod` 24
            shiftSeconds = intervalSecondsInLocalHour entry.timezone targetDate targetHour entry.startsAt entry.endsAt
            breakSeconds = case (entry.breakStartsAt, entry.breakEndsAt) of
                (Just breakStartsAt, Just breakEndsAt) -> intervalSecondsInLocalHour entry.timezone targetDate targetHour breakStartsAt breakEndsAt
                _ -> 0
         in toRational (max 0 (shiftSeconds - breakSeconds)) / 3600

intervalSecondsInLocalHour :: Text -> Day -> Int -> UTCTime -> UTCTime -> NominalDiffTime
intervalSecondsInLocalHour timezone targetDate targetHour startsAt endsAt =
    sum
        [ elapsed
        | (localDate, localHour, elapsed) <- storedIntervalLocalHourSegments timezone startsAt endsAt
        , localDate == targetDate
        , localHour == targetHour
        ]

storedIntervalLocalHourSegments :: Text -> UTCTime -> UTCTime -> [(Day, Int, NominalDiffTime)]
storedIntervalLocalHourSegments timezone startsAt endsAt = go startsAt
  where
    go cursor
        | cursor >= endsAt = []
        | otherwise =
            let local = storedInstantLocalTime timezone cursor
                segmentEnd = min endsAt (nextStoredLocalHourBoundary timezone cursor local)
             in (local.localDay, local.localTimeOfDay.todHour, diffUTCTime segmentEnd cursor) : go segmentEnd

nextStoredLocalHourBoundary :: Text -> UTCTime -> LocalTime -> UTCTime
nextStoredLocalHourBoundary timezone cursor local = findBoundary firstCandidateLocal
  where
    localHourStart = LocalTime local.localDay (TimeOfDay local.localTimeOfDay.todHour 0 0)
    firstCandidateLocal = addLocalTime 3600 localHourStart

    findBoundary candidateLocal =
        case filter (> cursor) (resolvedCandidates candidateLocal) of
            []         -> findBoundary (addLocalTime 3600 candidateLocal)
            candidates -> minimum candidates

    resolvedCandidates candidateLocal =
        let occurrences =
                if civilBoundaryIsRepeated candidateLocal.localDay candidateLocal.localTimeOfDay
                    then [Just FirstOccurrence, Just SecondOccurrence]
                    else [Nothing]
         in mapMaybe
                (either (const Nothing) Just . resolveBoundaryInstant timezone candidateLocal.localDay candidateLocal.localTimeOfDay)
                occurrences

formatHourlyWindow :: Int -> Text
formatHourlyWindow hourOfWindow
    | hourOfWindow < 24 = Text.pack (printf "%02d:00" hourOfWindow :: String)
    | otherwise = Text.pack (printf "%02d:00+1" (hourOfWindow - 24) :: String)

formatHourlyBreakdownHours :: Rational -> Text
formatHourlyBreakdownHours = formatRationalDecimal 6

fallbackReportDayLabels :: Day -> [Text]
fallbackReportDayLabels reportWeekStart =
    map (fallbackReportDayLabel reportWeekStart) [0 .. 6]

fallbackReportDayLabel :: Day -> Int -> Text
fallbackReportDayLabel reportWeekStart dayOffset =
    Text.pack (formatTime defaultTimeLocale "%A" (addDays (toInteger dayOffset) reportWeekStart))

renderApprovedTimesheetCsv ::
    [TimesheetEntry] ->
    Map.Map UUID Staff ->
    Map.Map UUID User ->
    Map.Map UUID Text ->
    Text
renderApprovedTimesheetCsv entries staffById approversById versionManifestByEntryId =
    Text.unlines (csvHeader : map renderRow entries)
    where
        csvHeader =
            Text.intercalate ","
                [ "worked_on"
                , "staff_name"
                , "start_time"
                , "end_time"
                , "break_seconds"
                , "pay_config_version_manifest"
                , "approved_at"
                , "approved_by_email"
                ]

        renderRow entry =
            Text.intercalate ","
                [ csvCell (tshow (timesheetEntryWorkedOn entry))
                , csvCell (staffDisplayNameForEntry entry.staffId)
                , csvCell (formatTimeOfDay (timesheetEntryStartTime entry))
                , csvCell (formatTimeOfDay (timesheetEntryEndTime entry))
                , csvCell (formatElapsedSeconds (timesheetEntryBreakElapsedSeconds entry))
                , csvCell (fromMaybe "" (Map.lookup (unpackId entry.id) versionManifestByEntryId))
                , csvCell (maybe "" formatUtc entry.approvedAt)
                , csvCell (maybe "" (.email) (entry.approvedByUserId >>= (`Map.lookup` approversById)))
                ]

        staffDisplayNameForEntry staffId =
            case Map.lookup staffId staffById of
                Just staff -> staff.lastName <> ", " <> staff.firstName
                Nothing    -> "Unknown staff"

formatTimeOfDay :: TimeOfDay -> Text
formatTimeOfDay timeOfDay = Text.pack (formatTime defaultTimeLocale "%H:%M" timeOfDay)

formatElapsedSeconds :: NominalDiffTime -> Text
formatElapsedSeconds elapsedSeconds =
    tshow (fromRational (toRational elapsedSeconds) :: Scientific.Scientific)

formatUtc :: UTCTime -> Text
formatUtc timestamp = Text.pack (formatTime defaultTimeLocale "%Y-%m-%d %H:%M:%S UTC" timestamp)

csvCell :: Text -> Text
csvCell value
    | Text.any (`elem` [',', '"', '\n', '\r', '\t']) neutralizedValue =
        "\"" <> Text.replace "\"" "\"\"" neutralizedValue <> "\""
    | otherwise = neutralizedValue
    where
        neutralizedValue = neutralizeSpreadsheetFormula value

neutralizeSpreadsheetFormula :: Text -> Text
neutralizeSpreadsheetFormula value
    | Text.isPrefixOf "\t" value || Text.isPrefixOf "\r" value || Text.isPrefixOf "\n" value = "'" <> value
    | otherwise =
        case Text.uncons (Text.dropWhile isSpreadsheetFormulaWhitespace value) of
            Just (firstChar, _) | firstChar `elem` ['=', '+', '-', '@'] -> "'" <> value
            _ -> value

isSpreadsheetFormulaWhitespace :: Char -> Bool
isSpreadsheetFormulaWhitespace char =
    char == ' ' || char == '\t' || char == '\r' || char == '\n'
