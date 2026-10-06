-- | Frozen selected-content rendering and the transport envelope. The renderer
-- cannot select destinations, sender addresses or attachments. It never reads
-- current business data or reevaluates captured calculations.
module Web.Mail.DaysheetReport
    ( ReportMailContent (..), DaysheetReportMail (..)
    , FrozenReportIdentity (..), frozenReportMailContent
    ) where

import Application.Daysheet.Report (ReportContent (..))
import Application.Helper.View.DaysheetReport (renderReportContent, reportPlainText)
import qualified Data.Char as Char
import qualified Data.Text as Text
import IHP.MailPrelude
import qualified IHP.HSX.Markup as Markup
import Web.Mail.Shared

data ReportMailContent = ReportMailContent
    { reportSubject :: !Text
    , reportHtml :: !Markup.Html
    , reportText :: !Text
    }

data FrozenReportIdentity = FrozenReportIdentity
    { operationalDate :: !Day
    , capturedAt :: !UTCTime
    , cutoffAt :: !(Maybe UTCTime)
    }

frozenReportMailContent :: FrozenReportIdentity -> ReportContent -> ReportMailContent
frozenReportMailContent identity selected@(ReportContent label _) = ReportMailContent
    { reportSubject = "Bepis Daysheet " <> tshow identity.operationalDate <> " — " <> Text.take 180 safeLabel
    , reportHtml = [hsx|
        <h1>{label}</h1>
        <p><strong>{origin}</strong></p>
        <p>Operational date: {tshow identity.operationalDate}</p>
        <p>Captured: {tshow identity.capturedAt}</p>
        {forEach identity.cutoffAt renderCutoff}
        <p>Frozen saved values. Later changes to the Daysheet are not included.</p>
        {renderReportContent selected}
    |]
    , reportText = Text.unlines
        ([origin, "Operational date: " <> tshow identity.operationalDate, "Captured: " <> tshow identity.capturedAt]
        <> maybe [] (\cutoff -> ["Scheduled cutoff: " <> tshow cutoff]) identity.cutoffAt
        <> ["Frozen saved values. Later changes to the Daysheet are not included.", "", reportPlainText selected])
    }
  where
    origin = if isJust identity.cutoffAt then "Scheduled frozen report" :: Text else "Manual frozen report"
    safeLabel = Text.unwords (Text.words (Text.map (\char -> if Char.isControl char then ' ' else char) label))
    renderCutoff cutoff = [hsx|<p>Scheduled cutoff: {tshow cutoff}</p>|]

data DaysheetReportMail = DaysheetReportMail
    { recipientAddress :: !Text
    , fromAddress :: !Text
    , replyToAddress :: !Text
    , content :: !ReportMailContent
    }

instance BuildMail DaysheetReportMail where
    subject = ?mail.content.reportSubject
    to mail = Address Nothing mail.recipientAddress
    from = bepisFrom ?mail.fromAddress
    replyTo mail = bepisReplyTo mail.replyToAddress
    html mail = mail.content.reportHtml
    text mail = mail.content.reportText
