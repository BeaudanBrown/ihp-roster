module Application.Helper.Export.PayrollWorkbook
    ( PayrollWorkbook (..)
    , PayrollWorkbookCell (..)
    , PayrollWorkbookCellStyle (..)
    , PayrollWorkbookCellValue (..)
    , PayrollWorkbookColor
    , PayrollWorkbookDefinition (..)
    , PayrollWorkbookFilter (..)
    , PayrollWorkbookSheet (..)
    , PayrollWorkbookSheetFamily (..)
    , availablePayrollWorkbookSheetFamilies
    , currentPayrollWorkbookDefinitionVersion
    , defaultPayrollWorkbookCellStyle
    , defaultPayrollWorkbookDefinition
    , payrollWorkbookFromDefinition
    , payrollWorkbookColor
    , payrollWorkbookSheetFamilyFromText
    , payrollWorkbookSheetFamilyKey
    , payrollWorkbookSheetFamilyConfigurationLabel
    , renderPayrollWorkbook
    , renderPayrollWorkbookBase64
    , validatePayrollWorkbookDefinition
    ) where

import Application.Error.Runtime (ExternalRuntimeCategory (CheckedConfigurationInvariant),
                                  externalRuntimeInvariantFailure)
import Application.Helper.Export.HourlyBreakdown (formatHourlyWindowRange,
                                                  hourlyReportHours,
                                                  roundRationalAt)
import Application.Helper.Export.PayrollWorkbookModel
import Application.Helper.Export.Types (HourlyOccurrence (..),
                                        HourlyShiftTypeColumn (..))
import Application.Helper.WeekBoundaries (startOfWeekFor)
import qualified "zip-archive" Codec.Archive.Zip as Zip
import Codec.Xlsx
import Codec.Xlsx.Formatted
import qualified Data.ByteString.Base64 as Base64
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Char as Char
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Text.Encoding (decodeUtf8)
import IHP.ControllerPrelude
import qualified Text.XML as Xml

newtype PayrollWorkbookColor = PayrollWorkbookColor Text
    deriving (Eq, Show)

data PayrollWorkbookCellValue
    = PayrollWorkbookText !Text
    | PayrollWorkbookNumber !Double
    | PayrollWorkbookFormula !Text
    deriving (Eq, Show)

data PayrollWorkbookCellStyle = PayrollWorkbookCellStyle
    { bold         :: !Bool
    , fillColor    :: !(Maybe PayrollWorkbookColor)
    , numberFormat :: !(Maybe Text)
    }
    deriving (Eq, Show)

data PayrollWorkbookCell = PayrollWorkbookCell
    { row    :: !Int
    , column :: !Int
    , value  :: !PayrollWorkbookCellValue
    , style  :: !PayrollWorkbookCellStyle
    }
    deriving (Eq, Show)

data PayrollWorkbookFilter = PayrollWorkbookFilter
    { firstRow    :: !Int
    , firstColumn :: !Int
    , lastRow     :: !Int
    , lastColumn  :: !Int
    }
    deriving (Eq, Show)

data PayrollWorkbookSheet = PayrollWorkbookSheet
    { name          :: !Text
    , hidden        :: !Bool
    , cells         :: ![PayrollWorkbookCell]
    , columnWidths  :: ![(Int, Double)]
    , hiddenColumns :: ![Int]
    , tabColor      :: !(Maybe PayrollWorkbookColor)
    , autoFilter    :: !(Maybe PayrollWorkbookFilter)
    , frozenRows    :: !Int
    , frozenColumns :: !Int
    }
    deriving (Eq, Show)

newtype PayrollWorkbook = PayrollWorkbook
    { sheets :: [PayrollWorkbookSheet]
    }
    deriving (Eq, Show)

data PayrollWorkbookSheetFamily
    = PayrollWorkbookSummary
    | PayrollWorkbookEmployeePayBucketHours
    | PayrollWorkbookShiftTypeHours
    | PayrollWorkbookEmployeePayBucketWages
    | PayrollWorkbookShiftTypeWages
    deriving (Eq, Ord, Show, Enum, Bounded)

instance InputValue PayrollWorkbookSheetFamily where
    inputValue = payrollWorkbookSheetFamilyKey

data PayrollWorkbookDefinition = PayrollWorkbookDefinition
    { payrollWorkbookDefinitionKey           :: !Text
    , payrollWorkbookDefinitionVersion       :: !Int
    , payrollWorkbookDefinitionSheetFamilies :: ![PayrollWorkbookSheetFamily]
    }
    deriving (Eq, Show)

defaultPayrollWorkbookDefinition :: PayrollWorkbookDefinition
defaultPayrollWorkbookDefinition =
    PayrollWorkbookDefinition
        { payrollWorkbookDefinitionKey = "builtin-default"
        , payrollWorkbookDefinitionVersion = currentPayrollWorkbookDefinitionVersion
        , payrollWorkbookDefinitionSheetFamilies = availablePayrollWorkbookSheetFamilies
        }

currentPayrollWorkbookDefinitionVersion :: Int
currentPayrollWorkbookDefinitionVersion = 1

availablePayrollWorkbookSheetFamilies :: [PayrollWorkbookSheetFamily]
availablePayrollWorkbookSheetFamilies =
    [ PayrollWorkbookSummary
    , PayrollWorkbookEmployeePayBucketHours
    , PayrollWorkbookShiftTypeHours
    , PayrollWorkbookEmployeePayBucketWages
    , PayrollWorkbookShiftTypeWages
    ]

