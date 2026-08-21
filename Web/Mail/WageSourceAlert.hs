module Web.Mail.WageSourceAlert
    ( WageSourceAlertMail (..)
    , formatMelbourneTimestamp
    , wageSourceAlertSubject
    ) where

import Application.VenueTime
import Application.WageSourceAlert.Types
import qualified Data.Text as Text
import Data.Time.Format (defaultTimeLocale, formatTime)
import IHP.MailPrelude
import qualified Text.Blaze.Html5 as Html
import Web.Mail.Shared


data WageSourceAlertMail = WageSourceAlertMail
    { recipientAddress :: !Text
    , snapshot         :: !WageSourceAlertSnapshot
    , supportUrl       :: !Text
    , fromAddress      :: !Text
    , replyToAddress   :: !Text
    }

instance BuildMail WageSourceAlertMail where
    subject = wageSourceAlertSubject ?mail.snapshot
    to WageSourceAlertMail { recipientAddress } = Address Nothing recipientAddress
    from = bepisFrom ?mail.fromAddress
    replyTo WageSourceAlertMail { replyToAddress } = bepisReplyTo replyToAddress
    html mail =
        [hsx|
            <h1>{wageSourceAlertSubject mail.snapshot}</h1>
            <p>{alertSummary mail.snapshot}</p>
            <dl>
                <dt>Source</dt><dd>{wageSourceLabel mail.snapshot.source}</dd>
                <dt>Detected</dt><dd>{formatMelbourneTimestamp mail.snapshot.detectedAt}</dd>
                {failureHtmlFields mail.snapshot}
                {affectedYearsHtml mail.snapshot.affectedYears}
                {latestSuccessHtml mail.snapshot.latestValidSuccessAt}
                {annualBoundaryHtml mail.snapshot.annualRequiredOnOrAfter}
            </dl>
            <p><a href={mail.supportUrl}>Open Bepis Support</a></p>
        |]
    text mail =
        Text.intercalate
            "\n"
            ( [ wageSourceAlertSubject mail.snapshot
              , ""
              , alertSummary mail.snapshot
              , ""
              , "Source: " <> wageSourceLabel mail.snapshot.source
              , "Detected: " <> formatMelbourneTimestamp mail.snapshot.detectedAt
              ]
                <> failureTextFields mail.snapshot
                <> optionalLine "Affected years" (renderYears mail.snapshot.affectedYears)
                <> optionalLine "Latest valid success" (formatMelbourneTimestamp <$> mail.snapshot.latestValidSuccessAt)
                <> optionalLine "Annual refresh required on or after" (tshow <$> mail.snapshot.annualRequiredOnOrAfter)
                <> ["", "Open Bepis Support: " <> mail.supportUrl]
            )

wageSourceAlertSubject :: WageSourceAlertSnapshot -> Text
wageSourceAlertSubject snapshot =
    case snapshot.alertKind of
        RefreshFailedAlert -> wageSourceLabel snapshot.source <> " refresh failed"
        SourceMissingAlert -> wageSourceLabel snapshot.source <> " data is missing"
        SourceStaleAlert -> wageSourceLabel snapshot.source <> " data is stale"
        FwcAnnualRefreshMissingAlert -> "FWC annual wage refresh is missing"

alertSummary :: WageSourceAlertSnapshot -> Text
alertSummary snapshot =
    case snapshot.alertKind of
        RefreshFailedAlert -> "The final automatic retry failed. Existing persisted source data was evaluated separately."
        SourceMissingAlert -> "Bepis cannot find a complete authoritative snapshot for the required source scope."
        SourceStaleAlert -> "The latest complete authoritative snapshot is older than the allowed freshness threshold."
        FwcAnnualRefreshMissingAlert -> "No complete FWC snapshot published on or after 1 July was available when the earliest active venue reached its first full pay week."

failureTextFields :: WageSourceAlertSnapshot -> [Text]
failureTextFields snapshot
    | snapshot.alertKind /= RefreshFailedAlert = []
    | otherwise =
        [ "Refresh job ID: " <> tshow snapshot.sourceJobId
        , "Refresh class: " <> maybe "unknown" refreshTriggerClassText snapshot.refreshTriggerClass
        ]

failureHtmlFields :: WageSourceAlertSnapshot -> Html.Html
failureHtmlFields snapshot
    | snapshot.alertKind /= RefreshFailedAlert = mempty
    | otherwise =
        Html.dt "Refresh job ID"
            <> Html.dd (Html.toHtml (tshow snapshot.sourceJobId))
            <> Html.dt "Refresh class"
            <> Html.dd (Html.toHtml (maybe "unknown" refreshTriggerClassText snapshot.refreshTriggerClass))

affectedYearsHtml :: [Integer] -> Html.Html
affectedYearsHtml years =
    maybe mempty (\value -> Html.dt "Affected years" <> Html.dd (Html.toHtml value)) (renderYears years)

latestSuccessHtml :: Maybe UTCTime -> Html.Html
latestSuccessHtml =
    maybe mempty (\value -> Html.dt "Latest valid success" <> Html.dd (Html.toHtml (formatMelbourneTimestamp value)))

annualBoundaryHtml :: Maybe Day -> Html.Html
annualBoundaryHtml =
    maybe mempty (\value -> Html.dt "Annual refresh required on or after" <> Html.dd (Html.toHtml (tshow value)))

optionalLine :: Text -> Maybe Text -> [Text]
optionalLine label = maybe [] (\value -> [label <> ": " <> value])

renderYears :: [Integer] -> Maybe Text
renderYears []    = Nothing
renderYears years = Just (Text.intercalate ", " (map tshow years))

formatMelbourneTimestamp :: UTCTime -> Text
formatMelbourneTimestamp timestamp =
    cs (formatTime defaultTimeLocale "%Y-%m-%d %H:%M:%S" localTime)
        <> " "
        <> melbourneTimeZoneName
  where
    localTime = resolvedInstantLocalTime (resolvedInstantFromUTC timestamp)
