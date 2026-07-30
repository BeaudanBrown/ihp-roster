module Test.WageSourceEnforcementSpec where

import Application.Helper.Controller (PlatformRole (SuperAdminRole))
import Application.WageSourceEnforcement
import Application.WageSourceNotifications (emitLatestAwardDriftNotifications,
                                            wageSourceDriftNotificationJobKind)
import Application.WageSourcePolicy (PolicyClock (..), SourceDiagnostic (..))
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as AesonTypes
import Data.Either (isLeft, isRight)
import qualified Data.Text as Text
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime, addUTCTime, getCurrentTime)
import Data.UUID (UUID)
import Generated.Types
import IHP.ControllerPrelude
import IHP.Prelude
import IHP.Test.Mocking (withContext)
import Test.Hspec
import Test.Support

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

        it "deduplicates Award drift notifications to active platform super admins only" $ withContext do
            withCleanDb do
                superAdmin <- createUserRecordWithPlatformRole "drift-super@example.com" "staff" (Just SuperAdminRole) True
                _ordinaryUser <- createUserRecord "drift-ordinary@example.com" "staff" True
                now <- getCurrentTime
                seedFingerprintSnapshot now 1 "Hospitality level 1"
                seedFingerprintSnapshot (addUTCTime 1 now) 2 "Hospitality level one"

                first <- emitLatestAwardDriftNotifications
                second <- emitLatestAwardDriftNotifications

                length first `shouldBe` 3
                map (.id) second `shouldBe` map (.id) first
                jobs <- query @AppJob
                    |> filterWhere (#jobKind, wageSourceDriftNotificationJobKind)
                    |> fetch
                length jobs `shouldBe` 3
                mapMaybe payloadRecipient jobs `shouldBe` replicate 3 (unpackId superAdmin.id)
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
payloadRecipient job = AesonTypes.parseMaybe (Aeson.withObject "payload" (Aeson..: "userId")) job.payload
