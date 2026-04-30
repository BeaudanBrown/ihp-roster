module Application.Helper.Export.Render where

import Application.Helper.Controller
import Application.Helper.Export.Types
import Application.Helper.Pay (PaySegment (..), TimesheetPayResult (..))
import qualified Codec.Archive.Zip as Zip
import qualified Data.ByteString.Base64 as Base64
import qualified Data.ByteString.Lazy as LBS
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Text.Encoding (decodeUtf8, encodeUtf8)
import Data.Time.Calendar (Day, addDays)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Data.Time.LocalTime (TimeOfDay)
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
                (map csvCell (["Name/Type"] <> bucketLabels))

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
                , "hours"
                , "tracking_code"
                , "description"
                , "staff_id"
                , "timesheet_entry_ids"
                , "pay_config_version_manifest"
                , "source_penalty_kind"
                , "source_pay_level_name"
                , "source_shift_type_name"
                ]

        renderRow record =
            Text.intercalate ","
                [ csvCell record.staffFirstName
                , csvCell record.staffLastName
                , csvCell (tshow record.workDate)
                , csvCell record.earningsRateName
                , formatStaffPayHours record.hours
                , csvCell (fromMaybe "" record.trackingCode)
                , csvCell record.description
                , csvCell (tshow record.staffId)
                , csvCell (Text.intercalate " " (map tshow record.timesheetEntryIds))
                , csvCell (fromMaybe "" record.payConfigVersionManifest)
                , csvCell record.sourcePenaltyKind
                , csvCell (fromMaybe "" record.sourcePayLevelName)
                , csvCell (fromMaybe "" record.sourceShiftTypeName)
                ]

staffPayNameType :: StaffPayCsvRecord -> Text
staffPayNameType record
    | Text.null record.label = record.staffName
    | otherwise = record.staffName <> " " <> record.label

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

staffPaySegmentBucketIndex :: [StaffPayBucket] -> PaySegment -> Maybe Int
staffPaySegmentBucketIndex buckets segment =
    segment.segmentDate >>= \date ->
        let wantedKind = staffPaySegmentBucketKind date segment.segment
         in List.findIndex (\bucket -> bucket.bucketDate == date && bucket.bucketKind == wantedKind) buckets

staffPaySegmentBucketKind :: Day -> Text -> Text
staffPaySegmentBucketKind date segmentName =
    case formatTime defaultTimeLocale "%u" date :: String of
        _ | Text.isPrefixOf "delayed_meal_break_" segmentName -> "ordinary"
        "6" | segmentName == "late_night_after_midnight" -> "late_night_after_midnight"
        "6" -> "ordinary"
        "7" -> "ordinary"
        _ | segmentName == "evening_after_7pm" -> "evening_after_7pm"
        _ | segmentName == "late_night_after_midnight" -> "late_night_after_midnight"
        _ -> "ordinary"

bucketKindsForDate :: Day -> [(Text, Text)]
bucketKindsForDate date =
    case formatTime defaultTimeLocale "%u" date :: String of
        "6" -> [("ordinary", "Ord"), ("late_night_after_midnight", "12+")]
        "7" -> [("ordinary", "Ord")]
        _   -> [("ordinary", "Ord"), ("evening_after_7pm", "7-12"), ("late_night_after_midnight", "12+")]

shortDayLabel :: Text -> Text
shortDayLabel = Text.take 4

safeIndex :: [a] -> Int -> Maybe a
safeIndex values index
    | index < 0 = Nothing
    | otherwise =
        case drop index values of
            value : _ -> Just value
            []        -> Nothing

staffPayDisplayName :: Staff -> Text
staffPayDisplayName staff = staff.firstName

staffPayRecordLabel :: VenueReportDefinition -> TimesheetPayResult -> Text
staffPayRecordLabel reportDefinition payResult
    | null reportDefinition.shiftTypeFilters = fromMaybe "Unknown pay level" payResult.payLevelName
    | otherwise = ""

fixedStaffPayRecordLabel :: TimesheetPayResult -> Text
fixedStaffPayRecordLabel payResult =
    fromMaybe "Unknown pay level" payResult.payLevelName

reportDayIndex :: ReportWeekSelection -> Day -> Maybe Int
reportDayIndex reportWeekSelection workedOnDate =
    let dayIndex = fromInteger (diffDays workedOnDate reportWeekSelection.weekStart)
     in if dayIndex >= 0 && dayIndex < length reportWeekSelection.dayLabels
            then Just dayIndex
            else Nothing

addDayHours :: Int -> Double -> [Double] -> [Double]
addDayHours dayIndex hours existingDayHours =
    [ if index == dayIndex then currentHours + hours else currentHours
    | (index, currentHours) <- zip [0 ..] existingDayHours
    ]

