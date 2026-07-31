module Application.Fixture.DevFixtures.Deterministic
    ( dayAtOffset
    , deterministicIndex
    , deterministicPercent
    , freshUUIDs
    , minutesToTimeOfDay
    , safeIndex
    , textHash
    , timeOfDayToMinutes
    , uniqueWeekdaySequence
    ) where

import Control.Monad (replicateM)
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time.Calendar (Day, addDays)
import Data.Time.LocalTime (TimeOfDay (..))
import Data.UUID (UUID)
import qualified Data.UUID.V4 as UUIDv4
import IHP.Prelude

-- Stable pseudo-random helpers keep scenario projections reproducible without
-- introducing a mutable random generator into domain fixture modules.
deterministicPercent :: Int -> [Int] -> Int
deterministicPercent seedValue values = deterministicIndex seedValue values 100

deterministicIndex :: Int -> [Int] -> Int -> Int
deterministicIndex _ _ 0 = 0
deterministicIndex seedValue keys modulus =
    abs (foldl' (\acc value -> (acc * 1103515245) + value + 12345) (seedValue + 17) keys) `mod` modulus

textHash :: Text -> Int
textHash = Text.foldl' (\acc character -> (acc * 33) + fromEnum character) 7

uniqueWeekdaySequence :: Int -> [Int] -> [Int]
uniqueWeekdaySequence seedValue keys =
    nub (map (\offset -> deterministicIndex seedValue (keys <> [offset]) 7) [0 :: Int .. 20])

safeIndex :: [a] -> Int -> Maybe a
safeIndex values index
    | index < 0 = Nothing
    | otherwise = listToMaybe (drop index values)

freshUUIDs :: Int -> IO [UUID]
freshUUIDs count = replicateM count UUIDv4.nextRandom

timeOfDayToMinutes :: TimeOfDay -> Int
timeOfDayToMinutes timeOfDay = todHour timeOfDay * 60 + todMin timeOfDay

minutesToTimeOfDay :: Int -> TimeOfDay
minutesToTimeOfDay totalMinutes =
    TimeOfDay (totalMinutes `div` 60) (totalMinutes `mod` 60) 0

dayAtOffset :: Day -> Integer -> Day
dayAtOffset = flip addDays
