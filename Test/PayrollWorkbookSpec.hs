module Test.PayrollWorkbookSpec where

import Application.Helper.Export.PayrollWorkbook
import qualified "zip-archive" Codec.Archive.Zip as Zip
import qualified Codec.Xlsx as Xlsx
import "crypton" Crypto.Hash (Digest, SHA256, hashlazy)
import qualified Data.ByteString.Lazy as LBS
import Data.Either (isRight)
import qualified Data.Text as Text
import Data.Text.Encoding (decodeUtf8)
import Data.Time.Calendar (fromGregorian)
import IHP.Prelude
import Test.Hspec

tests :: Spec
tests =
    describe "Payroll Workbook XLSX foundation" do
        it "renders deterministic typed cells and workbook presentation primitives" do
            let workbook = minimalPayrollWorkbook (fromGregorian 2025 1 6) (fromGregorian 2025 1 12)
            let firstRender = renderPayrollWorkbook workbook
            let secondRender = renderPayrollWorkbook workbook
            firstRender `shouldBe` secondRender
            show (hashlazy firstRender :: Digest SHA256)
                `shouldBe` "36faa7a22e81c63a26546fe5eda735e2c1eb0f16b8c15ce0af6c8f8b8044a784"
            LBS.take 2 firstRender `shouldBe` "PK"
            Xlsx.toXlsxEither firstRender `shouldSatisfy` isRight

            let archive = Zip.toArchive firstRender
            forM_ ["xl/worksheets/sheet1.xml", "xl/styles.xml", "xl/sharedStrings.xml"] \path ->
                Zip.filesInArchive archive `shouldSatisfy` elem path
            sheetXml <- archiveText "xl/worksheets/sheet1.xml" archive
            stylesXml <- archiveText "xl/styles.xml" archive
            sharedStringsXml <- archiveText "xl/sharedStrings.xml" archive

            sheetXml `shouldSatisfy` Text.isInfixOf "<sheetPr><tabColor rgb=\"FF4472C4\"/></sheetPr>"
            sheetXml `shouldSatisfy` Text.isInfixOf "hidden=\"1\""
            sheetXml `shouldSatisfy` Text.isInfixOf "state=\"frozen\""
            sheetXml `shouldSatisfy` Text.isInfixOf "topLeftCell=\"B2\""
            sheetXml `shouldSatisfy` Text.isInfixOf "ref=\"A1:C2\""
            sheetXml `shouldSatisfy` Text.isInfixOf "SUM(B2:B2)"
            stylesXml `shouldSatisfy` Text.isInfixOf "D9EAF7"
            stylesXml `shouldSatisfy` Text.isInfixOf "formatCode=\"0.00\""
            sharedStringsXml `shouldSatisfy` Text.isInfixOf "Payroll Workbook"

        it "normalizes RGB colours and rejects malformed colours" do
            payrollWorkbookColor "4472c4" `shouldBe` payrollWorkbookColor "FF4472C4"
            payrollWorkbookColor "blue" `shouldBe` Left "Workbook colours must be six-digit RGB or eight-digit ARGB hexadecimal values."

archiveText :: FilePath -> Zip.Archive -> IO Text
archiveText path archive =
    case Zip.findEntryByPath path archive of
        Nothing -> expectationFailure ("Missing XLSX archive entry: " <> path) >> pure ""
        Just entry -> pure (decodeUtf8 (LBS.toStrict (Zip.fromEntry entry)))
