module Test.DaysheetDailySpec where

import Prelude
import Application.Daysheet.Contract
import Application.Daysheet.Daily
import qualified Application.Daysheet.Evaluation as E
import Application.Daysheet.References
import qualified Data.Aeson as Aeson
import qualified Data.UUID as UUID
import qualified Data.Text as Text
import Data.Word (Word32)
import Test.Hspec

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

tests :: Spec
tests = describe "Daysheet daily content" do
    it "creates exactly the preserved active checklist rows with read-only pairing" do
        Right document <- pure fresh
        rowKeys document `shouldBe` [ReferenceKey (list 20) (row 1)]
        Right snapshot <- pure (dailySnapshot definition references owner document)
        let result = E.prepareEvaluation definition snapshot >>= \ready -> E.evaluate ready [E.RowTarget (list 20) (row 1) (field 7)]
        result `shouldBe` Right [Known (E.Reference (E.RecordReference owner (list 10) (row 1)))]
        add (ReferenceKey (list 20) (row 2)) document `shouldBe` Left ChecklistRowsAreFixed
        planDeletion definition (ReferenceKey (list 20) (row 1)) document `shouldBe` Left ChecklistRowsAreFixed
        save (RowCell (ReferenceKey (list 20) (row 1)) (field 7)) 0 Nothing document `shouldBe` Left ReadOnlyDailyField
    it "merges independent fields but requires fresh explicit same-field resolution, including ABA" do
        Right original <- pure fresh
        Right first <- pure (save (RootCell (field 1)) 0 (text "First editor") original)
        Right second <- pure (save (RootCell (field 2)) 0 (Just (ReferenceScalar (WholeLiteral 0))) first)
        readCell second (RootCell (field 1)) `shouldBe` Right (Cell 1 (text "First editor"))
        readCell second (RootCell (field 2)) `shouldBe` Right (Cell 1 (Just (ReferenceScalar (WholeLiteral 0))))
        save (RootCell (field 1)) 0 (text "Unsaved second value") second `shouldBe` Left CellRevisionConflict
        Right cleared <- pure (save (RootCell (field 1)) 1 Nothing second)
        save (RootCell (field 1)) 0 (text "Stale blank baseline") cleared `shouldBe` Left CellRevisionConflict
        Right replaced <- pure (save (RootCell (field 1)) 2 (text "Deliberate replacement") cleared)
        readCell replaced (RootCell (field 1)) `shouldBe` Right (Cell 3 (text "Deliberate replacement"))
    it "rejects foreign references, wrong types and changes to preserved venue rows" do
        Right document <- pure fresh
        save (RootCell (field 3)) 0 (Just (ReferenceLink band)) document `shouldBe` Left InvalidDailyReference
        save (RootCell (field 2)) 0 (text "Not a number") document `shouldBe` Left (InvalidDailyInput (E.InvalidInput (field 2)))
        save (RowCell (ReferenceKey (list 10) (row 1)) (field 9)) 0 (text "Changed") document `shouldBe` Left ReadOnlyDailyField
    it "clears all confirmed incoming links while retaining referencing rows and unrelated values" do
        Right document <- pure linked
        Right approval <- pure (planDeletion definition band document)
        length (incomingCells approval) `shouldBe` 2
        Right removed <- pure (remove approval document)
        rowKeys removed `shouldSatisfy` (reading `elem`)
        rowKeys removed `shouldSatisfy` (band `notElem`)
        readCell removed (RowCell reading (field 5)) `shouldBe` Right (Cell 2 Nothing)
        readCell removed (RootCell (field 3)) `shouldBe` Right (Cell 2 Nothing)
        readCell removed (RowCell reading (field 6)) `shouldBe` Right (Cell 1 (Just (ReferenceScalar (WholeLiteral 94))))
        let evaluated = do
                snapshot <- dailySnapshot definition references owner removed
                ready <- either (Left . InvalidDailyInput) Right (E.prepareEvaluation definition snapshot)
                either (Left . InvalidDailyInput) Right (E.evaluate ready [E.RowTarget (list 40) (row 60) (field 11)])
        evaluated `shouldBe` Right [Unavailable (MissingInput (field 5))]
    it "refreshes deletion confirmation for changed target values or changed incoming links" do
        Right document <- pure linked
        Right approval <- pure (planDeletion definition band document)
        Right changed <- pure (save (RowCell band (field 4)) 1 (text "Edited target") document)
        remove approval changed `shouldBe` Left DeletionConfirmationChanged
        Right expanded <- pure (add otherReading document >>= save (RowCell otherReading (field 5)) 0 (Just (ReferenceLink band)))
        remove approval expanded `shouldBe` Left DeletionConfirmationChanged
        Right refreshed <- pure (planDeletion definition band expanded)
        length (incomingCells refreshed) `shouldBe` 3
        remove refreshed expanded `shouldSatisfy` either (const False) (const True)
    it "never resurrects a deleted row through a stale edit or repeated add command" do
        Right document <- pure linked
        Right approval <- pure (planDeletion definition band document)
        Right removed <- pure (remove approval document)
        save (RowCell band (field 4)) 1 (text "Keep this unsaved") removed `shouldBe` Left RowNoLongerExists
        add band removed `shouldBe` Left RowNoLongerExists
        add band document `shouldBe` Right document
    it "round-trips bounded server documents without exposing a second browser mutation schema" do
        Right document <- pure linked
        let decoded = encodeDaily document >>= decodeDaily definition references owner
        decoded `shouldBe` Right document
        let forged = Aeson.object ["version" Aeson..= (1 :: Int), "cells" Aeson..= [(field 1, Cell (-1) Nothing)], "rows" Aeson..= ([] :: [Aeson.Value]), "deleted" Aeson..= ([] :: [Aeson.Value])]
        decodeDaily definition references owner forged `shouldBe` Left InvalidDailyDocument
