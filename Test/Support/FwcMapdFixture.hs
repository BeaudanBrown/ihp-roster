module Test.Support.FwcMapdFixture (loadFwcMapdFixture) where

import Application.FwcMapd.Client (MapdResultsPage (..))
import Application.FwcMapd.Curation
import Application.FwcMapd.Payload
import Application.FwcMapd.Validation
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LByteString
import Data.Time.Calendar (fromGregorian)
import IHP.Prelude

loadFwcMapdFixture :: IO CuratedMapdAwardData
loadFwcMapdFixture = do
    awardValues <- readMapdFixtureValues "award.json"
    classificationValues <- readMapdFixtureValues "classifications.json"
    payRateValues <- readMapdFixtureValues "pay-rates.json"
    penaltyRateValues <- readMapdFixtureValues "penalties.json"
    wageAllowanceValues <- readMapdFixtureValues "wage-allowances.json"
    awards <- decodePayloads "fixture awards" awardValues
    classifications <- decodePayloads "fixture classifications" classificationValues
    payRates <- decodePayloads "fixture pay rates" payRateValues
    penaltyRates <- decodePayloads "fixture penalty rates" penaltyRateValues
    wageAllowances <- decodePayloads "fixture wage allowances" wageAllowanceValues
    let asOfDate = fromGregorian 2026 7 24
        (curatedAwardFixedId, curatedAwards, curatedClassifications, curatedPayRates, curatedPenaltyRates) =
            curateAwardData
                barVenueCurationProfile
                asOfDate
                (9, awards, classifications, payRates, penaltyRates)
        curatedWageAllowances =
            curateWageAllowances barVenueCurationProfile asOfDate wageAllowances
    pure CuratedMapdAwardData { .. }

fwcMapdFixtureRoot :: FilePath
fwcMapdFixtureRoot = "Test/Fixtures/wage-sources/2026-07-24/fwc-mapd/"

readMapdFixtureValues :: FilePath -> IO [Aeson.Value]
readMapdFixtureValues fixtureName = do
    payload <- LByteString.readFile (fwcMapdFixtureRoot <> fixtureName)
    case Aeson.eitherDecode payload of
        Left errorMessage -> fail ("Could not decode FWC MAPD fixture " <> fixtureName <> ": " <> errorMessage)
        Right page -> pure (page :: MapdResultsPage).results
