{-# LANGUAGE TypeApplications #-}

module Application.Helper.Controller where

import qualified Data.Aeson as Aeson
import Data.Coerce (coerce)
import Data.List (find, sortOn)
import Data.Time.Calendar (Day, addDays, diffDays)
import Data.Time.Clock (UTCTime (..), getCurrentTime)
import Data.Time.Format (defaultTimeLocale, parseTimeM)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.Controller.Context (maybeFromContext, putContext)
import IHP.ControllerPrelude
import System.IO.Unsafe (unsafePerformIO)
import Web.Routes ()
import Web.Types (ProfilesController (EditProfileAction))

-- Here you can add functions which are available in all your controllers

currentVenueSessionKey :: ByteString
currentVenueSessionKey = "currentVenueId"

fetchVenueConfig :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO VenueConfig
fetchVenueConfig =
    query @VenueConfig
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> fetchOne

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

newtype SupportVenueOptions = SupportVenueOptions { supportVenueOptions :: [Venue] }

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
    , "export_generated"
    , "export_downloaded"
    , "support_access_granted"
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
    unless (isOperationallyActive currentUser) do
        setErrorMessage "Please complete your profile to continue."
        redirectTo EditProfileAction

currentVenueOrNothing :: (?context :: ControllerContext) => Maybe Venue
currentVenueOrNothing = unsafePerformIO (join <$> maybeFromContext @(Maybe Venue))
{-# NOINLINE currentVenueOrNothing #-}

currentVenue :: (?context :: ControllerContext) => Venue
currentVenue =
    fromMaybe (error "currentVenue: no active venue in controller context") currentVenueOrNothing

currentVenueId :: (?context :: ControllerContext) => Id Venue
currentVenueId = get #id currentVenue

currentVenueMembershipOrNothing :: (?context :: ControllerContext) => Maybe VenueMembership
currentVenueMembershipOrNothing = unsafePerformIO (join <$> maybeFromContext @(Maybe VenueMembership))
{-# NOINLINE currentVenueMembershipOrNothing #-}

currentVenueMembership :: (?context :: ControllerContext) => VenueMembership
currentVenueMembership =
    fromMaybe (error "currentVenueMembership: no active venue membership in controller context") currentVenueMembershipOrNothing

currentVenueRoleOrNothing :: (?context :: ControllerContext) => Maybe VenueRole
currentVenueRoleOrNothing = unsafePerformIO (join <$> maybeFromContext @(Maybe VenueRole))
{-# NOINLINE currentVenueRoleOrNothing #-}

currentSupportVenueOptionsOrNothing :: (?context :: ControllerContext) => Maybe [Venue]
currentSupportVenueOptionsOrNothing =
    case unsafePerformIO (maybeFromContext @SupportVenueOptions) of
        Nothing -> Nothing
        Just (SupportVenueOptions venues) -> Just venues
{-# NOINLINE currentSupportVenueOptionsOrNothing #-}

currentSupportVenueOptions :: (?context :: ControllerContext) => [Venue]
currentSupportVenueOptions = fromMaybe [] currentSupportVenueOptionsOrNothing

currentVenueRole :: (?context :: ControllerContext) => VenueRole
currentVenueRole =
    fromMaybe (error "currentVenueRole: no active venue role in controller context") currentVenueRoleOrNothing

currentUserPlatformRoleOrNothing :: (?context :: ControllerContext) => Maybe PlatformRole
currentUserPlatformRoleOrNothing =
    currentUserOrNothing >>= \user ->
        platformRoleEnumToRole <$> user.platformRole

currentUserIsSuperAdmin :: (?context :: ControllerContext) => Bool
currentUserIsSuperAdmin = currentUserPlatformRoleOrNothing == Just SuperAdminRole

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

-- | True when the current request came from htmx.
isHtmxRequest :: (?context :: ControllerContext) => Bool
isHtmxRequest = getHeader "HX-Request" == Just "true"

-- | Ask htmx to push a canonical URL after a fragment response.
setHtmxPushUrl :: (?context :: ControllerContext) => Text -> IO ()
setHtmxPushUrl url = setHeader ("HX-Push-Url", cs url)

requestAuditSourceChannel :: (?context :: ControllerContext) => Text
requestAuditSourceChannel =
    if isHtmxRequest
        then "htmx"
        else "web"

recordAuditEvent ::
    (?modelContext :: ModelContext) =>
    UUID ->
    UUID ->
    Text ->
    Text ->
    UUID ->
    Aeson.Value ->
    Text ->
    IO AuditEvent
recordAuditEvent venueId actorUserId eventType targetTable targetId payload sourceChannel =
    newRecord @AuditEvent
        |> set #venueId venueId
        |> set #actorUserId actorUserId
        |> set #eventType eventType
        |> set #targetTable targetTable
        |> set #targetId targetId
        |> set #payload payload
        |> set #sourceChannel sourceChannel
        |> createRecord

recordCurrentUserAuditEvent ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Text ->
    Text ->
    UUID ->
    Aeson.Value ->
    IO AuditEvent
recordCurrentUserAuditEvent eventType targetTable targetId payload =
    recordAuditEvent
        (unpackId currentVenueId)
        (unpackId (get #id currentUser))
        eventType
        targetTable
        targetId
        payload
        requestAuditSourceChannel

timesheetEntrySnapshot :: TimesheetEntry -> Aeson.Value
timesheetEntrySnapshot entry =
    Aeson.object
        [ "id" Aeson..= unpackId (get #id entry)
        , "venueId" Aeson..= entry.venueId
        , "staffId" Aeson..= entry.staffId
        , "shiftTypeId" Aeson..= entry.shiftTypeId
        , "workedOn" Aeson..= entry.workedOn
        , "startTime" Aeson..= entry.startTime
        , "endTime" Aeson..= entry.endTime
        , "hadBreak" Aeson..= entry.hadBreak
        , "breakStartTime" Aeson..= entry.breakStartTime
        , "breakEndTime" Aeson..= entry.breakEndTime
        , "breakMinutes" Aeson..= entry.breakMinutes
        , "isApproved" Aeson..= entry.isApproved
        , "approvedAt" Aeson..= entry.approvedAt
        , "approvedByUserId" Aeson..= entry.approvedByUserId
        ]

recordTimesheetEntryVersion ::
    (?modelContext :: ModelContext) =>
    UUID ->
    UUID ->
    EntryVersionActionEnum ->
    TimesheetEntry ->
    Aeson.Value ->
    IO TimesheetEntryVersion
recordTimesheetEntryVersion venueId actorUserId versionAction entry payload =
    newRecord @TimesheetEntryVersion
        |> set #venueId venueId
        |> set #timesheetEntryId (unpackId (get #id entry))
        |> set #actorUserId actorUserId
        |> set #versionAction versionAction
        |> set #snapshot (timesheetEntrySnapshot entry)
        |> set #payload payload
        |> createRecord

recordCurrentUserTimesheetEntryVersion ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    EntryVersionActionEnum ->
    TimesheetEntry ->
    Aeson.Value ->
    IO TimesheetEntryVersion
recordCurrentUserTimesheetEntryVersion =
    recordTimesheetEntryVersion
        (unpackId currentVenueId)
        (unpackId (get #id currentUser))

recordLeaveRequestEvent ::
    (?modelContext :: ModelContext) =>
    UUID ->
    UUID ->
    UUID ->
    LeaveRequestEventTypeEnum ->
    Maybe LeaveRequestStatusEnum ->
    Maybe LeaveRequestStatusEnum ->
    Aeson.Value ->
    IO LeaveRequestEvent
recordLeaveRequestEvent venueId actorUserId leaveRequestId eventType previousStatus newStatus payload =
    newRecord @LeaveRequestEvent
        |> set #venueId venueId
        |> set #leaveRequestId leaveRequestId
        |> set #actorUserId actorUserId
        |> set #eventType eventType
        |> set #previousStatus previousStatus
        |> set #newStatus newStatus
        |> set #payload payload
        |> createRecord

recordCurrentUserLeaveRequestEvent ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    LeaveRequest ->
    LeaveRequestEventTypeEnum ->
    Maybe LeaveRequestStatusEnum ->
    Maybe LeaveRequestStatusEnum ->
    Aeson.Value ->
    IO LeaveRequestEvent
recordCurrentUserLeaveRequestEvent leaveRequest =
    recordLeaveRequestEvent
        (unpackId currentVenueId)
        (unpackId (get #id currentUser))
        (unpackId (get #id leaveRequest))

recordVenueMembershipRoleEvent ::
    (?modelContext :: ModelContext) =>
    UUID ->
    UUID ->
    VenueMembership ->
    VenueMembershipRoleEventTypeEnum ->
    Maybe VenueRoleEnum ->
    VenueRoleEnum ->
    Aeson.Value ->
    IO VenueMembershipRoleEvent
recordVenueMembershipRoleEvent venueId actorUserId membership eventType previousRole newRole payload =
    newRecord @VenueMembershipRoleEvent
        |> set #venueId venueId
        |> set #venueMembershipId (unpackId (get #id membership))
        |> set #actorUserId actorUserId
        |> set #eventType eventType
        |> set #previousRole previousRole
        |> set #newRole newRole
        |> set #payload payload
        |> createRecord

updateVenueMembershipRoleWithAudit ::
    (?modelContext :: ModelContext) =>
    UUID ->
    Text ->
    VenueMembership ->
    VenueRoleEnum ->
    Aeson.Value ->
    IO VenueMembership
updateVenueMembershipRoleWithAudit actorUserId sourceChannel membership newRole payload
    | membership.venueRole == newRole = pure membership
    | otherwise = withTransaction do
        updatedMembership <- membership |> set #venueRole newRole |> updateRecord
        _ <- recordAuditEvent
            membership.venueId
            actorUserId
            "venue_role_changed"
            "venue_memberships"
            (unpackId (get #id membership))
            (Aeson.object
                [ "previousRole" Aeson..= inputValue membership.venueRole
                , "newRole" Aeson..= inputValue newRole
                , "details" Aeson..= payload
                ]
            )
            sourceChannel
        _ <- recordVenueMembershipRoleEvent
            membership.venueId
            actorUserId
            updatedMembership
            Changed
            (Just membership.venueRole)
            newRole
            payload
        pure updatedMembership

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
        |> filterWhere (#userId, Just (coerce (get #id currentUser)))
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

selectCurrentVenueMembership :: Maybe (Id Venue) -> [VenueMembership] -> Maybe VenueMembership
selectCurrentVenueMembership sessionVenueId memberships =
    let orderedMemberships = sortOn (.createdAt) memberships
     in case sessionVenueId >>= \venueId -> find (\membership -> membership.venueId == coerce venueId) orderedMemberships of
            Just membership -> Just membership
            Nothing         -> listToMaybe orderedMemberships

initCurrentVenueContext :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO ()
initCurrentVenueContext = do
    supportVenues <-
        query @Venue
            |> filterWhere (#status, unsafeEnumFromText @VenueStatusEnum "active")
            |> orderByAsc #createdAt
            |> fetch

    putContext (Nothing :: Maybe Venue)
    putContext (Nothing :: Maybe VenueMembership)
    putContext (Nothing :: Maybe VenueRole)
    putContext (SupportVenueOptions supportVenues)

    forM_ currentUserOrNothing \user -> do
        sessionVenueId <- getSession @(Id Venue) currentVenueSessionKey
        maybeVenueContext <- resolveVenueContextForUser sessionVenueId user
        case maybeVenueContext of
            Nothing -> deleteSession currentVenueSessionKey
            Just (membership, venue, role) -> do
                putContext (Just venue)
                putContext membership
                putContext role
                setSession currentVenueSessionKey (get #id venue)

resolveVenueContextForUser :: (?modelContext :: ModelContext) => Maybe (Id Venue) -> User -> IO (Maybe (Maybe VenueMembership, Venue, Maybe VenueRole))
resolveVenueContextForUser sessionVenueId user = do
    memberships <- query @VenueMembership
        |> filterWhere (#userId, unpackId (get #id user))
        |> filterWhere (#isActive, True)
        |> orderByAsc #createdAt
        |> fetch

    let venueIds = map (Id . (.venueId)) memberships
    venues <-
        if null venueIds
            then pure []
            else query @Venue
                |> filterWhereIn (#id, venueIds)
                |> filterWhere (#status, unsafeEnumFromText @VenueStatusEnum "active")
                |> fetch

    let activeVenueIds = map (coerce . (.id)) venues
    let activeMemberships = filter (\membership -> membership.venueId `elem` activeVenueIds) memberships

    let selectedMembership =
            selectCurrentVenueMembership sessionVenueId activeMemberships
    let selectedMembershipVenue =
            selectedMembership >>= \membership ->
                find (\candidate -> coerce (get #id candidate) == membership.venueId) venues

    if user.platformRole == Just (platformRoleToEnum SuperAdminRole)
        then do
            activeVenues <- query @Venue
                |> filterWhere (#status, unsafeEnumFromText @VenueStatusEnum "active")
                |> orderByAsc #createdAt
                |> fetch

            let selectedVenue =
                    (sessionVenueId >>= \venueId -> find (\candidate -> get #id candidate == venueId) activeVenues)
                        <|> selectedMembershipVenue
                        <|> listToMaybe activeVenues

            pure do
                venue <- selectedVenue
                let membership = find (\candidate -> candidate.venueId == unpackId (get #id venue)) activeMemberships
                let role = membership >>= parseVenueRole . (.venueRole)
                pure (membership, venue, role)
        else
            pure do
                membership <- selectedMembership
                venue <- selectedMembershipVenue
                role <- parseVenueRole membership.venueRole
                pure (Just membership, venue, Just role)
