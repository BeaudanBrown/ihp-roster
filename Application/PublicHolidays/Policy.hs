module Application.PublicHolidays.Policy
    ( publicHolidayFreshnessWarningAge
    , publicHolidayJurisdiction
    , targetPublicHolidayYears
    ) where

import Application.WageSourcePolicy (dataVicMaximumAge)
import Data.Time.Calendar (Day, toGregorian)
import Data.Time.Clock (NominalDiffTime)
import IHP.Prelude

publicHolidayJurisdiction :: Text
publicHolidayJurisdiction = "VIC"

publicHolidayFreshnessWarningAge :: NominalDiffTime
publicHolidayFreshnessWarningAge = dataVicMaximumAge

targetPublicHolidayYears :: Day -> [Integer]
targetPublicHolidayYears today =
    let (year, _, _) = toGregorian today
     in [year - 1, year, year + 1]
