module Web.Mail.Users.PasskeySetupLink where

import Generated.Types
import IHP.MailPrelude
import Web.Mail.Shared

data PasskeySetupLinkMail = PasskeySetupLinkMail
    { user           :: User
    , setupUrl       :: Text
    , fromAddress    :: Text
    , replyToAddress :: Text
    , supportEmail   :: Text
    , purposeLabel   :: Text
    }

instance BuildMail PasskeySetupLinkMail where
    subject = "Set up a new passkey"

    to PasskeySetupLinkMail { user } =
        Address
            { addressName = Nothing
            , addressEmail = user.email
            }

    from = bepisFrom ?mail.fromAddress

    replyTo PasskeySetupLinkMail { replyToAddress } = bepisReplyTo replyToAddress

    html PasskeySetupLinkMail { setupUrl, purposeLabel, supportEmail } = [hsx|
        <p>{purposeLabel} for your Bepis account.</p>
        <p><a href={setupUrl}>Set up passkey</a></p>
        <p>This link expires in one hour and can only be used once.</p>
        <hr/>
        <p>
            You’re receiving this because this email address is associated with a Bepis account, venue, or invitation.
            If this wasn’t expected, you can ignore this email or contact {supportEmail}.
        </p>
    |]

    text PasskeySetupLinkMail { setupUrl, purposeLabel, supportEmail } =
        purposeLabel <> " for your Bepis account:\n\n"
            <> setupUrl
            <> "\n\nThis link expires in one hour and can only be used once."
            <> supportFooterText supportEmail
