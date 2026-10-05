module Test.DaysheetDailyStorageSpec where

import qualified Application.Daysheet.Contract as D
import qualified Application.Daysheet.Daily as Daily
import Application.Daysheet.DailyStorage
import Application.Daysheet.ReferenceCodec
import Application.Daysheet.References
import Application.Daysheet.Storage
import Control.Concurrent.Async (concurrently)
import Control.Exception (SomeException, try)
import Data.Either (isLeft, isRight)
import Generated.Types
import IHP.ControllerPrelude
import IHP.Test.Mocking
import qualified Test.Support.Daysheet as Fixture
import Test.DaysheetStorageSpec (errorSuffix)
import Test.Hspec
import Test.Support

setup :: (?modelContext :: ModelContext) => IO (VenueMembership, VenueMembership)
setup = do
    venue <- createVenueWithConfig "Daily lifecycle"
    ownerUser <- createUserRecord "daily-owner@example.test" "admin" True
    managerUser <- createUserRecord "daily-manager@example.test" "manager" True
    owner <- createVenueMembershipRecord venue ownerUser VenueOwner
    manager <- createVenueMembershipRecord venue managerUser Manager
    Right _ <- saveDraft owner 0 Nothing Fixture.definition Fixture.references
    Right _ <- publishDraft owner 0 0
    pure (owner, manager)

