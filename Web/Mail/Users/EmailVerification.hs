module Web.Mail.Users.EmailVerification where

import Generated.Types
import IHP.MailPrelude

data EmailVerificationMail = EmailVerificationMail
    { user            :: User
    , verificationUrl :: Text
    , fromAddress     :: Text
    }

instance BuildMail EmailVerificationMail where
    subject = "Verify your email"

    to EmailVerificationMail { user } =
        Address
            { addressName = Nothing
            , addressEmail = user.email
            }

    from =
        Address
            { addressName = Just "Bepis"
            , addressEmail = ?mail.fromAddress
            }

    html EmailVerificationMail { verificationUrl } = [hsx|
        <p>Verify your email to finish setting up your account.</p>
        <p><a href={verificationUrl}>Verify email</a></p>
        <p>If you did not expect this email, you can ignore it.</p>
    |]

    text EmailVerificationMail { verificationUrl } =
        "Verify your email to finish setting up your account:\n\n" <> verificationUrl
