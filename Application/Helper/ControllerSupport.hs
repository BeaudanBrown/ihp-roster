{-# LANGUAGE TypeApplications #-}

module Application.Helper.ControllerSupport where

import Data.List (find)
import Generated.Types
import IHP.ControllerPrelude

data UserRole
    = StaffRole
    | ManagerRole
    | AdminRole
    deriving (Eq, Show)

leaveRequestIsArchivedOn :: Day -> LeaveRequest -> Bool
leaveRequestIsArchivedOn today leaveRequest =
    leaveRequest.endDate < today

allUserRoleValues :: [Text]
allUserRoleValues = ["staff", "manager", "admin"]

allVenueRoleValues :: [Text]
allVenueRoleValues = map inputValue (allEnumValues @VenueRoleEnum)

allPlatformRoleValues :: [Text]
allPlatformRoleValues = map inputValue (allEnumValues @PlatformRoleEnum)

allLeaveRequestStatusValues :: [Text]
allLeaveRequestStatusValues = map inputValue (allEnumValues @LeaveRequestStatusEnum)

allAuditEventTypeValues :: [Text]
allAuditEventTypeValues =
    [ "timesheet_approved"
    , "timesheet_unapproved"
    , "timesheet_approval_reset"
    , "leave_approved"
    , "leave_denied"
    , "leave_deleted"
    , "venue_role_assigned"
    , "venue_role_changed"
    , "venue_bootstrapped"
    , "export_generated"
    , "export_downloaded"
    , "support_access_granted"
    , "login_succeeded"
    , "login_failed"
    , "login_blocked"
    , "passkey_step_up_succeeded"
    , "passkey_step_up_failed"
    ]

allAuditSourceChannelValues :: [Text]
allAuditSourceChannelValues = ["web", "htmx", "system"]

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