payrollWorkbookSheetFamilyKey :: PayrollWorkbookSheetFamily -> Text
payrollWorkbookSheetFamilyKey = \case
    PayrollWorkbookSummary                -> "summary"
    PayrollWorkbookEmployeePayBucketHours -> "employee-pay-bucket-hours"
    PayrollWorkbookShiftTypeHours         -> "shift-type-hours"
    PayrollWorkbookEmployeePayBucketWages -> "employee-pay-bucket-wages"
    PayrollWorkbookShiftTypeWages         -> "shift-type-wages"

payrollWorkbookSheetFamilyConfigurationLabel :: PayrollWorkbookSheetFamily -> Text
payrollWorkbookSheetFamilyConfigurationLabel = \case
    PayrollWorkbookSummary                -> "Summary"
    PayrollWorkbookEmployeePayBucketHours -> "Hours by Staff"
    PayrollWorkbookShiftTypeHours         -> "Hours by Shift Type"
    PayrollWorkbookEmployeePayBucketWages -> "Wages by Staff"
    PayrollWorkbookShiftTypeWages         -> "Wages by Shift Type"

payrollWorkbookSheetFamilyFromText :: Text -> Either Text PayrollWorkbookSheetFamily
payrollWorkbookSheetFamilyFromText value =
    case Text.strip value of
        "summary"                   -> Right PayrollWorkbookSummary
        "employee-pay-bucket-hours" -> Right PayrollWorkbookEmployeePayBucketHours
        "shift-type-hours"          -> Right PayrollWorkbookShiftTypeHours
        "employee-pay-bucket-wages" -> Right PayrollWorkbookEmployeePayBucketWages
        "shift-type-wages"          -> Right PayrollWorkbookShiftTypeWages
        unsupported                 -> Left ("Unsupported Payroll Workbook sheet family: " <> unsupported <> ".")

defaultPayrollWorkbookCellStyle :: PayrollWorkbookCellStyle
defaultPayrollWorkbookCellStyle =
    PayrollWorkbookCellStyle
        { bold = False
        , fillColor = Nothing
        , numberFormat = Nothing
        }

payrollWorkbookColor :: Text -> Either Text PayrollWorkbookColor
payrollWorkbookColor input
    | Text.length normalized == 6 && Text.all Char.isHexDigit normalized = Right (PayrollWorkbookColor ("FF" <> normalized))
    | Text.length normalized == 8 && Text.all Char.isHexDigit normalized = Right (PayrollWorkbookColor normalized)
    | otherwise = Left "Workbook colours must be six-digit RGB or eight-digit ARGB hexadecimal values."
  where
    normalized = Text.map Char.toUpper (Text.strip input)

payrollWorkbookFromDefinition ::
    PayrollWorkbookDefinition ->
    Int ->
    PayrollWorkbookFactModel ->
    Either Text PayrollWorkbook
payrollWorkbookFromDefinition definition rosterWeekStartsOn factModel = do
    validatePayrollWorkbookDefinition definition
    pure (payrollWorkbookFromValidatedDefinition definition rosterWeekStartsOn factModel)

payrollWorkbookFromValidatedDefinition ::
    PayrollWorkbookDefinition ->
    Int ->
    PayrollWorkbookFactModel ->
    PayrollWorkbook
payrollWorkbookFromValidatedDefinition definition rosterWeekStartsOn factModel =
    let projected = payrollWorkbookHourlyModelFromFacts factModel
     in PayrollWorkbook
            { sheets = concatMap (familySheets projected) definition.payrollWorkbookDefinitionSheetFamilies <> [dataSheet factModel]
            }
  where
    familySheets projected = \case
        PayrollWorkbookSummary ->
            map (summarySheetFromFacts projected) (summaryWeekAnchors rosterWeekStartsOn projected)
        PayrollWorkbookEmployeePayBucketHours ->
            map (dailySheet projected DailyHours) projected.payrollModelDays
        PayrollWorkbookShiftTypeHours ->
            map (shiftTypeSheet factModel shiftTypeModel ShiftTypeHours) [factModel.payrollFactModelRangeStart .. factModel.payrollFactModelRangeEnd]
        PayrollWorkbookEmployeePayBucketWages ->
            map (dailySheet projected DailyWages) projected.payrollModelDays
        PayrollWorkbookShiftTypeWages ->
            map (shiftTypeSheet factModel shiftTypeModel ShiftTypeWages) [factModel.payrollFactModelRangeStart .. factModel.payrollFactModelRangeEnd]
    shiftTypeModel = shiftTypeModelFromFacts factModel.payrollFactModelFacts

validatePayrollWorkbookDefinition :: PayrollWorkbookDefinition -> Either Text ()
validatePayrollWorkbookDefinition definition
    | Text.null (Text.strip definition.payrollWorkbookDefinitionKey) =
        Left "Payroll Workbook definitions require a stable non-empty key."
    | definition.payrollWorkbookDefinitionVersion /= currentPayrollWorkbookDefinitionVersion =
        Left ("Unsupported Payroll Workbook definition version: " <> tshow definition.payrollWorkbookDefinitionVersion <> ".")
    | null families =
        Left "Payroll Workbook definitions require at least one presentation sheet family."
    | duplicate : _ <- duplicateFamilies =
        Left ("Payroll Workbook definitions cannot contain duplicate sheet families: " <> payrollWorkbookSheetFamilyKey duplicate <> ".")
    | unavailable : _ <- filter (`notElem` availablePayrollWorkbookSheetFamilies) families =
        Left
            ( "Payroll Workbook sheet family is not available in definition version 1: "
                <> payrollWorkbookSheetFamilyKey unavailable
                <> "."
            )
    | otherwise = Right ()
  where
    families = definition.payrollWorkbookDefinitionSheetFamilies
    duplicateFamilies = families List.\\ List.nub families

