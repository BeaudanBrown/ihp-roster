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

data VenueRole
    = WorkerRole
    | ManagerRole'
    | VenueAdminRole
    | VenueOwnerRole
    deriving (Eq, Ord, Show, Enum, Bounded)

data PlatformRole
    = SuperAdminRole
    deriving (Eq, Show)

data LeaveRequestStatus
    = LeavePending
    | LeaveApproved
    | LeaveDenied
    deriving (Eq, Show)

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

unsafeEnumFromText :: forall enum. (Enum enum, InputValue enum) => Text -> enum
unsafeEnumFromText value =
    fromMaybe (error ("Unknown enum value: " <> cs value)) (enumFromText @enum value)

parseUserRole :: InputValue value => value -> Maybe UserRole
parseUserRole value =
    case inputValue value of
        "staff"   -> Just StaffRole
        "manager" -> Just ManagerRole
        "admin"   -> Just AdminRole
        _         -> Nothing

parseVenueRole :: InputValue value => value -> Maybe VenueRole
parseVenueRole value = venueRoleEnumToRole <$> enumFromText @VenueRoleEnum (inputValue value)

parsePlatformRole :: InputValue value => value -> Maybe PlatformRole
parsePlatformRole value = platformRoleEnumToRole <$> enumFromText @PlatformRoleEnum (inputValue value)

parseLeaveRequestStatus :: InputValue value => value -> Maybe LeaveRequestStatus
parseLeaveRequestStatus value = leaveRequestStatusEnumToStatus <$> enumFromText @LeaveRequestStatusEnum (inputValue value)

userRoleToText :: UserRole -> Text
userRoleToText StaffRole   = "staff"
userRoleToText ManagerRole = "manager"
userRoleToText AdminRole   = "admin"

venueRoleToText :: VenueRole -> Text
venueRoleToText WorkerRole     = "worker"
venueRoleToText ManagerRole'   = "manager"
venueRoleToText VenueAdminRole = "venue_admin"
venueRoleToText VenueOwnerRole = "venue_owner"

platformRoleToText :: PlatformRole -> Text
platformRoleToText SuperAdminRole = "super_admin"

leaveRequestStatusToText :: LeaveRequestStatus -> Text
leaveRequestStatusToText LeavePending  = "pending"
leaveRequestStatusToText LeaveApproved = "approved"
leaveRequestStatusToText LeaveDenied   = "denied"

venueRoleEnumToRole :: VenueRoleEnum -> VenueRole
venueRoleEnumToRole enumValue =
    case inputValue enumValue of
        "worker"      -> WorkerRole
        "manager"     -> ManagerRole'
        "venue_admin" -> VenueAdminRole
        "venue_owner" -> VenueOwnerRole
        unexpected    -> error ("Unexpected venue role enum: " <> cs unexpected)

venueRoleToEnum :: VenueRole -> VenueRoleEnum
venueRoleToEnum = unsafeEnumFromText @VenueRoleEnum . venueRoleToText

platformRoleEnumToRole :: PlatformRoleEnum -> PlatformRole
platformRoleEnumToRole enumValue =
    case inputValue enumValue of
        "super_admin" -> SuperAdminRole
        unexpected    -> error ("Unexpected platform role enum: " <> cs unexpected)

platformRoleToEnum :: PlatformRole -> PlatformRoleEnum
platformRoleToEnum = unsafeEnumFromText @PlatformRoleEnum . platformRoleToText

leaveRequestStatusEnumToStatus :: LeaveRequestStatusEnum -> LeaveRequestStatus
leaveRequestStatusEnumToStatus enumValue =
    case inputValue enumValue of
        "pending" -> LeavePending
        "approved" -> LeaveApproved
        "denied" -> LeaveDenied
        unexpected -> error ("Unexpected leave request status enum: " <> cs unexpected)

leaveRequestStatusToEnum :: LeaveRequestStatus -> LeaveRequestStatusEnum
leaveRequestStatusToEnum = unsafeEnumFromText @LeaveRequestStatusEnum . leaveRequestStatusToText
