module Application.Helper.Audit
    ( module Application.Helper.Audit.Vocabulary
    , recordAuditEvent
    , recordAuditEventWithFactKind
    , recordCurrentUserAuditEvent
    , recordCurrentUserLeaveRequestEvent
    , recordCurrentUserTimesheetEntryVersion
    , recordLeaveRequestEvent
    , recordTimesheetEntryVersion
    , recordUserAuthenticationAuditEvent
    , recordVenueMembershipRoleEvent
    , timesheetEntrySnapshot
    , updateVenueMembershipRoleWithAudit
    , updateVenueMembershipRoleWithAuditInCurrentTransaction
    ) where

import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as AesonKeyMap
import Generated.Types
import IHP.ControllerPrelude

import Application.Bepis.Fact (BepisAuditFact (..), BepisAuditFactKind (..),
                               BepisFact (..), emitBepisFact)
import Application.Helper.Audit.Vocabulary
import Application.Helper.ControllerContext (authenticatedCurrentUser,
                                             currentUserIsSuperAdmin,
                                             currentVenueId,
                                             currentVenueMembershipOrNothing,
                                             resolveVenueContextForUser)
import Application.Helper.Htmx (requestAuditSourceChannel)

recordAuditEvent ::
    (?modelContext :: ModelContext) =>
    UUID ->
    UUID ->
    AuditEventType ->
    Text ->
    UUID ->
    Aeson.Value ->
    AuditSourceChannel ->
    IO AuditEvent
recordAuditEvent venueId actorUserId eventType targetTable targetId payload sourceChannel =
    recordAuditEventWithFactKind BepisAuditEventRecorded venueId actorUserId eventType targetTable targetId payload sourceChannel

recordAuditEventWithFactKind ::
    (?modelContext :: ModelContext) =>
    BepisAuditFactKind ->
    UUID ->
    UUID ->
    AuditEventType ->
    Text ->
    UUID ->
    Aeson.Value ->
    AuditSourceChannel ->
    IO AuditEvent
recordAuditEventWithFactKind factKind venueId actorUserId eventType targetTable targetId payload sourceChannel = do
    event <- newRecord @AuditEvent
        |> set #venueId venueId
        |> set #actorUserId actorUserId
        |> set #eventType (auditEventTypeText eventType)
        |> set #targetTable targetTable
        |> set #targetId targetId
        |> set #payload payload
        |> set #sourceChannel (auditSourceChannelText sourceChannel)
        |> createRecord
    emitAuditFact factKind (auditEventTypeText eventType) targetTable sourceChannel
    pure event

recordCurrentUserAuditEvent ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    AuditEventType ->
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
        (currentRequestAuditPayload payload)
        requestAuditSourceChannel

currentRequestAuditPayload :: (?context :: ControllerContext) => Aeson.Value -> Aeson.Value
currentRequestAuditPayload payload
    | currentUserIsSuperAdmin && isNothing currentVenueMembershipOrNothing =
        attachAuditRequestContext FounderSupportAuditAccess payload
    | otherwise = payload

data AuditAccessMode
    = FounderSupportAuditAccess

attachAuditRequestContext :: AuditAccessMode -> Aeson.Value -> Aeson.Value
attachAuditRequestContext accessMode payload =
    case payload of
        Aeson.Object fields -> Aeson.Object (AesonKeyMap.insert "requestContext" requestContext fields)
        other               -> Aeson.object ["payload" Aeson..= other, "requestContext" Aeson..= requestContext]
  where
    requestContext = Aeson.object ["accessMode" Aeson..= auditAccessModeText accessMode]

auditAccessModeText :: AuditAccessMode -> Text
auditAccessModeText FounderSupportAuditAccess = "support"

recordUserAuthenticationAuditEvent ::
    (?modelContext :: ModelContext) =>
    User ->
    AuditEventType ->
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
                WebAuditSource
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
    emitAuditFact BepisVersionEventRecorded (inputValue versionAction) "timesheet_entries" WebAuditSource
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
    emitAuditFact BepisAuditEventRecorded (inputValue eventType) "leave_requests" WebAuditSource
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
    -- Dedicated role-history facts retain their historical web classification.
    emitAuditFact BepisAuditEventRecorded (inputValue eventType) "venue_memberships" WebAuditSource
    pure event

updateVenueMembershipRoleWithAudit ::
    (?modelContext :: ModelContext) =>
    UUID ->
    AuditSourceChannel ->
    VenueMembership ->
    VenueRoleEnum ->
    Aeson.Value ->
    IO VenueMembership
updateVenueMembershipRoleWithAudit actorUserId sourceChannel membership newRole payload =
    withTransaction (updateVenueMembershipRoleWithAuditInCurrentTransaction actorUserId sourceChannel membership newRole payload)

updateVenueMembershipRoleWithAuditInCurrentTransaction ::
    (?modelContext :: ModelContext) =>
    UUID ->
    AuditSourceChannel ->
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
            VenueRoleChangedAudit
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

emitAuditFact :: BepisAuditFactKind -> Text -> Text -> AuditSourceChannel -> IO ()
emitAuditFact kind eventType target sourceChannel =
    emitBepisFact $ BepisAuditFactValue BepisAuditFact
        { auditFactKind = kind
        , auditFactEventType = eventType
        , auditFactTarget = target
        , auditFactSourceChannel = auditSourceChannelText sourceChannel
        }
