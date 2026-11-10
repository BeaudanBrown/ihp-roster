module Test.SecondsSpec where

import qualified Application.VenueTime.Seconds as Seconds
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..), addUTCTime)
import IHP.Prelude
import Test.Hspec

tests :: Spec
tests = describe "Whole-second business durations" do
    it "rounds decimal ledger hours back to exact seconds" do
        Seconds.toSeconds (Seconds.fromStoredHours (166666666667 / 1000000000000)) `shouldBe` 600
        Seconds.toSeconds (Seconds.fromStoredHours (333333333333 / 1000000000000)) `shouldBe` 1200
        Seconds.toSeconds (Seconds.fromStoredHours (1 / 2)) `shouldBe` 1800
    it "rounds signed half seconds away from zero" do
        map (Seconds.toSeconds . Seconds.fromElapsed) [0, 0.4, 0.5, 1.5, -0.4, -0.5, -1.5]
            `shouldBe` [0, 0, 1, 2, 0, -1, -2]
    it "subtracts timestamps before rounding and supports reverse offsets" do
        let start = UTCTime (fromGregorian 2026 11 4) 0
        Seconds.toSeconds (Seconds.between (addUTCTime 0.4 start) (addUTCTime 1.6 start)) `shouldBe` 1
        Seconds.toSeconds (Seconds.between (addUTCTime 1.6 start) (addUTCTime 0.4 start)) `shouldBe` (-1)
    it "keeps arithmetic exact, signed and unbounded" do
        let large = 10 ^ (30 :: Int)
        Seconds.toSeconds (Seconds.add (Seconds.fromSeconds large) (Seconds.fromMinutes 1)) `shouldBe` large + 60
        Seconds.toSeconds (Seconds.subtract (Seconds.fromMinutes 30) (Seconds.fromMinutes 31)) `shouldBe` (-60)
        Seconds.sum [Seconds.fromSeconds 30, Seconds.fromSeconds (-30)] `shouldBe` Seconds.fromSeconds 0
        Seconds.toHours (Seconds.fromMinutes 10) `shouldBe` 1 / 6
    it "reconstructs the missed-break endpoint without an overrun" do
        let start = UTCTime (fromGregorian 2026 11 4) 0
        Seconds.addTo (Seconds.fromStoredHours (166666666667 / 1000000000000)) start
            `shouldBe` addUTCTime 600 start
