-- | Transport envelope only. The Daysheet report projection owns rendering;
-- it cannot select destinations, sender addresses, or attachments through this
-- interface. Nothing here renders or stores a second copy of business data.
module Web.Mail.DaysheetReport (ReportMailContent (..), DaysheetReportMail (..)) where

import IHP.MailPrelude
import qualified IHP.HSX.Markup as Markup
import Web.Mail.Shared

data ReportMailContent = ReportMailContent
    { reportSubject :: !Text
    , reportHtml :: !Markup.Html
    , reportText :: !Text
    }

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
