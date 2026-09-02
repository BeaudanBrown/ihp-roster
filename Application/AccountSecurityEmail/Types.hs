module Application.AccountSecurityEmail.Types
    ( PasskeySetupTokenPurpose (..)
    , accountRecoveryRequestCooldown
    , accountRecoveryTokenLifetime
    , emailVerificationMailKind
    , isAccountSecurityMailKind
    , passkeySetupMailKind
    , passkeySetupTokenPurposeEmailLabel
    , passkeySetupTokenPurposeFromText
    , passkeySetupTokenPurposeText
    , passwordResetMailKind
    ) where

import IHP.Prelude

data PasskeySetupTokenPurpose
    = SelfNewDevicePasskeySetup
    | StaffNewDevicePasskeySetup
    | StaffPasskeyRecovery
    deriving (Eq, Show)

accountRecoveryTokenLifetime :: NominalDiffTime
accountRecoveryTokenLifetime = 60 * 60 * 6

accountRecoveryRequestCooldown :: NominalDiffTime
accountRecoveryRequestCooldown = 60 * 5

emailVerificationMailKind :: Text
emailVerificationMailKind = "account_email_verification"

passwordResetMailKind :: Text
passwordResetMailKind = "account_password_reset"

passkeySetupMailKind :: Text
passkeySetupMailKind = "account_passkey_setup"

isAccountSecurityMailKind :: Text -> Bool
isAccountSecurityMailKind mailKind =
    mailKind `elem` [emailVerificationMailKind, passwordResetMailKind, passkeySetupMailKind]

passkeySetupTokenPurposeText :: PasskeySetupTokenPurpose -> Text
passkeySetupTokenPurposeText SelfNewDevicePasskeySetup  = "self_new_device"
passkeySetupTokenPurposeText StaffNewDevicePasskeySetup = "staff_new_device"
passkeySetupTokenPurposeText StaffPasskeyRecovery       = "staff_recovery"

passkeySetupTokenPurposeFromText :: Text -> Maybe PasskeySetupTokenPurpose
passkeySetupTokenPurposeFromText "self_new_device" = Just SelfNewDevicePasskeySetup
passkeySetupTokenPurposeFromText "staff_new_device" = Just StaffNewDevicePasskeySetup
passkeySetupTokenPurposeFromText "staff_recovery" = Just StaffPasskeyRecovery
passkeySetupTokenPurposeFromText _ = Nothing

passkeySetupTokenPurposeEmailLabel :: PasskeySetupTokenPurpose -> Text
passkeySetupTokenPurposeEmailLabel SelfNewDevicePasskeySetup = "Set up a new passkey"
passkeySetupTokenPurposeEmailLabel StaffNewDevicePasskeySetup = "Set up a staff passkey"
passkeySetupTokenPurposeEmailLabel StaffPasskeyRecovery = "Recover passkey access"
