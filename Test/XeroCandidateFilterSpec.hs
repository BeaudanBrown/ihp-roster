module Test.XeroCandidateFilterSpec where

import Application.Helper.FrontendContract.XeroCandidateFilter.Runtime
import Application.Helper.Xero (XeroEarningsRateRef (..))
import Application.Xero.Admin.ImportedPayItems (XeroImportedPayItemCandidate (..))
import Config
import Control.Exception (evaluate)
import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import IHP.Prelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support
import Text.Blaze.Html (Html)
import qualified Text.Blaze.Html.Renderer.Text as HtmlRenderer
import Web.View.Admin.Xero.ImportedPayItems (renderXeroImportedPayItemImportDialog)

tests :: Spec
tests = do
    describe "Xero candidate filter contract runtime" do
        it "renders generated roles with one normalized opaque search projection" do
            xeroCandidateFilterRootAttrs
                `shouldBe` [("data-bepis-xero-candidate-filter-root", "true")]
            xeroCandidateFilterSearchAttrs
                `shouldBe` [("data-bepis-xero-candidate-filter-search", "true")]
            xeroCandidateFilterCandidateAttrs
                (xeroCandidateSearchProjection ["  Venue  Custom ORDINARY ", " 477 "])
                `shouldBe`
                    [ ("data-bepis-xero-candidate-filter-candidate", "true")
                    , ("data-bepis-xero-candidate-filter-config", "{\"searchProjection\":\"venue custom ordinary 477\"}")
                    ]
            xeroCandidateFilterEmptyAttrs
                `shouldBe` [("data-bepis-xero-candidate-filter-empty", "true")]

        it "rejects an empty Haskell-owned search projection" do
            evaluate
                (attrsTextLength (xeroCandidateFilterCandidateAttrs (xeroCandidateSearchProjection ["  ", "\t"])))
                `shouldThrow` errorCall "Xero candidate search projection must not be empty"

    aroundAll withDatabaseTestContext do
        describe "Xero candidate filter rendering" do
            it "renders generated filter roles, Haskell-selected projection, accessibility, and import fields" $ withContext do
                withCurrentControllerContext do
                    let html = renderText (renderXeroImportedPayItemImportDialog [candidate])

                    html `shouldSatisfy` Text.isInfixOf "data-bepis-xero-candidate-filter-root=\"true\""
                    html `shouldSatisfy` Text.isInfixOf "data-bepis-xero-candidate-filter-search=\"true\""
                    html `shouldSatisfy` Text.isInfixOf "data-bepis-xero-candidate-filter-candidate=\"true\""
                    html `shouldSatisfy` Text.isInfixOf "data-bepis-xero-candidate-filter-config=\"{&quot;searchProjection&quot;:&quot;venue custom ordinary 477&quot;}\""
                    html `shouldSatisfy` Text.isInfixOf "data-bepis-xero-candidate-filter-empty=\"true\""
                    html `shouldSatisfy` Text.isInfixOf "aria-label=\"Search pay items\""
                    html `shouldSatisfy` Text.isInfixOf "role=\"status\""
                    html `shouldSatisfy` Text.isInfixOf "aria-live=\"polite\""
                    html `shouldSatisfy` Text.isInfixOf "No pay items match your search."
                    html `shouldSatisfy` Text.isInfixOf "id=\"xero-imported-pay-items-import-form\""
                    html `shouldSatisfy` Text.isInfixOf "hx-post=\"/ImportXeroPayItems\""
                    html `shouldSatisfy` Text.isInfixOf "hx-target=\"#dialog-overlay-mount\""
                    html `shouldSatisfy` Text.isInfixOf "hx-swap=\"innerHTML\""
                    html `shouldSatisfy` Text.isInfixOf "name=\"xeroEarningsRateId\""
                    html `shouldSatisfy` Text.isInfixOf "value=\"rate-1\""
                    html `shouldSatisfy` not . Text.isInfixOf "data-xero-import-"

            it "preserves the server-owned no-candidates empty state without a browser projection" $ withContext do
                withCurrentControllerContext do
                    let html = renderText (renderXeroImportedPayItemImportDialog [])

                    html `shouldSatisfy` Text.isInfixOf "No new supported Xero pay items are available to import."
                    html `shouldSatisfy` Text.isInfixOf "data-bepis-xero-candidate-filter-root=\"true\""
                    html `shouldSatisfy` Text.isInfixOf "data-bepis-xero-candidate-filter-search=\"true\""
                    html `shouldSatisfy` not . Text.isInfixOf "data-bepis-xero-candidate-filter-candidate"
                    html `shouldSatisfy` not . Text.isInfixOf "data-bepis-xero-candidate-filter-config"

candidate :: XeroImportedPayItemCandidate
candidate = XeroImportedPayItemCandidate
    { candidateEarningsRate = XeroEarningsRateRef
        { xeroEarningsRateId = "rate-1"
        , xeroEarningsRateName = "Venue  Custom Ordinary"
        , xeroEarningsRateType = Just "ORDINARYTIMEEARNINGS"
        , xeroEarningsRateRateType = Just "RATEPERUNIT"
        , xeroEarningsRateAccountCode = Just "477"
        , xeroEarningsRateTypeOfUnits = Just "Hours"
        , xeroEarningsRateRatePerUnit = Just 30
        , xeroEarningsRateIsActive = True
        , xeroEarningsRateRaw = Aeson.object []
        }
    }

renderText :: Html -> Text
renderText = cs . HtmlRenderer.renderHtml

attrsTextLength :: [(Text, Text)] -> Int
attrsTextLength = Text.length . Text.concat . fmap snd
