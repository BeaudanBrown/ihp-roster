module Test.Support.Daysheet where

import Prelude
import Application.Daysheet.Contract
import Application.Daysheet.Daily
import qualified Application.Daysheet.Evaluation as E
import Application.Daysheet.References
import qualified Data.UUID as UUID
import qualified Data.Text as Text
import Data.Word (Word32)

field :: Word32 -> FieldId
field n = FieldId (UUID.fromWords 0 0 0 n)
list :: Word32 -> ListId
list n = ListId (UUID.fromWords 0 0 0 n)
row :: Word32 -> E.RowId
row n = E.RowId (UUID.fromWords 0 0 0 n)
owner :: E.SnapshotKey
owner = E.SnapshotKey (UUID.fromWords 0 0 0 100) (UUID.fromWords 0 0 0 101)
definition :: Definition
definition = Definition 2
    [Field (field 1) "Comments" TextType Entered, Field (field 2) "Count" WholeType Entered, Field (field 3) "Selected band" (ReferenceType (list 30)) Entered]
    [RecordList (list 10) "Terminals" VenueReference [Field (field 9) "Label" TextType Entered]
    , RecordList (list 20) "Receipts" (ReferenceChecklist (list 10))
        [Field (field 7) "Terminal" (ReferenceType (list 10)) (Calculated (ChecklistReference Current)), Field (field 8) "Receipt" MoneyType Entered]
    , RecordList (list 30) "Bands" OpenDaily [Field (field 4) "Band" TextType Entered]
    , RecordList (list 40) "Readings" OpenDaily
        [Field (field 5) "Band" (ReferenceType (list 30)) Entered, Field (field 6) "Reading" WholeType Entered
        , Field (field 11) "Band label" TextType (Calculated (ReadField (FieldPath Current [field 5, field 4])))]] [] []
references :: ReferenceData
references = ReferenceData [ReferenceList (list 10)
    [ReferenceRecord (row 1) False [(field 9, ReferenceScalar (TextLiteral "Preserved terminal"))]
    , ReferenceRecord (row 2) True [(field 9, ReferenceScalar (TextLiteral "Retired terminal"))]]]
fresh :: Either DailyError DailyDocument
fresh = emptyDaily definition references owner
save :: CellAddress -> Integer -> Maybe ReferenceValue -> DailyDocument -> Either DailyError DailyDocument
save = saveCell definition references owner
add :: ReferenceKey -> DailyDocument -> Either DailyError DailyDocument
add = addOpenRow definition references owner
remove :: DeletionPlan -> DailyDocument -> Either DailyError DailyDocument
remove = confirmDeletion definition references owner
text :: String -> Maybe ReferenceValue
text = Just . ReferenceScalar . TextLiteral . Text.pack

band, reading, otherReading :: ReferenceKey
band = ReferenceKey (list 30) (row 50)
reading = ReferenceKey (list 40) (row 60)
otherReading = ReferenceKey (list 40) (row 61)

linked :: Either DailyError DailyDocument
linked = fresh >>= add band >>= add reading
    >>= save (RowCell band (field 4)) 0 (text "Band A")
    >>= save (RowCell reading (field 5)) 0 (Just (ReferenceLink band))
    >>= save (RowCell reading (field 6)) 0 (Just (ReferenceScalar (WholeLiteral 94)))
    >>= save (RootCell (field 3)) 0 (Just (ReferenceLink band))

-- Browser/controller fixtures use the largest realistic venue baseline, not
-- the engine ceiling. This is authored test data, independent of the workbook.
entryDefinition :: Definition
entryDefinition = definition
    { rootFields = rootFields definition <>
        [ Field (field 12) "Closing time" OperationalTimeType Entered
        , Field (field 13) "Measured quantity" DecimalType Entered
        , Field (field 14) "Checked" BooleanType Entered
        , Field (field 15) "Rate" PercentageType Entered
        , Field (field 16) "Receipt total" MoneyType (Calculated (Fold Sum (list 20) Nothing (ReadField (FieldPath Item [field 8]))))
        , Field (field 17) "Event date" DateType Entered
        ]
    , entryLayout =
        [ Section (SectionId (UUID.fromWords 0 0 0 700)) "Daily entry"
            [ FieldBlock (field 1), FieldBlock (field 2)
            , TableBlock (list 20) [field 7, field 8] Nothing []
            , TableBlock (list 30) [field 4] Nothing []
            ]
        , Section (SectionId (UUID.fromWords 0 0 0 701)) "Checks"
            [ FieldBlock (field 3), FieldBlock (field 12), FieldBlock (field 13)
            , FieldBlock (field 14), FieldBlock (field 15), FieldBlock (field 16), FieldBlock (field 17)
            , AdvisoryBlock (Advisory (Binary GreaterOrEqual (ReadField (FieldPath Root [field 2])) (Constant (WholeLiteral 0))) "Count is non-negative" "Review negative count")
            , TableBlock (list 40) [field 5, field 6, field 11] Nothing []
            ]
        ]
    }

entryReferences :: ReferenceData
entryReferences = ReferenceData [ReferenceList (list 10)
    [ReferenceRecord (row n) False [(field 9, ReferenceScalar (TextLiteral ("Terminal " <> Text.pack (show n))))] | n <- [1 .. 8]]]
