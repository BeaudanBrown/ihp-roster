module Test.DaysheetReportCodecSpec where

import Prelude
import qualified Application.Daysheet.Contract as D
import qualified Application.Daysheet.Number as Number
import Application.Daysheet.Report
import Application.Daysheet.ReportCodec
import Application.Daysheet.Wire (literalJson, parseLiteralJson)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Text as Text
import Data.Time (TimeOfDay (..), fromGregorian)
import qualified Data.UUID as UUID
import Data.Either (isLeft)
import Test.Hspec

report :: ReportContent
report = ReportContent "Closing" [ReportSection "Totals"
    [ ReportInstructions "<script>not executable</script> =SUM(A1:A2)"
    , ReportField "Unavailable" (ReportUnavailable "Required input has not been entered.")
    , ReportAdvisory (ReportPassed "Passed")
    , ReportAdvisory (ReportConcern "Check totals")
    , ReportRowAdvisories "Rows" [("Row 1", ReportNotEvaluated "No input")]
    , ReportTable "Selected table" ["Text", "Flag"] (Just "Text")
        [ ReportGroup (Just (ReportValue (D.TextLiteral "Captured label") "Captured label"))
            [[ReportValue (D.TextLiteral "zero") "zero", ReportValue (D.BooleanLiteral False) "No"]]
        , ReportGroup Nothing []
        ]
    ]]

tests :: Spec
tests = describe "Daysheet frozen report codec" do
    it "preserves ordered selected content, captured copy and all advisory outcomes" do
        Right encoded <- pure (encodeReportContent report)
        decodeReportContent encoded `shouldBe` Right report
        fmap (Aeson.encode) (encodeReportContent report) `shouldBe` Right (Aeson.encode encoded)
    it "retains exact calculated money without relaxing authored whole-cent input" do
        Right third <- pure (Number.number 1 3)
        let literal = D.MoneyLiteral third
        let content = ReportContent "Money" [ReportSection "Summary" [ReportField "Exact amount" (ReportValue literal "Captured exact 1/3 AUD")]]
        (encodeReportContent content >>= decodeReportContent) `shouldBe` Right content
        isLeft (Aeson.parseEither parseLiteralJson (literalJson literal)) `shouldBe` True
    it "retains every resolved scalar and its original display rather than reformatting" do
        Right third <- pure (Number.number 1 3)
        let values = [D.TextLiteral "=HYPERLINK(unsafe)", D.BooleanLiteral False, D.WholeLiteral 0,
                D.DecimalLiteral third, D.MoneyLiteral third, D.PercentageLiteral third,
                D.DateLiteral (fromGregorian 2026 10 6), D.OperationalTimeLiteral (TimeOfDay 5 59 59)]
        let content = ReportContent "Scalars" [ReportSection "Selected"
                [ReportField "Value" (ReportValue value "Captured display, not today's formatter") | value <- values]]
        (encodeReportContent content >>= decodeReportContent) `shouldBe` Right content
    it "rejects raw nominal identities and NUL throughout the selected document" do
        let content block = ReportContent "Selected" [ReportSection "Section" [block]]
        encodeReportContent (content (ReportField "Choice" (ReportValue (D.ChoiceLiteral (D.ChoiceId UUID.nil)) "Unknown"))) `shouldBe` Left InvalidReportPayload
        mapM_ (\value -> encodeReportContent value `shouldBe` Left InvalidReportPayload)
            [ ReportContent "\NUL" []
            , content (ReportInstructions "\NUL")
            , content (ReportField "Label" (ReportValue (D.TextLiteral "\NUL") "Safe display"))
            , content (ReportField "Label" (ReportValue (D.WholeLiteral 0) "\NUL"))
            , content (ReportAdvisory (ReportConcern "\NUL"))
            , content (ReportTable "Table" ["\NUL"] Nothing [])
            ]
    it "rejects unknown versions, envelope fields and cell fields without echoing content" do
        Right (Aeson.Object encoded) <- pure (encodeReportContent report)
        decodeReportContent (Aeson.Object (KeyMap.insert "version" (Aeson.toJSON (2 :: Int)) encoded)) `shouldBe` Left InvalidReportPayload
        decodeReportContent (Aeson.Object (KeyMap.insert "extra" Aeson.Null encoded)) `shouldBe` Left InvalidReportPayload
        decodeReportContent (Aeson.Object (KeyMap.delete "version" encoded)) `shouldBe` Left InvalidReportPayload
        let cell = Aeson.object ["kind" Aeson..= ("unavailable" :: Text.Text), "reason" Aeson..= ("Private input" :: Text.Text), "extra" Aeson..= True]
        isLeft (Aeson.parseEither Aeson.parseJSON cell :: Either String ReportCell) `shouldBe` True
    it "bounds the complete selected payload before storage or interpretation" do
        let content = ReportContent "Large" [ReportSection "Section" [ReportInstructions (Text.replicate 16777216 "x")]]
        encodeReportContent content `shouldBe` Left ReportPayloadTooLarge
