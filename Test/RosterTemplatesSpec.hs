module Test.RosterTemplatesSpec where

import Application.RosterShiftAssignment (RosterShiftAssignment (..))
import Application.RosterTemplates
import Data.Either (isRight)
import qualified Data.UUID as UUID
import Generated.Types hiding (createRosterTemplate)
import IHP.ControllerPrelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Roster template snapshots" do
        it "stores and loads one complete detached Week snapshot" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Template snapshots"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                owner <- createUserRecord "snapshot-owner@example.com" "staff" True
                staff <- createStaffRecord venue Nothing "Template" "Worker"
                shiftType <- ensureVenueDefaultShiftType venue
                let actor = rosterTemplateActor owner venue True
                let content = completeWeekContent shiftType.id (StaffAssignment staff.id)

                created <- createRosterTemplate actor rosterGroup Week "  Standard week  " content
                let Right snapshot = created
                loaded <- fetchRosterTemplate actor snapshot.snapshotTemplate.id

                snapshot.snapshotTemplate.name `shouldBe` "Standard week"
                snapshot.snapshotTemplate.scale `shouldBe` Week
                map (.dayIndex) snapshot.snapshotDays `shouldBe` [0 .. 6]
                length snapshot.snapshotColumns `shouldBe` 1
                length snapshot.snapshotShifts `shouldBe` 1
                loaded `shouldBe` Just snapshot

        it "rejects incomplete Week content and Day creation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Template completeness"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                owner <- createUserRecord "completeness-owner@example.com" "staff" True
                shiftType <- ensureVenueDefaultShiftType venue
                let actor = rosterTemplateActor owner venue True
                let incomplete = (completeWeekContent shiftType.id OpenAssignment) { contentDays = [RosterTemplateDayInput 0 (Just 0) False 1] }

                weekResult <- createRosterTemplate actor rosterGroup Week "Incomplete" incomplete
                dayResult <- createRosterTemplate actor rosterGroup Day "Day" (oneDayContent shiftType.id)

                weekResult `shouldBe` Left (RosterTemplateInvalidContent "A Week template must contain all seven unique weekdays.")
                dayResult `shouldBe` Left RosterTemplateUnsupportedScale

        it "enforces active name identity and allows reuse after soft deletion" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Template names"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                owner <- createUserRecord "name-owner@example.com" "staff" True
                shiftType <- ensureVenueDefaultShiftType venue
                let actor = rosterTemplateActor owner venue True
                let content = completeWeekContent shiftType.id OpenAssignment
                Right first <- createRosterTemplate actor rosterGroup Week "Opening week" content

                duplicate <- createRosterTemplate actor rosterGroup Week "  OPENING WEEK " content
                deleted <- softDeleteRosterTemplate actor first.snapshotTemplate.id "Retired"
                reused <- createRosterTemplate actor rosterGroup Week "opening week" content

                duplicate `shouldBe` Left RosterTemplateDuplicateName
                deleted `shouldBe` Right ()
                reused `shouldSatisfy` isRight

        it "replaces content directly without retaining versions" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Template remediation"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                owner <- createUserRecord "remediation-owner@example.com" "staff" True
                staff <- createStaffRecord venue Nothing "Template" "Worker"
                shiftType <- ensureVenueDefaultShiftType venue
                let actor = rosterTemplateActor owner venue True
                Right created <- createRosterTemplate actor rosterGroup Week "Remediation" (completeWeekContent shiftType.id (StaffAssignment staff.id))
                beforeRevision <- pure (rosterTemplateSnapshotRevision created)
                let assignedShiftId = (fromMaybe (error "assigned template shift missing") (head created.snapshotShifts)).id

                remediated <- withTransaction do
                    remediateRosterTemplateAssignmentsInCurrentTransaction actor created [assignedShiftId]
                replaced <- replaceRosterTemplateContent actor created.snapshotTemplate.id (completeWeekContent shiftType.id OpenAssignment)
                let Right updated = replaced
                let duplicateShift = fromMaybe (error "week fixture shift missing") (head (completeWeekContent shiftType.id OpenAssignment).contentShifts)
                rejected <- replaceRosterTemplateContent actor created.snapshotTemplate.id
                    (completeWeekContent shiftType.id OpenAssignment)
                        { contentShifts = [duplicateShift, duplicateShift] }
                retained <- fetchRosterTemplate actor created.snapshotTemplate.id
                templates <- query @RosterTemplate |> fetch
                days <- query @RosterTemplateDay |> fetch
                columns <- query @RosterTemplateColumn |> fetch
                shifts <- query @RosterTemplateShift |> fetch

                remediated `shouldSatisfy` isRight
                rosterTemplateSnapshotRevision updated `shouldNotBe` beforeRevision
                rejected `shouldBe` Left (RosterTemplateInvalidContent "Template columns, shifts, rows, or times are invalid.")
                retained `shouldBe` Just updated
                map (.assignmentState) updated.snapshotShifts `shouldBe` ["open"]
                map (.staffId) updated.snapshotShifts `shouldBe` [Nothing]
                map (.id) templates `shouldBe` [created.snapshotTemplate.id]
                length days `shouldBe` 7
                length columns `shouldBe` 1
                length shifts `shouldBe` 1

        it "keeps authorization and venue scope explicit" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Template authority"
                foreignVenue <- createVenueWithConfig "Foreign template authority"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                owner <- createUserRecord "authority-owner@example.com" "staff" True
                shiftType <- ensureVenueDefaultShiftType venue
                let content = completeWeekContent shiftType.id OpenAssignment
                let forbidden = rosterTemplateActor owner venue False
                let crossVenue = rosterTemplateActor owner foreignVenue True

                forbiddenResult <- createRosterTemplate forbidden rosterGroup Week "Forbidden" content
                crossVenueResult <- createRosterTemplate crossVenue rosterGroup Week "Foreign" content

                forbiddenResult `shouldBe` Left RosterTemplateForbidden
                crossVenueResult `shouldBe` Left RosterTemplateScopeMismatch

completeWeekContent :: Id ShiftType -> RosterShiftAssignment -> RosterTemplateContent
completeWeekContent shiftTypeId assignment =
    RosterTemplateContent
        { contentDays = [RosterTemplateDayInput dayIndex (Just dayIndex) False 1 | dayIndex <- [0 .. 6]]
        , contentColumns = [RosterTemplateColumnInput "Early" 0]
        , contentShifts = [RosterTemplateShiftInput 0 0 0 540 1020 shiftTypeId assignment]
        }

oneDayContent :: Id ShiftType -> RosterTemplateContent
oneDayContent shiftTypeId =
    RosterTemplateContent
        { contentDays = [RosterTemplateDayInput 0 Nothing False 1]
        , contentColumns = [RosterTemplateColumnInput "Early" 0]
        , contentShifts = [RosterTemplateShiftInput 0 0 0 540 1020 shiftTypeId OpenAssignment]
        }
