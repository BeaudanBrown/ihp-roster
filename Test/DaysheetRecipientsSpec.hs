module Test.DaysheetRecipientsSpec where

import Application.Daysheet.Authority (memberAccess)
import qualified Application.Daysheet.Contract as D
import Application.Daysheet.Recipients
import Application.Daysheet.References (ReferenceData (..))
import Application.Daysheet.Storage
import Application.EmailDelivery.Envelope (ExternalRecipient (..), ExternalEmailPayload (..))
import Application.EmailDelivery
import Application.Daysheet.EmailContract
import Application.Async.Boundary (throwAppJobError)
import Application.Async.Error (AppJobError (JobConfigurationUnavailable))
import Config
import Control.Exception (SomeException, try)
import qualified Data.Aeson as Aeson
import IHP.FrameworkConfig (withFrameworkConfig)
import Test.Support.EmailDelivery
import Web.Mail.DaysheetReport (ReportMailContent (..))
import Application.Error.Types (appErrorCode)
import Control.Concurrent.Async (withAsync, wait)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Data.IORef
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import Generated.Types
import IHP.ControllerPrelude
import IHP.Test.Mocking
import System.Timeout (timeout)
import Test.Hspec
import Test.Support

reportKey :: D.ReportId
reportKey = D.ReportId UUID.nil

