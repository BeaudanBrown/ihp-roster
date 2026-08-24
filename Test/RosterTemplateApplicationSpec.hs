module Test.RosterTemplateApplicationSpec where

import Application.Helper.WeekBoundaries (weekdayIndexForDay)
import Application.RosterShiftAssignment (RosterShiftAssignment (..),
                                          applyRosterShiftAssignment)
import Application.RosterTemplates
import Application.VenueTime.Model (noShiftCopyOccurrenceSelections)
import Data.Either (isRight)
import Data.Time.Calendar (addDays)
import Generated.Types hiding (createRosterTemplate)
import IHP.ControllerPrelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support
import Web.RosterWeeks.TemplateApplication

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Roster template snapshot application" do
        it "applies by operational weekday and durably remediates stale Staff assignments" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Snapshot application"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "snapshot-application@example.com" "staff" True
                staff <- createStaffRecord venue Nothing "Template" "Worker"
                shiftType <- ensureVenueDefaultShiftType venue
                let actor = rosterTemplateActor manager venue True
                Right snapshot <- createRosterTemplate actor rosterGroup Week "Standard week" (completeWeekContent shiftType.id (StaffAssignment staff.id))
                targetWeek <- createRosterWindowRecordForRosterGroupAt venue rosterGroup (testAnchorForOffset 10) False
                targetDays <- forM ([0 .. 6] :: [Int]) (\dayIndex -> createNativeRosterDayRecord venue rosterGroup (addDays (toInteger dayIndex) targetWeek.fixtureWindowStart) dayIndex)
                existingDefinition <- createDefinition targetWeek "Existing" 0
                oldSlot <- createSlot (targetDays !! 0) existingDefinition shiftType OpenAssignment 0
                timesheet <- newRecord @TimesheetEntry
                    |> set #venueId (unpackId venue.id)
                    |> set #staffId (unpackId staff.id)
                    |> set #shiftTypeId (unpackId shiftType.id)
                    |> set #startsAt (fromMaybe (error "fixture roster start missing") oldSlot.startsAt)
                    |> set #endsAt (fromMaybe (error "fixture roster end missing") oldSlot.endsAt)
                    |> set #timezone "Australia/Melbourne"
                    |> set #operationalDate (targetDays !! 0).operationalDate
                    |> set #sourceRosterSlotId (Just (unpackId oldSlot.id))
                    |> createRecord
                membership <- query @StaffRosterGroup
                    |> filterWhere (#staffId, unpackId staff.id)
                    |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetchOne
                now <- getCurrentTime
                _ <- membership |> set #deletedAt (Just now) |> updateRecord
                let request = applicationRequest snapshot.snapshotTemplate.id targetWeek

                Right preview <- previewRosterTemplateApplication actor request
                applied <- applyRosterTemplateApplication actor request 0 preview.applicationExpectedTargetRevision preview.applicationRosterCalendarRevision
                refreshedTemplate <- fetchRosterTemplate actor snapshot.snapshotTemplate.id
                activeSlots <- query @RosterSlot
                    |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) targetDays)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetch
                retainedTimesheet <- fetch timesheet.id
                replacedSlot <- fetch oldSlot.id

                applied `shouldSatisfy` isRight
                map (.assignmentState) activeSlots `shouldBe` ["open"]
                map (.operationalDate) (filter (\day -> unpackId day.id `elem` map (.rosterDayId) activeSlots) targetDays)
                    `shouldSatisfy` all ((== 0) . weekdayIndexForDay)
                fmap (map (.assignmentState) . (.snapshotShifts)) refreshedTemplate `shouldBe` Just ["open"]
                replacedSlot.deletedAt `shouldSatisfy` isJust
                retainedTimesheet.sourceRosterSlotId `shouldBe` Just (unpackId oldSlot.id)

        it "rejects a template content change made after preview" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Snapshot content conflict"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "snapshot-content-conflict@example.com" "staff" True
                shiftType <- ensureVenueDefaultShiftType venue
                let actor = rosterTemplateActor manager venue True
                Right snapshot <- createRosterTemplate actor rosterGroup Week "Conflict week" (completeWeekContent shiftType.id OpenAssignment)
                targetWeek <- createRosterWindowRecordForRosterGroupAt venue rosterGroup (testAnchorForOffset 11) False
                targetDays <- forM ([0 .. 6] :: [Int]) (\dayIndex -> createNativeRosterDayRecord venue rosterGroup (addDays (toInteger dayIndex) targetWeek.fixtureWindowStart) dayIndex)
                definition <- createDefinition targetWeek "Existing" 0
                oldSlot <- createSlot (targetDays !! 0) definition shiftType OpenAssignment 0
                let request = applicationRequest snapshot.snapshotTemplate.id targetWeek
                Right preview <- previewRosterTemplateApplication actor request
                let changedContent = (completeWeekContent shiftType.id OpenAssignment)
                        { contentDays = [RosterTemplateDayInput dayIndex (Just dayIndex) (dayIndex == 0) 1 | dayIndex <- [0 .. 6]] }
                Right _ <- replaceRosterTemplateContent actor snapshot.snapshotTemplate.id changedContent

                applied <- applyRosterTemplateApplication actor request 0 preview.applicationExpectedTargetRevision preview.applicationRosterCalendarRevision
                retainedSlot <- fetch oldSlot.id

                applied `shouldBe` Left RosterTemplateApplicationTargetConflict
                retainedSlot.deletedAt `shouldBe` Nothing

        it "rejects a stale calendar revision before replacing the target" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Snapshot calendar conflict"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "snapshot-calendar@example.com" "staff" True
                shiftType <- ensureVenueDefaultShiftType venue
                let actor = rosterTemplateActor manager venue True
                Right snapshot <- createRosterTemplate actor rosterGroup Week "Calendar week" (completeWeekContent shiftType.id OpenAssignment)
                targetWeek <- createRosterWindowRecordForRosterGroupAt venue rosterGroup (testAnchorForOffset 12) False
                targetDays <- forM ([0 .. 6] :: [Int]) (\dayIndex -> createNativeRosterDayRecord venue rosterGroup (addDays (toInteger dayIndex) targetWeek.fixtureWindowStart) dayIndex)
                definition <- createDefinition targetWeek "Existing" 0
                oldSlot <- createSlot (targetDays !! 0) definition shiftType OpenAssignment 0
                let request = applicationRequest snapshot.snapshotTemplate.id targetWeek
                Right preview <- previewRosterTemplateApplication actor request
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                _ <- venueConfig |> set #rosterWeekStartsOn ((venueConfig.rosterWeekStartsOn + 1) `mod` 7) |> updateRecord

                applied <- applyRosterTemplateApplication actor request 0 preview.applicationExpectedTargetRevision preview.applicationRosterCalendarRevision
                retainedSlot <- fetch oldSlot.id

                applied `shouldBe` Left RosterTemplateApplicationCalendarConflict
                retainedSlot.deletedAt `shouldBe` Nothing

