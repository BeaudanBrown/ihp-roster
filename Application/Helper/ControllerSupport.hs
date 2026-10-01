{-# LANGUAGE TypeApplications #-}

module Application.Helper.ControllerSupport where

import Generated.Types
import IHP.ControllerPrelude

data UserRole
    = StaffRole
    | ManagerRole
    | AdminRole
    deriving (Eq, Show)

-- The stored end date is exclusive, so the request is already past on that day.
leaveRequestIsArchivedOn :: Day -> LeaveRequest -> Bool
leaveRequestIsArchivedOn today leaveRequest =
    leaveRequest.endDate <= today

currentVenueCalendarDay :: (?modelContext :: ModelContext) => VenueConfig -> IO Day
currentVenueCalendarDay venueConfig = getCurrentTime >>= venueCalendarDayAt venueConfig

venueCalendarDayAt :: (?modelContext :: ModelContext) => VenueConfig -> UTCTime -> IO Day
venueCalendarDayAt venueConfig now =
    unsafeSqlQueryScalar
        "SELECT (?::timestamptz AT TIME ZONE ?)::date"
        (now, venueConfig.timezone)

allUserRoleValues :: [Text]
allUserRoleValues = ["staff", "manager", "admin"]

allVenueRoleValues :: [Text]
allVenueRoleValues = map inputValue (allEnumValues @VenueRoleEnum)

allPlatformRoleValues :: [Text]
allPlatformRoleValues = map inputValue (allEnumValues @PlatformRoleEnum)

allLeaveRequestStatusValues :: [Text]
allLeaveRequestStatusValues = map inputValue (allEnumValues @LeaveRequestStatusEnum)

enumFromText :: forall enum. (Enum enum, InputValue enum) => Text -> Maybe enum
enumFromText value = find (\enumValue -> inputValue enumValue == value) (allEnumValues @enum)

parseUserRole :: InputValue value => value -> Maybe UserRole
parseUserRole value =
    case inputValue value of
        "staff"   -> Just StaffRole
        "manager" -> Just ManagerRole
        "admin"   -> Just AdminRole
        _         -> Nothing

userRoleToText :: UserRole -> Text
userRoleToText StaffRole   = "staff"
userRoleToText ManagerRole = "manager"
userRoleToText AdminRole   = "admin"
