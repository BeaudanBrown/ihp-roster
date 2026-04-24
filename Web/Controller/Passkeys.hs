module Web.Controller.Passkeys where

import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import Web.Controller.Prelude

instance Controller PasskeysController where
    beforeAction = ensureIsUser

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

        deleteRecord passkey
        setSuccessMessage "Passkey removed."
        if currentUserIsSuperAdmin
            then redirectTo SupportAction
            else redirectTo EditProfileAction