applicationRequest :: Id RosterTemplate -> TestRosterWindow -> RosterTemplateApplicationRequest
applicationRequest templateId targetWeek =
    RosterTemplateApplicationRequest
        { applicationTemplateId = templateId
        , applicationTargetRosterGroupId = Id targetWeek.fixtureRosterGroupId
        , applicationTargetWindowStart = windowStart
        , applicationTargetWindowEnd = addDays 7 windowStart
        , applicationTargetOperationalDate = Nothing
        , applicationOccurrenceSelections = noShiftCopyOccurrenceSelections
        }
  where
    windowStart = targetWeek.fixtureWindowStart

completeWeekContent :: Id ShiftType -> RosterShiftAssignment -> RosterTemplateContent
completeWeekContent shiftTypeId assignment =
    RosterTemplateContent
        { contentDays = [RosterTemplateDayInput dayIndex (Just dayIndex) False 1 | dayIndex <- [0 .. 6]]
        , contentColumns = [RosterTemplateColumnInput "Only" 0]
        , contentShifts = [RosterTemplateShiftInput 0 0 0 540 1020 shiftTypeId assignment]
        }

data TestLaneDefinition = TestLaneDefinition
    { definitionName      :: !Text
    , definitionSortOrder :: !Int
    }

createDefinition :: (?modelContext :: ModelContext) => TestRosterWindow -> Text -> Int -> IO TestLaneDefinition
createDefinition _rosterWindow name sortOrder = pure TestLaneDefinition
    { definitionName = name
    , definitionSortOrder = sortOrder
    }

createSlot :: (?modelContext :: ModelContext) => RosterDay -> TestLaneDefinition -> ShiftType -> RosterShiftAssignment -> Int -> IO RosterSlot
createSlot rosterDay definition shiftType assignment rowIndex = do
    rosterLane <- newRecord @RosterLane
        |> set #rosterDayId (unpackId rosterDay.id)
        |> set #name definition.definitionName
        |> set #sortOrder definition.definitionSortOrder
        |> createRecord
    newRecord @RosterSlot
        |> set #rosterDayId (unpackId rosterDay.id)
        |> set #rosterLaneId (unpackId rosterLane.id)
        |> set #slotSortOrder definition.definitionSortOrder
        |> set #rowIndex rowIndex
        |> set #startsAt (Just (fixtureInstant rosterDay.operationalDate 9))
        |> set #endsAt (Just (fixtureInstant rosterDay.operationalDate 17))
        |> set #timezone "Australia/Melbourne"
        |> set #shiftTypeId (Just (unpackId shiftType.id))
        |> applyRosterShiftAssignment assignment
        |> createRecord

fixtureInstant :: Day -> Integer -> UTCTime
fixtureInstant day hour = UTCTime day (secondsToDiffTime (hour * 60 * 60))
