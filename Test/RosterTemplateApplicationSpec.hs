module Test.RosterTemplateApplicationSpec where

import Application.Helper.FrontendContract.Surface.Roster.Resource (rosterSlotsContentResource,
                                                                    rosterSlotsStructureResource,
                                                                    rosterTemplateLibraryResource,
                                                                    rosterWeekResource,
                                                                    rosterWeekStructureResource)
import Application.Helper.FrontendContract.Surface.Timesheets.Resource (timesheetWeekResource)
import Application.Helper.WeekBoundaries (weekdayIndexForDay)
import Application.RosterShiftAssignment (RosterShiftAssignment (..),
                                          applyRosterShiftAssignment)
import Application.RosterTemplates
import Application.VenueTime (RepeatedTimeOccurrence (FirstOccurrence))
import Application.VenueTime.Model (resolveBoundaryInstant)
import Data.Either (fromRight, isRight)
import qualified Data.Map.Strict as Map
import Data.Time.Calendar (addDays, fromGregorian)
import Data.Time.LocalTime (TimeOfDay (..))
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
                applied <- applyRosterTemplateApplication actor request preview.applicationExpectedTargetRevision preview.applicationRosterCalendarRevision
                refreshedTemplate <- fetchRosterTemplate actor snapshot.snapshotTemplate.id
                activeSlots <- query @RosterSlot
                    |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) targetDays)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetch
                retainedTimesheet <- fetch timesheet.id
                replacedSlot <- fetch oldSlot.id

                applied `shouldSatisfy` isRight
                let result = fromRight (error "expected successful Staff cleanup") applied
                result.appliedTemplateChanged `shouldBe` True
                result.appliedTouchedResources `shouldContain` [rosterTemplateLibraryResource (unpackId rosterGroup.id)]
                result.appliedTouchedResources `shouldContain`
                    [timesheetWeekResource (unpackId venue.id) targetWeek.fixtureWindowStart (addDays 7 targetWeek.fixtureWindowStart)]
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

                applied <- applyRosterTemplateApplication actor request preview.applicationExpectedTargetRevision preview.applicationRosterCalendarRevision
                retainedSlot <- fetch oldSlot.id

                applied `shouldBe` Left RosterTemplateApplicationTargetConflict
                retainedSlot.deletedAt `shouldBe` Nothing

        it "rejects a target-window change made after preview without partial replacement" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Snapshot target conflict"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "snapshot-target-conflict@example.com" "staff" True
                shiftType <- ensureVenueDefaultShiftType venue
                let actor = rosterTemplateActor manager venue True
                Right snapshot <- createRosterTemplate actor rosterGroup Week "Target conflict week" (completeWeekContent shiftType.id OpenAssignment)
                targetWeek <- createRosterWindowRecordForRosterGroupAt venue rosterGroup (testAnchorForOffset 18) False
                targetDays <- forM ([0 .. 6] :: [Int]) (\dayIndex -> createNativeRosterDayRecord venue rosterGroup (addDays (toInteger dayIndex) targetWeek.fixtureWindowStart) dayIndex)
                definition <- createDefinition targetWeek "Existing" 0
                oldSlot <- createSlot (targetDays !! 1) definition shiftType OpenAssignment 0
                let request = applicationRequest snapshot.snapshotTemplate.id targetWeek
                Right preview <- previewRosterTemplateApplication actor request
                changedDay <- targetDays !! 4 |> set #rowCount 9 |> updateRecord

                applied <- applyRosterTemplateApplication actor request preview.applicationExpectedTargetRevision preview.applicationRosterCalendarRevision
                retainedDay <- fetch changedDay.id
                retainedSlot <- fetch oldSlot.id

                applied `shouldBe` Left RosterTemplateApplicationTargetConflict
                retainedDay.rowCount `shouldBe` 9
                retainedSlot.deletedAt `shouldBe` Nothing

        it "converts approved-leave assignments only in the target roster" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Snapshot approved leave"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "snapshot-leave@example.com" "staff" True
                staff <- createStaffRecord venue Nothing "Leave" "Worker"
                shiftType <- ensureVenueDefaultShiftType venue
                let actor = rosterTemplateActor manager venue True
                Right snapshot <- createRosterTemplate actor rosterGroup Week "Leave week" (completeWeekContent shiftType.id (StaffAssignment staff.id))
                targetWeek <- createRosterWindowRecordForRosterGroupAt venue rosterGroup (testAnchorForOffset 13) False
                _ <- forM ([0 .. 6] :: [Int]) (\dayIndex -> createNativeRosterDayRecord venue rosterGroup (addDays (toInteger dayIndex) targetWeek.fixtureWindowStart) dayIndex)
                let assignedDate = fromMaybe (error "target week missing Sunday") (find ((== 0) . weekdayIndexForDay) [addDays offset targetWeek.fixtureWindowStart | offset <- [0 .. 6]])
                _ <- createLeaveRequestRecord venue staff assignedDate (addDays 1 assignedDate) LeaveRequestStatusEnumApproved
                let request = applicationRequest snapshot.snapshotTemplate.id targetWeek

                Right preview <- previewRosterTemplateApplication actor request
                Right result <- applyRosterTemplateApplication actor request preview.applicationExpectedTargetRevision preview.applicationRosterCalendarRevision
                refreshedTemplate <- fetchRosterTemplate actor snapshot.snapshotTemplate.id
                targetSlots <- query @RosterSlot |> filterWhere (#deletedAt, Nothing) |> fetch

                result.appliedTemplateChanged `shouldBe` False
                map (.assignmentState) targetSlots `shouldBe` ["open"]
                fmap (map (.assignmentState) . (.snapshotShifts)) refreshedTemplate `shouldBe` Just ["staff"]
                preview.applicationWarnings `shouldContain`
                    [RosterTemplateApplicationAssignmentConvertedToOpen staff.id "Leave Worker" RosterTemplateStaffOnApprovedLeave 1]

        it "invalidates confirmation when referenced Staff facts change" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Snapshot Staff conflict"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "snapshot-staff-conflict@example.com" "staff" True
                staff <- createStaffRecord venue Nothing "Before" "Name"
                shiftType <- ensureVenueDefaultShiftType venue
                let actor = rosterTemplateActor manager venue True
                Right snapshot <- createRosterTemplate actor rosterGroup Week "Staff conflict week" (completeWeekContent shiftType.id (StaffAssignment staff.id))
                targetWeek <- createRosterWindowRecordForRosterGroupAt venue rosterGroup (testAnchorForOffset 17) False
                _ <- forM ([0 .. 6] :: [Int]) (\dayIndex -> createNativeRosterDayRecord venue rosterGroup (addDays (toInteger dayIndex) targetWeek.fixtureWindowStart) dayIndex)
                let request = applicationRequest snapshot.snapshotTemplate.id targetWeek
                Right preview <- previewRosterTemplateApplication actor request
                _ <- staff |> set #firstName "After" |> updateRecord

                applied <- applyRosterTemplateApplication actor request preview.applicationExpectedTargetRevision preview.applicationRosterCalendarRevision
                slotCount <- query @RosterSlot |> fetchCount

                applied `shouldBe` Left RosterTemplateApplicationTargetConflict
                slotCount `shouldBe` 0

        it "requires stale Shift type mapping and atomically cleans target and template" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Snapshot Shift mapping"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "snapshot-shift-map@example.com" "staff" True
                staleShiftType <- ensureVenueDefaultShiftType venue
                awardLevel <- query @AwardLevel |> filterWhere (#isActive, True) |> fetchOne
                replacement <- newRecord @ShiftType
                    |> set #venueId (unpackId venue.id)
                    |> set #name "Replacement"
                    |> set #sortOrder 10
                    |> set #payAssignmentMode AwardRate
                    |> set #overrideAwardLevelId (Just awardLevel.id)
                    |> createRecord
                let actor = rosterTemplateActor manager venue True
                Right snapshot <- createRosterTemplate actor rosterGroup Week "Mapped week" (completeWeekContent staleShiftType.id OpenAssignment)
                _ <- staleShiftType |> set #isActive False |> updateRecord
                targetWeek <- createRosterWindowRecordForRosterGroupAt venue rosterGroup (testAnchorForOffset 14) False
                _ <- forM ([0 .. 6] :: [Int]) (\dayIndex -> createNativeRosterDayRecord venue rosterGroup (addDays (toInteger dayIndex) targetWeek.fixtureWindowStart) dayIndex)
                let unmappedRequest = applicationRequest snapshot.snapshotTemplate.id targetWeek

                Right unmappedPreview <- previewRosterTemplateApplication actor unmappedRequest
                unmapped <- applyRosterTemplateApplication actor unmappedRequest unmappedPreview.applicationExpectedTargetRevision unmappedPreview.applicationRosterCalendarRevision
                let mappedRequest = unmappedRequest { applicationShiftTypeMappings = Map.singleton staleShiftType.id replacement.id }
                Right initialMappedPreview <- previewRosterTemplateApplication actor mappedRequest
                unavailableReplacement <- replacement |> set #isActive False |> updateRecord
                mappingConflict <- applyRosterTemplateApplication actor mappedRequest initialMappedPreview.applicationExpectedTargetRevision initialMappedPreview.applicationRosterCalendarRevision
                _ <- unavailableReplacement |> set #isActive True |> updateRecord
                Right payReferencePreview <- previewRosterTemplateApplication actor mappedRequest
                unavailableAwardLevel <- awardLevel |> set #isActive False |> updateRecord
                payReferenceConflict <- applyRosterTemplateApplication actor mappedRequest payReferencePreview.applicationExpectedTargetRevision payReferencePreview.applicationRosterCalendarRevision
                _ <- unavailableAwardLevel |> set #isActive True |> updateRecord
                Right mappedPreview <- previewRosterTemplateApplication actor mappedRequest
                firstTargetDay <- query @RosterDay
                    |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
                    |> orderByAsc #operationalDate
                    |> fetchOne
                publishedTargetDay <- firstTargetDay |> set #publicationState Published |> updateRecord
                blocked <- applyRosterTemplateApplication actor mappedRequest mappedPreview.applicationExpectedTargetRevision mappedPreview.applicationRosterCalendarRevision
                retainedAfterRollback <- fetchRosterTemplate actor snapshot.snapshotTemplate.id
                _ <- publishedTargetDay |> set #publicationState Draft |> updateRecord
                Right refreshedPreview <- previewRosterTemplateApplication actor mappedRequest
                Right result <- applyRosterTemplateApplication actor mappedRequest refreshedPreview.applicationExpectedTargetRevision refreshedPreview.applicationRosterCalendarRevision
                refreshedTemplate <- fetchRosterTemplate actor snapshot.snapshotTemplate.id
                targetSlots <- query @RosterSlot |> filterWhere (#deletedAt, Nothing) |> fetch

                unmapped `shouldBe` Left (RosterTemplateApplicationShiftTypeMappingsRequired [staleShiftType.id])
                mappingConflict `shouldBe` Left RosterTemplateApplicationTargetConflict
                payReferenceConflict `shouldBe` Left RosterTemplateApplicationTargetConflict
                blocked `shouldBe` Left RosterTemplateApplicationTargetLive
                fmap (map (.shiftTypeId) . (.snapshotShifts)) retainedAfterRollback `shouldBe` Just [unpackId staleShiftType.id]
                result.appliedTemplateChanged `shouldBe` True
                map (.shiftTypeId) targetSlots `shouldBe` [Just (unpackId replacement.id)]
                fmap (map (.shiftTypeId) . (.snapshotShifts)) refreshedTemplate `shouldBe` Just [unpackId replacement.id]
                result.appliedTouchedResources `shouldContain` [rosterTemplateLibraryResource (unpackId rosterGroup.id)]

        it "replaces all Week structure while preserving duplicate Staff assignments as advisory" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Structured snapshot application"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                _ <- venueConfig
                    |> set #rosterWeekStartsOn 3
                    |> set #rosterCalendarRevision (venueConfig.rosterCalendarRevision + 1)
                    |> updateRecord
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "snapshot-structure@example.com" "staff" True
                staff <- createStaffRecord venue Nothing "Advisory" "Duplicate"
                shiftType <- ensureVenueDefaultShiftType venue
                let actor = rosterTemplateActor manager venue True
                    content = RosterTemplateContent
                        { contentDays = [RosterTemplateDayInput dayIndex (Just dayIndex) (dayIndex == 2) (dayIndex + 1) | dayIndex <- [0 .. 6]]
                        , contentColumns = [RosterTemplateColumnInput "Early" 0, RosterTemplateColumnInput "Late" 1]
                        , contentShifts =
                            [ RosterTemplateShiftInput 0 0 0 540 720 shiftType.id (StaffAssignment staff.id)
                            , RosterTemplateShiftInput 0 1 0 780 1020 shiftType.id (StaffAssignment staff.id)
                            ]
                        }
                Right snapshot <- createRosterTemplate actor rosterGroup Week "Structured week" content
                targetWeek <- createRosterWindowRecordForRosterGroupAt venue rosterGroup (testAnchorForOffset 19) False
                targetDays <- forM ([0 .. 6] :: [Int]) (\dayIndex -> createNativeRosterDayRecord venue rosterGroup (addDays (toInteger dayIndex) targetWeek.fixtureWindowStart) dayIndex)
                existing <- createDefinition targetWeek "Obsolete" 0
                oldSlot <- createSlot (targetDays !! 0) existing shiftType OpenAssignment 0
                let request = applicationRequest snapshot.snapshotTemplate.id targetWeek

                Right preview <- previewRosterTemplateApplication actor request
                Right _ <- applyRosterTemplateApplication actor request preview.applicationExpectedTargetRevision preview.applicationRosterCalendarRevision
                appliedDays <- query @RosterDay
                    |> filterWhereIn (#id, map (.id) targetDays)
                    |> orderByAsc #operationalDate
                    |> fetch
                appliedLanes <- query @RosterLane
                    |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) targetDays)
                    |> filterWhere (#deletedAt, Nothing)
                    |> orderByAsc #sortOrder
                    |> fetch
                appliedSlots <- query @RosterSlot
                    |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) targetDays)
                    |> filterWhere (#deletedAt, Nothing)
                    |> orderByAsc #startsAt
                    |> fetch
                replacedSlot <- fetch oldSlot.id

                map (.publicationState) appliedDays `shouldBe` replicate 7 Draft
                map (\day -> (day.isClosed, day.rowCount)) appliedDays
                    `shouldBe` [(weekday == 2, weekday + 1) | day <- appliedDays, let weekday = weekdayIndexForDay day.operationalDate]
                Map.map sort (Map.fromListWith (<>) [(lane.rosterDayId, [lane.name]) | lane <- appliedLanes])
                    `shouldBe` Map.fromList [(unpackId day.id, ["Early", "Late"]) | day <- appliedDays]
                length appliedSlots `shouldBe` 2
                map (.assignmentState) appliedSlots `shouldBe` ["staff", "staff"]
                map (.staffId) appliedSlots `shouldBe` replicate 2 (Just (unpackId staff.id))
                map (weekdayIndexForDay . (.operationalDate)) (filter (\day -> unpackId day.id `elem` map (.rosterDayId) appliedSlots) appliedDays)
                    `shouldBe` [0]
                replacedSlot.deletedAt `shouldSatisfy` isJust

        it "applies an empty Week snapshot to a complete Draft target" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Empty snapshot application"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "snapshot-empty@example.com" "staff" True
                shiftType <- ensureVenueDefaultShiftType venue
                let actor = rosterTemplateActor manager venue True
                    emptyContent = (completeWeekContent shiftType.id OpenAssignment) { contentShifts = [] }
                Right snapshot <- createRosterTemplate actor rosterGroup Week "Empty week" emptyContent
                targetWeek <- createRosterWindowRecordForRosterGroupAt venue rosterGroup (testAnchorForOffset 16) False
                targetDays <- forM ([0 .. 6] :: [Int]) (\dayIndex -> createNativeRosterDayRecord venue rosterGroup (addDays (toInteger dayIndex) targetWeek.fixtureWindowStart) dayIndex)
                existing <- createDefinition targetWeek "Existing" 0
                _ <- createSlot (targetDays !! 0) existing shiftType OpenAssignment 0
                let request = applicationRequest snapshot.snapshotTemplate.id targetWeek

                Right preview <- previewRosterTemplateApplication actor request
                Right result <- applyRosterTemplateApplication actor request preview.applicationExpectedTargetRevision preview.applicationRosterCalendarRevision
                activeSlotCount <- query @RosterSlot |> filterWhere (#deletedAt, Nothing) |> fetchCount

                activeSlotCount `shouldBe` 0
                result.appliedTemplateChanged `shouldBe` False
                let targetWindowEnd = addDays 7 targetWeek.fixtureWindowStart
                result.appliedTouchedResources `shouldMatchList`
                    [ rosterWeekResource (unpackId rosterGroup.id) targetWeek.fixtureWindowStart targetWindowEnd
                    , rosterWeekStructureResource (unpackId rosterGroup.id) targetWeek.fixtureWindowStart targetWindowEnd
                    , rosterSlotsStructureResource (unpackId rosterGroup.id) targetWeek.fixtureWindowStart targetWindowEnd
                    , rosterSlotsContentResource (unpackId rosterGroup.id) targetWeek.fixtureWindowStart targetWindowEnd
                    , timesheetWeekResource (unpackId venue.id) targetWeek.fixtureWindowStart targetWindowEnd
                    , rosterTemplateLibraryResource (unpackId rosterGroup.id)
                    ]

        it "rejects Published and incomplete targets without mutating either side" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Snapshot target guards"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "snapshot-target-guards@example.com" "staff" True
                shiftType <- ensureVenueDefaultShiftType venue
                let actor = rosterTemplateActor manager venue True
                Right snapshot <- createRosterTemplate actor rosterGroup Week "Guarded week" (completeWeekContent shiftType.id OpenAssignment)
                targetWeek <- createRosterWindowRecordForRosterGroupAt venue rosterGroup (testAnchorForOffset 15) False
                days <- forM ([0 .. 5] :: [Int]) (\dayIndex -> createNativeRosterDayRecord venue rosterGroup (addDays (toInteger dayIndex) targetWeek.fixtureWindowStart) dayIndex)
                incomplete <- previewRosterTemplateApplication actor (applicationRequest snapshot.snapshotTemplate.id targetWeek)
                _ <- createNativeRosterDayRecord venue rosterGroup (addDays 6 targetWeek.fixtureWindowStart) 6
                _ <- (days !! 0) |> set #publicationState Published |> updateRecord
                published <- previewRosterTemplateApplication actor (applicationRequest snapshot.snapshotTemplate.id targetWeek)
                templateCount <- query @RosterTemplateShift |> fetchCount
                slotCount <- query @RosterSlot |> fetchCount

                incomplete `shouldBe` Left RosterTemplateApplicationInvalidTargetDay
                published `shouldBe` Left RosterTemplateApplicationTargetLive
                templateCount `shouldBe` 1
                slotCount `shouldBe` 0

        it "uses the first Melbourne occurrence and rejects nonexistent local times" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Snapshot DST application"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "snapshot-dst@example.com" "staff" True
                shiftType <- ensureVenueDefaultShiftType venue
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                _ <- venueConfig |> set #rosterWeekStartsOn 0 |> set #rosterCalendarRevision (venueConfig.rosterCalendarRevision + 1) |> updateRecord
                let actor = rosterTemplateActor manager venue True
                    repeatedContent = (completeWeekContent shiftType.id OpenAssignment)
                        { contentShifts = [RosterTemplateShiftInput 0 0 0 150 210 shiftType.id OpenAssignment] }
                Right repeatedSnapshot <- createRosterTemplate actor rosterGroup Week "Repeated week" repeatedContent
                repeatedWindow <- createRosterWindowRecordForRosterGroupAt venue rosterGroup (fromGregorian 2026 4 5) False
                _ <- forM ([0 .. 6] :: [Int]) (\dayIndex -> createNativeRosterDayRecord venue rosterGroup (addDays (toInteger dayIndex) repeatedWindow.fixtureWindowStart) dayIndex)

                Right repeatedPreview <- previewRosterTemplateApplication actor (applicationRequest repeatedSnapshot.snapshotTemplate.id repeatedWindow)
                let expectedStart = fromRight (error "expected repeated Melbourne boundary") (resolveBoundaryInstant "Australia/Melbourne" (fromGregorian 2026 4 5) (TimeOfDay 2 30 0) (Just FirstOccurrence))
                map (.resolvedStartsAt) repeatedPreview.applicationResolvedShifts `shouldBe` [expectedStart]

                let nonexistentContent = repeatedContent
                        { contentShifts = [RosterTemplateShiftInput 0 0 0 150 240 shiftType.id OpenAssignment] }
                Right nonexistentSnapshot <- createRosterTemplate actor rosterGroup Week "Nonexistent week" nonexistentContent
                nonexistentWindow <- createRosterWindowRecordForRosterGroupAt venue rosterGroup (fromGregorian 2026 10 4) False
                _ <- forM ([0 .. 6] :: [Int]) (\dayIndex -> createNativeRosterDayRecord venue rosterGroup (addDays (toInteger dayIndex) nonexistentWindow.fixtureWindowStart) dayIndex)
                nonexistent <- previewRosterTemplateApplication actor (applicationRequest nonexistentSnapshot.snapshotTemplate.id nonexistentWindow)
                nonexistent `shouldSatisfy` \case
                    Left RosterTemplateApplicationBoundaryError {} -> True
                    _ -> False

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

                applied <- applyRosterTemplateApplication actor request preview.applicationExpectedTargetRevision preview.applicationRosterCalendarRevision
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
        , applicationShiftTypeMappings = Map.empty
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
