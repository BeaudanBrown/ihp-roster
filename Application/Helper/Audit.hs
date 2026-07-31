module Application.Helper.Audit where

import qualified Data.Aeson as Aeson
import Generated.Types
import IHP.ControllerPrelude

import Application.Bepis.Fact (BepisAuditFact (..), BepisAuditFactKind (..),
                               BepisFact (..), emitBepisFact)
import Application.Helper.ControllerContext (authenticatedCurrentUser,
                                             currentVenueId,
                                             resolveVenueContextForUser)
import Application.Helper.Htmx (requestAuditSourceChannel)

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
    recordAuditEventWithFactKind BepisAuditEventRecorded venueId actorUserId eventType targetTable targetId payload sourceChannel

recordAuditEventWithFactKind ::
    (?modelContext :: ModelContext) =>
    BepisAuditFactKind ->
    UUID ->
    UUID ->
    Text ->
    Text ->
    UUID ->
    Aeson.Value ->
    Text ->
    IO AuditEvent
recordAuditEventWithFactKind factKind venueId actorUserId eventType targetTable targetId payload sourceChannel = do
    event <- newRecord @AuditEvent
        |> set #venueId venueId
        |> set #actorUserId actorUserId
        |> set #eventType eventType
        |> set #targetTable targetTable
        |> set #targetId targetId
        |> set #payload payload
        |> set #sourceChannel sourceChannel
        |> createRecord
    emitAuditFact factKind eventType targetTable sourceChannel
    pure event

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
        (unpackId (get #id authenticatedCurrentUser))
        eventType
        targetTable
        targetId
        payload
        requestAuditSourceChannel

recordUserAuthenticationAuditEvent ::
    (?modelContext :: ModelContext) =>
    User ->
    Text ->
    Aeson.Value ->
    IO (Maybe AuditEvent)
recordUserAuthenticationAuditEvent user eventType payload =
    resolveVenueContextForUser Nothing user >>= \case
        Nothing -> pure Nothing
        Just (_, venue, _) -> do
            event <- recordAuditEventWithFactKind
                BepisAuthenticationAuditRecorded
                (unpackId (get #id venue))
                (unpackId (get #id user))
                eventType
                "users"
                (unpackId (get #id user))
                payload
                "web"
            pure (Just event)

timesheetEntrySnapshot :: TimesheetEntry -> Aeson.Value
timesheetEntrySnapshot entry =
    Aeson.object
        [ "id" Aeson..= unpackId (get #id entry)
        , "venueId" Aeson..= entry.venueId
        , "staffId" Aeson..= entry.staffId
        , "shiftTypeId" Aeson..= entry.shiftTypeId
        , "startsAt" Aeson..= entry.startsAt
        , "endsAt" Aeson..= entry.endsAt
        , "breakStartsAt" Aeson..= entry.breakStartsAt
        , "breakEndsAt" Aeson..= entry.breakEndsAt
        , "timezone" Aeson..= entry.timezone
        , "sourceRosterSlotId" Aeson..= entry.sourceRosterSlotId
        , "staffComment" Aeson..= entry.staffComment
        , "managerNote" Aeson..= entry.managerNote
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
recordTimesheetEntryVersion venueId actorUserId versionAction entry payload = do
    version <- newRecord @TimesheetEntryVersion
        |> set #venueId venueId
        |> set #timesheetEntryId (unpackId (get #id entry))
        |> set #actorUserId actorUserId
        |> set #versionAction versionAction
        |> set #snapshot (timesheetEntrySnapshot entry)
        |> set #payload payload
        |> createRecord
    emitAuditFact BepisVersionEventRecorded (inputValue versionAction) "timesheet_entries" "web"
    pure version

recordCurrentUserTimesheetEntryVersion ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    EntryVersionActionEnum ->
    TimesheetEntry ->
    Aeson.Value ->
    IO TimesheetEntryVersion
recordCurrentUserTimesheetEntryVersion =
    recordTimesheetEntryVersion
        (unpackId currentVenueId)
        (unpackId (get #id authenticatedCurrentUser))

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
recordLeaveRequestEvent venueId actorUserId leaveRequestId eventType previousStatus newStatus payload = do
    event <- newRecord @LeaveRequestEvent
        |> set #venueId venueId
        |> set #leaveRequestId leaveRequestId
        |> set #actorUserId actorUserId
        |> set #eventType eventType
        |> set #previousStatus previousStatus
        |> set #newStatus newStatus
        |> set #payload payload
        |> createRecord
    emitAuditFact BepisAuditEventRecorded (inputValue eventType) "leave_requests" "web"
    pure event

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
        (unpackId (get #id authenticatedCurrentUser))
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
recordVenueMembershipRoleEvent venueId actorUserId membership eventType previousRole newRole payload = do
    event <- newRecord @VenueMembershipRoleEvent
        |> set #venueId venueId
        |> set #venueMembershipId (unpackId (get #id membership))
        |> set #actorUserId actorUserId
        |> set #eventType eventType
        |> set #previousRole previousRole
        |> set #newRole newRole
        |> set #payload payload
        |> createRecord
    emitAuditFact BepisAuditEventRecorded (inputValue eventType) "venue_memberships" "web"
    pure event

updateVenueMembershipRoleWithAudit ::
    (?modelContext :: ModelContext) =>
    UUID ->
    Text ->
    VenueMembership ->
    VenueRoleEnum ->
    Aeson.Value ->
    IO VenueMembership
updateVenueMembershipRoleWithAudit actorUserId sourceChannel membership newRole payload =
    withTransaction (updateVenueMembershipRoleWithAuditInCurrentTransaction actorUserId sourceChannel membership newRole payload)

updateVenueMembershipRoleWithAuditInCurrentTransaction ::
    (?modelContext :: ModelContext) =>
    UUID ->
    Text ->
    VenueMembership ->
    VenueRoleEnum ->
    Aeson.Value ->
    IO VenueMembership
updateVenueMembershipRoleWithAuditInCurrentTransaction actorUserId sourceChannel membership newRole payload
    | membership.venueRole == newRole = pure membership
    | otherwise = do
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

emitAuditFact :: BepisAuditFactKind -> Text -> Text -> Text -> IO ()
emitAuditFact kind eventType target sourceChannel =
    emitBepisFact $ BepisAuditFactValue BepisAuditFact
        { auditFactKind = kind
        , auditFactEventType = eventType
        , auditFactTarget = target
        , auditFactSourceChannel = sourceChannel
        }
