module Test.Support.DataVicFixture (loadDataVicHolidayFixture) where

import Application.PublicHolidays.Sync (DataVicHolidayRecord,
                                        decodeDataVicPublicHolidayResponse)
import qualified Data.ByteString.Lazy as LByteString
import IHP.Prelude

loadDataVicHolidayFixture :: IO [DataVicHolidayRecord]
loadDataVicHolidayFixture = do
    payload <- LByteString.readFile dataVicFixturePath
    case decodeDataVicPublicHolidayResponse payload of
        Left errorMessage -> fail ("Could not decode DataVic fixture: " <> errorMessage)
        Right records -> pure records

dataVicFixturePath :: FilePath
dataVicFixturePath = "Test/Fixtures/wage-sources/2026-07-24/datavic/public-holidays.json"