paidMinutesToHours :: Int -> Double
paidMinutesToHours paidMinutes = fromIntegral paidMinutes / 60

formatStaffPayHours :: Double -> Text
formatStaffPayHours value = Text.pack (printf "%.2f" value :: String)

renderHourlyBreakdownZipBase64 :: ReportWeekSelection -> [ShiftType] -> [TimesheetEntry] -> Text
renderHourlyBreakdownZipBase64 reportWeekSelection shiftTypes entries =
    renderTextZipBase64
        [ (dayLabel <> ".csv", renderHourlyBreakdownDayCsv reportWeekSelection dayOffset shiftTypes entries)
        | (dayOffset, dayLabel) <- zip [0 ..] reportWeekSelection.dayLabels
        ]

renderHourlyBreakdownDateCsv :: Day -> [ShiftType] -> [TimesheetEntry] -> Text
renderHourlyBreakdownDateCsv date shiftTypes entries =
    Text.unlines (csvHeader : map renderHourRow [8 .. 27])
    where
        csvHeader =
            Text.intercalate ","
                (map csvCell ("Time" : map (.name) shiftTypes))

        dayEntries =
            filter (\entry -> entry.workedOn == date) entries

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

renderHourlyBreakdownDayCsv :: ReportWeekSelection -> Int -> [ShiftType] -> [TimesheetEntry] -> Text
renderHourlyBreakdownDayCsv reportWeekSelection dayOffset shiftTypes entries =
    Text.unlines (csvHeader : map renderHourRow [8 .. 27])
    where
        csvHeader =
            Text.intercalate ","
                (map csvCell ("Time" : map (.name) shiftTypes))

        dayEntries =
            filter (\entry -> reportDayIndex reportWeekSelection entry.workedOn == Just dayOffset) entries

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

entryHoursForHourlyWindow :: Int -> ShiftType -> TimesheetEntry -> Double
entryHoursForHourlyWindow hourOfWindow shiftType entry
    | entry.shiftTypeId /= unpackId (get #id shiftType) = 0
    | otherwise =
        let windowStart = hourlyWindowStartMinute hourOfWindow
            windowEnd = windowStart + 60
            entryStart = timeOfDayToMinutes entry.startTime
            entryEndRaw = timeOfDayToMinutes entry.endTime
            entryEnd = if entryEndRaw <= entryStart then entryEndRaw + 1440 else entryEndRaw
            overlapMinutes =
                max 0
                    (min entryEnd windowEnd - max entryStart windowStart)
            paidMinutes = max 0 (overlapMinutes - breakOverlapMinutes windowStart windowEnd entry)
         in fromIntegral paidMinutes / 60

breakOverlapMinutes :: Int -> Int -> TimesheetEntry -> Int
breakOverlapMinutes windowStart windowEnd entry
    | not entry.hadBreak = 0
    | entry.breakMinutes <= 0 = 0
    | otherwise =
        case (entry.breakStartTime, entry.breakEndTime) of
            (Just breakStartTime, Just breakEndTime) ->
                let breakStart = timeOfDayToMinutes breakStartTime
                    breakEndRaw = timeOfDayToMinutes breakEndTime
                    breakEnd = if breakEndRaw <= breakStart then breakEndRaw + 1440 else breakEndRaw
                 in max 0 (min breakEnd windowEnd - max breakStart windowStart)
            _ -> 0

hourlyWindowStartMinute :: Int -> Int
hourlyWindowStartMinute hourOfWindow
    | hourOfWindow < 24 = hourOfWindow * 60
    | otherwise = (hourOfWindow - 24) * 60 + 1440

formatHourlyWindow :: Int -> Text
formatHourlyWindow hourOfWindow
    | hourOfWindow < 24 = Text.pack (printf "%02d:00" hourOfWindow :: String)
    | otherwise = Text.pack (printf "%02d:00+1" (hourOfWindow - 24) :: String)

formatHourlyBreakdownHours :: Double -> Text
formatHourlyBreakdownHours value = Text.pack (printf "%.1f" value :: String)

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
                , "break_minutes"
                , "pay_config_version_manifest"
                , "approved_at"
                , "approved_by_email"
                ]

        renderRow entry =
            Text.intercalate ","
                [ csvCell (tshow entry.workedOn)
                , csvCell (staffDisplayNameForEntry entry.staffId)
                , csvCell (formatTimeOfDay entry.startTime)
                , csvCell (formatTimeOfDay entry.endTime)
                , csvCell (tshow entry.breakMinutes)
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
