module Test.XeroImportedPayItemsSpec where

import Application.Helper.Xero
import Application.Xero.Admin.ImportedPayItems
import qualified Data.Aeson as Aeson
import Data.Scientific (Scientific)
import Generated.Types
import IHP.ModelSupport
import IHP.Prelude
import Test.Hspec

tests :: Spec
tests =
    describe "Imported Xero pay items" do
        it "accepts only Bepis-shaped active hourly ordinary earnings rates" do
            xeroEarningsRateIsSupportedImportedPayItem supportedRate `shouldBe` True
            xeroEarningsRateIsSupportedImportedPayItem supportedRate { xeroEarningsRateIsActive = False } `shouldBe` False
            xeroEarningsRateIsSupportedImportedPayItem supportedRate { xeroEarningsRateType = Just "ALLOWANCE" } `shouldBe` False
            xeroEarningsRateIsSupportedImportedPayItem supportedRate { xeroEarningsRateRateType = Just "MULTIPLE" } `shouldBe` False
            xeroEarningsRateIsSupportedImportedPayItem supportedRate { xeroEarningsRateTypeOfUnits = Just "Days" } `shouldBe` False
            xeroEarningsRateIsSupportedImportedPayItem supportedRate { xeroEarningsRateRatePerUnit = Nothing } `shouldBe` False

        it "filters Bepis-generated and already imported rates from import candidates" do
            let candidates = viableImportedPayItemCandidates [importedPayItem "already-imported"]
                    [ supportedRate { xeroEarningsRateId = "new", xeroEarningsRateName = "Venue custom ordinary" }
                    , supportedRate { xeroEarningsRateId = "bepis", xeroEarningsRateName = "Bepis - Ordinary L4" }
                    , supportedRate { xeroEarningsRateId = "already-imported", xeroEarningsRateName = "Already imported" }
                    ]
            map (.candidateEarningsRate.xeroEarningsRateId) candidates `shouldBe` ["new"]

supportedRate :: XeroEarningsRateRef
supportedRate =
    XeroEarningsRateRef
        { xeroEarningsRateId = "supported"
        , xeroEarningsRateName = "Venue custom ordinary"
        , xeroEarningsRateType = Just "ORDINARYTIMEEARNINGS"
        , xeroEarningsRateRateType = Just "RATEPERUNIT"
        , xeroEarningsRateAccountCode = Just "477"
        , xeroEarningsRateTypeOfUnits = Just "Hours"
        , xeroEarningsRateRatePerUnit = Just (30 :: Scientific)
        , xeroEarningsRateIsActive = True
        , xeroEarningsRateRaw = Aeson.object []
        }

importedPayItem :: Text -> XeroImportedPayItem
importedPayItem earningsRateId =
    newRecord @XeroImportedPayItem
        |> set #xeroEarningsRateId earningsRateId
