module Web.Controller.Passkeys where

import Application.Helper.PasskeyRecoveryCodes (verifyAndConsumeRecoveryCode)
import Application.Helper.PasskeySetupTokens
import qualified Data.Text as Text
import Web.Controller.Prelude
import Web.View.Passkeys.SetupModal
import Web.View.Passkeys.StepUp

instance Controller PasskeysController where
    beforeAction = bepisBeforeAction BepisAuthenticatedController do
        annotateTelemetryAction
        ensureIsUser
        ensureNotImpersonatingAccountSecurity

    action currentAction@PasskeyStepUpAction = runBepis currentAction BepisPageAction do
        rawStepUpRedirectTo <- getSession @Text passkeyStepUpRedirectSessionKey
        let stepUpRedirectTo = rawStepUpRedirectTo >>= nonEmptyText
        strongAuthenticationRequired <- currentUserRequiresMandatoryPasskey
        unless (strongAuthenticationRequired || isJust stepUpRedirectTo) do
            redirectTo RosterWeeksAction
        passkeys <- fetchCurrentUserPasskeys
        when (null passkeys) do
            redirectTo PasskeySetupAction
        render StepUpView { .. }

    action currentAction@PasskeySetupAction = runBepis currentAction BepisPageAction do
        rawRedirectTo <- getSession @Text passkeyStepUpRedirectSessionKey
        let passkeySetupRedirectTo = fromMaybe (pathTo RosterWeeksAction) (rawRedirectTo >>= nonEmptyText)
        render PasskeySetupView { .. }

    action currentAction@DismissMandatoryPasskeySetupAction = runBepis currentAction BepisMutationAction do
        deleteSession passkeyStepUpRedirectSessionKey
        setErrorMessage "Create a passkey before opening restricted admin pages."
        redirectTo RosterWeeksAction

    action currentAction@ShowPasskeySetupDialogAction = runBepis currentAction BepisDialogAction do
        let successRedirect = safeLocalRedirect (paramOrDefault @Text profileSecurityPath "successRedirect")
        respondHtml (renderPasskeySetupDialog OptionalFirstPasskey successRedirect)

    action currentAction@ShowPasskeyRecoveryCodeDialogAction = runBepis currentAction BepisDialogAction do
        strongAuthenticationRequired <- currentUserRequiresMandatoryPasskey
        unless strongAuthenticationRequired do
            redirectTo RosterWeeksAction
        passkeys <- fetchCurrentUserPasskeys
        when (null passkeys) do
            setErrorMessage "Add your first passkey before using a recovery code."
            redirectToPath mandatoryPasskeySetupPath
        respondHtml renderPasskeyRecoveryCodeDialog

    action currentAction@UsePasskeyRecoveryCodeAction = runBepis currentAction BepisMutationAction do
        strongAuthenticationRequired <- currentUserRequiresMandatoryPasskey
        unless strongAuthenticationRequired do
            redirectTo RosterWeeksAction
        passkeys <- fetchCurrentUserPasskeys
        when (null passkeys) do
            setErrorMessage "Add your first passkey before using a recovery code."
            redirectToPath mandatoryPasskeySetupPath
        let submittedCode = param @Text "recoveryCode"
        verified <- verifyAndConsumeRecoveryCode currentUser.id submittedCode
        if verified
            then do
                markCurrentUserPasskeyRecoveryVerified
                setSuccessMessage "Recovery code accepted. Add a new passkey now to restore access."
                redirectTo PasskeySetupAction
            else do
                setErrorMessage "That recovery code was not valid or has already been used."
                redirectTo PasskeyStepUpAction

    action currentAction@SendNewDevicePasskeySetupEmailAction = runBepis currentAction BepisMutationAction do
        passkeys <- fetchCurrentUserPasskeys
        when (null passkeys) do
            setErrorMessage "Add your first passkey before sending a new-device setup link."
            redirectToPath profileSecurityPath
        verified <- isCurrentUserPasskeyVerified
        unless verified do
            setSession passkeyStepUpRedirectSessionKey profileSecurityPath
            setErrorMessage "Verify with your passkey before sending a new-device setup link."
            strongAuthenticationRequired <- currentUserRequiresMandatoryPasskey
            if strongAuthenticationRequired
                then redirectTo PasskeyStepUpAction
                else redirectToPath profileSecurityPath
        let venueId = (.id) <$> currentVenueOrNothing
        (_, rawToken) <- issuePasskeySetupToken SelfNewDevicePasskeySetup currentUser (Just currentUser.id) venueId
        sendPasskeySetupTokenEmail currentUser SelfNewDevicePasskeySetup rawToken
        setSuccessMessage "New-device passkey setup email sent. Open it on the device you want to add."
        redirectToPath profileSecurityPath

    action currentAction@DeletePasskeyAction { passkeyId } = runBepis currentAction BepisMutationAction do
        passkey <- fetch passkeyId
        accessDeniedUnless (passkey.userId == unpackId currentUser.id)
        passkeyCount <-
            query @Passkey
                |> filterWhere (#userId, unpackId currentUser.id)
                |> fetchCount
        strongAuthenticationRequired <- currentUserRequiresMandatoryPasskey
        when (strongAuthenticationRequired && passkeyCount <= 1) do
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

safeLocalRedirect :: Text -> Text
safeLocalRedirect value
    | "/" `Text.isPrefixOf` value && not ("//" `Text.isPrefixOf` value) = value
    | otherwise = profileSecurityPath

ensureFreshPasskeyForProfileSecurity :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO ()
ensureFreshPasskeyForProfileSecurity = do
    verified <- isCurrentUserPasskeyVerified
    unless verified do
        withRequestContext do
            setSession passkeyStepUpRedirectSessionKey profileSecurityPath
            setErrorMessage "Verify with your passkey before changing passkey settings."
            redirectTo PasskeyStepUpAction
