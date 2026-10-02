module Test.DaysheetStorageSpec where

import qualified Application.Daysheet.Contract as D
import Application.Daysheet.DefinitionCodec
import Application.Daysheet.ReferenceCodec
import Application.Daysheet.References
import Application.Daysheet.Storage
import Application.Error.Types (AppError, appErrorCode)
import Control.Concurrent.Async (concurrently)
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude
import IHP.Test.Mocking
import qualified Test.DaysheetReferencesSpec as Fixture
import Test.Hspec
import Test.Support

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Daysheet persistence lifecycle" do
        it "publishes staged corrections only for future captures" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Daysheets"
                user <- createUserRecord "daysheet-owner@example.test" "admin" True
                member <- createVenueMembershipRecord venue user VenueOwner
                Right saved <- saveDraft member 0 Nothing Fixture.definition Fixture.references
                saved.revision `shouldBe` 0
                Right first <- publishDraft member 0 0
                Right old <- captureDefinition member (fromGregorian 2026 10 1)
                let changed = Fixture.definition { D.rootFields = [D.Field (D.FieldId (unpackId user.id)) "New instructions" D.TextType D.Entered] }
                Right _ <- saveDraft member 1 Nothing changed Fixture.references
                Right beforePublish <- captureDefinition member (fromGregorian 2026 10 2)
                beforePublish.definitionVersionId `shouldBe` unpackId first.id
                Right second <- publishDraft member 1 0
                Right fresh <- captureDefinition member (fromGregorian 2026 10 3)
                fresh.definitionVersionId `shouldBe` unpackId second.id
                oldAgain <- fetch old.id
                oldAgain `shouldBe` old
                Right repeated <- captureDefinition member (fromGregorian 2026 10 1)
                repeated.id `shouldBe` old.id
                decodeDefinition first.definition `shouldBe` Right Fixture.definition
                decodeDefinition second.definition `shouldBe` Right changed
        it "blocks incompatible reference values without modifying publication" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Daysheets"
                user <- createUserRecord "daysheet-admin@example.test" "admin" True
                member <- createVenueMembershipRecord venue user VenueAdmin
                Right _ <- saveDraft member 0 Nothing Fixture.definition Fixture.references
                Right first <- publishDraft member 0 0
                let changed = Fixture.definition { D.recordLists = [D.RecordList Fixture.areaList "Areas" D.VenueReference [], D.RecordList Fixture.terminalList "Terminals" D.VenueReference [D.Field Fixture.areaField "Area text" D.TextType D.Entered]] }
                Right _ <- saveDraft member 1 Nothing changed Fixture.references
                rejected <- publishDraft member 1 0
                errorSuffix rejected `shouldBe` Just "invalid-reference-document"
                config <- query @DaysheetConfiguration |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                config.publishedVersionId `shouldBe` Just (unpackId first.id)
                config.revision `shouldBe` 1
                query @DaysheetDefinitionVersion |> filterWhere (#venueId, unpackId venue.id) |> fetchCount >>= (`shouldBe` 1)
                let corrected = ReferenceData
                        [ReferenceList Fixture.areaList [ReferenceRecord Fixture.areaA False [], ReferenceRecord Fixture.areaB False []]
                        ,ReferenceList Fixture.terminalList [ReferenceRecord Fixture.terminal False [(Fixture.areaField, ReferenceScalar (D.TextLiteral "Inside"))]]]
                Right _ <- saveDraft member 1 (Just 0) changed corrected
                Right second <- publishDraft member 1 1
                decodeReferenceData second.referenceData `shouldBe` Right corrected
                oldVersion <- fetch first.id
                decodeReferenceData oldVersion.referenceData `shouldBe` Right Fixture.references
        it "invalidates a draft base when live reference data changes" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Daysheets"
                user <- createUserRecord "daysheet-live-reference@example.test" "admin" True
                member <- createVenueMembershipRecord venue user VenueAdmin
                Right _ <- saveDraft member 0 Nothing Fixture.definition Fixture.references
                Right first <- publishDraft member 0 0
                Right _ <- saveDraft member 1 Nothing Fixture.definition Fixture.references
                Right updated <- updateCurrentReferences member 1 Fixture.references
                updated.publishedVersionId `shouldBe` Just (unpackId first.id)
                errorSuffix <$> publishDraft member 1 0 `shouldReturn` Just "revision-conflict"
                errorSuffix <$> updateCurrentReferences member 2 (ReferenceData []) `shouldReturn` Just "reference-removal-requires-retirement"
                saved <- query @DaysheetDefinitionDraft |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                saved.baseRevision `shouldBe` 1
        it "rejects stale saves and preserves the second editor's unsaved input" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Daysheets"
                user <- createUserRecord "daysheet-editor@example.test" "admin" True
                member <- createVenueMembershipRecord venue user VenueAdmin
                Right _ <- saveDraft member 0 Nothing Fixture.definition Fixture.references
                Right updated <- saveDraft member 0 (Just 0) Fixture.definition Fixture.references
                updated.revision `shouldBe` 1
                rejected <- saveDraft member 0 (Just 0) Fixture.definition Fixture.references
                errorSuffix rejected `shouldBe` Just "revision-conflict"
                rejectedPublish <- publishDraft member 0 0
                errorSuffix rejectedPublish `shouldBe` Just "revision-conflict"
        it "enforces current membership and cannot substitute global user role" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Daysheets"
                other <- createVenueWithConfig "Other"
                user <- createUserRecord "daysheet-worker@example.test" "admin" True
                worker <- createVenueMembershipRecord venue user Worker
                blocked <- saveDraft worker 0 Nothing Fixture.definition Fixture.references
                errorSuffix blocked `shouldBe` Just "access-denied"
                admin <- createVenueMembershipRecord other user VenueAdmin
                forged <- saveDraft (admin |> set #venueId (unpackId venue.id)) 0 Nothing Fixture.definition Fixture.references
                errorSuffix forged `shouldBe` Just "access-denied"
                _ <- worker |> set #venueRole VenueAdmin |> updateRecord
                _ <- worker |> set #isActive False |> updateRecord
                inactive <- saveDraft worker 0 Nothing Fixture.definition Fixture.references
                errorSuffix inactive `shouldBe` Just "access-denied"
        it "requires explicit retirement choices and leaves existing captures intact" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Daysheets"
                user <- createUserRecord "daysheet-retirement@example.test" "admin" True
                member <- createVenueMembershipRecord venue user VenueAdmin
                Right _ <- saveDraft member 0 Nothing Fixture.definition Fixture.references
                Right _ <- publishDraft member 0 0
                Right old <- captureDefinition member (fromGregorian 2026 10 1)
                let target = ReferenceKey Fixture.areaList Fixture.areaA
                denied <- retireCurrentReferences member 1 target []
                errorSuffix denied `shouldBe` Just "invalid-reference-document"
                Right _ <- retireCurrentReferences member 1 target [ReassignReference (ReferenceKey Fixture.terminalList Fixture.terminal) Fixture.areaField (ReferenceKey Fixture.areaList Fixture.areaB)]
                stale <- retireCurrentReferences member 1 target []
                errorSuffix stale `shouldBe` Just "revision-conflict"
                Right fresh <- captureDefinition member (fromGregorian 2026 10 2)
                fresh.referenceData `shouldNotBe` old.referenceData
                oldAgain <- fetch old.id
                oldAgain.referenceData `shouldBe` old.referenceData
        it "serializes concurrent venue/day creation to one capture" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Daysheets"
                user <- createUserRecord "daysheet-concurrent@example.test" "admin" True
                member <- createVenueMembershipRecord venue user VenueOwner
                Right _ <- saveDraft member 0 Nothing Fixture.definition Fixture.references
                Right _ <- publishDraft member 0 0
                (Right a, Right b) <- concurrently (captureDefinition member (fromGregorian 2026 10 1)) (captureDefinition member (fromGregorian 2026 10 1))
                a.id `shouldBe` b.id
                query @DaysheetDefinitionCapture |> filterWhere (#venueId, unpackId venue.id) |> fetchCount >>= (`shouldBe` 1)

errorSuffix :: Either AppError a -> Maybe Text
errorSuffix = either (Just . snd . Text.breakOnEnd "/" . appErrorCode) (const Nothing)
