module Test.DaysheetDesignerSpec (tests) where

import Prelude
import Application.Daysheet.Contract
import Application.Daysheet.Designer
import Application.Daysheet.Validation (validateDefinition)
import Data.Either (isLeft)
import Data.List (find)
import qualified Data.UUID as UUID
import Test.Hspec
import qualified Test.Support.Daysheet as Fixture

section :: SectionId
section = SectionId (UUID.fromWords 0 0 0 800)
report :: ReportId
report = ReportId (UUID.fromWords 0 0 0 801)

reference :: Context -> FieldId -> Expression
reference context key = ReadField (FieldPath context [key])

calculated :: Definition
calculated = Fixture.definition
    { rootFields = rootFields Fixture.definition <>
        [Field (Fixture.field 19) "Twice count" WholeType (Calculated (Binary Multiply (reference Root (Fixture.field 2)) (Constant (WholeLiteral 2))))]
    }

tests :: Spec
tests = describe "Daysheet designer edits" do
    it "renames and reorders fields without changing identities or the source definition" do
        Right renamed <- pure (applyEdit (ChangeField (Fixture.field 1) "Closing notes" TextType Entered) Fixture.definition)
        Right reordered <- pure (applyEdit (MoveField (Fixture.field 1) 2) renamed)
        map fieldId (rootFields reordered) `shouldBe` map Fixture.field [2, 3, 1]
        map fieldLabel (rootFields reordered) `shouldBe` ["Count", "Selected band", "Closing notes"]
        map fieldLabel (rootFields Fixture.definition) `shouldBe` ["Comments", "Count", "Selected band"]

    it "keeps row-field moves within their existing list" do
        Right moved <- pure (applyEdit (MoveField (Fixture.field 5) 2) Fixture.definition)
        rootFields moved `shouldBe` rootFields Fixture.definition
        Just readings <- pure (find ((== Fixture.list 40) . listId) (recordLists moved))
        map fieldId (listFields readings) `shouldBe` map Fixture.field [6, 11, 5]

    it "rejects changes and deletions that break existing reference-path dependants" do
        applyEdit (ChangeField (Fixture.field 4) "Band" WholeType Entered) Fixture.definition `shouldSatisfy` isLeft
        applyEdit (RemoveField (Fixture.field 4)) Fixture.definition `shouldSatisfy` isLeft
        applyEdit (RemoveList (Fixture.list 30)) Fixture.definition `shouldSatisfy` isLeft
        applyEdit (RemoveList (Fixture.list 10)) Fixture.definition `shouldSatisfy` isLeft

    it "rejects forged scope, position and duplicate identities without no-op success" do
        applyEdit (MoveField (Fixture.field 1) (-1)) Fixture.definition `shouldBe` Left InvalidPosition
        applyEdit (MoveField (Fixture.field 1) 3) Fixture.definition `shouldBe` Left InvalidPosition
        applyEdit (RemoveField (Fixture.field 999)) Fixture.definition `shouldBe` Left (MissingField (Fixture.field 999))
        let duplicate = Field (Fixture.field 1) "Duplicate" TextType Entered
        applyEdit (AddField (Just (Fixture.list 999)) 0 duplicate) Fixture.definition
            `shouldBe` Left (MissingList (Fixture.list 999))
        applyEdit (AddField Nothing 0 duplicate) Fixture.definition `shouldSatisfy` isLeft

    it "edits entry and report layouts independently over shared field identities" do
        Right withEntry <- pure (applyEdit (AddSection EntryLayout 0 (Section section "Entry" [FieldBlock (Fixture.field 1)])) Fixture.definition)
        Right withReport <- pure (applyEdit (AddReport 0 (Report report "Close" [] [FormattedReport, ExcelDownload])) withEntry)
        let reportSection = SectionId (UUID.fromWords 0 0 0 802)
        Right withLayout <- pure (applyEdit (AddSection (ReportLayout report) 0 (Section reportSection "Totals" [FieldBlock (Fixture.field 2)])) withReport)
        Right renamed <- pure (applyEdit (ChangeReport report "Closing report" [ExcelDownload]) withLayout)
        entryLayout renamed `shouldBe` entryLayout withEntry
        reports renamed `shouldBe` [Report report "Closing report" [Section reportSection "Totals" [FieldBlock (Fixture.field 2)]] [ExcelDownload]]
        applyEdit (RemoveField (Fixture.field 2)) renamed `shouldSatisfy` isLeft

    it "moves structured blocks and rejects invalid table references" do
        let first = Instructions "Compare saved figures"
            second = FieldBlock (Fixture.field 2)
        Right laidOut <- pure (applyEdit (AddSection EntryLayout 0 (Section section "Entry" [first, second])) Fixture.definition)
        Right moved <- pure (applyEdit (MoveBlock EntryLayout section 0 1) laidOut)
        entryLayout moved `shouldBe` [Section section "Entry" [second, first]]
        applyEdit (ChangeBlock EntryLayout section 0 (TableBlock (Fixture.list 20) [Fixture.field 999] Nothing [])) moved `shouldSatisfy` isLeft
        applyEdit (RemoveBlock EntryLayout section 2) moved `shouldBe` Left InvalidPosition

    it "offers only compatible and cycle-safe field expressions using canonical validation" do
        let count = reference Root (Fixture.field 2)
            text = reference Root (Fixture.field 1)
            cycle = reference Root (Fixture.field 19)
            choices = [text, count, cycle, Constant (WholeLiteral 3)]
        permittedCalculationParts (Fixture.field 2) [] choices calculated `shouldBe` [Constant (WholeLiteral 3)]
        replaceCalculationPart (Fixture.field 2) [] cycle calculated `shouldSatisfy` isLeft
        permittedCalculationParts (Fixture.field 19) [BinaryRight] choices calculated
            `shouldBe` [count, Constant (WholeLiteral 3)]

    it "retains surrounding expression meaning when replacing a nested operand" do
        Right updated <- pure (replaceCalculationPart (Fixture.field 19) [BinaryRight] (Constant (WholeLiteral 3)) calculated)
        Just result <- pure (find ((== Fixture.field 19) . fieldId) (rootFields updated))
        fieldSource result `shouldBe`
            Calculated (Binary Multiply (reference Root (Fixture.field 2)) (Constant (WholeLiteral 3)))
        validateDefinition updated `shouldBe` Right ()
        replaceCalculationPart (Fixture.field 19) [WhenFalse] (Constant (WholeLiteral 3)) calculated
            `shouldBe` Left InvalidExpressionLocation
        replaceCalculationPart (Fixture.field 19) (replicate 33 UnaryInput) (Constant (WholeLiteral 3)) calculated
            `shouldBe` Left InvalidExpressionLocation

    it "uses the enclosing aggregate scope when guiding filter and value edits" do
        let aggregate = Fold Sum (Fixture.list 20) (Just (Constant (BooleanLiteral True))) (reference Item (Fixture.field 8))
            total = Field (Fixture.field 19) "Total" MoneyType (Calculated aggregate)
            definition = Fixture.definition { rootFields = rootFields Fixture.definition <> [total] }
            candidates = [reference Item (Fixture.field 8), reference Root (Fixture.field 1)]
        permittedCalculationParts (Fixture.field 19) [FoldValue] candidates definition `shouldBe` take 1 candidates
        permittedCalculationParts (Fixture.field 19) [FoldFilter] [Constant (BooleanLiteral False), Constant (WholeLiteral 1)] definition
            `shouldBe` [Constant (BooleanLiteral False)]
        replaceCalculationPart (Fixture.field 19) [FoldValue] (reference Item (Fixture.field 8)) definition `shouldBe` Right definition

    it "does not offer an edit that would violate captured reference-only formula scope" do
        let field = Field (Fixture.field 21) "Venue count" WholeType Entered
        Right added <- pure (applyEdit (AddField (Just (Fixture.list 10)) 1 field) Fixture.definition)
        permittedCalculationParts (Fixture.field 21) [] [reference Root (Fixture.field 2), Constant (WholeLiteral 1)] added
            `shouldBe` [Constant (WholeLiteral 1)]
