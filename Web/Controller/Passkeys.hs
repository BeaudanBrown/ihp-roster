module Web.Controller.Passkeys where

import Application.Helper.PasskeyRecoveryCodes (verifyAndConsumeRecoveryCode)
import Application.Helper.PasskeySetupTokens
import Control.Monad (void)
import qualified Data.Text as Text
import Web.Controller.Prelude
import Web.View.Passkeys.SetupModal
import Web.View.Passkeys.StepUp

instance Controller PasskeysController where
    beforeAction = bepisBeforeAction BepisAuthenticatedController do
        annotateTelemetryAction
        ensureIsUser
        redirectPermissionDeniedUnless
            (not currentUserIsImpersonating || (currentUserCanUseOwnerImpersonationAccountSecurity && passkeysActionAllowsOwnerImpersonation ?theAction))
            "Exit support impersonation before managing sign-in or account security."

    action currentAction@PasskeyStepUpAction = runBepis currentAction BepisPageAction do
        rawStepUpRedirectTo <- getSession @Text passkeyStepUpRedirectSessionKey
        let stepUpRedirectTo = rawStepUpRedirectTo >>= safePasskeyReturnPath
        strongAuthenticationRequired <- currentUserRequiresMandatoryPasskey
        unless (strongAuthenticationRequired || isJust stepUpRedirectTo) do
            redirectTo RosterWeeksAction
        passkeys <- fetchAuthenticatedUserPasskeys
        when (null passkeys) do
            redirectTo PasskeySetupAction
        render StepUpView { .. }

    action currentAction@ShowPasskeyStepUpDialogAction = runBepis currentAction BepisDialogAction do
        rawStepUpRedirectTo <- getSession @Text passkeyStepUpRedirectSessionKey
        let stepUpRedirectTo = rawStepUpRedirectTo >>= safePasskeyReturnPath
        when (isNothing stepUpRedirectTo) do
            if isHtmxRequest
                then do
                    setHeader ("HX-Redirect", cs (pathTo RosterWeeksAction))
                    renderPlain ""
                else redirectTo RosterWeeksAction
        passkeys <- fetchAuthenticatedUserPasskeys
        when (null passkeys) do
            if isHtmxRequest
                then do
                    setHeader ("HX-Redirect", cs (pathTo PasskeySetupAction))
                    renderPlain ""
                else redirectTo PasskeySetupAction
        respondHtml (renderStepUpDialog stepUpRedirectTo)

    action currentAction@PasskeySetupAction = runBepis currentAction BepisPageAction do
        rawRedirectTo <- getSession @Text passkeyStepUpRedirectSessionKey
        let passkeySetupRedirectTo = fromMaybe passkeyManagementPath (rawRedirectTo >>= safePasskeyReturnPath)
        render PasskeySetupView { .. }

    action currentAction@DismissMandatoryPasskeySetupAction = runBepis currentAction BepisMutationAction do
        deleteSession passkeyStepUpRedirectSessionKey
        setErrorMessage "Create a passkey before opening restricted admin pages."
        redirectTo RosterWeeksAction

    action currentAction@ShowPasskeySetupDialogAction = runBepis currentAction BepisDialogAction do
        let requestedRedirect = safeLocalRedirect (paramOrDefault @Text profileSecurityPath "successRedirect")
        let successRedirect = if currentUserIsSuperAdmin then passkeyManagementPath else requestedRedirect
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
        let managementPath = passkeyManagementPath
        passkeys <- fetchCurrentUserPasskeys
        when (null passkeys) do
            setErrorMessage "Add your first passkey before sending a new-device setup link."
            redirectToPath managementPath
        verified <- isCurrentUserPasskeyVerified
        unless verified do
            setSession passkeyStepUpRedirectSessionKey managementPath
            strongAuthenticationRequired <- currentUserRequiresMandatoryPasskey
            if isHtmxRequest
                then redirectTo ShowPasskeyStepUpDialogAction
                else do
                    setErrorMessage "Verify with your passkey before sending a new-device setup link."
                    if strongAuthenticationRequired
                        then redirectTo PasskeyStepUpAction
                        else redirectToPath managementPath
        let venueId = (.id) <$> currentVenueOrNothing
        void (issuePasskeySetupToken SelfNewDevicePasskeySetup currentUser (Just currentUser.id) venueId)
        setSuccessMessage "New-device passkey setup email queued. It should arrive shortly; open it on the device you want to add."
        if isHtmxRequest
            then do
                setHeader ("HX-Redirect", cs managementPath)
                renderPlain ""
            else redirectToPath managementPath

    action currentAction@DeletePasskeyAction { passkeyId } = runBepis currentAction BepisMutationAction do
        passkey <- fetch passkeyId
        accessDeniedUnless (passkey.userId == unpackId currentUser.id)
        passkeyCount <-
            query @Passkey
                |> filterWhere (#userId, unpackId currentUser.id)
                |> fetchCount
        strongAuthenticationRequired <- currentUserRequiresMandatoryPasskey
        let managementPath = passkeyManagementPath
        when (strongAuthenticationRequired && passkeyCount <= 1) do
            setErrorMessage "Venue admins and owners must keep at least one passkey on their account."
            redirectToPath managementPath
        ensureFreshPasskeyForManagement managementPath

        deleteRecord passkey
        setSuccessMessage "Passkey removed."
        redirectToPath managementPath

passkeysActionAllowsOwnerImpersonation :: PasskeysController -> Bool
passkeysActionAllowsOwnerImpersonation PasskeyStepUpAction = True
passkeysActionAllowsOwnerImpersonation ShowPasskeyStepUpDialogAction = True
passkeysActionAllowsOwnerImpersonation PasskeySetupAction = True
passkeysActionAllowsOwnerImpersonation DismissMandatoryPasskeySetupAction = True
passkeysActionAllowsOwnerImpersonation _ = False

safeLocalRedirect :: Text -> Text
safeLocalRedirect value
    | "/" `Text.isPrefixOf` value && not ("//" `Text.isPrefixOf` value) = value
    | otherwise = profileSecurityPath

ensureFreshPasskeyForManagement :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Text -> IO ()
ensureFreshPasskeyForManagement managementPath = do
    verified <- isCurrentUserPasskeyVerified
    unless verified do
        withRequestContext do
            setSession passkeyStepUpRedirectSessionKey managementPath
            if isHtmxRequest
                then redirectTo ShowPasskeyStepUpDialogAction
                else do
                    setErrorMessage "Verify with your passkey before changing passkey settings."
                    redirectTo PasskeyStepUpAction