dataSheet :: PayrollWorkbookFactModel -> PayrollWorkbookSheet
dataSheet factModel =
    PayrollWorkbookSheet
        { name = "Data"
        , hidden = True
        , cells = headerCells <> concat (zipWith factCells [2 ..] factModel.payrollFactModelFacts)
        , columnWidths =
            [ (1, 16), (2, 38), (3, 38), (4, 24), (5, 38), (6, 20)
            , (7, 18), (8, 38), (9, 20), (10, 16), (11, 16), (12, 16)
            , (13, 16), (14, 14), (15, 14), (16, 38), (17, 38), (18, 38)
            , (19, 28), (20, 24)
            ]
        , hiddenColumns = []
        , tabColor = Just (color "A5A5A5")
        , autoFilter = Just PayrollWorkbookFilter
            { firstRow = 1
            , firstColumn = 1
            , lastRow = max 1 (length factModel.payrollFactModelFacts + 1)
            , lastColumn = length dataHeaders
            }
        , frozenRows = 1
        , frozenColumns = 0
        }
  where
    dataHeaders =
        [ "Operational Date", "Entry ID", "Staff ID", "Employee"
        , "Shift Type ID", "Shift Type", "Pay Bucket Type", "Pay Bucket ID"
        , "Pay Bucket", "Hour of Window", "Hour Occurrence", "Worked Hours"
        , "Paid Hours", "Wage Cents", "Wage Amount", "Pay Calculation ID"
        , "Staff Pay Version ID", "Shift Type Pay Version ID"
        , "Calculation Version", "Rate Book Version"
        ]
    headerCells =
        [ textCell 1 column header dataHeaderStyle
        | (column, header) <- zip [1 ..] dataHeaders
        ]
    factCells rowNumber fact =
        let (payBucketType, payBucketId) = payBucketIdentity fact.payrollFactPayBucket.payrollPayBucketKey
         in [ textCell rowNumber 1 (tshow fact.payrollFactOperationalDate) defaultPayrollWorkbookCellStyle
            , textCell rowNumber 2 (tshow fact.payrollFactEntryId) defaultPayrollWorkbookCellStyle
            , textCell rowNumber 3 (tshow fact.payrollFactStaffId) defaultPayrollWorkbookCellStyle
            , textCell rowNumber 4 (fact.payrollFactStaffFirstName <> " " <> fact.payrollFactStaffLastName) defaultPayrollWorkbookCellStyle
            , textCell rowNumber 5 (tshow fact.payrollFactShiftTypeId) defaultPayrollWorkbookCellStyle
            , textCell rowNumber 6 fact.payrollFactShiftTypeLabel defaultPayrollWorkbookCellStyle
            , textCell rowNumber 7 payBucketType defaultPayrollWorkbookCellStyle
            , textCell rowNumber 8 (tshow payBucketId) defaultPayrollWorkbookCellStyle
            , textCell rowNumber 9 fact.payrollFactPayBucket.payrollPayBucketLabel defaultPayrollWorkbookCellStyle
            , numberCell rowNumber 10 (fromIntegral fact.payrollFactHourSlot.payrollHourOfWindow) defaultPayrollWorkbookCellStyle
            , textCell rowNumber 11 (hourOccurrenceText fact.payrollFactHourSlot.payrollHourOccurrence) defaultPayrollWorkbookCellStyle
            , numberCell rowNumber 12 (fromRational fact.payrollFactWorkedHours) hoursStyle
            , numberCell rowNumber 13 (fromRational fact.payrollFactPaidHours) hoursStyle
            , numberCell rowNumber 14 (fromIntegral fact.payrollFactWageCents) defaultPayrollWorkbookCellStyle { numberFormat = Just "0" }
            , numberCell rowNumber 15 (fromIntegral fact.payrollFactWageCents / 100) (dailyNumberStyle DailyWages)
            , textCell rowNumber 16 (maybe "" tshow fact.payrollFactActiveCalculationId) defaultPayrollWorkbookCellStyle
            , textCell rowNumber 17 (maybe "" tshow fact.payrollFactStaffPayVersionId) defaultPayrollWorkbookCellStyle
            , textCell rowNumber 18 (maybe "" tshow fact.payrollFactShiftTypePayVersionId) defaultPayrollWorkbookCellStyle
            , textCell rowNumber 19 fact.payrollFactCalculationVersion defaultPayrollWorkbookCellStyle
            , textCell rowNumber 20 (fromMaybe "" fact.payrollFactRateBookVersion) defaultPayrollWorkbookCellStyle
            ]

    dataHeaderStyle = defaultPayrollWorkbookCellStyle { bold = True, fillColor = Just (color "D9E1F2") }

payBucketIdentity :: PayrollWorkbookPayBucketKey -> (Text, UUID)
payBucketIdentity = \case
    PayrollWorkbookAwardLevel identifier     -> ("award_level", identifier)
    PayrollWorkbookImportedPayItem identifier -> ("imported_pay_item", identifier)

hourOccurrenceText :: HourlyOccurrence -> Text
hourOccurrenceText FirstHourlyOccurrence  = "first"
hourOccurrenceText SecondHourlyOccurrence = "second"

data DailySheetKind = DailyHours | DailyWages

data SummaryBucketKind = SummaryOrdinary | SummaryEvening | SummaryAfterMidnight
    deriving (Eq)

data SummaryBucket = SummaryBucket
    { summaryBucketDate  :: !Day
    , summaryBucketKind  :: !SummaryBucketKind
    , summaryBucketLabel :: !Text
    }

