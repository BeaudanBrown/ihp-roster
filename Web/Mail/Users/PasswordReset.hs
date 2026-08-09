module Web.Mail.Users.PasswordReset where

import Generated.Types
import IHP.MailPrelude
import Web.Mail.Shared

data PasswordResetMail = PasswordResetMail
    { user           :: User
    , resetUrl       :: Text
    , fromAddress    :: Text
    , replyToAddress :: Text
    , supportEmail   :: Text
    }

instance BuildMail PasswordResetMail where
    subject = "Reset your Bepis password"

    to PasswordResetMail { user } =
        Address
            { addressName = Nothing
            , addressEmail = user.email
            }

    from = bepisFrom ?mail.fromAddress

    replyTo PasswordResetMail { replyToAddress } = bepisReplyTo replyToAddress

    html PasswordResetMail { resetUrl, supportEmail } = [hsx|
        <p>A venue administrator sent a password reset link for your Bepis account.</p>
        <p><a href={resetUrl}>Reset password</a></p>
        <p>This link expires in one hour and can only be used once.</p>
        <p>Completing the reset signs your account out on all devices. Your passkeys remain available.</p>
        <hr/>
        <p>
            You’re receiving this because this email address is associated with a Bepis account, venue, or invitation.
            If this wasn’t expected, you can ignore this email or contact {supportEmail}.
        </p>
    |]

    text PasswordResetMail { resetUrl, supportEmail } =
        "A venue administrator sent a password reset link for your Bepis account:\n\n"
            <> resetUrl
            <> "\n\nThis link expires in one hour and can only be used once."
            <> "\n\nCompleting the reset signs your account out on all devices. Your passkeys remain available."
            <> supportFooterText supportEmail
