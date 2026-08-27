module Application.Helper.Export.PayrollWorkbook
    ( PayrollWorkbook (..)
    , PayrollWorkbookCell (..)
    , PayrollWorkbookCellStyle (..)
    , PayrollWorkbookCellValue (..)
    , PayrollWorkbookColor
    , PayrollWorkbookFilter (..)
    , PayrollWorkbookSheet (..)
    , defaultPayrollWorkbookCellStyle
    , minimalPayrollWorkbook
    , payrollWorkbookColor
    , renderPayrollWorkbook
    , renderPayrollWorkbookBase64
    ) where

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
import Data.Time.Calendar (Day)
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
    , cells         :: ![PayrollWorkbookCell]
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

minimalPayrollWorkbook :: Day -> Day -> PayrollWorkbook
minimalPayrollWorkbook rangeStart rangeEnd =
    PayrollWorkbook
        { sheets =
            [ PayrollWorkbookSheet
                { name = "Payroll Workbook"
                , cells =
                    [ textCell 1 1 "Payroll Workbook" headerStyle
                    , textCell 1 2 "Value" headerStyle
                    , textCell 1 3 "Internal" headerStyle
                    , textCell 2 1 (tshow rangeStart <> " to " <> tshow rangeEnd) defaultPayrollWorkbookCellStyle
                    , numberCell 2 2 1 defaultPayrollWorkbookCellStyle { numberFormat = Just "0.00" }
                    , formulaCell 3 2 "SUM(B2:B2)" defaultPayrollWorkbookCellStyle { bold = True, numberFormat = Just "0.00" }
                    ]
                , hiddenColumns = [3]
                , tabColor = either (const Nothing) Just (payrollWorkbookColor "4472C4")
                , autoFilter = Just PayrollWorkbookFilter { firstRow = 1, firstColumn = 1, lastRow = 2, lastColumn = 3 }
                , frozenRows = 1
                , frozenColumns = 1
                }
            ]
        }
  where
    headerStyle =
        defaultPayrollWorkbookCellStyle
            { bold = True
            , fillColor = either (const Nothing) Just (payrollWorkbookColor "D9EAF7")
            }
    textCell row column value style = PayrollWorkbookCell { row, column, value = PayrollWorkbookText value, style }
    numberCell row column value style = PayrollWorkbookCell { row, column, value = PayrollWorkbookNumber value, style }
    formulaCell row column value style = PayrollWorkbookCell { row, column, value = PayrollWorkbookFormula value, style }

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
        { _wsColumnsProperties = map hiddenColumn sheet.hiddenColumns
        , _wsCells = formattedCellMap formattedSheet
        , _wsMerges = formattedMerges formattedSheet
        , _wsSheetViews = freezeSheetViews sheet.frozenRows sheet.frozenColumns
        , _wsAutoFilter = renderAutoFilter <$> sheet.autoFilter
        }
  where
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