summaryWeekAnchors :: Int -> PayrollWorkbookHourlyModel -> [Day]
summaryWeekAnchors rosterWeekStartsOn model =
    takeWhile (<= model.payrollModelRangeEnd) (iterate (addDays 7) firstAnchor)
  where
    firstAnchor = startOfWeekFor rosterWeekStartsOn model.payrollModelRangeStart

-- Definition-based workbooks always include Data, so Summary formulas use that
-- implementation-owned authority rather than depending on an optional Hours
-- presentation family.
summarySheetFromFacts :: PayrollWorkbookHourlyModel -> Day -> PayrollWorkbookSheet
summarySheetFromFacts model weekAnchor =
    PayrollWorkbookSheet
        { name = summarySheetName weekAnchor
        , hidden = False
        , cells = headerCells <> rowCells
        , columnWidths = [(1, 24), (2, 18)] <> [(column, 13) | column <- [3 .. staffIdColumn - 1]]
        , hiddenColumns = [staffIdColumn, payBucketKeyColumn]
        , tabColor = Just summaryTabColor
        , autoFilter = Nothing
        , frozenRows = 0
        , frozenColumns = 0
        }
  where
    buckets = summaryBuckets weekAnchor
    rows = summaryRowsForWeek model weekAnchor
    staffIdColumn = 3 + length buckets
    payBucketKeyColumn = staffIdColumn + 1
    headerCells =
        zipWith (\column label -> textCell 1 column label summaryHeaderStyle)
            [1 ..]
            ("Employee" : "Pay level / rate" : map (.summaryBucketLabel) buckets <> ["Staff ID", "Pay bucket key"])
    rowCells = concat
        [ [ textCell rowNumber 1 (payrollEmployeeName row) defaultPayrollWorkbookCellStyle
          , textCell rowNumber 2 row.payrollRowPayBucket.payrollPayBucketLabel defaultPayrollWorkbookCellStyle
          ]
            <> zipWith
                (\column bucket -> formulaCell rowNumber column (summaryBucketFactFormula model rowNumber staffIdColumn row bucket) hoursStyle)
                [3 ..]
                buckets
            <> [ textCell rowNumber staffIdColumn (tshow row.payrollRowStaffId) defaultPayrollWorkbookCellStyle
               , textCell rowNumber payBucketKeyColumn (payBucketKeyText row.payrollRowPayBucket.payrollPayBucketKey) defaultPayrollWorkbookCellStyle
               ]
        | (rowNumber, row) <- zip [2 ..] rows
        ]

summaryRowsForWeek :: PayrollWorkbookHourlyModel -> Day -> [PayrollWorkbookRow]
summaryRowsForWeek model weekAnchor =
    [ row
    | (_key, row) <- Map.toAscList rowsByKey
    ]
  where
    weekEnd = addDays 6 weekAnchor
    rowsByKey = Map.fromList
        [ (payrollRowKey row, row)
        | day <- model.payrollModelDays
        , day.payrollDayDate >= weekAnchor
        , day.payrollDayDate <= weekEnd
        , row <- day.payrollDayRows
        ]

summaryBuckets :: Day -> [SummaryBucket]
summaryBuckets weekAnchor = concatMap bucketsForDate [weekAnchor .. addDays 6 weekAnchor]
  where
    bucketsForDate date =
        [ SummaryBucket date kind (summaryDayName date <> " " <> suffix)
        | (kind, suffix) <- case formatTime defaultTimeLocale "%u" date :: String of
            "6" -> [(SummaryOrdinary, "Ord"), (SummaryAfterMidnight, "12+")]
            "7" -> [(SummaryOrdinary, "Ord"), (SummaryAfterMidnight, "12+")]
            _   -> [(SummaryOrdinary, "Ord"), (SummaryEvening, "7-12"), (SummaryAfterMidnight, "12+")]
        ]

summaryBucketFactFormula :: PayrollWorkbookHourlyModel -> Int -> Int -> PayrollWorkbookRow -> SummaryBucket -> Text
summaryBucketFactFormula model summaryRow staffIdColumn row bucket
    | bucket.summaryBucketDate < model.payrollModelRangeStart = "SUM()"
    | bucket.summaryBucketDate > model.payrollModelRangeEnd = "SUM()"
    | null matchingSlots = "SUM()"
    | otherwise = Text.intercalate "+" (map sumIfFormula matchingSlots)
  where
    matchingSlots = filter (summarySlotMatches bucket) model.payrollModelHourSlots
    (payBucketType, payBucketId) = payBucketIdentity row.payrollRowPayBucket.payrollPayBucketKey
    dataSource = quoteSheetName "Data"
    sumIfFormula slot =
        "SUMIFS("
            <> dataSource <> "!$M:$M"
            <> "," <> dataSource <> "!$A:$A,\"" <> tshow bucket.summaryBucketDate <> "\""
            <> "," <> dataSource <> "!$C:$C,$" <> columnName staffIdColumn <> tshow summaryRow
            <> "," <> dataSource <> "!$G:$G,\"" <> payBucketType <> "\""
            <> "," <> dataSource <> "!$H:$H,\"" <> tshow payBucketId <> "\""
            <> "," <> dataSource <> "!$J:$J," <> tshow slot.payrollHourOfWindow
            <> "," <> dataSource <> "!$K:$K,\"" <> hourOccurrenceText slot.payrollHourOccurrence <> "\""
            <> ")"

