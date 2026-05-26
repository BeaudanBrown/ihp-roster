module Web.Controller.Passkeys where

import Application.Helper.PasskeyRecoveryCodes (verifyAndConsumeRecoveryCode)
import Application.Helper.PasskeySetupTokens
import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import Web.Controller.Prelude
import Web.View.Passkeys.StepUp

instance Controller PasskeysController where
    beforeAction = ensureIsUser

    action PasskeyStepUpAction = do
        unless currentUserRequiresMandatoryPasskey do
            redirectTo RosterWeeksAction
        passkeys <- fetchCurrentUserPasskeys
        when (null passkeys) do
            setErrorMessage "Venue admins and owners must add a passkey before continuing."
            redirectToPath profileSecurityPath
        rawStepUpRedirectTo <- getSession @Text passkeyStepUpRedirectSessionKey
        let stepUpRedirectTo = rawStepUpRedirectTo >>= nonEmptyText
        render StepUpView { .. }

    action UsePasskeyRecoveryCodeAction = do
        unless currentUserRequiresMandatoryPasskey do
            redirectTo RosterWeeksAction
        passkeys <- fetchCurrentUserPasskeys
        when (null passkeys) do
            setErrorMessage "Add your first passkey from your profile security settings."
            redirectToPath profileSecurityPath
        let submittedCode = param @Text "recoveryCode"
        verified <- verifyAndConsumeRecoveryCode currentUser.id submittedCode
        if verified
            then do
                markCurrentUserPasskeyRecoveryVerified
                setSuccessMessage "Recovery code accepted. Add a new passkey now to restore access."
                redirectToPath profileSecurityPath
            else do
                setErrorMessage "That recovery code was not valid or has already been used."
                redirectTo PasskeyStepUpAction

    action SendNewDevicePasskeySetupEmailAction = do
        passkeys <- fetchCurrentUserPasskeys
        when (null passkeys) do
            setErrorMessage "Add your first passkey before sending a new-device setup link."
            redirectToPath profileSecurityPath
        verified <- isCurrentUserPasskeyVerified
        unless verified do
            setSession passkeyStepUpRedirectSessionKey profileSecurityPath
            setErrorMessage "Verify with your passkey before sending a new-device setup link."
            if currentUserRequiresMandatoryPasskey
                then redirectTo PasskeyStepUpAction
                else redirectToPath profileSecurityPath
        let venueId = (.id) <$> currentVenueOrNothing
        (_, rawToken) <- issuePasskeySetupToken SelfNewDevicePasskeySetup currentUser (Just currentUser.id) venueId
        sendPasskeySetupTokenEmail currentUser SelfNewDevicePasskeySetup rawToken
        setSuccessMessage "New-device passkey setup email sent. Open it on the device you want to add."
        redirectToPath profileSecurityPath

    action UpdatePasskeyNameAction { passkeyId } = do
        passkey <- fetch passkeyId
        accessDeniedUnless (passkey.userId == unpackId currentUser.id)
        ensureFreshPasskeyForProfileSecurity
        let submittedName = Text.strip (param @Text "name")
        let newName = if Text.null submittedName then "Passkey" else submittedName

        passkey
            |> set #name newName
            |> updateRecordDiscardResult

        renderJson (Aeson.object ["ok" Aeson..= True, "name" Aeson..= newName])

    action DeletePasskeyAction { passkeyId } = do
        passkey <- fetch passkeyId
        accessDeniedUnless (passkey.userId == unpackId currentUser.id)
        passkeyCount <-
            query @Passkey
                |> filterWhere (#userId, unpackId currentUser.id)
                |> fetchCount
        when (currentUserRequiresMandatoryPasskey && passkeyCount <= 1) do
            setErrorMessage "Venue admins and owners must keep at least one passkey on their account."
            redirectToPath profileSecurityPath
        ensureFreshPasskeyForProfileSecurity

        deleteRecord passkey
        setSuccessMessage "Passkey removed."
        if currentUserIsSuperAdmin
            then redirectTo SupportAction
            else redirectTo EditProfileAction

nonEmptyText :: Text -> Maybe Text
nonEmptyText value =
    if Text.null value
        then Nothing
        else Just value

ensureFreshPasskeyForProfileSecurity :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO ()
ensureFreshPasskeyForProfileSecurity = do
    when currentUserRequiresMandatoryPasskey do
        verified <- isCurrentUserPasskeyVerified
        unless verified do
            withRequestContext do
                setSession passkeyStepUpRedirectSessionKey profileSecurityPath
                setErrorMessage "Verify with your passkey before changing passkey settings."
                redirectTo PasskeyStepUpAction
