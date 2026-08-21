module Web.Mail.Users.EmailVerification where

import IHP.MailPrelude
import Web.Mail.Shared

data EmailVerificationMail = EmailVerificationMail
    { recipientAddress :: Text
    , verificationUrl  :: Text
    , fromAddress      :: Text
    , replyToAddress   :: Text
    , supportEmail     :: Text
    }

instance BuildMail EmailVerificationMail where
    subject = "Verify your email"

    to EmailVerificationMail { recipientAddress } =
        Address
            { addressName = Nothing
            , addressEmail = recipientAddress
            }

    from = bepisFrom ?mail.fromAddress

    replyTo EmailVerificationMail { replyToAddress } = bepisReplyTo replyToAddress

    html EmailVerificationMail { verificationUrl, supportEmail } = [hsx|
        <p>Verify your email to finish setting up your Bepis account.</p>
        <p><a href={verificationUrl}>Verify email</a></p>
        <hr/>
        <p>
            You’re receiving this because this email address is associated with a Bepis account, venue, or invitation.
            If this wasn’t expected, you can ignore this email or contact {supportEmail}.
        </p>
    |]

    text EmailVerificationMail { verificationUrl, supportEmail } =
        "Verify your email to finish setting up your Bepis account:\n\n"
            <> verificationUrl
            <> supportFooterText supportEmail
