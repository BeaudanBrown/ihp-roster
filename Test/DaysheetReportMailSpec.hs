module Test.DaysheetReportMailSpec where

import Prelude
import Application.Daysheet.Report
import Application.Helper.View.DaysheetReport (reportPlainText)
import qualified Data.Text as Text
import qualified Data.Text.Lazy as LazyText
import Data.Time
import qualified IHP.HSX.Markup as Markup
import Test.Hspec
import qualified Test.DaysheetReportCodecSpec as Fixture
import Web.Mail.DaysheetReport

tests :: Spec
tests = describe "Daysheet frozen report mail" do
    it "renders selected tables and every check state in HTML and plain text" do
        let at = UTCTime (fromGregorian 2030 10 1) 0
        let content = frozenReportMailContent (FrozenReportIdentity (fromGregorian 2030 9 30) at Nothing) Fixture.report
        let html = LazyText.toStrict (Markup.renderMarkupLazyText content.reportHtml)
        mapM_ (\label -> content.reportText `shouldSatisfy` Text.isInfixOf label)
            ["Manual frozen report", "Captured:", "Selected table", "Text: Captured label", "Flag: No", "Passed:", "Concern:", "Not evaluated:", "Unavailable:"]
        html `shouldSatisfy` Text.isInfixOf "&lt;script&gt;not executable&lt;/script&gt;"
        html `shouldSatisfy` (not . Text.isInfixOf "<script>")
        reportPlainText (ReportContent "Empty" [ReportSection "Table" [ReportTable "Rows" ["Value"] Nothing []]]) `shouldSatisfy` Text.isInfixOf "No rows."
    it "distinguishes actual capture time from scheduled cutoff and normalizes header controls" do
        let cutoff = UTCTime (fromGregorian 2030 10 1) 0
        let actual = addUTCTime 0.01 cutoff
        let content = frozenReportMailContent (FrozenReportIdentity (fromGregorian 2030 9 30) actual (Just cutoff))
                (ReportContent (Text.replicate 500 "x" <> "\r\nBcc: private@example.test\NUL") [])
        content.reportText `shouldSatisfy` Text.isInfixOf "Scheduled frozen report"
        content.reportText `shouldSatisfy` Text.isInfixOf "Captured: 2030-10-01 00:00:00.01 UTC"
        content.reportText `shouldSatisfy` Text.isInfixOf "Scheduled cutoff: 2030-10-01 00:00:00 UTC"
        Text.length content.reportSubject `shouldSatisfy` (<= 254)
        Text.any (`elem` ['\r', '\n', '\NUL']) content.reportSubject `shouldBe` False