summarySlotMatches :: SummaryBucket -> PayrollWorkbookHourSlot -> Bool
summarySlotMatches bucket slot =
    case bucket.summaryBucketKind of
        SummaryOrdinary      -> slot.payrollHourOfWindow < ordinaryEnd
        SummaryEvening       -> slot.payrollHourOfWindow >= 19 && slot.payrollHourOfWindow < 24
        SummaryAfterMidnight -> slot.payrollHourOfWindow >= 24
  where
    isWeekend = formatTime defaultTimeLocale "%u" bucket.summaryBucketDate `elem` (["6", "7"] :: [String])
    ordinaryEnd = if isWeekend then 24 else 19

summarySheetName :: Day -> Text
summarySheetName weekAnchor = "Summary " <> tshow weekAnchor

dailySheet :: PayrollWorkbookHourlyModel -> DailySheetKind -> PayrollWorkbookDay -> PayrollWorkbookSheet
dailySheet model kind day =
    PayrollWorkbookSheet
        { name = dailySheetName kind day.payrollDayDate
        , hidden = False
        , cells = headerCells <> detailCells <> totalCells <> metadataCells
        , columnWidths =
            [(1, 22)]
                <> [(column, 28) | column <- staffColumns]
                <> [(totalColumn, 14)]
                <> [(staffColumnMetadataColumn, 14), (staffIdMetadataColumn, 38), (payBucketKeyMetadataColumn, 42)]
        , hiddenColumns = [staffColumnMetadataColumn, staffIdMetadataColumn, payBucketKeyMetadataColumn]
        , tabColor = Just (dailyTabColor kind)
        , autoFilter = Nothing
        , frozenRows = 1
        , frozenColumns = 1
        }
  where
    staffRows = day.payrollDayRows
    staffColumns = [2 .. length staffRows + 1]
    totalColumn = length staffRows + 2
    staffColumnMetadataColumn = totalColumn + 1
    staffIdMetadataColumn = totalColumn + 2
    payBucketKeyMetadataColumn = totalColumn + 3
    reportHours = model.payrollModelHourSlots
    totalRow = length reportHours + 2
    numberStyle = dailyNumberStyle kind
    staffHeadings = disambiguatePayrollStaffHeadings staffRows
    headerCells =
        zipWith (\column label -> textCell 1 column label (dailyHeaderStyle kind))
            [1 ..]
            ("Time" : staffHeadings <> ["Total", "Staff column", "Staff ID", "Pay bucket key"])
    detailCells = concat
        [ [textCell rowNumber 1 (hourSlotLabel model hour) defaultPayrollWorkbookCellStyle]
            <> concat
                [ maybeToList (numberCell rowNumber column <$> dailyDetailValue kind hourIndex staffRow <*> pure numberStyle)
                | (column, staffRow) <- zip staffColumns staffRows
                ]
            <> [formulaCell rowNumber totalColumn (dailyRowTotalFormula rowNumber) numberStyle]
        | (rowNumber, hourIndex, hour) <- zip3 [2 ..] [0 ..] reportHours
        ]
    totalCells =
        [textCell totalRow 1 "Total" defaultPayrollWorkbookCellStyle { bold = True }]
            <> [ formulaCell totalRow column (columnTotalFormula column (length reportHours)) numberStyle { bold = True }
               | column <- staffColumns
               ]
            <> [formulaCell totalRow totalColumn (dailyRowTotalFormula totalRow) numberStyle { bold = True }]
    metadataCells = concat
        [ [ textCell metadataRow staffColumnMetadataColumn (columnName staffColumn) defaultPayrollWorkbookCellStyle
          , textCell metadataRow staffIdMetadataColumn (tshow staffRow.payrollRowStaffId) defaultPayrollWorkbookCellStyle
          , textCell metadataRow payBucketKeyMetadataColumn (payBucketKeyText staffRow.payrollRowPayBucket.payrollPayBucketKey) defaultPayrollWorkbookCellStyle
          ]
        | (metadataRow, staffColumn, staffRow) <- zip3 [2 ..] staffColumns staffRows
        ]
    dailyRowTotalFormula rowNumber
        | null staffColumns = "SUM()"
        | otherwise = sumFormula rowNumber 2 (totalColumn - 1)

data ShiftTypeSheetKind = ShiftTypeHours | ShiftTypeWages

data ShiftTypeModel = ShiftTypeModel
    { shiftTypeHoursByCell     :: !(Map.Map (Day, Int, UUID) Rational)
    , shiftTypeWageCentsByCell :: !(Map.Map (Day, Int, UUID) Integer)
    }

shiftTypeModelFromFacts :: [PayrollWorkbookFact] -> ShiftTypeModel
shiftTypeModelFromFacts = foldl' accumulate emptyModel
  where
    emptyModel = ShiftTypeModel Map.empty Map.empty
    accumulate model fact =
        let key =
                ( fact.payrollFactOperationalDate
                , fact.payrollFactHourSlot.payrollHourOfWindow
                , fact.payrollFactShiftTypeId
                )
         in ShiftTypeModel
                { shiftTypeHoursByCell = Map.insertWith (+) key fact.payrollFactWorkedHours model.shiftTypeHoursByCell
                , shiftTypeWageCentsByCell = Map.insertWith (+) key fact.payrollFactWageCents model.shiftTypeWageCentsByCell
                }

