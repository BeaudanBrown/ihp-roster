module Test.RosterTemplateDesignerSpec where

import Application.Helper.WeekBoundaries (venueWeekStartDate)
import Application.RosterShiftAssignment (RosterShiftAssignment (..))
import Application.RosterTemplates
import Control.Concurrent (newEmptyMVar, putMVar, readMVar, takeMVar,
                           threadDelay)
import Control.Concurrent.Async (concurrently)
import Data.Either (isRight)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support
import Web.RosterWeeks.TemplateDesigner

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Roster Template Designer workflow" do
        it "starts scale-appropriate blank drafts and reports an occupied private slot" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Blank designer"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                owner <- createUserRecord "designer-blank@example.com" "staff" True
                let actor = rosterTemplateActor owner venue True

                first <- startBlankRosterTemplateDesignerDraft actor rosterGroup Week "Standard week"
                occupied <- startBlankRosterTemplateDesignerDraft actor rosterGroup Day "Second draft"

                let Right draft = first
                map (.dayIndex) draft.draftDays `shouldBe` [0 .. 6]
                map (.rowCount) draft.draftDays `shouldBe` replicate 7 1
                map (.name) draft.draftColumns `shouldBe` ["Shift"]
                draft.draftShifts `shouldBe` []
                occupied `shouldBe` Left RosterTemplateDraftSlotOccupied

        it "autosaves only complete valid shift mutations into the private draft" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Designer autosave"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                owner <- createUserRecord "designer-autosave@example.com" "staff" True
                staff <- createStaffRecord venue Nothing "Autosave" "Worker"
                shiftType <- ensureVenueDefaultShiftType venue
                let actor = rosterTemplateActor owner venue True
                Right draft <- startBlankRosterTemplateDesignerDraft actor rosterGroup Day "Autosave day"
                let completeShift = RosterTemplateShiftInput 0 0 0 540 1020 shiftType.id (StaffAssignment staff.id)

                saved <- mutateRosterTemplateDesignerDraft actor draft.draftDesign.id (UpsertRosterTemplateShift completeShift)
                invalid <- mutateRosterTemplateDesignerDraft actor draft.draftDesign.id
                    (UpsertRosterTemplateShift completeShift { inputShiftEndMinute = 500 })
                persisted <- fetchPrivateRosterTemplateDraft actor

                saved `shouldBe` Right ()
                invalid `shouldBe` Left (RosterTemplateInvalidContent "Template days, columns, shifts, or times are invalid.")
                fmap (map (.startMinute) . (.draftShifts)) persisted `shouldBe` Just [540]
                fmap (map (.endMinute) . (.draftShifts)) persisted `shouldBe` Just [1020]

        it "serializes concurrent autosaves so acknowledged changes are both retained" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Designer concurrent autosave"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                owner <- createUserRecord "designer-concurrent-autosave@example.com" "staff" True
                let actor = rosterTemplateActor owner venue True
                Right draft <- startBlankRosterTemplateDesignerDraft actor rosterGroup Day "Concurrent day"
                startGate <- newEmptyMVar
                let run mutation = do
                        readMVar startGate
                        mutateRosterTemplateDesignerDraft actor draft.draftDesign.id mutation

                putMVar startGate ()
                (columnResult, dayResult) <- concurrently
                    (run (AddRosterTemplateColumn "Second"))
                    (run (SetRosterTemplateDay 0 False 2))
                persisted <- fetchPrivateRosterTemplateDraft actor

                columnResult `shouldBe` Right ()
                dayResult `shouldBe` Right ()
                fmap (map (.name) . (.draftColumns)) persisted `shouldBe` Just ["Shift", "Second"]
                fmap (map (.rowCount) . (.draftDays)) persisted `shouldBe` Just [2]

        it "rejects stale day, column, and shift mutation targets instead of reporting autosave success" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Designer stale mutation target"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                owner <- createUserRecord "designer-stale-target@example.com" "staff" True
                let actor = rosterTemplateActor owner venue True
                Right draft <- startBlankRosterTemplateDesignerDraft actor rosterGroup Day "Target day"

                staleDay <- mutateRosterTemplateDesignerDraft actor draft.draftDesign.id (SetRosterTemplateDay 6 False 1)
                staleColumn <- mutateRosterTemplateDesignerDraft actor draft.draftDesign.id (RenameRosterTemplateColumn 9 "Missing")
                staleShift <- mutateRosterTemplateDesignerDraft actor draft.draftDesign.id (DeleteRosterTemplateShift 0 0 0)

                let expected = Left (RosterTemplateInvalidContent "The selected template day, column, or shift no longer exists.")
                staleDay `shouldBe` expected
                staleColumn `shouldBe` expected
                staleShift `shouldBe` expected

        it "rejects shifts outside the visible row grid" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Designer row bounds"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                owner <- createUserRecord "designer-row-bounds@example.com" "staff" True
                shiftType <- ensureVenueDefaultShiftType venue
                let actor = rosterTemplateActor owner venue True
                Right draft <- startBlankRosterTemplateDesignerDraft actor rosterGroup Day "Bounded day"

                outsideRows <- mutateRosterTemplateDesignerDraft actor draft.draftDesign.id
                    (UpsertRosterTemplateShift (RosterTemplateShiftInput 0 0 1 540 1020 shiftType.id OpenAssignment))

                outsideRows `shouldBe` Left (RosterTemplateInvalidContent "Template days, columns, shifts, or times are invalid.")

        it "rejects archived Shift types before an autosave can persist" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Designer stale type"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                owner <- createUserRecord "designer-stale-type@example.com" "staff" True
                shiftType <- ensureVenueDefaultShiftType venue
                let actor = rosterTemplateActor owner venue True
                Right draft <- startBlankRosterTemplateDesignerDraft actor rosterGroup Day "Stale role day"
                _ <- shiftType |> set #isActive False |> updateRecord

                result <- mutateRosterTemplateDesignerDraft actor draft.draftDesign.id
                    (UpsertRosterTemplateShift (RosterTemplateShiftInput 0 0 0 540 1020 shiftType.id OpenAssignment))
                persisted <- fetchPrivateRosterTemplateDraft actor

                result `shouldBe` Left (RosterTemplateInvalidShiftTypes [shiftType.id])
                fmap (.draftShifts) persisted `shouldBe` Just []

        it "rejects stale Shift type and Staff references before creating a reference draft" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Template stale reference"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                owner <- createUserRecord "designer-stale-reference@example.com" "staff" True
                staff <- createStaffRecord venue Nothing "Stale" "Reference"
                shiftType <- ensureVenueDefaultShiftType venue
                slotName <- fetchSlotNameRecordForRosterGroup rosterGroup "Early"
                sourceWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 0 True
                sourceDay <- createRosterDayRecord sourceWeek 0
                _ <- createCompleteRosterSlotRecord sourceDay slotName staff 0
                    >>= updateRecord
                        . setTestRosterSlotBoundaries
                            (venueWeekStartDate venueConfig 0)
                            (TimeOfDay 9 0 0)
                            (TimeOfDay 17 0 0)
                let actor = rosterTemplateActor owner venue True
                _ <- shiftType |> set #isActive False |> updateRecord

                staleType <- startRosterTemplateDraftFromReference actor rosterGroup "Stale type" (RosterTemplateDayReference sourceWeek.id 0)
                noTypeDraft <- fetchPrivateRosterTemplateDraft actor
                _ <- shiftType |> set #isActive True |> updateRecord
                _ <- staff |> set #isActive False |> updateRecord
                staleStaff <- startRosterTemplateDraftFromReference actor rosterGroup "Stale staff" (RosterTemplateDayReference sourceWeek.id 0)
                noStaffDraft <- fetchPrivateRosterTemplateDraft actor

                staleType `shouldBe` Left (RosterTemplateInvalidShiftTypes [shiftType.id])
                noTypeDraft `shouldBe` Nothing
                staleStaff `shouldBe` Left (RosterTemplateInvalidContent "Choose an available roster-group staff member with valid pay configuration.")
                noStaffDraft `shouldBe` Nothing

        it "revalidates reference Shift types while locked against concurrent archival" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Template concurrent stale reference"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                owner <- createUserRecord "designer-concurrent-reference@example.com" "staff" True
                shiftType <- ensureVenueDefaultShiftType venue
                slotName <- fetchSlotNameRecordForRosterGroup rosterGroup "Early"
                sourceWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 0 True
                sourceDay <- createRosterDayRecord sourceWeek 0
                _ <- createRosterSlotRecord sourceDay slotName Nothing 0
                    >>= updateRecord
                        . set #shiftTypeId (Just (unpackId shiftType.id))
                        . setTestRosterSlotBoundaries
                            (venueWeekStartDate venueConfig 0)
                            (TimeOfDay 9 0 0)
                            (TimeOfDay 17 0 0)
                let actor = rosterTemplateActor owner venue True
                archiveStarted <- newEmptyMVar
                let archiveReference = withTransaction do
                        _ <- shiftType |> set #isActive False |> updateRecord
                        putMVar archiveStarted ()
                        threadDelay 200000
                let createAfterArchiveStarts = do
                        takeMVar archiveStarted
                        startRosterTemplateDraftFromReference actor rosterGroup "Concurrent reference" (RosterTemplateDayReference sourceWeek.id 0)

                (_, result) <- concurrently archiveReference createAfterArchiveStarts
                persisted <- fetchPrivateRosterTemplateDraft actor

                result `shouldBe` Left (RosterTemplateInvalidShiftTypes [shiftType.id])
                persisted `shouldBe` Nothing

        it "copies all seven day states and columns for a Week reference" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Template week reference"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                owner <- createUserRecord "designer-week-reference@example.com" "staff" True
                sourceWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 4 False
                sourceDays <- forM [0 .. 6] (createRosterDayRecord sourceWeek)
                _ <- forM sourceDays (\day -> day |> set #rowCount (day.dayOffset + 1) |> set #isClosed (day.dayOffset == 6) |> updateRecord)
                let actor = rosterTemplateActor owner venue True

                result <- startRosterTemplateDraftFromReference actor rosterGroup "Reference week" (RosterTemplateWeekReference sourceWeek.id)

                let Right draft = result
                map (.dayIndex) draft.draftDays `shouldBe` [0 .. 6]
                map (.rowCount) draft.draftDays `shouldBe` [1 .. 7]
                map (.isClosed) draft.draftDays `shouldBe` replicate 6 False <> [True]
                map (.name) draft.draftColumns `shouldBe` ["Shift"]

        it "serializes concurrent starts into one draft and one occupied outcome" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Concurrent designer start"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                owner <- createUserRecord "designer-concurrent-start@example.com" "staff" True
                let actor = rosterTemplateActor owner venue True

                (first, second) <- concurrently
                    (startBlankRosterTemplateDesignerDraft actor rosterGroup Day "First")
                    (startBlankRosterTemplateDesignerDraft actor rosterGroup Week "Second")
                draftCount <- query @RosterTemplateDesign
                    |> filterWhere (#draftOwnerUserId, Just (unpackId owner.id))
                    |> fetchCount

                length (filter isRight [first, second]) `shouldBe` 1
                length (filter (== Left RosterTemplateDraftSlotOccupied) [first, second]) `shouldBe` 1
                draftCount `shouldBe` 1

        it "allows a confirmed occupied draft revision to be replaced only once" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Single-use designer replacement"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                owner <- createUserRecord "designer-single-replacement@example.com" "staff" True
                sourceWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 0 False
                _ <- createRosterDayRecord sourceWeek 0
                let actor = rosterTemplateActor owner venue True
                Right existing <- startBlankRosterTemplateDesignerDraft actor rosterGroup Day "Existing"
                let reference = RosterTemplateDayReference sourceWeek.id 0
                Just sourceRevision <- fetchRosterTemplateReferenceRevision rosterGroup reference

                let confirmedDraftRevision = rosterTemplateDraftRevision existing
                first <- replaceRosterTemplateDraftFromReference actor existing.draftDesign.id rosterGroup "First replacement" reference sourceRevision confirmedDraftRevision
                second <- replaceRosterTemplateDraftFromReference actor existing.draftDesign.id rosterGroup "Replayed replacement" reference sourceRevision confirmedDraftRevision
                retained <- fetchPrivateRosterTemplateDraft actor

                first `shouldSatisfy` isRight
                second `shouldBe` Left RosterTemplateDraftSlotOccupied
                fmap (.draftName) retained `shouldBe` Just "First replacement"

        it "creates an isolated Day draft from one reference roster day" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Template reference"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                owner <- createUserRecord "designer-reference@example.com" "staff" True
                staff <- createStaffRecord venue Nothing "Reference" "Worker"
                slotName <- fetchSlotNameRecordForRosterGroup rosterGroup "Early"
                sourceWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 0 True
                sourceDay <- createRosterDayRecord sourceWeek 2
                _ <- sourceDay |> set #rowCount 2 |> updateRecord
                sourceSlot <- createCompleteRosterSlotRecord sourceDay slotName staff 1
                    >>= updateRecord
                        . setTestRosterSlotBoundaries
                            (addDays 2 (venueWeekStartDate venueConfig 0))
                            (TimeOfDay 9 0 0)
                            (TimeOfDay 17 0 0)
                let actor = rosterTemplateActor owner venue True

                result <- startRosterTemplateDraftFromReference
                    actor
                    rosterGroup
                    "Reference day"
                    (RosterTemplateDayReference sourceWeek.id 2)
                persistedSource <- fetch sourceSlot.id

                let Right draft = result
                map (.dayIndex) draft.draftDays `shouldBe` [0]
                map (.rowCount) draft.draftDays `shouldBe` [2]
                map (.name) draft.draftColumns `shouldBe` ["Early"]
                map (.rowIndex) draft.draftShifts `shouldBe` [1]
                map (.startMinute) draft.draftShifts `shouldBe` [540]
                map (.endMinute) draft.draftShifts `shouldBe` [1020]
                map (.assignmentState) draft.draftShifts `shouldBe` ["staff"]
                map (.staffId) draft.draftShifts `shouldBe` [Just (unpackId staff.id)]
                persistedSource `shouldBe` sourceSlot
