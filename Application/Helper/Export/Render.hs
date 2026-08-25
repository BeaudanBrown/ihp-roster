module Application.Helper.Export.Render where

import Application.Helper.Controller
import Application.Helper.Export.HourlyBreakdown
import Application.Helper.Export.Types
import Application.VenueTime.Model (ValidatedTimesheetTiming,
                                    timesheetTimingBreakElapsedSeconds,
                                    timesheetTimingEndTime,
                                    timesheetTimingStartTime,
                                    timesheetTimingWorkedOn)
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
import Data.Time.Clock (NominalDiffTime, UTCTime)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Data.Time.LocalTime (TimeOfDay (..))
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
                (map (csvCell . spreadsheetText) ("Employee" : bucketLabels))

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
                , "operational_date"
                , "component_date"
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
                , csvCell (tshow record.operationalDate)
                , csvCell (tshow record.componentDate)
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
        <|> List.findIndex
            (\bucket -> bucket.bucketDate == contribution.staffHoursDate && bucket.bucketKind == "ordinary")
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

-- CSV carries no cell-type metadata. Google Sheets otherwise imports values such
-- as "Wed 7-12" as dates, while treating this conventional prefix as text.
spreadsheetText :: Text -> Text
spreadsheetText value = "'" <> value

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

renderHourlyBreakdownDateCsv :: Day -> HourlyReportWindow -> [HourlyShiftTypeColumn] -> [TimesheetEntry] -> Text
renderHourlyBreakdownDateCsv date window columns entries =
    Text.unlines (csvHeader : map renderHourRow reportHours <> [renderTotalRow])
  where
    reportHours = hourlyReportHours window
    dayEntries = filter ((== date) . (.operationalDate)) entries
    displayedHours hour column =
        sum (map (entryHoursForHourlyWindow hour column.hourlyShiftTypeId) dayEntries)
            |> roundRationalAt 1000000
    hourMatrix =
        Map.fromList
            [ ((hour, column.hourlyShiftTypeId), displayedHours hour column)
            | hour <- reportHours
            , column <- columns
            ]
    csvHeader = Text.intercalate "," (map csvCell ("Time" : map (.hourlyShiftTypeLabel) columns <> ["Total"]))

    renderHourRow hour =
        let values = [Map.findWithDefault 0 (hour, column.hourlyShiftTypeId) hourMatrix | column <- columns]
            renderedValues = map (\value -> if value <= 0 then "" else formatHourlyBreakdownHours value) values
            rowTotal = sum values
         in Text.intercalate "," (map csvCell (formatHourlyWindowRange hour : renderedValues <> [formatHourlyBreakdownHours rowTotal]))

    renderTotalRow =
        let columnTotals =
                [ sum [Map.findWithDefault 0 (hour, column.hourlyShiftTypeId) hourMatrix | hour <- reportHours]
                | column <- columns
                ]
         in Text.intercalate "," (map csvCell ("Total" : map formatHourlyBreakdownHours columnTotals <> [formatHourlyBreakdownHours (sum columnTotals)]))

formatHourlyBreakdownHours :: Rational -> Text
formatHourlyBreakdownHours = formatRationalDecimal 6

renderHourlyWageTotalsDateCsv :: Day -> HourlyReportWindow -> [HourlyShiftTypeColumn] -> Map.Map (Day, Int, UUID) Integer -> Text
renderHourlyWageTotalsDateCsv date window columns wageCents =
    Text.unlines (csvHeader : map renderHourRow reportHours <> [renderTotalRow])
  where
    reportHours = hourlyReportHours window
    centsFor hour column = Map.findWithDefault 0 (date, hour, column.hourlyShiftTypeId) wageCents
    csvHeader = Text.intercalate "," (map csvCell ("Time" : map (.hourlyShiftTypeLabel) columns <> ["Total"]))

    renderHourRow hour =
        let values = map (centsFor hour) columns
            renderedValues = map (\value -> if value <= 0 then "" else formatMoneyCents value) values
         in Text.intercalate "," (map csvCell (formatHourlyWindowRange hour : renderedValues <> [formatMoneyCents (sum values)]))

    renderTotalRow =
        let columnTotals = [sum [centsFor hour column | hour <- reportHours] | column <- columns]
         in Text.intercalate "," (map csvCell ("Total" : map formatMoneyCents columnTotals <> [formatMoneyCents (sum columnTotals)]))

formatMoneyCents :: Integer -> Text
formatMoneyCents cents =
    let (whole, fraction) = cents `divMod` 100
     in Text.pack (printf "%d.%02d" whole fraction :: String)

fallbackReportDayLabels :: Day -> [Text]
fallbackReportDayLabels reportWeekStart =
    map (fallbackReportDayLabel reportWeekStart) [0 .. 6]

fallbackReportDayLabel :: Day -> Int -> Text
fallbackReportDayLabel reportWeekStart dayOffset =
    Text.pack (formatTime defaultTimeLocale "%A" (addDays (toInteger dayOffset) reportWeekStart))

renderApprovedTimesheetCsv ::
    [(TimesheetEntry, ValidatedTimesheetTiming)] ->
    Map.Map UUID Staff ->
    Map.Map UUID User ->
    Map.Map UUID Text ->
    Text
renderApprovedTimesheetCsv entriesWithTiming staffById approversById versionManifestByEntryId =
    Text.unlines (csvHeader : map renderRow entriesWithTiming)
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

        renderRow (entry, timing) =
            Text.intercalate ","
                [ csvCell (tshow (timesheetTimingWorkedOn timing))
                , csvCell (staffDisplayNameForEntry entry.staffId)
                , csvCell (formatTimeOfDay (timesheetTimingStartTime timing))
                , csvCell (formatTimeOfDay (timesheetTimingEndTime timing))
                , csvCell (formatElapsedSeconds (timesheetTimingBreakElapsedSeconds timing))
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
