module Application.Billing.Notifications
    ( BillingNotification (..)
    , BillingNotificationKind (..)
    , billingNotificationJobKind
    , enqueueBillingNotifications
    , enqueueBillingSupportNotificationAfterFinalAttempt
    , performBillingNotificationJob
    )
where

import Application.Async.Queue
import Application.Billing.NotificationKind
import Application.Billing.Persistence (lockVenueForBilling)
import Application.Helper.EmailVerification (isEmailDeliveryDisabled)
import Application.Helper.Mail
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import Data.Time.Clock.POSIX (utcTimeToPOSIXSeconds)
import IHP.EnvVar
import IHP.Mail
import IHP.ModelSupport (withTransaction)
import Web.Mail.Billing.Notification
import Web.Routes ()
import Web.Types

import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig (ConfigProvider, FrameworkConfig)

billingNotificationJobKind :: Text
billingNotificationJobKind = "billing_notification"

data BillingNotification = BillingNotification
    { notificationKind               :: !BillingNotificationKind
    , notificationSubscriptionId     :: !(Maybe Text)
    , notificationBillingPeriodStart :: !(Maybe UTCTime)
    , notificationBillingPeriodEnd   :: !(Maybe UTCTime)
    }
    deriving (Eq, Show)

data BillingNotificationPayload = BillingNotificationPayload
    { payloadUserId           :: !UUID
    , payloadVenueId          :: !UUID
    , payloadBillingEventId   :: !(Maybe UUID)
    , payloadSourceAppJobId   :: !(Maybe UUID)
    , payloadNotificationKind :: !BillingNotificationKind
    }
    deriving (Eq, Show)

data BillingNotificationSource
    = BillingEventSource !BillingEvent
    | BillingOperationalJobSource !AppJob

instance Aeson.FromJSON BillingNotificationPayload where
    parseJSON =
        Aeson.withObject "BillingNotificationPayload" \object -> do
            notificationKindText <- object Aeson..: "notificationKind"
            parsedNotificationKind <-
                case parseBillingNotificationKind notificationKindText of
                    Just kind -> pure kind
                    Nothing   -> fail "Unknown billing notification kind"
            BillingNotificationPayload
                <$> object Aeson..: "userId"
                <*> object Aeson..: "venueId"
                <*> object Aeson..:? "billingEventId"
                <*> object Aeson..:? "sourceAppJobId"
                <*> pure parsedNotificationKind

billingNotificationPayload :: User -> Venue -> BillingNotificationSource -> BillingNotification -> Aeson.Value
billingNotificationPayload user venue source notification =
    Aeson.object
        [ "userId" Aeson..= unpackId user.id
        , "venueId" Aeson..= unpackId venue.id
        , "billingEventId" Aeson..= sourceBillingEventId source
        , "sourceAppJobId" Aeson..= sourceAppJobId source
        , "notificationKind" Aeson..= billingNotificationKindText notification.notificationKind
        , "stripeSubscriptionId" Aeson..= notification.notificationSubscriptionId
        , "billingPeriodStart" Aeson..= notification.notificationBillingPeriodStart
        , "billingPeriodEnd" Aeson..= notification.notificationBillingPeriodEnd
        ]

enqueueBillingNotifications ::
    (?modelContext :: ModelContext) =>
    Venue ->
    BillingEvent ->
    BillingNotification ->
    IO [AppJob]
-- The webhook caller owns the transaction and venue lock so event state and
-- notification jobs commit atomically without hiding that serialization.
enqueueBillingNotifications venue billingEvent notification = do
    recipients <- billingNotificationRecipients venue
    enqueueNotificationJobs venue recipients (BillingEventSource billingEvent) notification

-- | Call this from a failing billing operation before rethrowing its final
-- attempt. IHP increments @attempts_count@ in @fetchNextJob@ before @perform@,
-- so a value equal to the shared limit identifies the current final attempt.
-- Retryable failures stay silent, while the source job and recipient form a
-- permanent one-shot key.
enqueueBillingSupportNotificationAfterFinalAttempt ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    IO [AppJob]
enqueueBillingSupportNotificationAfterFinalAttempt sourceJob
    | sourceJob.attemptsCount < appJobMaxAttempts = pure []
    | sourceJob.jobKind == billingNotificationJobKind = pure []
    | otherwise =
        case sourceJob.venueId of
            Nothing -> pure []
            Just venueUuid ->
                withTransaction do
                    venue <- fetch (Id venueUuid :: Id Venue)
                    lockVenueForBilling venueUuid
                    recipients <- billingSupportRecipients
                    enqueueNotificationJobs
                        venue
                        recipients
                        (BillingOperationalJobSource sourceJob)
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
        enqueueNotificationJobOnce
            AppJobRequest
                { jobKind = billingNotificationJobKind
                , payload = billingNotificationPayload recipient venue source notification
                , payloadSchemaVersion = 2
                , requestedByUserId = Nothing
                , venueId = Just (unpackId venue.id)
                , relatedTable = Just (sourceRelatedTable source)
                , relatedId = Just (sourceRelatedId source)
                , dedupeKey = Just (billingNotificationDedupeKey venue source notification recipient)
                , runAt = Nothing
                }

