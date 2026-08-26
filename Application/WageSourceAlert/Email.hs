module Application.WageSourceAlert.Email
    ( isWageSourceAlertMailKind
    , loadWageSourceAlertMail
    ) where

import Application.Helper.Mail
import Application.WageSourceAlert.Types
import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig (ConfigProvider)
import Web.Mail.WageSourceAlert
import Web.Routes ()
import Web.Types


loadWageSourceAlertMail ::
    (?context :: context, ConfigProvider context, ?modelContext :: ModelContext) =>
    Text ->
    Text ->
    UUID ->
    AppMailSettings ->
    Text ->
    IO (Maybe WageSourceAlertMail)
loadWageSourceAlertMail mailKind recipientAddress healthCheckJobId settings appBaseUrl = do
    maybeHealthCheck <-
        query @AppJob
            |> filterWhere (#id, Id healthCheckJobId)
            |> fetchOneOrNothing
    pure do
        healthCheck <- maybeHealthCheck
        snapshots <- decodeSnapshots healthCheck.result
        snapshot <- find ((== mailKind) . (\candidate -> alertMailKind candidate.source candidate.alertKind)) snapshots
        pure
            WageSourceAlertMail
                { recipientAddress
                , snapshot
                , supportUrl = stripTrailingSlash appBaseUrl <> pathTo SupportAction
                , fromAddress = settings.mailFromAddress
                , replyToAddress = settings.mailReplyToAddress
                }

newtype AlertResult = AlertResult
    { alerts :: [WageSourceAlertSnapshot]
    }

instance Aeson.FromJSON AlertResult where
    parseJSON = Aeson.withObject "Wage-source health-check result" \object ->
        AlertResult <$> object Aeson..:? "alerts" Aeson..!= []

decodeSnapshots :: Aeson.Value -> Maybe [WageSourceAlertSnapshot]
decodeSnapshots value =
    case Aeson.fromJSON value of
        Aeson.Error _                        -> Nothing
        Aeson.Success AlertResult { alerts } -> Just alerts

stripTrailingSlash :: Text -> Text
stripTrailingSlash = Text.dropWhileEnd (== '/')
