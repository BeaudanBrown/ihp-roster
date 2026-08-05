module Test.RosterTemplateDesignerSpec where

import Application.Helper.WeekBoundaries (venueWeekStartDate)
import Application.RosterShiftAssignment (RosterShiftAssignment (..))
import Application.RosterTemplates
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
