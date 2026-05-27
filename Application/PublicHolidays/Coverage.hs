module Application.PublicHolidays.Coverage
    ( PublicHolidayCoverageStatus (..)
    , PublicHolidayCoverageYear (..)
    , fetchPublicHolidayCoverage
    , publicHolidayCoverageHasWarning
    ) where

import Application.PublicHolidays.Policy (publicHolidayFreshnessWarningAge,
                                           targetPublicHolidayYears)
import qualified Application.PublicHolidays.Policy as PublicHolidayPolicy
import qualified Data.Map.Strict as Map
import Data.Time.Calendar (toGregorian)
import Data.Time.Clock (UTCTime, addUTCTime, getCurrentTime, utctDay)
import Generated.Types
import IHP.ControllerPrelude

data PublicHolidayCoverageStatus
    = PublicHolidayCoverageHealthy
    | PublicHolidayCoverageMissing
    | PublicHolidayCoverageStale
    deriving (Eq, Show)

data PublicHolidayCoverageYear = PublicHolidayCoverageYear
    { year             :: !Integer
    , cachedCount      :: !Int
    , latestImportedAt :: !(Maybe UTCTime)
    , status           :: !PublicHolidayCoverageStatus
    }
    deriving (Eq, Show)

fetchPublicHolidayCoverage ::
    (?modelContext :: ModelContext) =>
    IO [PublicHolidayCoverageYear]
fetchPublicHolidayCoverage = do
    now <- getCurrentTime
    holidays <-
        query @PublicHoliday
            |> filterWhere (#jurisdiction, PublicHolidayPolicy.publicHolidayJurisdiction)
            |> filterWhere (#isRegional, False)
            |> fetch
    let staleBefore = addUTCTime (negate publicHolidayFreshnessWarningAge) now
    let grouped = foldl' insertHoliday Map.empty holidays
    pure (map (coverageYear staleBefore grouped) (targetPublicHolidayYears (utctDay now)))

publicHolidayCoverageHasWarning :: [PublicHolidayCoverageYear] -> Bool
publicHolidayCoverageHasWarning coverage =
    any (\entry -> entry.status /= PublicHolidayCoverageHealthy) coverage

coverageYear :: UTCTime -> Map.Map Integer [PublicHoliday] -> Integer -> PublicHolidayCoverageYear
coverageYear staleBefore grouped year =
    let holidays = fromMaybe [] (Map.lookup year grouped)
        latestImportedAt = maximumMaybe (mapMaybe (.importedAt) holidays)
        status
            | null holidays = PublicHolidayCoverageMissing
            | maybe True (< staleBefore) latestImportedAt = PublicHolidayCoverageStale
            | otherwise = PublicHolidayCoverageHealthy
     in PublicHolidayCoverageYear
            { year
            , cachedCount = length holidays
            , latestImportedAt
            , status
            }

insertHoliday :: Map.Map Integer [PublicHoliday] -> PublicHoliday -> Map.Map Integer [PublicHoliday]
insertHoliday grouped holiday =
    Map.insertWith (<>) (holidayYear holiday) [holiday] grouped

holidayYear :: PublicHoliday -> Integer
holidayYear holiday =
    let (year, _, _) = toGregorian holiday.holidayDate
     in year

maximumMaybe :: Ord a => [a] -> Maybe a
maximumMaybe []     = Nothing
maximumMaybe values = Just (maximum values)
