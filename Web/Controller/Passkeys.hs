module Web.Controller.Passkeys where

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

    action UpdatePasskeyNameAction { passkeyId } = do
        passkey <- fetch passkeyId
        accessDeniedUnless (passkey.userId == unpackId currentUser.id)
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
