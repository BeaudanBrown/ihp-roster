module Web.Mail.Users.PasswordReset where

import IHP.MailPrelude
import Web.Mail.Shared

data PasswordResetMail = PasswordResetMail
    { recipientAddress :: Text
    , resetUrl         :: Text
    , fromAddress      :: Text
    , replyToAddress   :: Text
    , supportEmail     :: Text
    , initiatedByAccountHolder :: Bool
    }

instance BuildMail PasswordResetMail where
    subject = "Reset your Bepis password"

    to PasswordResetMail { recipientAddress } =
        Address
            { addressName = Nothing
            , addressEmail = recipientAddress
            }

    from = bepisFrom ?mail.fromAddress

    replyTo PasswordResetMail { replyToAddress } = bepisReplyTo replyToAddress

    html PasswordResetMail { resetUrl, supportEmail, initiatedByAccountHolder } = [hsx|
        <p>{passwordResetIntroduction initiatedByAccountHolder}</p>
        <p><a href={resetUrl}>Reset password</a></p>
        <p>This link expires in six hours and can only be used once.</p>
        <p>Completing the reset signs your account out on all devices. Your passkeys remain available.</p>
        <hr/>
        <p>
            You’re receiving this because this email address is associated with a Bepis account, venue, or invitation.
            If this wasn’t expected, you can ignore this email or contact {supportEmail}.
        </p>
    |]

    text PasswordResetMail { resetUrl, supportEmail, initiatedByAccountHolder } =
        passwordResetIntroduction initiatedByAccountHolder
            <> ":\n\n"
            <> resetUrl
            <> "\n\nThis link expires in six hours and can only be used once."
            <> "\n\nCompleting the reset signs your account out on all devices. Your passkeys remain available."
            <> supportFooterText supportEmail

passwordResetIntroduction :: Bool -> Text
passwordResetIntroduction True = "A password reset was requested for your Bepis account"
passwordResetIntroduction False = "A venue administrator sent a password reset link for your Bepis account"