shiftTypeSheet :: PayrollWorkbookFactModel -> ShiftTypeModel -> ShiftTypeSheetKind -> Day -> PayrollWorkbookSheet
shiftTypeSheet factModel shiftTypeModel kind date =
    PayrollWorkbookSheet
        { name = shiftTypeSheetName kind date
        , hidden = False
        , cells = headerCells <> detailCells <> totalCells
        , columnWidths = [(1, 22)] <> [(column, 18) | column <- [2 .. totalColumn - 1]] <> [(totalColumn, 14)]
        , hiddenColumns = []
        , tabColor = Just (shiftTypeTabColor kind)
        , autoFilter = Nothing
        , frozenRows = 1
        , frozenColumns = 1
        }
  where
    columns = factModel.payrollFactModelShiftTypeColumns
    reportHours = hourlyReportHours factModel.payrollFactModelWindow
    totalColumn = length columns + 2
    totalRow = length reportHours + 2
    numberStyle = shiftTypeNumberStyle kind
    totalNumberStyle = shiftTypeTotalNumberStyle kind
    headerCells =
        zipWith (\column label -> textCell 1 column label defaultPayrollWorkbookCellStyle { bold = True })
            [1 ..]
            ("Time" : map (.hourlyShiftTypeLabel) columns <> ["Total"])
    detailCells = concat
        [ [textCell rowNumber 1 (formatHourlyWindowRange hour) defaultPayrollWorkbookCellStyle]
            <> concat
                [ maybeToList (numberCell rowNumber columnIndex <$> detailValue hour column <*> pure numberStyle)
                | (columnIndex, column) <- zip [2 ..] columns
                ]
            <> [ formulaCell rowNumber totalColumn (rowTotalFormula rowNumber) totalNumberStyle
               ]
        | (rowNumber, hour) <- zip [2 ..] reportHours
        ]
    totalCells =
        [textCell totalRow 1 "Total" defaultPayrollWorkbookCellStyle { bold = True }]
            <> [ formulaCell totalRow column (columnTotalFormula column (length reportHours)) totalNumberStyle { bold = True }
               | column <- [2 .. totalColumn - 1]
               ]
            <> [formulaCell totalRow totalColumn (rowTotalFormula totalRow) totalNumberStyle { bold = True }]

    rowTotalFormula rowNumber
        | null columns = "SUM()"
        | otherwise = sumFormula rowNumber 2 (totalColumn - 1)

    detailValue hour column =
        case kind of
            ShiftTypeHours ->
                let hours =
                        Map.findWithDefault 0 (date, hour, column.hourlyShiftTypeId) shiftTypeModel.shiftTypeHoursByCell
                            |> roundRationalAt 1000000
                 in if hours > 0 then Just (fromRational hours) else Nothing
            ShiftTypeWages ->
                let cents = Map.findWithDefault 0 (date, hour, column.hourlyShiftTypeId) shiftTypeModel.shiftTypeWageCentsByCell
                 in if cents > 0 then Just (fromIntegral cents / 100) else Nothing

shiftTypeSheetName :: ShiftTypeSheetKind -> Day -> Text
shiftTypeSheetName kind date =
    kindLabel <> " " <> shortDayName date <> " " <> tshow date
  where
    kindLabel = case kind of
        ShiftTypeHours -> "Shift Type Hours"
        ShiftTypeWages -> "Shift Type Wages"

shiftTypeNumberStyle :: ShiftTypeSheetKind -> PayrollWorkbookCellStyle
shiftTypeNumberStyle ShiftTypeHours = hoursStyle
shiftTypeNumberStyle ShiftTypeWages = dailyNumberStyle DailyWages

shiftTypeTotalNumberStyle :: ShiftTypeSheetKind -> PayrollWorkbookCellStyle
shiftTypeTotalNumberStyle ShiftTypeHours = defaultPayrollWorkbookCellStyle { numberFormat = Just "0.000000" }
shiftTypeTotalNumberStyle ShiftTypeWages = defaultPayrollWorkbookCellStyle { numberFormat = Just "$#,##0.00;[Red]-$#,##0.00;$0.00;" }

shiftTypeTabColor :: ShiftTypeSheetKind -> PayrollWorkbookColor
shiftTypeTabColor ShiftTypeHours = color "5B9BD5"
shiftTypeTabColor ShiftTypeWages = color "A5A5A5"

dailyDetailValue :: DailySheetKind -> Int -> PayrollWorkbookRow -> Maybe Double
dailyDetailValue kind hourIndex row =
    case kind of
        DailyHours -> do
            hours <- listToMaybe (drop hourIndex row.payrollRowHours)
            if hours > 0 then Just (fromRational hours) else Nothing
        DailyWages -> do
            cents <- listToMaybe (drop hourIndex row.payrollRowWageCents)
            if cents > 0 then Just (fromIntegral cents / 100) else Nothing

disambiguatePayrollStaffHeadings :: [PayrollWorkbookRow] -> [Text]
disambiguatePayrollStaffHeadings rows = snd (List.mapAccumL disambiguate Map.empty rows)
  where
    disambiguate counts row =
        let baseHeading = payrollStaffColumnHeading row
            occurrence = Map.findWithDefault 0 baseHeading counts + 1
            heading
                | occurrence == 1 = baseHeading
                | otherwise = baseHeading <> " (" <> tshow occurrence <> ")"
         in (Map.insert baseHeading occurrence counts, heading)

payrollStaffColumnHeading :: PayrollWorkbookRow -> Text
payrollStaffColumnHeading row =
    row.payrollRowStaffFirstName
        <> ", "
        <> row.payrollRowStaffLastName
        <> ", "
        <> payrollPayBucketColumnLabel row.payrollRowPayBucket.payrollPayBucketLabel

payrollPayBucketColumnLabel :: Text -> Text
payrollPayBucketColumnLabel label =
    case Text.stripPrefix "Level " (Text.strip label) of
        Just level -> "LVL " <> level
        Nothing    -> label

columnTotalFormula :: Int -> Int -> Text
columnTotalFormula column rowCount
    | rowCount <= 0 = "SUM()"
    | otherwise = "SUM(" <> columnName column <> "2:" <> columnName column <> tshow (rowCount + 1) <> ")"

