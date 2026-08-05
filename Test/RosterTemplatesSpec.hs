module Test.RosterTemplatesSpec where

import Application.RosterShiftAssignment (RosterShiftAssignment (..))
import Application.RosterTemplates
import Data.Either (isRight)
import qualified Data.UUID as UUID
import Generated.Types
import IHP.ControllerPrelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Roster template drafts" do
        it "hashes equivalent multi-day and multi-column content canonically" $ withContext do
            let shiftTypeId = Id UUID.nil
            let firstShift = RosterTemplateShiftInput 0 0 0 540 1020 shiftTypeId OpenAssignment
            let secondShift = RosterTemplateShiftInput 1 1 0 600 1080 shiftTypeId OpenAssignment
            let content = RosterTemplateContent
                    [RosterTemplateDayInput 0 False 1, RosterTemplateDayInput 1 False 1]
                    [RosterTemplateColumnInput "Early" 0, RosterTemplateColumnInput "Late" 1]
                    [firstShift, secondShift]
            let reordered = content
                    { contentDays = reverse content.contentDays
                    , contentColumns = reverse content.contentColumns
                    , contentShifts = reverse content.contentShifts
                    }

            rosterTemplateContentRevision reordered `shouldBe` rosterTemplateContentRevision content

        it "keeps one private recoverable draft per authorized effective user" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Template drafts"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                owner <- createUserRecord "draft-owner@example.com" "staff" True
                otherUser <- createUserRecord "draft-other@example.com" "staff" True
                let ownerActor = rosterTemplateActor owner venue True
                let otherActor = rosterTemplateActor otherUser venue True
                let forbiddenActor = rosterTemplateActor otherUser venue False

                started <- startBlankRosterTemplateDraft ownerActor rosterGroup Day "Opening day"
                secondStart <- startBlankRosterTemplateDraft ownerActor rosterGroup Week "Other plan"
                ownerDraft <- fetchPrivateRosterTemplateDraft ownerActor
                otherDraft <- fetchPrivateRosterTemplateDraft otherActor
                forbidden <- startBlankRosterTemplateDraft forbiddenActor rosterGroup Day "Forbidden"

                started `shouldSatisfy` isRight
                secondStart `shouldBe` Left RosterTemplateDraftSlotOccupied
                fmap (.draftName) ownerDraft `shouldBe` Just "Opening day"
                otherDraft `shouldBe` Nothing
                forbidden `shouldBe` Left RosterTemplateForbidden

        it "replaces draft content only through its private typed aggregate" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Template content"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                owner <- createUserRecord "content-owner@example.com" "staff" True
                otherUser <- createUserRecord "content-other@example.com" "staff" True
                staff <- createStaffRecord venue Nothing "Template" "Worker"
                shiftType <- ensureVenueDefaultShiftType venue
                foreignVenue <- createVenueWithConfig "Foreign template content"
                foreignGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId foreignVenue.id) |> fetchOne
                let ownerActor = rosterTemplateActor owner venue True
                let otherActor = rosterTemplateActor otherUser venue True
                let crossVenueActor = rosterTemplateActor owner foreignVenue True
                Right draft <- startBlankRosterTemplateDraft ownerActor rosterGroup Day "Opening day"
                let content = RosterTemplateContent
                        { contentDays = [RosterTemplateDayInput 0 False 2]
                        , contentColumns = [RosterTemplateColumnInput "Early" 0]
                        , contentShifts =
                            [ RosterTemplateShiftInput 0 0 0 540 1020 shiftType.id (StaffAssignment staff.id)
                            , RosterTemplateShiftInput 0 0 1 600 1080 shiftType.id OpenAssignment
                            ]
                        }

                replaced <- replaceRosterTemplateDraftContent ownerActor draft.draftDesign.id content
                privateWrite <- replaceRosterTemplateDraftContent otherActor draft.draftDesign.id content
                crossVenueWrite <- replaceRosterTemplateDraftContent crossVenueActor draft.draftDesign.id content
                crossVenueRead <- fetchPrivateRosterTemplateDraft crossVenueActor
                crossVenueStart <- startBlankRosterTemplateDraft crossVenueActor foreignGroup Day "Foreign plan"
                reloaded <- fetchPrivateRosterTemplateDraft ownerActor

                replaced `shouldBe` Right ()
                privateWrite `shouldBe` Left RosterTemplateForbidden
                crossVenueWrite `shouldBe` Left RosterTemplateForbidden
                crossVenueRead `shouldBe` Nothing
                crossVenueStart `shouldBe` Left RosterTemplateDraftSlotOccupied
                fmap (length . (.draftShifts)) reloaded `shouldBe` Just 2

        it "returns a typed error for a reserved case-insensitive saved name" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Template duplicate service"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                firstUser <- createUserRecord "duplicate-first@example.com" "staff" True
                secondUser <- createUserRecord "duplicate-second@example.com" "staff" True
                let firstActor = rosterTemplateActor firstUser venue True
                let secondActor = rosterTemplateActor secondUser venue True
                Right firstDraft <- startBlankRosterTemplateDraft firstActor rosterGroup Day "Opening day"
                Right firstSave <- saveRosterTemplateDraft firstActor firstDraft.draftDesign.id
                Right secondDraft <- startBlankRosterTemplateDraft secondActor rosterGroup Week "Other week"

                duplicate <- saveRosterTemplateDraftAsNew secondActor secondDraft.draftDesign.id "  OPENING DAY  "
                _ <- softDeleteRosterTemplate firstActor firstSave.savedTemplate.id "Retired"
                reservedAfterDelete <- saveRosterTemplateDraftAsNew secondActor secondDraft.draftDesign.id "opening day"

                duplicate `shouldBe` Left RosterTemplateDuplicateName
                reservedAfterDelete `shouldBe` Left RosterTemplateDuplicateName

        it "keeps saved versions usable and reports optimistic edit conflicts" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Template conflicts"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                owner <- createUserRecord "conflict-owner@example.com" "staff" True
                otherUser <- createUserRecord "conflict-other@example.com" "staff" True
                let ownerActor = rosterTemplateActor owner venue True
                let otherActor = rosterTemplateActor otherUser venue True
                Right initialDraft <- startBlankRosterTemplateDraft ownerActor rosterGroup Day "Opening day"
                Right firstSave <- saveRosterTemplateDraft ownerActor initialDraft.draftDesign.id
                Right ownerEdit <- startRosterTemplateEditDraft ownerActor firstSave.savedTemplate.id
                Right otherEdit <- startRosterTemplateEditDraft otherActor firstSave.savedTemplate.id

                Right secondSave <- saveRosterTemplateDraft otherActor otherEdit.draftDesign.id
                staleSave <- saveRosterTemplateDraft ownerActor ownerEdit.draftDesign.id
                current <- fetchSavedRosterTemplate ownerActor firstSave.savedTemplate.id
                savedAsNew <- saveRosterTemplateDraftAsNew ownerActor ownerEdit.draftDesign.id "Owner variant"
                ownerDraft <- fetchPrivateRosterTemplateDraft ownerActor

                firstSave.savedVersion `shouldBe` 1
                secondSave.savedVersion `shouldBe` 2
                staleSave `shouldBe` Left (RosterTemplateConflict 2)
                fmap ((.currentVersion) . (.savedTemplate)) current `shouldBe` Just 2
                savedAsNew `shouldSatisfy` isRight
                ownerDraft `shouldBe` Nothing

        it "converts stale staff assignments to Open but blocks stale shift types" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Template stale references"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                owner <- createUserRecord "stale-owner@example.com" "staff" True
                otherUser <- createUserRecord "stale-other@example.com" "staff" True
                staff <- createStaffRecord venue Nothing "Stale" "Worker"
                shiftType <- ensureVenueDefaultShiftType venue
                let ownerActor = rosterTemplateActor owner venue True
                let otherActor = rosterTemplateActor otherUser venue True
                Right draft <- startBlankRosterTemplateDraft ownerActor rosterGroup Day "Stale staff"
                Right () <- replaceRosterTemplateDraftContent ownerActor draft.draftDesign.id (oneShiftContent shiftType.id (StaffAssignment staff.id))
                _ <- staff |> set #isActive False |> updateRecord

                saved <- saveRosterTemplateDraft ownerActor draft.draftDesign.id
                let Right savedResult = saved
                Just persisted <- fetchSavedRosterTemplate ownerActor savedResult.savedTemplate.id

                Right staleTypeDraft <- startBlankRosterTemplateDraft otherActor rosterGroup Day "Stale type"
                Right () <- replaceRosterTemplateDraftContent otherActor staleTypeDraft.draftDesign.id (oneShiftContent shiftType.id OpenAssignment)
                _ <- shiftType |> set #isActive False |> updateRecord
                blocked <- saveRosterTemplateDraft otherActor staleTypeDraft.draftDesign.id
                retainedDraft <- fetchPrivateRosterTemplateDraft otherActor

                savedResult.saveWarnings `shouldSatisfy` (not . null)
                map (.assignmentState) persisted.savedShifts `shouldBe` ["open"]
                map (.staffId) persisted.savedShifts `shouldBe` [Nothing]
                blocked `shouldBe` Left (RosterTemplateInvalidShiftTypes [shiftType.id])
                retainedDraft `shouldSatisfy` isJust

        it "reloads conflicted drafts, discards private work, and soft-deletes saved templates" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Template lifecycle"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                owner <- createUserRecord "lifecycle-owner@example.com" "staff" True
                otherUser <- createUserRecord "lifecycle-other@example.com" "staff" True
                let ownerActor = rosterTemplateActor owner venue True
                let otherActor = rosterTemplateActor otherUser venue True
                Right initial <- startBlankRosterTemplateDraft ownerActor rosterGroup Week "Standard week"
                Right saved <- saveRosterTemplateDraft ownerActor initial.draftDesign.id
                Right ownerEdit <- startRosterTemplateEditDraft ownerActor saved.savedTemplate.id
                Right otherEdit <- startRosterTemplateEditDraft otherActor saved.savedTemplate.id
                Right _ <- saveRosterTemplateDraft otherActor otherEdit.draftDesign.id
                Left (RosterTemplateConflict 2) <- saveRosterTemplateDraft ownerActor ownerEdit.draftDesign.id

                reloaded <- reloadLatestRosterTemplateDraft ownerActor ownerEdit.draftDesign.id
                let Right latestDraft = reloaded
                reloadedSave <- saveRosterTemplateDraft ownerActor latestDraft.draftDesign.id
                Right disposable <- startBlankRosterTemplateDraft otherActor rosterGroup Day "Disposable"
                discarded <- discardRosterTemplateDraft otherActor disposable.draftDesign.id
                deleted <- softDeleteRosterTemplate ownerActor saved.savedTemplate.id "No longer needed"
                library <- fetchRosterTemplateLibrary ownerActor rosterGroup
                versionCount <- query @RosterTemplateDesign |> filterWhere (#templateId, Just (unpackId saved.savedTemplate.id)) |> fetchCount

                reloadedSave `shouldSatisfy` isRight
                discarded `shouldBe` Right ()
                deleted `shouldBe` Right ()
                fmap (length . (.libraryTemplates)) library `shouldBe` Just 0
                versionCount `shouldBe` 3

oneShiftContent :: Id ShiftType -> RosterShiftAssignment -> RosterTemplateContent
oneShiftContent shiftTypeId assignment =
    RosterTemplateContent
        { contentDays = [RosterTemplateDayInput 0 False 1]
        , contentColumns = [RosterTemplateColumnInput "Early" 0]
        , contentShifts = [RosterTemplateShiftInput 0 0 0 540 1020 shiftTypeId assignment]
        }
