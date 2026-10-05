module Test.DaysheetDailySpec where

import Prelude
import Application.Daysheet.Contract
import Application.Daysheet.Daily
import Application.Daysheet.Entry
import Application.Daysheet.EntryLayout
import qualified Data.Map.Strict as Map
import qualified Application.Daysheet.Number as Number
import Application.Helper.NominalText
import Data.Either (isLeft)
import Data.Time (TimeOfDay (..))
import qualified Application.Daysheet.Evaluation as E
import Application.Daysheet.References
import qualified Data.Aeson as Aeson
import qualified Data.UUID as UUID
import qualified Data.Text as Text
import Test.Support.Daysheet
import Test.Hspec

tests :: Spec
tests = describe "Daysheet daily content" do
    it "keeps repeated layout placements distinct over the same scoped saved cell" do
        let displayed = definition { entryLayout = [Section (SectionId (UUID.fromWords 0 0 0 200)) "Daily entry"
                [FieldBlock (field 1), FieldBlock (field 1), TableBlock (list 10) [field 9] Nothing [], TableBlock (list 20) [field 7, field 8] Nothing []]] }
        Right document <- pure fresh
        Right snapshot <- pure (dailySnapshot displayed references owner document)
        Right layout <- pure (prepareEntryLayout displayed)
        Map.size (entryOccurrences layout) `shouldBe` 5
        Right first <- pure (resolveEntryCell layout snapshot document 0 Nothing)
        Right repeated <- pure (resolveEntryCell layout snapshot document 1 Nothing)
        entryAddress first `shouldBe` entryAddress repeated
        occurrenceIndex (entryOccurrence first) `shouldNotBe` occurrenceIndex (entryOccurrence repeated)
        Right venueCell <- pure (resolveEntryCell layout snapshot document 2 (Just (row 1)))
        entrySavedCell venueCell `shouldBe` Nothing
        Right paired <- pure (resolveEntryCell layout snapshot document 3 (Just (row 1)))
        entrySavedCell paired `shouldBe` Nothing
        Right editable <- pure (resolveEntryCell layout snapshot document 4 (Just (row 1)))
        entrySavedCell editable `shouldBe` Just (Cell 0 Nothing)
        resolveEntryCell layout snapshot document 0 (Just (row 1)) `shouldBe` Left UnknownDailyField
        resolveEntryCell layout snapshot document 4 Nothing `shouldBe` Left UnknownDailyField
        resolveEntryCell layout snapshot document 4 (Just (row 99)) `shouldBe` Left RowNoLongerExists
        resolveEntryCell layout snapshot document (-1) Nothing `shouldBe` Left UnknownDailyField
    it "keeps an eight-terminal checklist together in captured order without pagination" do
        let ids = map row [8, 7, 6, 5, 4, 3, 2, 1]
        let preserved = ReferenceData [ReferenceList (list 10) [ReferenceRecord key False [(field 9, ReferenceScalar (TextLiteral "Terminal"))] | key <- ids]]
        Right document <- pure (emptyDaily definition preserved owner)
        let checklist = RecordList (list 20) "Receipts" (ReferenceChecklist (list 10)) []
        entryRowIds checklist preserved document `shouldBe` ids
    it "binds deletion fingerprints to the sheet, target and exact incoming revisions" do
        let plan = DeletionPlan reading 2 [(RootCell (field 1), 3), (RowCell band (field 4), 4)]
        let token = deletionToken owner plan
        parseNominalText @DaysheetDeletionToken (renderNominalText token) `shouldBe` Right token
        deletionToken owner (plan { incomingCells = reverse (incomingCells plan) }) `shouldBe` token
        deletionToken owner (plan { targetRevision = 3 }) `shouldNotBe` token
        deletionToken owner (plan { deletionTarget = otherReading }) `shouldNotBe` token
        deletionToken owner (plan { incomingCells = [(RootCell (field 1), 4), (RowCell band (field 4), 4)] }) `shouldNotBe` token
        deletionToken owner (plan { incomingCells = [] }) `shouldNotBe` token
        deletionToken (E.SnapshotKey (UUID.fromWords 0 0 0 100) (UUID.fromWords 0 0 0 102)) plan `shouldNotBe` token
        parseNominalText @DaysheetDeletionToken (Text.replicate 64 "g") `shouldSatisfy` isLeft
    it "parses bounded numeric spelling exactly while preserving validation input" do
        let parse kind value = parseNominalText @DaysheetNumericEntry value >>= parseNumericEntry kind
        Right raw <- pure (parseNominalText @DaysheetNumericEntry " +001.60 ")
        renderNominalText raw `shouldBe` " +001.60 "
        Right (MoneyLiteral money) <- pure (parseNumericEntry MoneyType raw)
        Number.fraction money `shouldBe` (8, 5)
        Right (PercentageLiteral rate) <- pure (parse PercentageType "1.6")
        Number.fraction rate `shouldBe` (2, 125)
        parse WholeType "0" `shouldBe` Right (WholeLiteral 0)
        parse WholeType "-12.0" `shouldBe` Right (WholeLiteral (-12))
        map (parse MoneyType) ["1.005", "1+2", "1e3", "1,000", "", ".", "1/3"] `shouldSatisfy` all isLeft
        parse WholeType "1.5" `shouldSatisfy` isLeft
        parse DecimalType (Text.replicate 81 "1") `shouldSatisfy` isLeft
        parse DecimalType (Text.replicate 40 "9") `shouldSatisfy` isLeft
    it "parses clock values without inventing a date, instant, or invalid overnight time" do
        let parse value = parseNominalText @DaysheetClockEntry value >>= parseClockEntry
        parse "01:30" `shouldBe` Right (OperationalTimeLiteral (TimeOfDay 1 30 0))
        parse "23:59:59" `shouldBe` Right (OperationalTimeLiteral (TimeOfDay 23 59 59))
        map parse ["24:00", "23:60", "09:00:60", "tomorrow", "", "01:30\NUL"] `shouldSatisfy` all isLeft
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
        save (RootCell (field 1)) 0 (text "NUL\NULvalue") document `shouldBe` Left (InvalidDailyInput (E.InvalidInput (field 1)))
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
