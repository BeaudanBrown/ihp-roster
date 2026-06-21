module Application.Helper.Mail
    ( AppMailSettings (..)
    , loadAppMailSettings
    ) where

import IHP.EnvVar
import IHP.Prelude

data AppMailSettings = AppMailSettings
    { mailFromAddress    :: !Text
    , mailReplyToAddress :: !Text
    , mailSupportEmail   :: !Text
    }

loadAppMailSettings :: IO AppMailSettings
loadAppMailSettings = do
    mailFromAddress <- envOrDefault "MAIL_FROM" "noreply@dev.local"
    mailReplyToAddress <- envOrDefault "MAIL_REPLY_TO" "support@bepis.lol"
    mailSupportEmail <- envOrDefault "MAIL_SUPPORT_EMAIL" mailReplyToAddress
    pure AppMailSettings { .. }
