module Application.PublicHolidays.Override
    ( PublicHolidayOverrideStatus (..)
    , fetchActivePublicHolidayOverrides
    , overrideStatus
    , overriddenYears
    , usableOverrideYears
    , verifiedVic2026Holidays
    , verifiedVic2026Key
    , verifiedVic2026SourceUrl
    ) where

import qualified Data.Set as Set
import Generated.Types
import IHP.ControllerPrelude

-- Protection and usability are deliberately separate: expiry never enables
-- DataVic writes. Retirement requires the operator-controlled cutover runbook.
data PublicHolidayOverrideStatus = OverrideReady | OverrideExpired | OverrideInvalid
    deriving (Eq, Show)

verifiedVic2026Key :: Text
verifiedVic2026Key = "business-victoria-vic-2026-20260915-v1"

verifiedVic2026SourceUrl :: Text
verifiedVic2026SourceUrl = "https://business.vic.gov.au/business-information/public-holidays/victorian-public-holidays-2026"

-- Reviewed against Business Victoria on 2026-09-15. Names retain the existing
-- DataVic spelling so activating the snapshot does not rewrite row identities.
verifiedVic2026Holidays :: [(Day, Text)]
verifiedVic2026Holidays =
    [ holiday 1 1 "New Year's Day"
    , holiday 1 26 "Australia Day"
    , holiday 3 9 "Labour Day"
    , holiday 4 3 "Good Friday"
    , holiday 4 4 "Saturday before Easter Sunday"
    , holiday 4 5 "Easter Sunday"
    , holiday 4 6 "Easter Monday"
    , holiday 4 25 "ANZAC Day"
    , holiday 6 8 "King's Birthday"
    , holiday 9 25 "Friday before the AFL grand final"
    , holiday 11 3 "Melbourne Cup"
    , holiday 12 25 "Christmas Day"
    , holiday 12 26 "Boxing Day"
    , holiday 12 28 "Boxing Day"
    ]
  where
    holiday month day name = (fromGregorian 2026 month day, name)

fetchActivePublicHolidayOverrides :: (?modelContext :: ModelContext) => IO [PublicHolidayOverride]
fetchActivePublicHolidayOverrides =
    query @PublicHolidayOverride
        |> filterWhere (#jurisdiction, "VIC" :: Text)
        |> filterWhere (#retiredAt, Nothing)
        |> fetch

overriddenYears :: [PublicHolidayOverride] -> Set.Set Integer
overriddenYears overrides = Set.fromList [fromIntegral entry.targetYear | entry <- overrides, active entry]

usableOverrideYears :: UTCTime -> [PublicHoliday] -> [PublicHolidayOverride] -> Set.Set Integer
usableOverrideYears now holidays overrides =
    Set.fromList
        [ fromIntegral entry.targetYear
        | entry <- overrides
        , overrideStatus now holidays entry == OverrideReady
        ]

overrideStatus :: UTCTime -> [PublicHoliday] -> PublicHolidayOverride -> PublicHolidayOverrideStatus
overrideStatus now holidays entry
    | not (active entry)
        || entry.targetYear /= 2026
        || entry.snapshotKey /= verifiedVic2026Key
        || entry.sourceUrl /= verifiedVic2026SourceUrl
        || entry.verifiedAt > now
        || entry.reviewDueAt <= entry.verifiedAt
        || actual /= sort [(day, name, Nothing) | (day, name) <- verifiedVic2026Holidays] = OverrideInvalid
    | now >= entry.reviewDueAt = OverrideExpired
    | otherwise = OverrideReady
  where
    -- Compare the complete multiset, not just count or membership: extra,
    -- duplicate, missing, misdated and wrongly scoped rows cannot be trusted.
    actual = sort
        [ (holiday.holidayDate, holiday.name, holiday.region)
        | holiday <- holidays
        , holiday.jurisdiction == "VIC"
        , not holiday.isRegional
        , let (year, _, _) = toGregorian holiday.holidayDate
        , year == 2026
        ]

active :: PublicHolidayOverride -> Bool
active entry = entry.jurisdiction == "VIC" && isNothing entry.retiredAt
