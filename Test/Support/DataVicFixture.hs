module Test.Support.DataVicFixture (loadDataVicHolidayFixture) where

import Application.PublicHolidays.Client (DataVicDate, decodeDataVicYear)
import qualified Data.ByteString.Lazy as LByteString
import IHP.Prelude

loadDataVicHolidayFixture :: Integer -> IO [DataVicDate]
loadDataVicHolidayFixture year = do
    payload <- LByteString.readFile ("Test/Fixtures/wage-sources/datavic-v2/" <> cs (show year) <> ".json")
    either (fail . cs . show) pure (decodeDataVicYear year payload)