day :: Day
day = fromGregorian 2026 10 1

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Daysheet daily persistence" do
        it "never creates on reads and serializes explicit concurrent creation" $ withContext do
            withCleanDb do
                (owner, manager) <- setup
                Right Nothing <- readDailyForDate manager day
                query @Daysheet |> fetchCount >>= (`shouldBe` 0)
                query @DaysheetDefinitionCapture |> fetchCount >>= (`shouldBe` 0)
                (Right a, Right b) <- concurrently (createDailySheet owner day) (createDailySheet manager day)
                a.daysheet.id `shouldBe` b.daysheet.id
                a.captured.id `shouldBe` b.captured.id
                query @Daysheet |> fetchCount >>= (`shouldBe` 1)
                Right Nothing <- readDailyForDate manager (addDays 1 day)
                query @DaysheetDefinitionCapture |> fetchCount >>= (`shouldBe` 1)
        it "checks live membership and venue scope for reads, edits and submission" $ withContext do
            withCleanDb do
                (_, manager) <- setup
                Right state <- createDailySheet manager day
                workerUser <- createUserRecord "daily-worker@example.test" "admin" True
                venue <- fetch (Id manager.venueId :: Id Venue)
                worker <- createVenueMembershipRecord venue workerUser Worker
                errorSuffix <$> readDailySheet worker state.daysheet.id `shouldReturn` Just "access-denied"
                errorSuffix <$> submitDailySheet worker state.daysheet.id `shouldReturn` Just "access-denied"
                other <- createVenueWithConfig "Other daily venue"
                foreignMember <- createVenueMembershipRecord other workerUser VenueOwner
                errorSuffix <$> readDailySheet foreignMember state.daysheet.id `shouldReturn` Just "daysheet-not-found"
                errorSuffix <$> editDailyCell foreignMember state.daysheet.id (Daily.RootCell (Fixture.field 1)) 0 (Fixture.text "Foreign") `shouldReturn` Just "daysheet-not-found"
                _ <- manager |> set #isActive False |> updateRecord
                errorSuffix <$> submitDailySheet manager state.daysheet.id `shouldReturn` Just "access-denied"
        it "preserves old drafts across reference retirement and publication" $ withContext do
            withCleanDb do
                (owner, manager) <- setup
                Right old <- createDailySheet manager day
                Right retired <- retireCurrentReferences owner 1 (ReferenceKey (Fixture.list 10) (Fixture.row 1)) []
                Right corrected <- pure (decodeReferenceData retired.referenceData)
                let changed = Fixture.definition { D.rootFields = map (\field -> if D.fieldId field == Fixture.field 1 then field { D.fieldLabel = "New label" } else field) (D.rootFields Fixture.definition) }
                Right _ <- saveDraft owner 2 Nothing changed corrected
                Right published <- publishDraft owner 2 0
                Right fresh <- createDailySheet manager (addDays 1 day)
                Right retained <- readDailySheet manager old.daysheet.id
                retained.definition `shouldBe` Fixture.definition
                retained.daysheet.submittedAt `shouldBe` Nothing
                Daily.rowKeys retained.content `shouldBe` [ReferenceKey (Fixture.list 20) (Fixture.row 1)]
                Daily.rowKeys fresh.content `shouldBe` []
                fresh.captured.definitionVersionId `shouldBe` unpackId published.id
                retained.captured.id `shouldBe` old.captured.id
        it "merges independent simultaneous saves and rejects exactly one same-field race" $ withContext do
            withCleanDb do
                (owner, manager) <- setup
                Right state <- createDailySheet manager day
                let comments = Daily.RootCell (Fixture.field 1)
                let count = Daily.RootCell (Fixture.field 2)
                (Right _, Right _) <- concurrently
                    (editDailyCell owner state.daysheet.id comments 0 (Fixture.text "Owner"))
                    (editDailyCell manager state.daysheet.id count 0 (Just (ReferenceScalar (D.WholeLiteral 0))))
                Right saved <- readDailySheet manager state.daysheet.id
                Daily.readCell saved.content comments `shouldBe` Right (Daily.Cell 1 (Fixture.text "Owner"))
                Daily.readCell saved.content count `shouldBe` Right (Daily.Cell 1 (Just (ReferenceScalar (D.WholeLiteral 0))))
                (a, b) <- concurrently
                    (editDailyCell owner state.daysheet.id comments 1 (Fixture.text "First"))
                    (editDailyCell manager state.daysheet.id comments 1 (Fixture.text "Second"))
                length (filter isRight [a, b]) `shouldBe` 1
                [suffix | Just suffix <- map errorSuffix [a, b]] `shouldBe` ["daily-field-conflict"]
        it "refreshes stale deletion approval, clears incoming links, and does not resurrect rows" $ withContext do
            withCleanDb do
                (_, manager) <- setup
                Right state <- createDailySheet manager day
                Right _ <- addDailyRow manager state.daysheet.id Fixture.band
                Right _ <- addDailyRow manager state.daysheet.id Fixture.reading
                Right initial <- prepareDailyDeletion manager state.daysheet.id Fixture.band
                Right _ <- editDailyCell manager state.daysheet.id (Daily.RowCell Fixture.reading (Fixture.field 5)) 0 (Just (ReferenceLink Fixture.band))
                Right _ <- editDailyCell manager state.daysheet.id (Daily.RowCell Fixture.reading (Fixture.field 6)) 0 (Just (ReferenceScalar (D.WholeLiteral 94)))
                errorSuffix <$> deleteDailyRow manager state.daysheet.id initial `shouldReturn` Just "daily-deletion-conflict"
                Right approved <- prepareDailyDeletion manager state.daysheet.id Fixture.band
                Right removed <- deleteDailyRow manager state.daysheet.id approved
                Daily.readCell removed.content (Daily.RowCell Fixture.reading (Fixture.field 5)) `shouldBe` Right (Daily.Cell 2 Nothing)
                Daily.readCell removed.content (Daily.RowCell Fixture.reading (Fixture.field 6)) `shouldBe` Right (Daily.Cell 1 (Just (ReferenceScalar (D.WholeLiteral 94))))
                errorSuffix <$> editDailyCell manager state.daysheet.id (Daily.RowCell Fixture.band (Fixture.field 4)) 0 (Fixture.text "Unsaved") `shouldReturn` Just "daily-row-deleted"
                errorSuffix <$> addDailyRow manager state.daysheet.id Fixture.band `shouldReturn` Just "daily-row-deleted"
        it "submits blank data without reporting, then permits corrections without reopening" $ withContext do
            withCleanDb do
                (_, manager) <- setup
                Right initial <- createDailySheet manager day
                Right submitted <- submitDailySheet manager initial.daysheet.id
                submitted.daysheet.submittedAt `shouldSatisfy` isJust
                submitted.daysheet.submittedBy `shouldBe` Just (Id manager.userId)
                submitted.daysheet.savedData `shouldBe` initial.daysheet.savedData
                submitted.daysheet.lastEditedAt `shouldBe` initial.daysheet.lastEditedAt
                Right again <- submitDailySheet manager initial.daysheet.id
                again.daysheet.revision `shouldBe` submitted.daysheet.revision
                Right edited <- editDailyCell manager initial.daysheet.id (Daily.RootCell (Fixture.field 1)) 0 (Fixture.text "Correction")
                edited.daysheet.submittedAt `shouldBe` submitted.daysheet.submittedAt
                edited.daysheet.lastEditedBy `shouldBe` Id manager.userId
                query @AppJob |> fetchCount >>= (`shouldBe` 0)
                query @DaysheetDefinitionCapture |> fetchCount >>= (`shouldBe` 1)
                rejected <- try @SomeException (edited.daysheet |> set #submittedAt Nothing |> set #submittedBy Nothing |> set #revision (edited.daysheet.revision + 1) |> updateRecord)
                rejected `shouldSatisfy` isLeft
        it "rolls back captured meaning when initial daily materialization exceeds its bound" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Bounded daily creation"
                user <- createUserRecord "daily-limit@example.test" "admin" True
                owner <- createVenueMembershipRecord venue user VenueOwner
                let source = Fixture.list 10
                let largeDefinition = D.Definition 2 [] (D.RecordList source "Sources" D.VenueReference [] : [D.RecordList (Fixture.list n) "Checklist" (D.ReferenceChecklist source) [] | n <- [100..162]]) [] []
                let largeReferences = ReferenceData [ReferenceList source [ReferenceRecord (Fixture.row n) False [] | n <- [1..1000]]]
                Right _ <- saveDraft owner 0 Nothing largeDefinition largeReferences
                Right _ <- publishDraft owner 0 0
                errorSuffix <$> createDailySheet owner day `shouldReturn` Just "daily-capacity-reached"
                query @Daysheet |> fetchCount >>= (`shouldBe` 0)
                query @DaysheetDefinitionCapture |> fetchCount >>= (`shouldBe` 0)
