module Application.Billing.Notifications
    ( billingNotificationJobKind
    , enqueueBillingNotifications
    , performBillingNotificationJob
    )
where

import Application.Async.Queue
import Application.Helper.Controller (PlatformRole (SuperAdminRole),
                                      VenueRole (VenueOwnerRole),
                                      platformRoleToEnum, venueRoleToEnum)
import Application.Helper.EmailVerification (isEmailDeliveryDisabled)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import IHP.EnvVar
import IHP.Mail
import Web.Mail.Billing.Notification
import Web.Routes ()
import Web.Types

import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig (ConfigProvider, FrameworkConfig)

billingNotificationJobKind :: Text
billingNotificationJobKind = "billing_notification"

data BillingNotificationPayload = BillingNotificationPayload
    { payloadUserId           :: !UUID
    , payloadVenueId          :: !UUID
    , payloadBillingEventId   :: !UUID
    , payloadNotificationKind :: !Text
    }
    deriving (Eq, Show)

instance Aeson.FromJSON BillingNotificationPayload where
    parseJSON =
        Aeson.withObject "BillingNotificationPayload" \object ->
            BillingNotificationPayload
                <$> object Aeson..: "userId"
                <*> object Aeson..: "venueId"
                <*> object Aeson..: "billingEventId"
                <*> object Aeson..: "notificationKind"

billingNotificationPayload :: User -> Venue -> BillingEvent -> Text -> Aeson.Value
billingNotificationPayload user venue billingEvent notificationKind =
    Aeson.object
        [ "userId" Aeson..= unpackId user.id
        , "venueId" Aeson..= unpackId venue.id
        , "billingEventId" Aeson..= unpackId billingEvent.id
        , "notificationKind" Aeson..= notificationKind
        ]

enqueueBillingNotifications ::
    (?modelContext :: ModelContext) =>
    Venue ->
    BillingEvent ->
    Text ->
    IO [EnqueueAppJobResult]
enqueueBillingNotifications venue billingEvent notificationKind = do
    recipients <- billingNotificationRecipients venue
    forM recipients \recipient ->
        enqueueAppJob
            AppJobRequest
                { jobKind = billingNotificationJobKind
                , payload = billingNotificationPayload recipient venue billingEvent notificationKind
                , payloadSchemaVersion = 1
                , requestedByUserId = Nothing
                , venueId = Just (unpackId venue.id)
                , relatedTable = Just "billing_events"
                , relatedId = Just (unpackId billingEvent.id)
                , dedupeKey = Just ("billing-notification:" <> tshow billingEvent.id <> ":" <> tshow recipient.id)
                , runAt = Nothing
                }

billingNotificationRecipients :: (?modelContext :: ModelContext) => Venue -> IO [User]
billingNotificationRecipients venue = do
    ownerMemberships <-
        query @VenueMembership
            |> filterWhere (#venueId, unpackId venue.id)
            |> filterWhere (#venueRole, venueRoleToEnum VenueOwnerRole)
            |> filterWhere (#isActive, True)
            |> fetch
    let ownerIds = map (Id . (.userId)) ownerMemberships
    owners <-
        if null ownerIds
            then pure []
            else query @User
                |> filterWhereIn (#id, ownerIds)
                |> fetch
    superAdmins <-
        query @User
            |> filterWhere (#platformRole, Just (platformRoleToEnum SuperAdminRole))
            |> fetch
    pure (dedupeUsersById (owners <> superAdmins))

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
            billingEvent <- fetch (Id payloadBillingEventId :: Id BillingEvent)
            sendBillingNotificationEmail payloadNotificationKind user venue billingEvent
            void $
                appJob
                    |> set #result
                        ( Aeson.object
                            [ "userId" Aeson..= payloadUserId
                            , "venueId" Aeson..= payloadVenueId
                            , "billingEventId" Aeson..= payloadBillingEventId
                            , "notificationKind" Aeson..= payloadNotificationKind
                            ]
                        )
                    |> set #status JobStatusSucceeded
                    |> updateRecord

sendBillingNotificationEmail ::
    (?context :: context, ConfigProvider context, ?modelContext :: ModelContext) =>
    Text ->
    User ->
    Venue ->
    BillingEvent ->
    IO ()
sendBillingNotificationEmail notificationKind user venue billingEvent = do
    fromAddress :: Text <- envOrDefault "MAIL_FROM" "noreply@dev.local"
    appBaseUrl :: Text <- envOrDefault "APP_BASE_URL" "http://localhost:8000"
    emailDeliveryDisabled <- isEmailDeliveryDisabled
    unless emailDeliveryDisabled do
        sendMail BillingNotificationMail
            { recipient = user
            , venue = venue
            , billingEvent = billingEvent
            , notificationKind = notificationKind
            , billingUrl = appBaseUrl <> pathTo BillingAction
            , fromAddress = fromAddress
            }
