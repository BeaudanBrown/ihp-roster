module Web.Mail.OperationalIncident
    ( OperationalIncidentMail (..)
    , operationalIncidentSubject
    ) where

import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import IHP.MailPrelude
import qualified IHP.HSX.Markup as Markup
import Web.Mail.Shared

data OperationalIncidentMail = OperationalIncidentMail
    { recipientAddress :: !Text
    , category         :: !Text
    , affectedSource   :: !Text
    , transition       :: !Text
    , severity         :: !Text
    , symptomCodes     :: ![Text]
    , observedAt       :: !UTCTime
    , supportUrl       :: !Text
    , fromAddress      :: !Text
    , replyToAddress   :: !Text
    }

instance BuildMail OperationalIncidentMail where
    subject = operationalIncidentSubject ?mail
    to OperationalIncidentMail { recipientAddress } = Address Nothing recipientAddress
    from = bepisFrom ?mail.fromAddress
    replyTo OperationalIncidentMail { replyToAddress } = bepisReplyTo replyToAddress
    html mail =
        [hsx|
            <h1>{operationalIncidentSubject mail}</h1>
            <p>Bepis recorded a durable operational incident transition.</p>
            <dl>
                <dt>Category</dt><dd>{mail.category}</dd>
                <dt>Source</dt><dd>{mail.affectedSource}</dd>
                <dt>Transition</dt><dd>{mail.transition}</dd>
                <dt>Severity</dt><dd>{mail.severity}</dd>
                <dt>Observed</dt><dd>{tshow mail.observedAt}</dd>
                {symptomsHtml mail.symptomCodes}
            </dl>
            <p><a href={mail.supportUrl}>Open Bepis Support</a></p>
        |]
    text mail =
        Text.intercalate
            "\n"
            [ operationalIncidentSubject mail
            , ""
            , "Bepis recorded a durable operational incident transition."
            , "Category: " <> mail.category
            , "Source: " <> mail.affectedSource
            , "Transition: " <> mail.transition
            , "Severity: " <> mail.severity
            , "Observed: " <> tshow mail.observedAt
            , "Symptoms: " <> renderSymptoms mail.symptomCodes
            , ""
            , "Open Bepis Support: " <> mail.supportUrl
            ]

operationalIncidentSubject :: OperationalIncidentMail -> Text
operationalIncidentSubject mail =
    "Bepis " <> mail.category <> ": " <> mail.transition

symptomsHtml :: [Text] -> Markup.Html
symptomsHtml [] = mempty
symptomsHtml values = [hsx|<dt>Symptoms</dt><dd>{renderSymptoms values}</dd>|]

renderSymptoms :: [Text] -> Text
renderSymptoms = Text.intercalate ", "
