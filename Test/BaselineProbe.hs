module Test.BaselineProbe (tests) where

import qualified Data.Text as Text
import Generated.Types
import GHC.Clock (getMonotonicTimeNSec)
import IHP.Prelude
import IHP.Test.Mocking
import Network.HTTP.Types.Status (status200)
import System.Environment (lookupEnv)
import qualified System.IO as IO
import Test.Hspec
import Test.Support
import Web.Controller.RosterWeeks ()
import Web.FrontController ()
import Web.Types

-- This probe is selected explicitly by Test.HspecMain and is never registered
-- in the canonical suite. It keeps measurement phase boundaries out of product
-- and ordinary test behavior.
tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Hspec baseline fixture/application probe" do
        it "times representative roster fixture construction and application execution separately" $ withContext do
            withCleanDb do
                fixtureStartedAt <- getMonotonicTimeNSec
                venue <- createVenueWithConfig "Baseline Probe Venue"
                user <- createUserRecord "baseline-probe@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "manager"
                fixtureFinishedAt <- getMonotonicTimeNSec
                recordDuration "HSPEC_FIXTURE_METRICS_FILE" fixtureStartedAt fixtureFinishedAt

                applicationStartedAt <- getMonotonicTimeNSec
                response <- withUserAndCurrentVenue user venue.id do
                    callAction (ShowRosterWeekAction 0)
                applicationFinishedAt <- getMonotonicTimeNSec
                recordDuration "HSPEC_APPLICATION_METRICS_FILE" applicationStartedAt applicationFinishedAt

                response `responseStatusShouldBe` status200

recordDuration :: String -> Word64 -> Word64 -> IO ()
recordDuration variableName startedAt finishedAt = do
    lookupEnv variableName >>= \case
        Nothing -> pure ()
        Just metricsFile ->
            IO.appendFile metricsFile (Text.unpack (tshow (finishedAt - startedAt)) <> "\n")