setup :: (?modelContext :: ModelContext) => IO (VenueMembership, DaysheetDefinitionVersion)
setup = do
    venue <- createVenueWithConfig "Report recipients"
    user <- createUserRecord "report-owner@example.test" "admin" True
    member <- createVenueMembershipRecord venue user VenueOwner
    let definition = D.Definition 1 [] [] [] [D.Report reportKey "Daily report" [] [D.FormattedReport]]
    Right _ <- saveDraft (memberAccess member) 0 Nothing definition (ReferenceData [])
    Right version <- publishDraft (memberAccess member) 0 0
    pure (member, version)

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Daysheet external report recipients" do
        it "adds scoped identities without creating accounts or retroactive mail" $ withContext do
            withCleanDb do
                (member, version) <- setup
                usersBefore <- query @User |> fetchCount
                jobsBefore <- query @AppJob |> filterWhere (#jobKind, "email_delivery") |> fetchCount
                Right recipient <- addReportRecipient (memberAccess member) version.id reportKey " External@Example.test "
                recipient.address `shouldBe` "external@example.test"
                Right repeated <- addReportRecipient (memberAccess member) version.id reportKey "external@example.test"
                repeated.id `shouldBe` recipient.id
                query @User |> fetchCount >>= (`shouldBe` usersBefore)
                query @AppJob |> filterWhere (#jobKind, "email_delivery") |> fetchCount >>= (`shouldBe` jobsBefore)
                Right recipients <- readReportRecipients (memberAccess member) reportKey
                map (.id) recipients `shouldBe` [recipient.id]
        it "denies managers and foreign reports while allowing owner management" $ withContext do
            withCleanDb do
                (member, version) <- setup
                Right recipient <- addReportRecipient (memberAccess member) version.id reportKey "external@example.test"
                let invalidReport = D.ReportId (UUID.fromWords 0 0 0 1)
                unknown <- addReportRecipient (memberAccess member) version.id invalidReport "other@example.test"
                either (Text.isSuffixOf "/unknown-report" . appErrorCode) (const False) unknown `shouldBe` True
                other <- createVenueWithConfig "Other venue"
                forged <- addReportRecipient (memberAccess (member |> set #venueId (unpackId other.id))) version.id reportKey "other@example.test"
                either (Text.isSuffixOf "/access-denied" . appErrorCode) (const False) forged `shouldBe` True
                _ <- member |> set #venueRole Manager |> updateRecord
                denied <- addReportRecipient (memberAccess member) version.id reportKey "manager@example.test"
                either (Text.isSuffixOf "/access-denied" . appErrorCode) (const False) denied `shouldBe` True
                deniedRemoval <- removeReportRecipient (memberAccess member) reportKey recipient.id
                either (Text.isSuffixOf "/access-denied" . appErrorCode) (const False) deniedRemoval `shouldBe` True
                Right visible <- readReportRecipients (memberAccess member) reportKey
                map (.id) visible `shouldBe` [recipient.id]
                _ <- member |> set #isActive False |> updateRecord
                deniedRead <- readReportRecipients (memberAccess member) reportKey
                either (Text.isSuffixOf "/access-denied" . appErrorCode) (const False) deniedRead `shouldBe` True
        it "rejects malformed destinations and identity/address substitution" $ withContext do
            withCleanDb do
                (member, version) <- setup
                forM_ ["not an address", "external@example.test\r\nBcc: other@example.test", "<external@example.test>"] \address -> do
                    result <- addReportRecipient (memberAccess member) version.id reportKey address
                    either (Text.isSuffixOf "/invalid-address" . appErrorCode) (const False) result `shouldBe` True
                Right recipient <- addReportRecipient (memberAccess member) version.id reportKey "external@example.test"
                withEligibleReportRecipient (recipientIdentity recipient) "other@example.test" (pure ()) `shouldReturn` Left RecipientIdentityMismatch
                let foreignIdentity = (recipientIdentity recipient) { externalVenueId = UUID.fromWords 0 0 0 99 }
                withEligibleReportRecipient foreignIdentity recipient.address (pure ()) `shouldReturn` Left RecipientMissing
        it "keeps old retries cancelled after removing and re-adding an address" $ withContext do
            withCleanDb do
                (member, version) <- setup
                Right original <- addReportRecipient (memberAccess member) version.id reportKey "external@example.test"
                withEligibleReportRecipient (recipientIdentity original) original.address (pure ()) `shouldReturn` Right ()
                Right _ <- removeReportRecipient (memberAccess member) reportKey original.id
                Right replacement <- addReportRecipient (memberAccess member) version.id reportKey original.address
                replacement.id `shouldNotBe` original.id
                withEligibleReportRecipient (recipientIdentity original) original.address (pure ()) `shouldReturn` Left RecipientRemoved
                withEligibleReportRecipient (recipientIdentity replacement) replacement.address (pure ()) `shouldReturn` Right ()
        it "delivers v2 through the shared transport and permanently deduplicates the frozen event" $ withContext do
            withCleanDb do
                (member, version) <- setup
                Right recipient <- addReportRecipient (memberAccess member) version.id reportKey "external@example.test"
                let payload = ExternalEmailPayload daysheetReportMailKind (recipientIdentity recipient) recipient.address (UUID.fromWords 0 0 0 101)
                EnqueuedEmailDelivery queued <- enqueueExternalEmailDeliveryWithStatus payload (Just member.userId)
                queued.payloadSchemaVersion `shouldBe` 2
                calls <- newIORef (0 :: Int)
                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performEmailDeliveryJobWithReportResolver
                        (capturingEmailDeliveryRuntime (const (modifyIORef' calls (+ 1))))
                        (\_ -> pure (Just (ReportMailContent "Frozen report" mempty "Frozen selected content"))) queued
                readIORef calls `shouldReturn` 1
                completed <- fetch queued.id
                completed.status `shouldBe` JobStatusSucceeded
                completed.result `shouldBe` Aeson.object ["deliveryStatus" Aeson..= ("sent" :: Text), "mailKind" Aeson..= daysheetReportMailKind, "domainReferenceId" Aeson..= payload.externalDomainReferenceId]
                Text.isInfixOf recipient.address (tshow completed.result) `shouldBe` False
                ExistingEmailDelivery repeated <- enqueueExternalEmailDeliveryWithStatus payload (Just member.userId)
                repeated.id `shouldBe` queued.id
        it "cancels a queued external send before resolving or transporting report content" $ withContext do
            withCleanDb do
                (member, version) <- setup
                Right recipient <- addReportRecipient (memberAccess member) version.id reportKey "external@example.test"
                let payload = ExternalEmailPayload daysheetReportMailKind (recipientIdentity recipient) recipient.address (UUID.fromWords 0 0 0 102)
                EnqueuedEmailDelivery queued <- enqueueExternalEmailDeliveryWithStatus payload Nothing
                Right _ <- removeReportRecipient (memberAccess member) reportKey recipient.id
                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performEmailDeliveryJobWithReportResolver
                        (capturingEmailDeliveryRuntime (const (expectationFailure "removed recipient must not reach transport")))
                        (\_ -> expectationFailure "removed recipient must not resolve content" >> pure Nothing) queued
                completed <- fetch queued.id
                completed.result `shouldBe` Aeson.object ["deliveryStatus" Aeson..= ("delivery_skipped" :: Text), "mailKind" Aeson..= daysheetReportMailKind, "domainReferenceId" Aeson..= payload.externalDomainReferenceId, "reason" Aeson..= ("recipient_removed" :: Text)]
        it "uses the shared safe retry boundary and fails closed without a report resolver" $ withContext do
            withCleanDb do
                (member, version) <- setup
                Right recipient <- addReportRecipient (memberAccess member) version.id reportKey "external@example.test"
                let payload = ExternalEmailPayload daysheetReportMailKind (recipientIdentity recipient) recipient.address (UUID.fromWords 0 0 0 103)
                EnqueuedEmailDelivery queued <- enqueueExternalEmailDeliveryWithStatus payload Nothing
                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    missingResolver <- try @SomeException (performEmailDeliveryJobWithReportResolver enabledEmailDeliveryRuntime
                        (\_ -> throwAppJobError JobConfigurationUnavailable) queued)
                    either (const True) (const False) missingResolver `shouldBe` True
                    failed <- try @SomeException (performEmailDeliveryJobWithReportResolver
                        (failingEmailDeliveryRuntime "private SMTP diagnostic external@example.test")
                        (\_ -> pure (Just (ReportMailContent "Frozen report" mempty "Frozen content"))) queued)
                    either (\error -> not (Text.isInfixOf recipient.address (tshow error))) (const False) failed `shouldBe` True
                    performEmailDeliveryJobWithReportResolver enabledEmailDeliveryRuntime
                        (\_ -> pure (Just (ReportMailContent "Frozen report" mempty "Frozen content"))) queued
                completed <- fetch queued.id
                completed.status `shouldBe` JobStatusSucceeded
        it "makes the irreversible in-flight boundary explicit and cancels later attempts" $ withContext do
            withCleanDb do
                (member, version) <- setup
                Right recipient <- addReportRecipient (memberAccess member) version.id reportKey "external@example.test"
                started <- newEmptyMVar
                finish <- newEmptyMVar
                attempts <- newIORef (0 :: Int)
                withAsync (withEligibleReportRecipient (recipientIdentity recipient) recipient.address do
                    modifyIORef' attempts (+ 1)
                    putMVar started ()
                    takeMVar finish) \delivery -> do
                    takeMVar started
                    withAsync (removeReportRecipient (memberAccess member) reportKey recipient.id) \removal -> do
                        timeout 100000 (wait removal) >>= (`shouldBe` Nothing)
                        putMVar finish ()
                        wait delivery `shouldReturn` Right ()
                        Right removed <- wait removal
                        removed.removedAt `shouldSatisfy` isJust
                        withEligibleReportRecipient (recipientIdentity recipient) recipient.address (modifyIORef' attempts (+ 1)) `shouldReturn` Left RecipientRemoved
                        readIORef attempts `shouldReturn` 1
