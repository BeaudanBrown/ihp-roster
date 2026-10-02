module Test.DaysheetRecipientsSpec where

import qualified Application.Daysheet.Contract as D
import Application.Daysheet.Recipients
import Application.Daysheet.References (ReferenceData (..))
import Application.Daysheet.Storage
import Application.EmailDelivery.Envelope (ExternalRecipient (..))
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
    Right _ <- saveDraft member 0 Nothing definition (ReferenceData [])
    Right version <- publishDraft member 0 0
    pure (member, version)

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Daysheet external report recipients" do
        it "adds scoped identities without creating accounts or retroactive mail" $ withContext do
            withCleanDb do
                (member, version) <- setup
                usersBefore <- query @User |> fetchCount
                jobsBefore <- query @AppJob |> filterWhere (#jobKind, "email_delivery") |> fetchCount
                Right recipient <- addReportRecipient member version.id reportKey " External@Example.test "
                recipient.address `shouldBe` "external@example.test"
                Right repeated <- addReportRecipient member version.id reportKey "external@example.test"
                repeated.id `shouldBe` recipient.id
                query @User |> fetchCount >>= (`shouldBe` usersBefore)
                query @AppJob |> filterWhere (#jobKind, "email_delivery") |> fetchCount >>= (`shouldBe` jobsBefore)
                recipients <- activeReportRecipients member.venueId reportKey
                map (.id) recipients `shouldBe` [recipient.id]
        it "denies managers and foreign reports while allowing owner management" $ withContext do
            withCleanDb do
                (member, version) <- setup
                Right recipient <- addReportRecipient member version.id reportKey "external@example.test"
                let invalidReport = D.ReportId (UUID.fromWords 0 0 0 1)
                unknown <- addReportRecipient member version.id invalidReport "other@example.test"
                either (Text.isSuffixOf "/unknown-report" . appErrorCode) (const False) unknown `shouldBe` True
                other <- createVenueWithConfig "Other venue"
                forged <- addReportRecipient (member |> set #venueId (unpackId other.id)) version.id reportKey "other@example.test"
                either (Text.isSuffixOf "/access-denied" . appErrorCode) (const False) forged `shouldBe` True
                _ <- member |> set #venueRole Manager |> updateRecord
                denied <- addReportRecipient member version.id reportKey "manager@example.test"
                either (Text.isSuffixOf "/access-denied" . appErrorCode) (const False) denied `shouldBe` True
                deniedRemoval <- removeReportRecipient member reportKey recipient.id
                either (Text.isSuffixOf "/access-denied" . appErrorCode) (const False) deniedRemoval `shouldBe` True
        it "rejects malformed destinations and identity/address substitution" $ withContext do
            withCleanDb do
                (member, version) <- setup
                forM_ ["not an address", "external@example.test\r\nBcc: other@example.test", "<external@example.test>"] \address -> do
                    result <- addReportRecipient member version.id reportKey address
                    either (Text.isSuffixOf "/invalid-address" . appErrorCode) (const False) result `shouldBe` True
                Right recipient <- addReportRecipient member version.id reportKey "external@example.test"
                withEligibleReportRecipient (recipientIdentity recipient) "other@example.test" (pure ()) `shouldReturn` Left RecipientIdentityMismatch
                let foreignIdentity = (recipientIdentity recipient) { externalVenueId = UUID.fromWords 0 0 0 99 }
                withEligibleReportRecipient foreignIdentity recipient.address (pure ()) `shouldReturn` Left RecipientMissing
        it "keeps old retries cancelled after removing and re-adding an address" $ withContext do
            withCleanDb do
                (member, version) <- setup
                Right original <- addReportRecipient member version.id reportKey "external@example.test"
                withEligibleReportRecipient (recipientIdentity original) original.address (pure ()) `shouldReturn` Right ()
                Right _ <- removeReportRecipient member reportKey original.id
                Right replacement <- addReportRecipient member version.id reportKey original.address
                replacement.id `shouldNotBe` original.id
                withEligibleReportRecipient (recipientIdentity original) original.address (pure ()) `shouldReturn` Left RecipientRemoved
                withEligibleReportRecipient (recipientIdentity replacement) replacement.address (pure ()) `shouldReturn` Right ()
        it "makes the irreversible in-flight boundary explicit and cancels later attempts" $ withContext do
            withCleanDb do
                (member, version) <- setup
                Right recipient <- addReportRecipient member version.id reportKey "external@example.test"
                started <- newEmptyMVar
                finish <- newEmptyMVar
                attempts <- newIORef (0 :: Int)
                withAsync (withEligibleReportRecipient (recipientIdentity recipient) recipient.address do
                    modifyIORef' attempts (+ 1)
                    putMVar started ()
                    takeMVar finish) \delivery -> do
                    takeMVar started
                    withAsync (removeReportRecipient member reportKey recipient.id) \removal -> do
                        timeout 100000 (wait removal) >>= (`shouldBe` Nothing)
                        putMVar finish ()
                        wait delivery `shouldReturn` Right ()
                        Right removed <- wait removal
                        removed.removedAt `shouldSatisfy` isJust
                        withEligibleReportRecipient (recipientIdentity recipient) recipient.address (modifyIORef' attempts (+ 1)) `shouldReturn` Left RecipientRemoved
                        readIORef attempts `shouldReturn` 1
