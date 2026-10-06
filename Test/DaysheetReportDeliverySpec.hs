module Test.DaysheetReportDeliverySpec where

import qualified Application.Daysheet.Contract as D
import qualified Application.Daysheet.Daily as Daily
import Application.Daysheet.DailyStorage
import Application.Daysheet.EmailContract
import Application.Daysheet.Recipients
import Application.Daysheet.ReportDelivery
import Application.Daysheet.ReportStorage
import Application.EmailDelivery
import Application.EmailDelivery.Envelope
import Config
import Control.Exception (SomeException, try)
import Data.IORef
import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import qualified Data.Text.Lazy as LazyText
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig (withFrameworkConfig)
import qualified IHP.HSX.Markup as Markup
import qualified IHP.MailPrelude as Mail
import IHP.Test.Mocking
import Test.DaysheetReportStorageSpec (setup, reportKey, nonce)
import Test.Hspec
import Test.Support
import Test.Support.EmailDelivery
import qualified Test.Support.Daysheet as Fixture

readPayload :: AppJob -> IO ExternalEmailPayload
readPayload job = case Aeson.fromJSON job.payload of
    Aeson.Success payload -> pure payload
    Aeson.Error _ -> expectationFailure "Expected a shared v2 envelope" >> fail "invalid fixture envelope"

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Daysheet frozen report delivery" do
        it "uses the installed production resolver and keeps retries byte-identical after live corrections" $ withContext do
            withCleanDb do
                (owner, manager, version, state) <- setup
                Right _ <- addReportRecipient owner version.id reportKey "external@example.test"
                Right _ <- editDailyCell manager state.daysheet.id (Daily.RootCell (Fixture.field 1)) 0 (Fixture.text "<script>captured</script>")
                Right _ <- submitDailySheet manager state.daysheet.id
                Right snapshot <- captureManualReport manager state.daysheet.id reportKey (nonce 1)
                queued <- query @AppJob |> filterWhere (#relatedId, Just (unpackId snapshot.id)) |> fetchOne
                bodies <- newIORef ([] :: [(Text, Text)])
                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    let record :: Mail.BuildMail mail => mail -> IO ()
                        record mail = modifyIORef' bodies (<> [(LazyText.toStrict (Markup.renderMarkupLazyText (Mail.html mail)), Mail.text mail)])
                    failed <- try @SomeException (performEmailDeliveryJobWith
                        (capturingEmailDeliveryRuntime (\mail -> record mail >> ioError (userError "private provider failure"))) queued)
                    either (const True) (const False) failed `shouldBe` True
                    Right _ <- editDailyCell manager state.daysheet.id (Daily.RootCell (Fixture.field 1)) 1 (Fixture.text "Later correction")
                    performEmailDeliveryJobWith (capturingEmailDeliveryRuntime record) queued
                [first, retried] <- readIORef bodies
                first `shouldBe` retried
                fst first `shouldSatisfy` Text.isInfixOf "&lt;script&gt;captured&lt;/script&gt;"
                fst first `shouldSatisfy` (not . Text.isInfixOf "<script>")
                snd first `shouldSatisfy` Text.isInfixOf "Manual frozen report"
                snd first `shouldSatisfy` Text.isInfixOf "Unavailable:"
                snd first `shouldSatisfy` (not . Text.isInfixOf "Later correction")
                completed <- fetch queued.id
                completed.status `shouldBe` JobStatusSucceeded
                completed.result `shouldBe` Aeson.object ["deliveryStatus" Aeson..= ("sent" :: Text), "mailKind" Aeson..= daysheetReportMailKind, "domainReferenceId" Aeson..= unpackId snapshot.id]
        it "requires the exact captured recipient, address, venue and report" $ withContext do
            withCleanDb do
                (owner, manager, version, state) <- setup
                Right recipient <- addReportRecipient owner version.id reportKey "captured@example.test"
                Right _ <- submitDailySheet manager state.daysheet.id
                Right snapshot <- captureManualReport manager state.daysheet.id reportKey (nonce 1)
                queued <- query @AppJob |> filterWhere (#relatedId, Just (unpackId snapshot.id)) |> fetchOne
                payload <- readPayload queued
                isJust <$> resolveFrozenReport payload `shouldReturn` True
                Right later <- addReportRecipient owner version.id reportKey "later@example.test"
                let forged = payload { externalRecipient = recipientIdentity later, externalRecipientAddress = later.address }
                isNothing <$> resolveFrozenReport forged `shouldReturn` True
                isNothing <$> resolveFrozenReport (payload { externalRecipientAddress = "other@example.test" }) `shouldReturn` True
                let foreignVenue = payload { externalRecipient = (recipientIdentity recipient) { externalVenueId = nonce 999 } }
                isNothing <$> resolveFrozenReport foreignVenue `shouldReturn` True
                let wrongReport = payload { externalRecipient = (recipientIdentity recipient) { externalReportId = nonce 999 } }
                isNothing <$> resolveFrozenReport wrongReport `shouldReturn` True
                query @AppJob |> filterWhere (#relatedId, Just (unpackId snapshot.id)) |> fetchCount >>= (`shouldBe` 1)
        it "cancels retry after removal even when the same address is re-added" $ withContext do
            withCleanDb do
                (owner, manager, version, state) <- setup
                Right recipient <- addReportRecipient owner version.id reportKey "removed@example.test"
                Right _ <- submitDailySheet manager state.daysheet.id
                Right snapshot <- captureManualReport manager state.daysheet.id reportKey (nonce 1)
                queued <- query @AppJob |> filterWhere (#relatedId, Just (unpackId snapshot.id)) |> fetchOne
                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    failed <- try @SomeException (performEmailDeliveryJobWith (failingEmailDeliveryRuntime "private failure") queued)
                    either (const True) (const False) failed `shouldBe` True
                    Right _ <- removeReportRecipient owner reportKey recipient.id
                    Right replacement <- addReportRecipient owner version.id reportKey recipient.address
                    replacement.id `shouldNotBe` recipient.id
                    performEmailDeliveryJobWith (capturingEmailDeliveryRuntime (\_ -> expectationFailure "Removed identity must not reach transport")) queued
                completed <- fetch queued.id
                completed.result `shouldBe` Aeson.object ["deliveryStatus" Aeson..= ("delivery_skipped" :: Text), "mailKind" Aeson..= daysheetReportMailKind, "domainReferenceId" Aeson..= unpackId snapshot.id, "reason" Aeson..= ("recipient_removed" :: Text)]
                query @AppJob |> filterWhere (#relatedId, Just (unpackId snapshot.id)) |> fetchCount >>= (`shouldBe` 1)
        it "skips absent frozen references rather than rendering the current Daysheet" $ withContext do
            withCleanDb do
                (owner, _, version, _) <- setup
                Right recipient <- addReportRecipient owner version.id reportKey "missing@example.test"
                let payload = ExternalEmailPayload daysheetReportMailKind (recipientIdentity recipient) recipient.address (nonce 999)
                EnqueuedEmailDelivery queued <- enqueueExternalEmailDeliveryWithStatus payload Nothing
                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performEmailDeliveryJobWith (capturingEmailDeliveryRuntime (\_ -> expectationFailure "Missing frozen report must not reach transport")) queued
                completed <- fetch queued.id
                completed.result `shouldBe` Aeson.object ["deliveryStatus" Aeson..= ("delivery_skipped" :: Text), "mailKind" Aeson..= daysheetReportMailKind, "domainReferenceId" Aeson..= nonce 999, "reason" Aeson..= ("domain_reference_missing" :: Text)]