sumFormula :: Int -> Int -> Int -> Text
sumFormula rowNumber firstColumn lastColumn =
    "SUM(" <> columnName firstColumn <> tshow rowNumber <> ":" <> columnName lastColumn <> tshow rowNumber <> ")"

hourSlotLabel :: PayrollWorkbookHourlyModel -> PayrollWorkbookHourSlot -> Text
hourSlotLabel model slot =
    formatHourlyWindowRange slot.payrollHourOfWindow <> occurrenceSuffix
  where
    repeated = any (\candidate -> candidate.payrollHourOfWindow == slot.payrollHourOfWindow && candidate.payrollHourOccurrence == SecondHourlyOccurrence) model.payrollModelHourSlots
    occurrenceSuffix
        | not repeated = ""
        | slot.payrollHourOccurrence == FirstHourlyOccurrence = " (first)"
        | otherwise = " (second)"

dailySheetName :: DailySheetKind -> Day -> Text
dailySheetName kind date =
    kindLabel <> " " <> shortDayName date <> " " <> tshow date
  where
    kindLabel = case kind of
        DailyHours -> "Hours"
        DailyWages -> "Wages"

shortDayName :: Day -> Text
shortDayName = Text.pack . formatTime defaultTimeLocale "%a"

summaryDayName :: Day -> Text
summaryDayName date =
    case formatTime defaultTimeLocale "%u" date :: String of
        "2" -> "Tues"
        "4" -> "Thurs"
        _   -> shortDayName date

payrollEmployeeName :: PayrollWorkbookRow -> Text
payrollEmployeeName row = row.payrollRowStaffLastName <> ", " <> row.payrollRowStaffFirstName

payrollRowKey :: PayrollWorkbookRow -> (Text, Text, UUID, PayrollWorkbookPayBucketKey)
payrollRowKey row =
    ( row.payrollRowStaffLastName
    , row.payrollRowStaffFirstName
    , row.payrollRowStaffId
    , row.payrollRowPayBucket.payrollPayBucketKey
    )

payBucketKeyText :: PayrollWorkbookPayBucketKey -> Text
payBucketKeyText = \case
    PayrollWorkbookAwardLevel identifier -> "award_level:" <> tshow identifier
    PayrollWorkbookImportedPayItem identifier -> "imported_pay_item:" <> tshow identifier

quoteSheetName :: Text -> Text
quoteSheetName name = "'" <> Text.replace "'" "''" name <> "'"

columnName :: Int -> Text
columnName column
    | column <= 0 = ""
    | otherwise = columnName quotient <> Text.singleton (Char.chr (Char.ord 'A' + remainder))
  where
    (quotient, remainder) = (column - 1) `divMod` 26

textCell :: Int -> Int -> Text -> PayrollWorkbookCellStyle -> PayrollWorkbookCell
textCell row column value style = PayrollWorkbookCell { row, column, value = PayrollWorkbookText value, style }

numberCell :: Int -> Int -> Double -> PayrollWorkbookCellStyle -> PayrollWorkbookCell
numberCell row column value style = PayrollWorkbookCell { row, column, value = PayrollWorkbookNumber value, style }

formulaCell :: Int -> Int -> Text -> PayrollWorkbookCellStyle -> PayrollWorkbookCell
formulaCell row column value style = PayrollWorkbookCell { row, column, value = PayrollWorkbookFormula value, style }

summaryHeaderStyle :: PayrollWorkbookCellStyle
summaryHeaderStyle = defaultPayrollWorkbookCellStyle { bold = True }

dailyHeaderStyle :: DailySheetKind -> PayrollWorkbookCellStyle
dailyHeaderStyle _ = defaultPayrollWorkbookCellStyle { bold = True }

hoursStyle :: PayrollWorkbookCellStyle
hoursStyle = defaultPayrollWorkbookCellStyle { numberFormat = Just "0.000000;-0.000000;;" }

dailyNumberStyle :: DailySheetKind -> PayrollWorkbookCellStyle
dailyNumberStyle DailyHours = hoursStyle
dailyNumberStyle DailyWages = defaultPayrollWorkbookCellStyle { numberFormat = Just "$#,##0.00;[Red]-$#,##0.00;;" }

summaryTabColor :: PayrollWorkbookColor
summaryTabColor = color "FFC000"

dailyTabColor :: DailySheetKind -> PayrollWorkbookColor
dailyTabColor DailyHours = color "4472C4"
dailyTabColor DailyWages = color "70AD47"

color :: Text -> PayrollWorkbookColor
color value =
    either
        (externalRuntimeInvariantFailure CheckedConfigurationInvariant . cs)
        id
        (payrollWorkbookColor value)

renderPayrollWorkbookBase64 :: PayrollWorkbook -> Text
renderPayrollWorkbookBase64 = decodeUtf8 . Base64.encode . LBS.toStrict . renderPayrollWorkbook

renderPayrollWorkbook :: PayrollWorkbook -> LBS.ByteString
renderPayrollWorkbook workbook =
    applyTabColors workbook (fromXlsx 0 xlsx)
  where
    (finalStyleSheet, renderedSheets) =
        List.mapAccumL renderSheet minimalStyleSheet workbook.sheets
    renderSheet styleSheet sheet =
        let formattedSheet = formatted (Map.fromList (map renderCell sheet.cells)) styleSheet
         in ( formattedStyleSheet formattedSheet
            , ( sheet.name
              , worksheetFrom sheet formattedSheet
              )
            )
    xlsx =
        def
            { _xlSheets = renderedSheets
            , _xlStyles = renderStyleSheet finalStyleSheet
            }

