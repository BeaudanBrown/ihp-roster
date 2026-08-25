module Test.WageSourceEnforcementSpec where

import Application.EmailDelivery
import Application.Helper.Mail (AppMailSettings (..))
import Application.Helper.XeroTimesheetReadiness (XeroReadinessBlocker (..),
                                                   xeroWageFailureBlockers)
import Application.WageSourceEnforcement
import Application.WageSourceNotification.Email
import Application.WageSourceNotifications (emitLatestAwardDriftNotifications)
import Application.WageSourcePolicy (AwardDriftKind (AwardClassificationStructureChanged),
                                     PolicyClock (..), SourceDiagnostic (..))
import Config (config)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as AesonTypes
import Data.Either (isLeft, isRight)
import Data.IORef
import qualified Data.Text as Text
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime, addUTCTime, getCurrentTime)
import Data.UUID (UUID)
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig (withFrameworkConfig)
import IHP.Prelude
import IHP.Test.Mocking (withContext)
import Test.Hspec
import Test.Support
import Web.Mail.WageSourceDrift (WageSourceDriftMail (..))

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Wage source workflow enforcement" do
        it "keeps successful mixed draft previews while reporting entry-local source and calculation failures" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Wage Source Draft Venue"
                approver <- createUserRecord "wage-source-approver@example.com" "staff" True
                awardStaff <- createStaffRecord venue Nothing "Award" "Worker"
                importedStaff <- createStaffRecord venue Nothing "Imported" "Worker"
                importedItem <- createImportedXeroPayItemRecord venue approver "Imported Ordinary" "imported-ordinary" 42
                importedStaff <- importedStaff
                    |> set #payAssignmentMode XeroRate
                    |> set #importedXeroPayItemId (Just importedItem.id)
                    |> updateRecord
                now <- getCurrentTime
                awardEntry <- createApprovedTimesheetEntryRecordAt venue awardStaff approver (fromGregorian 2026 5 4) now
                importedEntry <- createApprovedTimesheetEntryRecordAt venue importedStaff approver (fromGregorian 2026 5 4) now
                validImportedDraft <- createTimesheetEntryRecord venue importedStaff (fromGregorian 2026 5 5)
                invalidShiftType <- newRecord @ShiftType
                    |> set #venueId (unpackId venue.id)
                    |> set #name ("Missing Award classification" :: Text)
                    |> set #sortOrder 99
                    |> set #overrideAwardLevelId Nothing
                    |> set #isActive True
                    |> createRecord
                invalidDraft <- createTimesheetEntryRecord venue awardStaff (fromGregorian 2026 5 5)
                    >>= updateRecord . set #shiftTypeId (unpackId invalidShiftType.id)
                let clock = PolicyClock (addUTCTime (9 * 24 * 60 * 60) now)
                    mixedEntries = [awardEntry, importedEntry, validImportedDraft, invalidDraft]

                outcomes <- evaluateDraftWageEntriesAt clock mixedEntries

                length outcomes `shouldBe` 4
                let awardOutcome = outcomes !! 0
                    importedOutcome = outcomes !! 1
                    validImportedDraftOutcome = outcomes !! 2
                    invalidOutcome = outcomes !! 3
                awardOutcome.outcomeCalculation `shouldSatisfy` isRight
                awardOutcome.outcomeSourceDiagnostics `shouldSatisfy` any isFwcStale
                importedOutcome.outcomeCalculation `shouldSatisfy` isRight
                importedOutcome.outcomeSourceDiagnostics `shouldBe` []
                validImportedDraftOutcome.outcomeCalculation `shouldSatisfy` isRight
                validImportedDraftOutcome.outcomeSourceDiagnostics `shouldBe` []
                invalidOutcome.outcomeCalculation `shouldSatisfy` isLeft
                invalidOutcome.outcomeSourceDiagnostics `shouldBe` []

                enforceFinalWageEntriesAt clock mixedEntries >>= \case
                    Right _ -> expectationFailure "strict enforcement unexpectedly accepted a mixed failing batch"
                    Left failures -> do
                        length failures `shouldBe` 2
                        failures `shouldSatisfy` any isAwardSourceFailure
                        failures `shouldSatisfy` any isInvalidCalculationFailure

                unavailableItem <- importedItem
                    |> set #providerAvailable False
                    |> set #providerUnavailableAt (Just now)
                    |> updateRecord
                unavailableOutcomes <- evaluateDraftWageEntriesAt clock [importedEntry]
                case unavailableOutcomes of
                    [unavailableOutcome] ->
                        unavailableOutcome.outcomeCalculation `shouldSatisfy` either ("no longer available" `Text.isInfixOf`) (const False)
                    _ -> expectationFailure "expected one unavailable imported-pay outcome"

                _ <- unavailableItem
                    |> set #providerAvailable True
                    |> set #providerUnavailableAt Nothing
                    |> set #archivedAt (Just now)
                    |> set #archivedByUserId (Just (unpackId approver.id))
                    |> set #archiveReason (Just "test_archive")
                    |> updateRecord
                archivedOutcomes <- evaluateDraftWageEntriesAt clock [importedEntry]
                let archivedOutcome :: WageEntryOutcome
                    archivedOutcome = fromMaybe (error "missing archived outcome") (head archivedOutcomes)
                archivedOutcome.outcomeCalculation `shouldSatisfy` isLeft

        it "fails a payroll batch closed on corrupt Timesheet timing with an entry-local safe message" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Wage Source Corrupt Timing"
                approver <- createUserRecord "wage-source-corrupt-timing@example.com" "staff" True
                importedStaff <- createStaffRecord venue Nothing "Imported" "Worker"
                importedItem <- createImportedXeroPayItemRecord venue approver "Imported Ordinary" "imported-corrupt-timing" 42
                importedStaff <- importedStaff
                    |> set #payAssignmentMode XeroRate
                    |> set #importedXeroPayItemId (Just importedItem.id)
                    |> updateRecord
                now <- getCurrentTime
                entry <- createApprovedTimesheetEntryRecordAt venue importedStaff approver (fromGregorian 2026 5 5) now
                let corruptEntry = entry |> set #timezone "not-a-zone"

                enforcement <- enforceFinalWageEntries [corruptEntry]
                case enforcement of
                    Left [WageCalculationFailed entryId message] -> do
                        entryId `shouldBe` unpackId entry.id
                        message `shouldBe` "Timesheet timing is invalid and must be repaired before payroll."
                        message `shouldNotSatisfy` Text.isInfixOf "not-a-zone"
                    outcome -> expectationFailure ("Expected one corrupt-timing failure, got " <> cs (tshow outcome))
                case xeroWageFailureBlockers enforcement of
                    [blocker] -> do
                        blocker.xeroBlockerTimesheetEntryId `shouldBe` Just (unpackId entry.id)
                        blocker.xeroBlockerMessage `shouldSatisfy` Text.isInfixOf "Timesheet timing is invalid and must be repaired before payroll."
                        blocker.xeroBlockerMessage `shouldNotSatisfy` Text.isInfixOf "not-a-zone"
                    blockers -> expectationFailure ("Expected one Xero timing blocker, got " <> cs (tshow blockers))

        it "deduplicates Award drift notifications to active platform super admins only" $ withContext do
            withCleanDb do
                superAdmin <- createUserRecordWithPlatformRole "drift-super@example.com" "staff" (Just SuperAdmin) True
                _ordinaryUser <- createUserRecord "drift-ordinary@example.com" "staff" True
                now <- getCurrentTime
                seedFingerprintSnapshot now 1 "Hospitality level 1"
                seedFingerprintSnapshot (addUTCTime 1 now) 2 "Hospitality level one"

                first <- emitLatestAwardDriftNotifications
                second <- emitLatestAwardDriftNotifications

                length first `shouldBe` 3
                map (.id) second `shouldBe` map (.id) first
                jobs <- query @AppJob
                    |> filterWhere (#jobKind, emailDeliveryJobKind)
                    |> fetch
                length jobs `shouldBe` 3
                mapMaybe payloadRecipient jobs `shouldBe` replicate 3 (unpackId superAdmin.id)
                map (.payload) jobs `shouldSatisfy` all (not . Text.isInfixOf "expectedValue" . cs . Aeson.encode)
                deactivatedAt <- getCurrentTime
                _ <- superAdmin |> set #deactivatedAt (Just deactivatedAt) |> updateRecord
                deliveryCalls <- newIORef (0 :: Int)
                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    forM_ jobs $
                        performEmailDeliveryJobWith
                            EmailDeliveryRuntime
                                { deliveryIsDisabled = pure False
                                , deliverMail = \_ -> modifyIORef' deliveryCalls (+ 1)
                                }
                readIORef deliveryCalls `shouldReturn` 0
                completed <- query @AppJob |> filterWhere (#jobKind, emailDeliveryJobKind) |> fetch
                map (.result) completed `shouldSatisfy` all (Text.isInfixOf "recipient_ineligible" . cs . Aeson.encode)

        it "renders Award drift from its referenced fingerprint after a newer refresh" $ withContext do
            withCleanDb do
                superAdmin <- createUserRecordWithPlatformRole "drift-snapshot@example.com" "staff" (Just SuperAdmin) True
                now <- getCurrentTime
                seedFingerprintSnapshot now 1 "Hospitality level 1"
                seedFingerprintSnapshot (addUTCTime 1 now) 2 "Hospitality level one"
                jobs <- emitLatestAwardDriftNotifications
                seedFingerprintSnapshot (addUTCTime 2 now) 3 "Hospitality renamed later"
                let targetKind = awardDriftMailKind AwardClassificationStructureChanged
                let Just job = find ((== Just targetKind) . payloadMailKind) jobs
                let Just referenceId = payloadDomainReference job
                projection <-
                    loadAwardDriftMail
                        targetKind
                        (unpackId superAdmin.id)
                        superAdmin.email
                        referenceId
                        AppMailSettings
                            { mailFromAddress = "noreply@example.com"
                            , mailReplyToAddress = "support@example.com"
                            , mailSupportEmail = "support@example.com"
                            }
                case projection of
                    AwardDriftMailSkipped reason -> expectationFailure (cs reason)
                    AwardDriftMailReady mail -> do
                        mail.expectedValue `shouldSatisfy` Text.isInfixOf "Hospitality level 1"
                        mail.observedValue `shouldSatisfy` Text.isInfixOf "Hospitality level one"
                        mail.observedValue `shouldSatisfy` not . Text.isInfixOf "renamed later"
  where
    isFwcStale FwcSnapshotStale {} = True
    isFwcStale _                   = False
    isAwardSourceFailure WageSourcesBlocked {} = True
    isAwardSourceFailure _                     = False
    isInvalidCalculationFailure (WageCalculationFailed _ _) = True
    isInvalidCalculationFailure _                           = False

seedFingerprintSnapshot :: (?modelContext :: ModelContext) => UTCTime -> Int -> Text -> IO ()
seedFingerprintSnapshot syncedAt versionNumber classification = do
    _ <- newRecord @FwcMapdAward
        |> set #awardFixedId 9
        |> set #awardId 1760
        |> set #code ("MA000009" :: Text)
        |> set #name ("Hospitality Industry (General) Award 2020" :: Text)
        |> set #publishedYear (Just 2026)
        |> set #versionNumber (Just versionNumber)
        |> set #rawJson (Aeson.object ["version" Aeson..= versionNumber])
        |> set #syncedAt syncedAt
        |> createRecord
    void $ newRecord @FwcMapdClassification
        |> set #awardFixedId 9
        |> set #classificationFixedId 243
        |> set #classification classification
        |> set #syncedAt syncedAt
        |> createRecord

payloadRecipient :: AppJob -> Maybe UUID
payloadRecipient job = AesonTypes.parseMaybe (Aeson.withObject "payload" (Aeson..: "recipientAccountId")) job.payload

payloadMailKind :: AppJob -> Maybe Text
payloadMailKind job = AesonTypes.parseMaybe (Aeson.withObject "payload" (Aeson..: "mailKind")) job.payload

payloadDomainReference :: AppJob -> Maybe UUID
payloadDomainReference job = AesonTypes.parseMaybe (Aeson.withObject "payload" (Aeson..: "domainReferenceId")) job.payload
