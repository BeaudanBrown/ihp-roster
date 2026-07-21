module Test.PasskeySpec where

import Application.Helper.FrontendContract.Passkey.Runtime
import Control.Exception (evaluate)
import qualified Data.Text as Text
import IHP.Prelude
import Test.Hspec

tests :: Spec
tests = describe "Passkey contract runtime" do
    it "renders an exact generated login flow with a mount-local status relationship" do
        passkeyLoginAttrs "/begin" "/finish" (Just "/after")
            `shouldBe`
                [ ("data-bepis-passkey-login", "true")
                , ( "data-bepis-passkey-flow-config"
                  , "{\"beginUrl\":\"/begin\",\"cancelledMessage\":\"No passkey was selected.\",\"failureMessage\":\"Passkey request failed.\",\"finishUrl\":\"/finish\",\"pendingLabel\":\"Please wait\",\"statusKey\":\"status\",\"successMessage\":\"Signed in.\",\"successRedirect\":\"/after\",\"tag\":\"login\",\"unsupportedMessage\":\"Passkeys are not supported in this browser.\",\"waitingMessage\":\"Waiting for your passkey...\"}"
                  )
                ]
        passkeyActionButtonAttrs
            `shouldBe` [("data-bepis-passkey-action-button", "true")]
        passkeyStatusAttrs
            `shouldBe` [("data-bepis-passkey-status", "status")]

    it "renders exact registration, recovery, and closed setup-prompt roles" do
        passkeyRegistrationAttrs "/register" "/finish-registration" Nothing
            `shouldBe`
                [ ("data-bepis-passkey-registration", "true")
                , ( "data-bepis-passkey-flow-config"
                  , "{\"beginUrl\":\"/register\",\"cancelledMessage\":\"Passkey registration was cancelled.\",\"failureMessage\":\"Passkey request failed.\",\"finishUrl\":\"/finish-registration\",\"pendingLabel\":\"Please wait\",\"statusKey\":\"status\",\"successMessage\":\"Passkey added.\",\"tag\":\"registration\",\"unsupportedMessage\":\"Passkeys are not supported in this browser.\",\"waitingMessage\":\"Waiting for your passkey...\"}"
                  )
                ]
        passkeySetupPromptAttrs "user-1" PasskeyAdditionalDevice
            `shouldBe`
                [ ("data-bepis-passkey-setup-prompt", "true")
                , ("data-bepis-passkey-flow-config", "{\"promptUserKey\":\"user-1\",\"setupPromptMode\":\"additional-device\",\"tag\":\"setup-prompt\"}")
                ]
        passkeyDeviceNameAttrs
            `shouldBe` [("data-bepis-passkey-device-name", "true")]
        passkeyRecoveryAttrs
            `shouldBe` [("data-bepis-passkey-recovery", "status")]
        passkeyDismissalAttrs
            `shouldBe` [("data-bepis-passkey-dismissal", "true")]
        fmap passkeySetupPromptModeValue [PasskeyFirstPasskey, PasskeyAdditionalDevice]
            `shouldBe` ["first-passkey", "additional-device"]

    it "rejects empty Haskell-owned flow URLs before rendering browser configuration" do
        evaluate (attrsTextLength (passkeyLoginAttrs " " "/finish" Nothing))
            `shouldThrow` errorCall "Passkey begin URL must not be empty"
        evaluate (attrsTextLength (passkeyRegistrationAttrs "/begin" "" Nothing))
            `shouldThrow` errorCall "Passkey finish URL must not be empty"

    it "rejects empty optional redirects and prompt user keys" do
        evaluate (attrsTextLength (passkeyRegistrationAttrs "/begin" "/finish" (Just " ")))
            `shouldThrow` errorCall "Passkey success redirect must not be empty"
        evaluate (attrsTextLength (passkeySetupPromptAttrs "" PasskeyFirstPasskey))
            `shouldThrow` errorCall "Passkey prompt user key must not be empty"

attrsTextLength :: [(Text, Text)] -> Int
attrsTextLength = Text.length . Text.concat . fmap snd