renderCell :: PayrollWorkbookCell -> ((RowIndex, ColumnIndex), FormattedCell)
renderCell cell =
    ( (RowIndex cell.row, ColumnIndex cell.column)
    , def
        { _formattedCell =
            def
                { _cellValue = cellValue
                , _cellFormula = cellFormula
                }
        , _formattedFormat = renderFormat cell.style
        }
    )
  where
    (cellValue, cellFormula) =
        case cell.value of
            PayrollWorkbookText value    -> (Just (CellText value), Nothing)
            PayrollWorkbookNumber value  -> (Just (CellDouble value), Nothing)
            PayrollWorkbookFormula value -> (Nothing, Just (simpleCellFormula value))

renderFormat :: PayrollWorkbookCellStyle -> Format
renderFormat style =
    def
        { _formatFont =
            if style.bold
                then Just def { _fontBold = Just True }
                else Nothing
        , _formatFill = renderFill <$> style.fillColor
        , _formatNumberFormat = UserNumberFormat <$> style.numberFormat
        }

renderFill :: PayrollWorkbookColor -> Fill
renderFill (PayrollWorkbookColor argb) =
    def
        { _fillPattern =
            Just
                def
                    { _fillPatternFgColor = Just def { _colorARGB = Just argb }
                    , _fillPatternType = Just PatternTypeSolid
                    }
        }

worksheetFrom :: PayrollWorkbookSheet -> Formatted -> Worksheet
worksheetFrom sheet formattedSheet =
    def
        { _wsColumnsProperties = map renderColumnWidth sheet.columnWidths <> map hiddenColumn sheet.hiddenColumns
        , _wsCells = formattedCellMap formattedSheet
        , _wsMerges = formattedMerges formattedSheet
        , _wsSheetViews = freezeSheetViews sheet.frozenRows sheet.frozenColumns
        , _wsAutoFilter = renderAutoFilter <$> sheet.autoFilter
        , _wsState = if sheet.hidden then Hidden else Visible
        }
  where
    renderColumnWidth (column, width) =
        ColumnsProperties
            { cpMin = column
            , cpMax = column
            , cpWidth = Just width
            , cpStyle = Nothing
            , cpHidden = False
            , cpCollapsed = False
            , cpBestFit = False
            }
    hiddenColumn column =
        ColumnsProperties
            { cpMin = column
            , cpMax = column
            , cpWidth = Nothing
            , cpStyle = Nothing
            , cpHidden = True
            , cpCollapsed = False
            , cpBestFit = False
            }

renderAutoFilter :: PayrollWorkbookFilter -> AutoFilter
renderAutoFilter range =
    def
        { _afRef =
            Just
                (mkRange
                    (RowIndex range.firstRow, ColumnIndex range.firstColumn)
                    (RowIndex range.lastRow, ColumnIndex range.lastColumn)
                )
        }

freezeSheetViews :: Int -> Int -> Maybe [SheetView]
freezeSheetViews frozenRows frozenColumns
    | frozenRows <= 0 && frozenColumns <= 0 = Nothing
    | otherwise =
        Just
            [ def
                { _sheetViewPane =
                    Just
                        def
                            { _paneActivePane = Just activePane
                            , _paneState = Just PaneStateFrozen
                            , _paneTopLeftCell = Just (singleCellRef (RowIndex (frozenRows + 1), ColumnIndex (frozenColumns + 1)))
                            , _paneXSplit = positiveDouble frozenColumns
                            , _paneYSplit = positiveDouble frozenRows
                            }
                }
            ]
  where
    activePane
        | frozenRows > 0 && frozenColumns > 0 = PaneTypeBottomRight
        | frozenRows > 0 = PaneTypeBottomLeft
        | otherwise = PaneTypeTopRight
    positiveDouble value
        | value > 0 = Just (fromIntegral value)
        | otherwise = Nothing

applyTabColors :: PayrollWorkbook -> LBS.ByteString -> LBS.ByteString
applyTabColors workbook bytes =
    Zip.fromArchive (foldl applyColor (Zip.toArchive bytes) indexedColors)
  where
    indexedColors =
        [ (index, color)
        | (index, sheet) <- zip [1 :: Int ..] workbook.sheets
        , color <- maybeToList sheet.tabColor
        ]
    applyColor archive (index, PayrollWorkbookColor argb) =
        let path = cs ("xl/worksheets/sheet" <> tshow index <> ".xml") :: FilePath
         in case Zip.findEntryByPath path archive of
                Nothing -> archive
                Just entry ->
                    let updatedXml = addWorksheetTabColor argb (Zip.fromEntry entry)
                        updatedEntry = Zip.toEntry path 0 updatedXml
                     in Zip.addEntryToArchive updatedEntry (Zip.deleteEntryFromArchive path archive)

addWorksheetTabColor :: Text -> LBS.ByteString -> LBS.ByteString
addWorksheetTabColor argb xml =
    Xml.renderLBS Xml.def updatedDocument
  where
    Xml.Document prologue root epilogue = Xml.parseLBS_ Xml.def xml
    Xml.Element rootName rootAttributes rootNodes = root
    spreadsheetNamespace = Just "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    tabColor =
        Xml.Element
            (Xml.Name "tabColor" spreadsheetNamespace Nothing)
            (Map.singleton (Xml.Name "rgb" Nothing Nothing) argb)
            []
    sheetProperties =
        Xml.Element
            (Xml.Name "sheetPr" spreadsheetNamespace Nothing)
            Map.empty
            [Xml.NodeElement tabColor]
    updatedRoot = Xml.Element rootName rootAttributes (Xml.NodeElement sheetProperties : rootNodes)
    updatedDocument = Xml.Document prologue updatedRoot epilogue
