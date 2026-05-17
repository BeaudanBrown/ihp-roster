module Test.MutationBoundarySpec where

import qualified Data.Text as Text
import qualified Data.Text.IO as Text
import IHP.Prelude
import Test.Hspec

tests :: Spec
tests = describe "Mutation boundary guard" do
    it "keeps leave request database writes in the mutation module" do
        source <- Text.readFile "Web/Controller/LeaveRequests.hs"
        let forbiddenTokens = ["createRecord", "updateRecord", "withTransaction", "recordCurrentUserLeaveRequestEvent", "recordCurrentUserAuditEvent"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []
