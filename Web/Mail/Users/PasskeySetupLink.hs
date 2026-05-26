module Web.Mail.Users.PasskeySetupLink where

import Generated.Types
import IHP.MailPrelude

data PasskeySetupLinkMail = PasskeySetupLinkMail
    { user         :: User
    , setupUrl     :: Text
    , fromAddress  :: Text
    , purposeLabel :: Text
    }

instance BuildMail PasskeySetupLinkMail where
    subject = "Set up a new passkey"

    to PasskeySetupLinkMail { user } =
        Address
            { addressName = Nothing
            , addressEmail = user.email
            }

    from =
        Address
            { addressName = Just "Bepis"
            , addressEmail = ?mail.fromAddress
            }

    html PasskeySetupLinkMail { setupUrl, purposeLabel } = [hsx|
        <p>{purposeLabel} for your Bepis account.</p>
        <p><a href={setupUrl}>Set up passkey</a></p>
        <p>This link expires in one hour and can only be used once.</p>
        <p>If you did not request this email, you can ignore it.</p>
    |]

    text PasskeySetupLinkMail { setupUrl, purposeLabel } =
        purposeLabel <> " for your Bepis account:\n\n"
            <> setupUrl
            <> "\n\nThis link expires in one hour and can only be used once."
