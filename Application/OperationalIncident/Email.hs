module Application.OperationalIncident.Email
    ( loadOperationalIncidentMail
    ) where

import Application.Helper.Mail
import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude
import Web.Mail.OperationalIncident
import Web.Routes ()
import Web.Types

loadOperationalIncidentMail ::
    (?context :: context, ConfigProvider context, ?modelContext :: ModelContext) =>
    UUID ->
    Text ->
    UUID ->
    AppMailSettings ->
    Text ->
    IO (Maybe OperationalIncidentMail)
loadOperationalIncidentMail recipientAccountId recipientAddress eventId settings appBaseUrl = do
    maybeEvent <- fetchOneOrNothing (Id eventId :: Id OperationalIncidentEvent)
    case maybeEvent of
        Nothing -> pure Nothing
        Just event -> do
            maybeRecipient <-
                query @OperationalIncidentEventRecipient
                    |> filterWhere (#operationalIncidentEventId, unpackId event.id)
                    |> filterWhere (#recipientUserId, recipientAccountId)
                    |> filterWhere (#recipientAddress, recipientAddress)
                    |> fetchOneOrNothing
            maybeIncident <- fetchOneOrNothing (Id event.operationalIncidentId :: Id OperationalIncident)
            pure do
                _ <- maybeRecipient
                incident <- maybeIncident
                symptoms <- decodeSymptoms event.symptomCodes
                pure
                    OperationalIncidentMail
                        { recipientAddress
                        , category = incident.category
                        , affectedSource = incident.affectedSource
                        , transition = event.transition
                        , severity = event.severity
                        , symptomCodes = symptoms
                        , observedAt = event.observedAt
                        , supportUrl = Text.dropWhileEnd (== '/') appBaseUrl <> pathTo SupportAction
                        , fromAddress = settings.mailFromAddress
                        , replyToAddress = settings.mailReplyToAddress
                        }

decodeSymptoms :: Aeson.Value -> Maybe [Text]
decodeSymptoms value = case Aeson.fromJSON value of
    Aeson.Success symptoms -> Just symptoms
    Aeson.Error _ -> Nothing
