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
import qualified IHP.HSX.Markup as Markup
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

failureHtmlFields :: WageSourceAlertSnapshot -> Markup.Html
failureHtmlFields snapshot
    | snapshot.alertKind /= RefreshFailedAlert = mempty
    | otherwise = [hsx|<dt>Refresh job ID</dt><dd>{tshow snapshot.sourceJobId}</dd><dt>Refresh class</dt><dd>{maybe "unknown" refreshTriggerClassText snapshot.refreshTriggerClass}</dd>|]

affectedYearsHtml :: [Integer] -> Markup.Html
affectedYearsHtml years =
    maybe mempty (\value -> [hsx|<dt>Affected years</dt><dd>{value}</dd>|]) (renderYears years)

latestSuccessHtml :: Maybe UTCTime -> Markup.Html
latestSuccessHtml =
    maybe mempty (\value -> [hsx|<dt>Latest valid success</dt><dd>{formatMelbourneTimestamp value}</dd>|])

annualBoundaryHtml :: Maybe Day -> Markup.Html
annualBoundaryHtml =
    maybe mempty (\value -> [hsx|<dt>Annual refresh required on or after</dt><dd>{tshow value}</dd>|])

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
