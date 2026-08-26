module Application.Billing.Notifications
    ( BillingNotification (..)
    , BillingNotificationKind (..)
    , enqueueBillingNotifications
    , enqueueBillingSupportNotificationAfterFinalAttempt
    )
where

import Application.Async.Queue (appJobMaxAttempts)
import Application.Billing.NotificationEmail (billingNotificationMailKind)
import Application.Billing.NotificationKind
import Application.Billing.Persistence (lockVenueForBilling)
import Application.EmailDelivery
import qualified Data.Text as Text
import Data.Time.Clock.POSIX (utcTimeToPOSIXSeconds)
import Generated.Types
import IHP.ControllerPrelude
import IHP.Job.Types (JobStatus (JobStatusSucceeded))
import IHP.ModelSupport (withTransaction)


data BillingNotificationSource
    = BillingEventSource !BillingEvent
    | BillingOperationalJobSource !AppJob

enqueueBillingNotifications ::
    (?modelContext :: ModelContext) =>
    Venue ->
    BillingEvent ->
    BillingNotification ->
    IO [AppJob]
-- The webhook caller owns the transaction and venue lock so event state,
-- immutable notification snapshot, and delivery envelopes commit atomically.
enqueueBillingNotifications venue billingEvent notification = do
    recipients <- billingNotificationRecipients venue
    enqueueNotificationJobs venue recipients (BillingEventSource billingEvent) notification

-- IHP increments attempts_count before perform. Re-fetching suppresses a false
-- alert when a post-operation publication step throws after the source job has
-- already committed success.
enqueueBillingSupportNotificationAfterFinalAttempt ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    IO [AppJob]
enqueueBillingSupportNotificationAfterFinalAttempt sourceJob
    | sourceJob.attemptsCount < appJobMaxAttempts = pure []
    | otherwise = do
        persistedSourceJob <- fetch sourceJob.id
        if persistedSourceJob.status == JobStatusSucceeded
            then pure []
            else case persistedSourceJob.venueId of
                Nothing -> pure []
                Just venueUuid ->
                    withTransaction do
                        venue <- fetch (Id venueUuid :: Id Venue)
                        lockVenueForBilling venueUuid
                        recipients <- billingSupportRecipients
                        enqueueNotificationJobs
                            venue
                            recipients
                            (BillingOperationalJobSource persistedSourceJob)
                            BillingNotification
                                { notificationKind = BillingOperationalRetriesExhausted
                                , notificationSubscriptionId = Nothing
                                , notificationBillingPeriodStart = Nothing
                                , notificationBillingPeriodEnd = Nothing
                                }

enqueueNotificationJobs ::
    (?modelContext :: ModelContext) =>
    Venue ->
    [User] ->
    BillingNotificationSource ->
    BillingNotification ->
    IO [AppJob]
enqueueNotificationJobs venue recipients source notification =
    forM recipients \recipient ->
        enqueueEmailDelivery
            EmailDeliveryRequest
                { mailKind = billingNotificationMailKind notification.notificationKind
                , recipientAccountId = unpackId recipient.id
                , recipientAddress = recipient.email
                , domainReferenceTable = sourceRelatedTable source
                , domainReferenceId = sourceRelatedId source
                , semanticEventKey = billingNotificationDedupeKey venue source notification
                , requestedByUserId = sourceRequestedByUserId source
                , venueId = Just (unpackId venue.id)
                }

billingNotificationDedupeKey :: Venue -> BillingNotificationSource -> BillingNotification -> Text
billingNotificationDedupeKey venue source notification =
    case source of
        BillingEventSource _ ->
            Text.intercalate ":" $
                [ "billing-notification"
                , billingNotificationModeKey source
                , inputValue venue.id
                , fromMaybe "unknown-subscription" notification.notificationSubscriptionId
                , billingNotificationKindText notification.notificationKind
                ]
                    <> billingNotificationPeriodKeys source notification
        BillingOperationalJobSource sourceJob ->
            Text.intercalate
                ":"
                [ "billing-notification"
                , "operational"
                , inputValue sourceJob.id
                ]

billingNotificationPeriodKeys :: BillingNotificationSource -> BillingNotification -> [Text]
billingNotificationPeriodKeys source notification =
    case notification.notificationKind of
        BillingPaymentTrouble -> [timestampKey renewalBoundary, timestampKey renewalBoundary]
        _ -> [timestampKey notification.notificationBillingPeriodStart, timestampKey notification.notificationBillingPeriodEnd]
  where
    renewalBoundary =
        case source of
            BillingEventSource event
                | event.providerObjectType == Just "invoice" -> notification.notificationBillingPeriodStart <|> notification.notificationBillingPeriodEnd
                | event.providerObjectType == Just "subscription" -> notification.notificationBillingPeriodEnd <|> notification.notificationBillingPeriodStart
            _ -> notification.notificationBillingPeriodEnd <|> notification.notificationBillingPeriodStart
    timestampKey = maybe "unknown" (tshow . (floor :: NominalDiffTime -> Integer) . utcTimeToPOSIXSeconds)

billingNotificationModeKey :: BillingNotificationSource -> Text
billingNotificationModeKey = \case
    BillingEventSource billingEvent
        | billingEvent.livemode -> "live"
        | otherwise -> "test"
    BillingOperationalJobSource _ -> "operational"

sourceRelatedTable :: BillingNotificationSource -> Text
sourceRelatedTable = \case
    BillingEventSource _          -> "billing_events"
    BillingOperationalJobSource _ -> "app_jobs"

sourceRelatedId :: BillingNotificationSource -> UUID
sourceRelatedId = \case
    BillingEventSource billingEvent          -> unpackId billingEvent.id
    BillingOperationalJobSource sourceAppJob -> unpackId sourceAppJob.id

sourceRequestedByUserId :: BillingNotificationSource -> Maybe UUID
sourceRequestedByUserId = \case
    BillingEventSource _                     -> Nothing
    BillingOperationalJobSource sourceAppJob -> sourceAppJob.requestedByUserId

billingNotificationRecipients :: (?modelContext :: ModelContext) => Venue -> IO [User]
billingNotificationRecipients venue = do
    owners <- billingOwnerRecipients venue
    superAdmins <- billingSupportRecipients
    pure (dedupeUsersById (owners <> superAdmins))

billingOwnerRecipients :: (?modelContext :: ModelContext) => Venue -> IO [User]
billingOwnerRecipients venue = do
    ownerMemberships <-
        query @VenueMembership
            |> filterWhere (#venueId, unpackId venue.id)
            |> filterWhere (#venueRole, VenueOwner)
            |> filterWhere (#isActive, True)
            |> filterWhere (#archivedAt, Nothing)
            |> fetch
    let ownerIds = map (Id . (.userId)) ownerMemberships
    if null ownerIds
        then pure []
        else
            query @User
                |> filterWhereIn (#id, ownerIds)
                |> filterWhere (#deactivatedAt, Nothing)
                |> fetch

billingSupportRecipients :: (?modelContext :: ModelContext) => IO [User]
billingSupportRecipients =
    query @User
        |> filterWhere (#platformRole, Just SuperAdmin)
        |> filterWhere (#deactivatedAt, Nothing)
        |> fetch

dedupeUsersById :: [User] -> [User]
dedupeUsersById =
    foldr
        ( \user acc ->
            if any (\existing -> existing.id == user.id) acc
                then acc
                else user : acc
        )
        []