-- The venue row lock serializes this historical lookup with insertion. Unlike
-- the generic queue's active-job dedupe, transition notifications remain
-- deduplicated after successful delivery and after terminal job failure.
enqueueNotificationJobOnce :: (?modelContext :: ModelContext) => AppJobRequest -> IO AppJob
enqueueNotificationJobOnce request =
    case request.dedupeKey of
        Nothing -> extractEnqueuedJob <$> enqueueAppJob request
        Just key -> do
            exactMatch <-
                query @AppJob
                    |> filterWhere (#dedupeKey, Just key)
                    |> orderByAsc #createdAt
                    |> fetchOneOrNothing
            case exactMatch of
                Just existingJob -> pure existingJob
                Nothing          -> extractEnqueuedJob <$> enqueueAppJob request

extractEnqueuedJob :: EnqueueAppJobResult -> AppJob
extractEnqueuedJob = \case
    EnqueuedAppJob appJob       -> appJob
    ExistingActiveAppJob appJob -> appJob

billingNotificationDedupeKey :: Venue -> BillingNotificationSource -> BillingNotification -> User -> Text
billingNotificationDedupeKey venue source notification recipient =
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
                    <> [inputValue recipient.id]
        BillingOperationalJobSource sourceJob ->
            Text.intercalate
                ":"
                [ "billing-notification"
                , "operational"
                , inputValue sourceJob.id
                , inputValue recipient.id
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

sourceBillingEventId :: BillingNotificationSource -> Maybe UUID
sourceBillingEventId = \case
    BillingEventSource billingEvent -> Just (unpackId billingEvent.id)
    BillingOperationalJobSource _   -> Nothing

sourceAppJobId :: BillingNotificationSource -> Maybe UUID
sourceAppJobId = \case
    BillingEventSource _                     -> Nothing
    BillingOperationalJobSource sourceAppJob -> Just (unpackId sourceAppJob.id)

sourceRelatedTable :: BillingNotificationSource -> Text
sourceRelatedTable = \case
    BillingEventSource _             -> "billing_events"
    BillingOperationalJobSource _    -> "app_jobs"

sourceRelatedId :: BillingNotificationSource -> UUID
sourceRelatedId = \case
    BillingEventSource billingEvent          -> unpackId billingEvent.id
    BillingOperationalJobSource sourceAppJob -> unpackId sourceAppJob.id

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
        else query @User
            |> filterWhereIn (#id, ownerIds)
            |> filterWhere (#deactivatedAt, Nothing)
            |> fetch

billingSupportRecipients :: (?modelContext :: ModelContext) => IO [User]
billingSupportRecipients =
    query @User
        |> filterWhere (#platformRole, Just (SuperAdmin))
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

performBillingNotificationJob ::
    (?context :: FrameworkConfig, ?modelContext :: ModelContext) =>
    AppJob ->
    IO ()
performBillingNotificationJob appJob =
    case Aeson.fromJSON appJob.payload of
        Aeson.Error err -> fail ("Invalid billing notification payload for job " <> cs (tshow appJob.id) <> ": " <> err)
        Aeson.Success BillingNotificationPayload { .. } -> do
            user <- fetch (Id payloadUserId :: Id User)
            venue <- fetch (Id payloadVenueId :: Id Venue)
            recipientIsEligible <- billingNotificationRecipientIsEligible payloadNotificationKind user venue
            when recipientIsEligible do
                sendBillingNotificationEmail payloadNotificationKind user venue payloadSourceAppJobId
            let deliveryStatus =
                    if recipientIsEligible
                        then "sent" :: Text
                        else "skipped_ineligible_recipient"
            void $
                appJob
                    |> set #result
                        ( Aeson.object
                            [ "userId" Aeson..= payloadUserId
                            , "venueId" Aeson..= payloadVenueId
                            , "billingEventId" Aeson..= payloadBillingEventId
                            , "sourceAppJobId" Aeson..= payloadSourceAppJobId
                            , "notificationKind" Aeson..= billingNotificationKindText payloadNotificationKind
                            , "deliveryStatus" Aeson..= deliveryStatus
                            ]
                        )
                    |> set #status JobStatusSucceeded
                    |> updateRecord

billingNotificationRecipientIsEligible :: (?modelContext :: ModelContext) => BillingNotificationKind -> User -> Venue -> IO Bool
billingNotificationRecipientIsEligible notificationKind user venue
    | isJust user.deactivatedAt = pure False
    | notificationKind == BillingOperationalRetriesExhausted = pure (isBillingSupportRecipient user)
    | isBillingSupportRecipient user = pure True
    | otherwise =
        query @VenueMembership
            |> filterWhere (#venueId, unpackId venue.id)
            |> filterWhere (#userId, unpackId user.id)
            |> filterWhere (#venueRole, VenueOwner)
            |> filterWhere (#isActive, True)
            |> filterWhere (#archivedAt, Nothing)
            |> fetchExists

isBillingSupportRecipient :: User -> Bool
isBillingSupportRecipient user =
    user.platformRole == Just (SuperAdmin)

sendBillingNotificationEmail ::
    (?context :: context, ConfigProvider context, ?modelContext :: ModelContext) =>
    BillingNotificationKind ->
    User ->
    Venue ->
    Maybe UUID ->
    IO ()
sendBillingNotificationEmail notificationKind user venue maybeSourceAppJobId = do
    AppMailSettings { .. } <- loadAppMailSettings
    appBaseUrl :: Text <- envOrDefault "APP_BASE_URL" "http://localhost:8000"
    emailDeliveryDisabled <- isEmailDeliveryDisabled
    unless emailDeliveryDisabled do
        sendMail BillingNotificationMail
            { recipient = user
            , venue = venue
            , notificationKind = notificationKind
            , sourceReference = tshow <$> maybeSourceAppJobId
            , billingUrl = appBaseUrl <> pathTo BillingAction
            , fromAddress = mailFromAddress
            , replyToAddress = mailReplyToAddress
            , supportEmail = mailSupportEmail
            }
