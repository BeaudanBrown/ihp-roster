module Test.DaysheetReportSpec where

import Prelude
import Application.Daysheet.Contract
import qualified Application.Daysheet.Daily as Daily
import qualified Application.Daysheet.Evaluation as E
import qualified Application.Daysheet.Saved as Saved
import Application.Daysheet.Report
import Application.Daysheet.References
import qualified Test.Support.Daysheet as Fixture
import Test.Hspec
import qualified Data.UUID as UUID
import qualified Data.Map.Strict as Map
import Data.Either (isLeft)

reportId :: ReportId
reportId = ReportId (UUID.fromWords 0 0 0 901)

withReport :: [Block] -> Definition
withReport blocks = Fixture.definition
    { reports = [Report reportId "Manager report" [Section (SectionId (UUID.fromWords 0 0 0 902)) "Summary" blocks] [FormattedReport, ExcelDownload]] }

tests :: Spec
tests = describe "Daysheet selected reports" do
    it "projects only authored selections and preserves plain text verbatim" do
        let text = "<script>alert('not markup')</script> =HYPERLINK(unsafe)"
        let definition = withReport [Instructions "Plain instructions", FieldBlock (Fixture.field 1)]
        Right document <- pure (Fixture.fresh
            >>= Fixture.save (Daily.RootCell (Fixture.field 1)) 0 (Just (ReferenceScalar (TextLiteral text)))
            >>= Fixture.save (Daily.RootCell (Fixture.field 2)) 0 (Just (ReferenceScalar (WholeLiteral 999))))
        Right saved <- pure (Saved.prepareSaved definition Fixture.references Fixture.owner document)
        projectReport saved reportId `shouldBe` Right (ReportContent "Manager report"
            [ReportSection "Summary" [ReportInstructions "Plain instructions", ReportField "Comments" (ReportValue (TextLiteral text) text)]])
        projectReport saved (ReportId UUID.nil) `shouldBe` Left UnknownReport
    it "recomputes selected calculations without leaking hidden missing-input labels" do
        let base = withReport [FieldBlock (Fixture.field 100)]
        let definition = base { rootFields = map (\field -> if fieldId field == Fixture.field 2 then field { fieldLabel = "Secret count" } else field) (rootFields base)
                <> [Field (Fixture.field 100) "Double" WholeType (Calculated (Binary Multiply (ReadField (FieldPath Root [Fixture.field 2])) (Constant (WholeLiteral 2))))] }
        Right document <- pure Fixture.fresh
        Right saved <- pure (Saved.prepareSaved definition Fixture.references Fixture.owner document)
        projectReport saved reportId `shouldBe` Right (ReportContent "Manager report"
            [ReportSection "Summary" [ReportField "Double" (ReportUnavailable "Required input has not been entered.")]])
        Right changed <- pure (Daily.saveCell definition Fixture.references Fixture.owner (Daily.RootCell (Fixture.field 2)) 0 (Just (ReferenceScalar (WholeLiteral 7))) document)
        Right changedSaved <- pure (Saved.prepareSaved definition Fixture.references Fixture.owner changed)
        projectReport changedSaved reportId `shouldBe` Right (ReportContent "Manager report"
            [ReportSection "Summary" [ReportField "Double" (ReportValue (WholeLiteral 14) "14")]])
    it "resolves selected references to captured labels without exposing source records" do
        let definition = withReport [TableBlock (Fixture.list 20) [Fixture.field 7] Nothing []]
        Right document <- pure Fixture.fresh
        Right saved <- pure (Saved.prepareSaved definition Fixture.references Fixture.owner document)
        projectReport saved reportId `shouldBe` Right (ReportContent "Manager report"
            [ReportSection "Summary" [ReportTable "Receipts" ["Terminal"] Nothing
                [ReportGroup Nothing [[ReportValue (TextLiteral "Preserved terminal") "Preserved terminal"]]]]])
    it "shows honest checks and never discovers hidden row text for advisory identities" do
        let check = Advisory (Binary GreaterOrEqual (ReadField (FieldPath Root [Fixture.field 2])) (Constant (WholeLiteral 0))) "Within tolerance" "Review count"
        let definition = withReport [AdvisoryBlock check, RowAdvisoryBlock (Fixture.list 30) check]
        Right document <- pure Fixture.linked
        Right saved <- pure (Saved.prepareSaved definition Fixture.references Fixture.owner document)
        projectReport saved reportId `shouldBe` Right (ReportContent "Manager report" [ReportSection "Summary"
            [ ReportAdvisory (ReportNotEvaluated "Required input has not been entered.")
            , ReportRowAdvisories "Bands" [("Bands record 1", ReportNotEvaluated "Required input has not been entered.")]]])
        Right changed <- pure (Daily.saveCell definition Fixture.references Fixture.owner (Daily.RootCell (Fixture.field 2)) 0 (Just (ReferenceScalar (WholeLiteral (-1)))) document)
        Right changedSaved <- pure (Saved.prepareSaved definition Fixture.references Fixture.owner changed)
        projectReport changedSaved reportId `shouldBe` Right (ReportContent "Manager report" [ReportSection "Summary"
            [ReportAdvisory (ReportConcern "Review count"), ReportRowAdvisories "Bands" [("Bands record 1", ReportConcern "Review count")]]])
    it "groups preserved references by display label and sorts selected rows within groups" do
        let definition = withReport [TableBlock (Fixture.list 40) [Fixture.field 5, Fixture.field 6] (Just (Fixture.field 5)) [(Fixture.field 6, Descending)]]
        let otherBand = ReferenceKey (Fixture.list 30) (Fixture.row 49)
        let thirdReading = ReferenceKey (Fixture.list 40) (Fixture.row 62)
        Right document <- pure (Fixture.linked >>= Fixture.add otherBand
            >>= Fixture.save (Daily.RowCell otherBand (Fixture.field 4)) 0 (Fixture.text "Z band")
            >>= Fixture.add Fixture.otherReading
            >>= Fixture.save (Daily.RowCell Fixture.otherReading (Fixture.field 5)) 0 (Just (ReferenceLink otherBand))
            >>= Fixture.save (Daily.RowCell Fixture.otherReading (Fixture.field 6)) 0 (Just (ReferenceScalar (WholeLiteral 10)))
            >>= Fixture.add thirdReading
            >>= Fixture.save (Daily.RowCell thirdReading (Fixture.field 5)) 0 (Just (ReferenceLink Fixture.band))
            >>= Fixture.save (Daily.RowCell thirdReading (Fixture.field 6)) 0 (Just (ReferenceScalar (WholeLiteral 93))))
        Right saved <- pure (Saved.prepareSaved definition Fixture.references Fixture.owner document)
        projectReport saved reportId `shouldBe` Right (ReportContent "Manager report" [ReportSection "Summary"
            [ReportTable "Readings" ["Band", "Reading"] (Just "Band")
                [ ReportGroup (Just (ReportValue (TextLiteral "Band A") "Band A"))
                    [[ReportValue (TextLiteral "Band A") "Band A", ReportValue (WholeLiteral 94) "94"], [ReportValue (TextLiteral "Band A") "Band A", ReportValue (WholeLiteral 93) "93"]]
                , ReportGroup (Just (ReportValue (TextLiteral "Z band") "Z band")) [[ReportValue (TextLiteral "Z band") "Z band", ReportValue (WholeLiteral 10) "10"]]]]])
    it "shares one execution budget across all report advisories" do
        let snapshot = E.Snapshot Fixture.owner Map.empty (Map.singleton (Fixture.list 30)
                (Map.fromList [(Fixture.row n, Map.empty) | n <- [1 .. 1000]]))
        Right evaluation <- pure (E.prepareEvaluation Fixture.definition snapshot)
        let check = Advisory (Binary GreaterOrEqual (Fold Count (Fixture.list 30) Nothing (Constant (WholeLiteral 1))) (Constant (WholeLiteral 0))) "Passed" "Concern"
        Right results <- pure (E.evaluateAdvisories evaluation (replicate 1024 (E.RootAdvisory check)))
        take 1 results `shouldBe` [[Passed "Passed"]]
        drop 1023 results `shouldBe` [[NotEvaluated EvaluationLimit]]
    it "bounds advisory batches and rejects unknown list scopes even when empty" do
        Right evaluation <- pure (E.prepareEvaluation Fixture.definition (E.Snapshot Fixture.owner Map.empty Map.empty))
        let check = Advisory (Constant (BooleanLiteral True)) "Passed" "Concern"
        E.evaluateAdvisories evaluation [E.ListAdvisory (Fixture.list 999) [] check] `shouldSatisfy` isLeft
        E.evaluateAdvisories evaluation (replicate (maxExpressionNodes limits + 1) (E.RootAdvisory check)) `shouldSatisfy` isLeft
        E.evaluateAdvisories evaluation [E.RootAdvisory check] `shouldBe` Right [[Passed "Passed"]]
