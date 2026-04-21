{-# LANGUAGE TypeApplications #-}

module Application.Helper.Controller
    ( module Application.Helper.Controller
    , module Application.Helper.ControllerContext
    , module Application.Helper.ControllerSupport
    , module Application.Helper.Htmx
    , module Application.Helper.Audit
    ) where

import Data.Coerce (coerce)
import Data.Time.Calendar (Day, addDays, diffDays)
import Data.Time.Clock (UTCTime (..), getCurrentTime)
import Data.Time.Format (defaultTimeLocale, parseTimeM)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude
import Web.Routes ()
import Web.Types (ProfilesController (EditProfileAction))

import Application.Helper.Audit
import Application.Helper.ControllerContext
import Application.Helper.ControllerSupport
import Application.Helper.Htmx

-- Here you can add functions which are available in all your controllers

fetchVenueConfig :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO VenueConfig
fetchVenueConfig =
    query @VenueConfig
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> fetchOne

requiredProfileFieldsCompleted :: Staff -> Bool
requiredProfileFieldsCompleted staff =
    not
        ( any
            isEmpty
            [ staff.firstName
            , staff.lastName
            , staff.phone
            , staff.emergencyContactName
            , staff.emergencyContactPhone
            ]
        )

isOperationallyActive :: User -> Bool
isOperationallyActive user = user.isProfileCompleted

ensureProfileCompleted :: (?context :: ControllerContext) => IO ()
ensureProfileCompleted =
    unless (isOperationallyActive authenticatedCurrentUser) do
        withRequestContext do
            setErrorMessage "Please complete your profile to continue."
            redirectTo EditProfileAction

hasVenueRole :: VenueRole -> VenueRole -> Bool
hasVenueRole actualRole minimumRole = actualRole >= minimumRole

hasRole :: (?context :: ControllerContext) => VenueRole -> Bool
hasRole minimumRole =
    currentUserIsSuperAdmin || maybe False (`hasVenueRole` minimumRole) currentVenueRoleOrNothing

ensureCurrentVenue :: (?context :: ControllerContext) => IO ()
ensureCurrentVenue = accessDeniedUnless (isJust currentVenueOrNothing)

-- | Deny access (403) unless the current user is a manager or admin.
ensureManagerRole :: (?context :: ControllerContext) => IO ()
ensureManagerRole = accessDeniedUnless (hasRole ManagerRole')

-- | Deny access (403) unless the current user is an admin.
ensureAdminRole :: (?context :: ControllerContext) => IO ()
ensureAdminRole = accessDeniedUnless (hasRole VenueAdminRole)

-- | Parse a HH:MM text value into a TimeOfDay.
parseTimeParam :: Text -> Maybe TimeOfDay
parseTimeParam value = parseTimeM True defaultTimeLocale "%H:%M" (cs value)

-- | True when a TimeOfDay falls on a 15-minute boundary.
isQuarterHourTime :: TimeOfDay -> Bool
isQuarterHourTime tod = todMin tod `mod` 15 == 0 && todSec tod == 0

-- | True when minutes are non-negative and divisible by 15.
isQuarterHourMinutes :: Int -> Bool
isQuarterHourMinutes mins = mins >= 0 && mins `mod` 15 == 0

-- | Compute shift duration in minutes (end - start).
shiftDurationMinutes :: TimeOfDay -> TimeOfDay -> Int
shiftDurationMinutes start end =
    normalizeShiftMinuteOfDay end - normalizeShiftMinuteOfDay start

timeOfDayToMinutes :: TimeOfDay -> Int
timeOfDayToMinutes tod = todHour tod * 60 + todMin tod

-- | Normalize shift-related times onto a linear timeline where 00:00-05:45
-- are treated as next-day continuation of the same working window.
normalizeShiftMinuteOfDay :: TimeOfDay -> Int
normalizeShiftMinuteOfDay tod =
    let minuteOfDay = timeOfDayToMinutes tod
    in if minuteOfDay < 360 then minuteOfDay + 1440 else minuteOfDay

-- | True when the worked-on date is within the staff edit window (inclusive).
-- The window is measured in days from today backwards.
isWithinEditWindow :: Day -> Day -> Int -> Bool
isWithinEditWindow today workedOn windowDays =
    diffDays today workedOn <= fromIntegral windowDays

-- | Guard that denies staff access to entries outside the edit window.
-- Manager/admin roles bypass the restriction entirely.
ensureEditWindowOrManager :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Day -> IO ()
ensureEditWindowOrManager workedOn =
    unless (hasRole ManagerRole') do
        config <- fetchVenueConfig
        today <- utctDay <$> getCurrentTime
        accessDeniedUnless (isWithinEditWindow today workedOn config.staffTimesheetEditWindowDays)

leaveRequestCanBeDeleted :: LeaveRequest -> Bool
leaveRequestCanBeDeleted leaveRequest =
    parseLeaveRequestStatus leaveRequest.status == Just LeavePending

-- | True when leave date range is valid.
-- Start date is first unavailable date, end date is first available date.
isLeaveDateRangeValid :: Day -> Day -> Bool
isLeaveDateRangeValid startDate endDate = endDate > startDate

-- | Returns all week offsets overlapped by an inclusive date range.
affectedWeekOffsetsForDateRange :: Day -> Day -> Day -> [Int]
affectedWeekOffsetsForDateRange epoch startDate endDate
    | not (isLeaveDateRangeValid startDate endDate) = []
    | otherwise = [startOffset .. endOffset]
    where
        toWeekOffset day = fromInteger (diffDays day epoch `div` 7)
        startOffset = toWeekOffset startDate
        leaveLastDate = addDays (-1) endDate
        endOffset = toWeekOffset leaveLastDate

fetchCurrentUserStaff :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO (Maybe Staff)
fetchCurrentUserStaff =
    query @Staff
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#userId, Just (coerce (get #id authenticatedCurrentUser)))
        |> fetchOneOrNothing

staffInCurrentVenueOrNothing :: (?context :: ControllerContext, ?modelContext :: ModelContext) => UUID -> IO (Maybe Staff)
staffInCurrentVenueOrNothing staffId =
    query @Staff
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#id, Id staffId)
        |> fetchOneOrNothing

ensureOptionalStaffInCurrentVenue :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe UUID -> IO ()
ensureOptionalStaffInCurrentVenue maybeStaffId =
    forM_ maybeStaffId \staffId -> do
        maybeStaff <- staffInCurrentVenueOrNothing staffId
        accessDeniedUnless (isJust maybeStaff)

ensureRecordInCurrentVenue :: (?context :: ControllerContext) => UUID -> IO ()
ensureRecordInCurrentVenue venueId =
    accessDeniedUnless (venueId == unpackId currentVenueId)
