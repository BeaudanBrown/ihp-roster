module Web.Mail.WageSourceDrift where

import IHP.MailPrelude
import Web.Mail.Shared


data WageSourceDriftMail = WageSourceDriftMail
    { recipientAddress :: !Text
    , driftKind        :: !Text
    , expectedValue    :: !Text
    , observedValue    :: !Text
    , fromAddress      :: !Text
    , replyToAddress   :: !Text
    , supportEmail     :: !Text
    }

instance BuildMail WageSourceDriftMail where
    subject = "Bepis Award source drift detected"
    to WageSourceDriftMail { recipientAddress } = Address Nothing recipientAddress
    from = bepisFrom ?mail.fromAddress
    replyTo WageSourceDriftMail { replyToAddress } = bepisReplyTo replyToAddress
    html WageSourceDriftMail { driftKind, expectedValue, observedValue, supportEmail } =
        [hsx|
            <h1>Award source drift detected</h1>
            <p>Bepis detected a non-blocking change in the Hospitality Award source structure.</p>
            <p><strong>Kind:</strong> {driftKind}</p>
            <p><strong>Previous:</strong> {expectedValue}</p>
            <p><strong>Current:</strong> {observedValue}</p>
            <hr/>
            <p>If this wasn’t expected, contact {supportEmail}.</p>
        |]
    text WageSourceDriftMail { driftKind, expectedValue, observedValue, supportEmail } =
        "Award source drift detected\n\nKind: " <> driftKind
            <> "\nPrevious: " <> expectedValue
            <> "\nCurrent: " <> observedValue
            <> supportFooterText supportEmail
