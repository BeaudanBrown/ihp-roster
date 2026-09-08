module Application.Billing.NotificationEmail
    ( BillingMailProjection (..)
    , billingNotificationMailKind
    , billingNotificationReferenceTable
    , isBillingNotificationMailKind
    , loadBillingNotificationMail
    ) where

import Application.Billing.NotificationKind
import Application.Error.Runtime (ExternalRuntimeCategory (..), externalRuntimeInvariantFailure)
import Application.Helper.Mail
import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude
import Web.Mail.Billing.Notification
import Web.Routes ()
import Web.Types


data BillingMailProjection
    = BillingMailReady !BillingNotificationMail
    | BillingMailSkipped !Text

billingNotificationMailKind :: BillingNotificationKind -> Text
billingNotificationMailKind kind =
    "billing_" <> billingNotificationKindText kind <> "_v1"

billingNotificationReferenceTable :: Text -> Maybe Text
billingNotificationReferenceTable mailKind =
    case billingNotificationKindFromMailKind mailKind of
        Just BillingOperationalRetriesExhausted -> Just "app_jobs"
        Just _                                  -> Just "billing_events"
        Nothing                                 -> Nothing

isBillingNotificationMailKind :: Text -> Bool
isBillingNotificationMailKind candidate =
    isJust (billingNotificationKindFromMailKind candidate)

loadBillingNotificationMail ::
    (?context :: context, ConfigProvider context, ?modelContext :: ModelContext) =>
    Text ->
    UUID ->
    Text ->
    UUID ->
    AppMailSettings ->
    Text ->
    IO BillingMailProjection
loadBillingNotificationMail mailKind recipientAccountId recipientAddress domainReferenceId settings appBaseUrl =
    case billingNotificationKindFromMailKind mailKind of
        Nothing -> pure (BillingMailSkipped "unknown_mail_kind")
        Just BillingOperationalRetriesExhausted ->
            loadOperationalMail recipientAccountId recipientAddress domainReferenceId settings appBaseUrl
        Just notificationKind ->
            loadLifecycleMail notificationKind recipientAccountId recipientAddress domainReferenceId settings appBaseUrl

loadLifecycleMail ::
    (?context :: context, ConfigProvider context, ?modelContext :: ModelContext) =>
    BillingNotificationKind ->
    UUID ->
    Text ->
    UUID ->
    AppMailSettings ->
    Text ->
    IO BillingMailProjection
loadLifecycleMail notificationKind recipientAccountId recipientAddress billingEventId settings appBaseUrl = do
    maybeEvent <- query @BillingEvent |> filterWhere (#id, Id billingEventId) |> fetchOneOrNothing
    maybeRecipient <- query @User |> filterWhere (#id, Id recipientAccountId) |> fetchOneOrNothing
    case (maybeEvent, maybeRecipient) of
        (Nothing, _) -> pure (BillingMailSkipped "domain_reference_missing")
        (_, Nothing) -> pure (BillingMailSkipped "recipient_missing")
        (Just event, Just recipient) ->
            case decodeNotificationSnapshot event.notificationSnapshot of
                Nothing -> pure (BillingMailSkipped "domain_reference_invalid")
                Just notifications
                    | not (any ((== notificationKind) . (.notificationKind)) notifications) ->
                        pure (BillingMailSkipped "notification_not_in_snapshot")
                    | otherwise -> do
                        venue <- fetchEventVenue event
                        eligible <- billingRecipientIsEligible notificationKind recipient venue
                        if eligible
                            then pure (BillingMailReady (buildMail notificationKind recipientAddress venue Nothing settings appBaseUrl))
                            else pure (BillingMailSkipped "recipient_ineligible")

loadOperationalMail ::
    (?context :: context, ConfigProvider context, ?modelContext :: ModelContext) =>
    UUID ->
    Text ->
    UUID ->
    AppMailSettings ->
    Text ->
    IO BillingMailProjection
loadOperationalMail recipientAccountId recipientAddress sourceJobId settings appBaseUrl = do
    maybeSourceJob <- query @AppJob |> filterWhere (#id, Id sourceJobId) |> fetchOneOrNothing
    maybeRecipient <- query @User |> filterWhere (#id, Id recipientAccountId) |> fetchOneOrNothing
    case (maybeSourceJob, maybeRecipient) of
        (Nothing, _) -> pure (BillingMailSkipped "domain_reference_missing")
        (_, Nothing) -> pure (BillingMailSkipped "recipient_missing")
        (Just sourceJob, Just recipient) -> case sourceJob.venueId of
            Nothing -> pure (BillingMailSkipped "domain_reference_invalid")
            Just venueId -> do
                venue <- fetch (Id venueId :: Id Venue)
                eligible <- billingRecipientIsEligible BillingOperationalRetriesExhausted recipient venue
                if eligible
                    then pure (BillingMailReady (buildMail BillingOperationalRetriesExhausted recipientAddress venue (Just sourceJobId) settings appBaseUrl))
                    else pure (BillingMailSkipped "recipient_ineligible")

buildMail :: BillingNotificationKind -> Text -> Venue -> Maybe UUID -> AppMailSettings -> Text -> BillingNotificationMail
buildMail notificationKind recipientAddress venue maybeSourceAppJobId settings appBaseUrl =
    BillingNotificationMail
        { recipientAddress
        , venue
        , notificationKind
        , sourceReference = tshow <$> maybeSourceAppJobId
        , billingUrl = stripTrailingSlash appBaseUrl <> pathTo BillingAction
        , fromAddress = settings.mailFromAddress
        , replyToAddress = settings.mailReplyToAddress
        , supportEmail = settings.mailSupportEmail
        }

billingRecipientIsEligible :: (?modelContext :: ModelContext) => BillingNotificationKind -> User -> Venue -> IO Bool
billingRecipientIsEligible notificationKind user venue
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
    user.platformRole == Just SuperAdmin

fetchEventVenue :: (?modelContext :: ModelContext) => BillingEvent -> IO Venue
fetchEventVenue event =
    case event.venueId of
        Nothing      -> externalRuntimeInvariantFailure JobProvenanceInvariant "Billing notification event has no venue"
        Just venueId -> fetch (Id venueId :: Id Venue)

decodeNotificationSnapshot :: Aeson.Value -> Maybe [BillingNotification]
decodeNotificationSnapshot value =
    case Aeson.fromJSON value of
        Aeson.Error _               -> Nothing
        Aeson.Success notifications -> Just notifications

billingNotificationKindFromMailKind :: Text -> Maybe BillingNotificationKind
billingNotificationKindFromMailKind candidate =
    find ((== candidate) . billingNotificationMailKind) allBillingNotificationKinds

allBillingNotificationKinds :: [BillingNotificationKind]
allBillingNotificationKinds =
    [ BillingPaymentTrouble
    , BillingPaymentRecovered
    , BillingCancellationScheduled
    , BillingRenewalResumed
    , BillingCancellationCompleted
    , BillingCheckoutPaymentFailed
    , BillingOperationalRetriesExhausted
    ]

stripTrailingSlash :: Text -> Text
stripTrailingSlash = Text.dropWhileEnd (== '/')
