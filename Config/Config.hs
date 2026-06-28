module Config where

import Application.Helper.Profiling (profilingMiddleware)
import Application.Helper.Telemetry (telemetryMiddleware)
import IHP.Environment
import IHP.EnvVar
import IHP.FrameworkConfig
import IHP.Mail
import IHP.Mail.Types (SMTPEncryption)
import IHP.Prelude
import Network.Socket (PortNumber)

config :: ConfigBuilder
config = do
    -- See https://ihp.digitallyinduced.com/Guide/config.html
    -- for what you can do here
    smtpHost <- env @Text "SMTP_HOST"
    smtpPort <- env @PortNumber "SMTP_PORT"
    smtpEncryption <- env @SMTPEncryption "SMTP_ENCRYPTION"
    smtpUserMaybe :: Maybe Text <- envOrNothing "SMTP_USER"
    smtpPasswordMaybe :: Maybe Text <- envOrNothing "SMTP_PASSWORD"

    let smtpCredentials = case (smtpUserMaybe, smtpPasswordMaybe) of
            (Just user, Just password) -> Just (cs user, cs password)
            _                          -> Nothing

    option $
        SMTP
            { host = cs smtpHost
            , port = smtpPort
            , credentials = smtpCredentials
            , encryption = smtpEncryption
            }
    option $ CustomMiddleware (telemetryMiddleware . profilingMiddleware)

    pure ()
