module Test.RosterTemplateApplicationSpec where

import Application.Helper.FrontendContract.Surface.Roster.Resource
import Application.Helper.FrontendContract.Surface.Timesheets.Resource (timesheetWeekResource)
import Application.Helper.WeekBoundaries (startOfWeekFor)
import Application.RosterShiftAssignment (RosterShiftAssignment (..),
                                          applyRosterShiftAssignment)
import Application.RosterTemplates
import Application.VenueTime (RepeatedTimeOccurrence (..))
import Application.VenueTime.Model (ShiftCopyOccurrenceSelections (..),
                                    applyTimesheetEntryBoundaries,
                                    authoritativeBoundariesFromInstants,
                                    noShiftCopyOccurrenceSelections)
import Control.Concurrent (newEmptyMVar, putMVar, takeMVar, threadDelay)
import Control.Concurrent.Async (concurrently)
import Data.Either (isLeft, isRight)
import qualified Data.Set as Set
import Data.Time (UTCTime (..), diffDays, diffUTCTime, fromGregorian,
                  secondsToDiffTime)
import Database.PostgreSQL.Simple (Only (..))
import Generated.Types
import IHP.ControllerPrelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support
import Web.RosterWeeks.TemplateApplication
import Web.RosterWeeks.TemplateDesigner (startBlankRosterTemplateDesignerDraft)

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Roster template application" do
        it "replaces one draft day while preserving unrelated days and week columns" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Day template application"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "day-template-apply@example.com" "staff" True
                staff <- createStaffRecord venue Nothing "Day" "Worker"
                shiftType <- ensureVenueDefaultShiftType venue
                let actor = rosterTemplateActor manager venue True
                Right draft <- startBlankRosterTemplateDraft actor rosterGroup Day "Opening day"
                Right () <- replaceRosterTemplateDraftContent actor draft.draftDesign.id RosterTemplateContent
                    { contentDays = [RosterTemplateDayInput 0 Nothing True 2]
                    , contentColumns =
                        [ RosterTemplateColumnInput "Early" 0
                        , RosterTemplateColumnInput "Late" 1
                        ]
                    , contentShifts =
                        [RosterTemplateShiftInput 0 1 1 540 1020 shiftType.id (StaffAssignment staff.id)]
                    }
                Right saved <- saveRosterTemplateDraft actor draft.draftDesign.id

                targetWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 10 False
                targetDays <- forM [0 .. 6] (createRosterDayRecord targetWeek)
                let targetDay = targetDays !! 2
                let unrelatedDay = targetDays !! 3
                existingDefinition <- createDefinition targetWeek "Existing" 0
                earlyDefinition <- createDefinition targetWeek "Early" 1
                oldTargetSlot <- createSlot targetDay existingDefinition shiftType OpenAssignment 0
                unrelatedSlot <- createSlot unrelatedDay existingDefinition shiftType OpenAssignment 0
                let request = (applicationRequestForTestWindow saved.savedTemplate.id targetWeek (Just 2) noShiftCopyOccurrenceSelections)
                        { applicationTargetOperationalDate = Just targetDay.operationalDate
                        }

                preview <- previewRosterTemplateApplication actor request
                let Right confirmation = preview
                applied <- applyRosterTemplateApplication actor request confirmation.applicationExpectedVersion confirmation.applicationExpectedTargetRevision confirmation.applicationRosterCalendarRevision
                refreshedTargetDay <- fetch targetDay.id
                activeTargetSlots <- query @RosterSlot
                    |> filterWhere (#rosterDayId, unpackId targetDay.id)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetch
                retainedUnrelated <- query @RosterSlot
                    |> filterWhere (#id, unrelatedSlot.id)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetchOneOrNothing
                targetLanes <- query @RosterLane
                    |> filterWhere (#rosterDayId, unpackId targetDay.id)
                    |> filterWhere (#deletedAt, Nothing)
                    |> orderByAsc #sortOrder
                    |> fetch
                replacedSlot <- fetch oldTargetSlot.id

                confirmation.applicationPreviewTemplateName `shouldBe` "Opening day"
                confirmation.applicationPreviewScale `shouldBe` Day
                confirmation.applicationPreviewTargetWindowStart `shouldBe` testAnchorForOffset 10
                confirmation.applicationPreviewTargetWindowEnd `shouldBe` addDays 7 (testAnchorForOffset 10)
                confirmation.applicationPreviewTargetOperationalDate `shouldBe` Just targetDay.operationalDate
                confirmation.applicationReplacementShiftCount `shouldBe` 1
                confirmation.applicationExistingShiftCount `shouldBe` 1
                Set.fromList confirmation.applicationTouchedResources `shouldBe` Set.fromList
                    [ rosterWeekResource (unpackId rosterGroup.id) confirmation.applicationPreviewTargetWindowStart (addDays 7 confirmation.applicationPreviewTargetWindowStart)
                    , rosterWeekStructureResource (unpackId rosterGroup.id) confirmation.applicationPreviewTargetWindowStart (addDays 7 confirmation.applicationPreviewTargetWindowStart)
                    , rosterSlotsStructureResource (unpackId rosterGroup.id) confirmation.applicationPreviewTargetWindowStart (addDays 7 confirmation.applicationPreviewTargetWindowStart)
                    , rosterSlotsContentResource (unpackId rosterGroup.id) confirmation.applicationPreviewTargetWindowStart (addDays 7 confirmation.applicationPreviewTargetWindowStart)
                    , timesheetWeekResource (unpackId venue.id) confirmation.applicationPreviewTargetWindowStart (addDays 7 confirmation.applicationPreviewTargetWindowStart)
                    ]
                applied `shouldSatisfy` isRight
                (refreshedTargetDay.isClosed, refreshedTargetDay.rowCount) `shouldBe` (True, 2)
                map (.name) targetLanes `shouldBe` ["Existing", "Early", "Late"]
                map (.rowIndex) activeTargetSlots `shouldBe` [1]
                map (.assignmentState) activeTargetSlots `shouldBe` ["staff"]
                retainedUnrelated `shouldSatisfy` isJust
                replacedSlot.deletedAt `shouldSatisfy` isJust

        it "rejects forbidden, cross-group, and live target weeks" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Template target scope"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                otherGroup <-
                    newRecord @RosterGroup
                        |> set #venueId (unpackId venue.id)
                        |> set #name "Other group"
                        |> set #sortOrder 1
                        |> createRecord
                manager <- createUserRecord "template-target-scope@example.com" "staff" True
                shiftType <- ensureVenueDefaultShiftType venue
                let actor = rosterTemplateActor manager venue True
                let forbiddenActor = rosterTemplateActor manager venue False
                Right draft <- startBlankRosterTemplateDraft actor rosterGroup Day "Scoped day"
                Right () <- replaceRosterTemplateDraftContent actor draft.draftDesign.id (oneOpenShiftContent shiftType.id 540 1020)
                Right saved <- saveRosterTemplateDraft actor draft.draftDesign.id
                crossGroupWeek <- createRosterWeekRecordForRosterGroup venue otherGroup 15 False
                _ <- createRosterDayRecord crossGroupWeek 0
                liveWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 16 True
                _ <- createRosterDayRecord liveWeek 0
                mixedWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 17 False
                _ <- createRosterDayRecord mixedWeek 0
                mixedPublishedDay <- createRosterDayRecord mixedWeek 1
                _ <- mixedPublishedDay |> set #publicationState Published |> updateRecord
                let crossGroupRequest = applicationRequestForTestWindow saved.savedTemplate.id crossGroupWeek (Just 0) noShiftCopyOccurrenceSelections
                let liveRequest = applicationRequestForTestWindow saved.savedTemplate.id liveWeek (Just 0) noShiftCopyOccurrenceSelections
                let mixedRequest = applicationRequestForTestWindow saved.savedTemplate.id mixedWeek (Just 0) noShiftCopyOccurrenceSelections

                forbidden <- previewRosterTemplateApplication forbiddenActor liveRequest
                crossGroup <- previewRosterTemplateApplication actor crossGroupRequest
                live <- previewRosterTemplateApplication actor liveRequest
                mixed <- previewRosterTemplateApplication actor mixedRequest

                forbidden `shouldBe` Left RosterTemplateApplicationForbidden
                crossGroup `shouldBe` Left RosterTemplateApplicationScopeMismatch
                live `shouldBe` Left RosterTemplateApplicationTargetLive
                mixed `shouldBe` Left RosterTemplateApplicationTargetLive

        it "blocks archived Shift types before changing template or target" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Template invalid Shift type"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "template-invalid-shift-type@example.com" "staff" True
                shiftType <- ensureVenueDefaultShiftType venue
                let actor = rosterTemplateActor manager venue True
                Right draft <- startBlankRosterTemplateDraft actor rosterGroup Day "Invalid role"
                Right () <- replaceRosterTemplateDraftContent actor draft.draftDesign.id (oneOpenShiftContent shiftType.id 540 1020)
                Right saved <- saveRosterTemplateDraft actor draft.draftDesign.id
                targetWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 14 False
                targetDay <- createRosterDayRecord targetWeek 0
                definition <- createDefinition targetWeek "Existing" 0
                oldSlot <- createSlot targetDay definition shiftType OpenAssignment 0
                _ <- shiftType |> set #isActive False |> set #archivedAt (Just (UTCTime (fromGregorian 2026 1 1) 0)) |> updateRecord
                let request = applicationRequestForTestWindow saved.savedTemplate.id targetWeek (Just 0) noShiftCopyOccurrenceSelections

                preview <- previewRosterTemplateApplication actor request
                refreshedTemplate <- fetch saved.savedTemplate.id
                refreshedSlot <- fetch oldSlot.id

                preview `shouldBe` Left (RosterTemplateApplicationInvalidShiftTypes [shiftType.id])
                refreshedTemplate.currentVersion `shouldBe` 1
                refreshedSlot.deletedAt `shouldBe` Nothing

        it "distinguishes group-invalid and pay-invalid assignments in confirmation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Template assignment reasons"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "template-assignment-reasons@example.com" "staff" True
                groupStaff <- createStaffRecord venue Nothing "Group" "Invalid"
                payStaff <- createStaffRecord venue Nothing "Pay" "Invalid"
                shiftType <- ensureVenueDefaultShiftType venue
                let actor = rosterTemplateActor manager venue True
                Right draft <- startBlankRosterTemplateDraft actor rosterGroup Day "Assignment reasons"
                Right () <- replaceRosterTemplateDraftContent actor draft.draftDesign.id RosterTemplateContent
                    { contentDays = [RosterTemplateDayInput 0 Nothing False 2]
                    , contentColumns = [RosterTemplateColumnInput "Only" 0]
                    , contentShifts =
                        [ RosterTemplateShiftInput 0 0 0 540 1020 shiftType.id (StaffAssignment groupStaff.id)
                        , RosterTemplateShiftInput 0 0 1 600 1080 shiftType.id (StaffAssignment payStaff.id)
                        ]
                    }
                Right saved <- saveRosterTemplateDraft actor draft.draftDesign.id
                Just savedAggregate <- fetchSavedRosterTemplate actor saved.savedTemplate.id
                let [groupShift, payShift] = savedAggregate.savedShifts
                groupAssignment <- query @StaffRosterGroup
                    |> filterWhere (#staffId, unpackId groupStaff.id)
                    |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetchOne
                now <- getCurrentTime
                _ <- groupAssignment
                    |> set #deletedAt (Just now)
                    |> set #deleteReason (Just "test_group_removed")
                    |> updateRecord
                _ <- payStaff |> set #payAssignmentMode LegacyUnresolved |> updateRecord
                targetWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 13 False
                _ <- createRosterDayRecord targetWeek 0
                let request = applicationRequestForTestWindow saved.savedTemplate.id targetWeek (Just 0) noShiftCopyOccurrenceSelections

                preview <- previewRosterTemplateApplication actor request
                let Right confirmation = preview

                confirmation.applicationWarnings `shouldContain`
                    [ RosterTemplateApplicationAssignmentConvertedToOpen groupShift.id RosterTemplateStaffOutsideGroup
                    , RosterTemplateApplicationAssignmentConvertedToOpen payShift.id RosterTemplateStaffPayInvalid
                    ]
                map (.resolvedAssignment) confirmation.applicationResolvedShifts `shouldBe` [OpenAssignment, OpenAssignment]

        it "atomically cleans stale assignments while preserving materialized Timesheets" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Template stale application"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "template-stale-apply@example.com" "staff" True
                staff <- createStaffRecord venue Nothing "Stale" "Worker"
                shiftType <- ensureVenueDefaultShiftType venue
                let actor = rosterTemplateActor manager venue True
                Right draft <- startBlankRosterTemplateDraft actor rosterGroup Day "Stale day"
                Right () <- replaceRosterTemplateDraftContent actor draft.draftDesign.id RosterTemplateContent
                    { contentDays = [RosterTemplateDayInput 0 Nothing False 1]
                    , contentColumns = [RosterTemplateColumnInput "Only" 0]
                    , contentShifts = [RosterTemplateShiftInput 0 0 0 540 1020 shiftType.id (StaffAssignment staff.id)]
                    }
                Right saved <- saveRosterTemplateDraft actor draft.draftDesign.id
                Just savedAggregate <- fetchSavedRosterTemplate actor saved.savedTemplate.id
                let staleTemplateShiftId = (savedAggregate.savedShifts !! 0).id
                targetWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 12 False
                targetDay <- createRosterDayRecord targetWeek 0
                definition <- createDefinition targetWeek "Old" 0
                oldSlot <- createSlot targetDay definition shiftType (StaffAssignment staff.id) 0
                let Just oldStartsAt = oldSlot.startsAt
                let Just oldEndsAt = oldSlot.endsAt
                let Right entryBoundaries = authoritativeBoundariesFromInstants oldSlot.timezone oldStartsAt oldEndsAt Nothing Nothing
                entry <-
                    newRecord @TimesheetEntry
                        |> set #venueId (unpackId venue.id)
                        |> set #staffId (unpackId staff.id)
                        |> set #shiftTypeId (unpackId shiftType.id)
                        |> set #sourceRosterSlotId (Just (unpackId oldSlot.id))
                        |> set #operationalDate targetDay.operationalDate
                        |> applyTimesheetEntryBoundaries entryBoundaries
                        |> createRecord
                let entrySnapshot = (entry.staffId, entry.startsAt, entry.endsAt, entry.sourceRosterSlotId)
                _ <- staff |> set #isActive False |> updateRecord
                let request = applicationRequestForTestWindow saved.savedTemplate.id targetWeek (Just 0) noShiftCopyOccurrenceSelections

                preview <- previewRosterTemplateApplication actor request
                let Right confirmation = preview
                applied <- applyRosterTemplateApplication actor request confirmation.applicationExpectedVersion confirmation.applicationExpectedTargetRevision confirmation.applicationRosterCalendarRevision
                refreshedEntry <- fetch entry.id
                activeTargetSlots <- query @RosterSlot
                    |> filterWhere (#rosterDayId, unpackId targetDay.id)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetch
                refreshedTemplate <- fetch saved.savedTemplate.id
                latestSaved <- fetchSavedRosterTemplate actor saved.savedTemplate.id

                confirmation.applicationWarnings `shouldContain`
                    [RosterTemplateApplicationAssignmentConvertedToOpen staleTemplateShiftId RosterTemplateStaffUnavailable]
                confirmation.applicationWarnings `shouldContain` [RosterTemplateApplicationExistingTimesheetsRemain 1]
                map (.resolvedAssignment) confirmation.applicationResolvedShifts `shouldBe` [OpenAssignment]
                applied `shouldSatisfy` isRight
                map (.assignmentState) activeTargetSlots `shouldBe` ["open"]
                (refreshedEntry.staffId, refreshedEntry.startsAt, refreshedEntry.endsAt, refreshedEntry.sourceRosterSlotId) `shouldBe` entrySnapshot
                refreshedTemplate.currentVersion `shouldBe` 2
                fmap (map (.assignmentState) . (.savedShifts)) latestSaved `shouldBe` Just ["open"]

        it "requires deterministic Melbourne DST choices and rejects nonexistent clocks" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Template DST"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "template-dst@example.com" "staff" True
                shiftType <- ensureVenueDefaultShiftType venue
                let actor = rosterTemplateActor manager venue True

                Right springDraft <- startBlankRosterTemplateDraft actor rosterGroup Day "Spring gap"
                Right () <- replaceRosterTemplateDraftContent actor springDraft.draftDesign.id (oneOpenShiftContent shiftType.id 1560 1620)
                Right springSaved <- saveRosterTemplateDraft actor springDraft.draftDesign.id
                let springOperationalDay = fromGregorian 2026 10 3
                let springWindowStart = startOfWeekFor venueConfig.rosterWeekStartsOn springOperationalDay
                let springDayOffset = fromInteger (diffDays springOperationalDay springWindowStart)
                springWeek <- createRosterWindowRecordForRosterGroupAt venue rosterGroup springWindowStart False
                _ <- createRosterDayRecord springWeek springDayOffset
                let springRequest = applicationRequestForTestWindow springSaved.savedTemplate.id springWeek (Just springDayOffset) noShiftCopyOccurrenceSelections

                springPreview <- previewRosterTemplateApplication actor springRequest

                springPreview `shouldSatisfy` isBoundaryFailure

                Right autumnDraft <- startBlankRosterTemplateDraft actor rosterGroup Day "Autumn fold"
                Right () <- replaceRosterTemplateDraftContent actor autumnDraft.draftDesign.id (oneOpenShiftContent shiftType.id 1590 1650)
                Right autumnSaved <- saveRosterTemplateDraft actor autumnDraft.draftDesign.id
                let autumnOperationalDay = fromGregorian 2026 4 4
                let autumnWindowStart = startOfWeekFor venueConfig.rosterWeekStartsOn autumnOperationalDay
                let autumnDayOffset = fromInteger (diffDays autumnOperationalDay autumnWindowStart)
                autumnWeek <- createRosterWindowRecordForRosterGroupAt venue rosterGroup autumnWindowStart False
                _ <- createRosterDayRecord autumnWeek autumnDayOffset
                let autumnRequest occurrence = applicationRequestForTestWindow
                        autumnSaved.savedTemplate.id
                        autumnWeek
                        (Just autumnDayOffset)
                        noShiftCopyOccurrenceSelections { copyShiftStartOccurrence = Just occurrence }

                let autumnMissingRequest = (autumnRequest FirstOccurrence) { applicationOccurrenceSelections = noShiftCopyOccurrenceSelections }
                missingChoice <- previewRosterTemplateApplication actor autumnMissingRequest
                firstChoice <- previewRosterTemplateApplication actor (autumnRequest FirstOccurrence)
                secondChoice <- previewRosterTemplateApplication actor (autumnRequest SecondOccurrence)
                let Right firstPreview = firstChoice
                let Right secondPreview = secondChoice
                let firstStart = (firstPreview.applicationResolvedShifts !! 0).resolvedStartsAt
                let secondStart = (secondPreview.applicationResolvedShifts !! 0).resolvedStartsAt

                missingChoice `shouldSatisfy` isBoundaryFailure
                diffUTCTime secondStart firstStart `shouldBe` 60 * 60

        it "recomputes Timesheet warnings after concurrent materialization" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Concurrent Timesheet warning"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "template-concurrent-timesheet@example.com" "staff" True
                staff <- createStaffRecord venue Nothing "Concurrent" "Timesheet"
                shiftType <- ensureVenueDefaultShiftType venue
                let actor = rosterTemplateActor manager venue True
                Right draft <- startBlankRosterTemplateDraft actor rosterGroup Day "Timesheet day"
                Right () <- replaceRosterTemplateDraftContent actor draft.draftDesign.id (oneOpenShiftContent shiftType.id 540 1020)
                Right saved <- saveRosterTemplateDraft actor draft.draftDesign.id
                targetWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 22 False
                targetDay <- createRosterDayRecord targetWeek 0
                definition <- createDefinition targetWeek "Existing" 0
                oldSlot <- createSlot targetDay definition shiftType (StaffAssignment staff.id) 0
                let Just oldStartsAt = oldSlot.startsAt
                let Just oldEndsAt = oldSlot.endsAt
                let Right entryBoundaries = authoritativeBoundariesFromInstants oldSlot.timezone oldStartsAt oldEndsAt Nothing Nothing
                let request = applicationRequestForTestWindow saved.savedTemplate.id targetWeek (Just 0) noShiftCopyOccurrenceSelections
                Right confirmation <- previewRosterTemplateApplication actor request
                materializationStarted <- newEmptyMVar
                let materialize = withTransaction do
                        _locked :: [Only UUID] <- sqlQuery "SELECT id FROM roster_slots WHERE id = ? FOR UPDATE" (Only (unpackId oldSlot.id))
                        entry <-
                            newRecord @TimesheetEntry
                                |> set #venueId (unpackId venue.id)
                                |> set #staffId (unpackId staff.id)
                                |> set #shiftTypeId (unpackId shiftType.id)
                                |> set #sourceRosterSlotId (Just (unpackId oldSlot.id))
                                |> set #operationalDate targetDay.operationalDate
                                |> applyTimesheetEntryBoundaries entryBoundaries
                                |> createRecord
                        putMVar materializationStarted ()
                        threadDelay 200000
                        pure entry
                let confirmAfterMaterializationStarts = do
                        takeMVar materializationStarted
                        applyRosterTemplateApplication actor request confirmation.applicationExpectedVersion confirmation.applicationExpectedTargetRevision confirmation.applicationRosterCalendarRevision

                (entry, staleApply) <- concurrently materialize confirmAfterMaterializationStarts
                refreshedConfirmation <- previewRosterTemplateApplication actor request
                let Right currentConfirmation = refreshedConfirmation
                applied <- applyRosterTemplateApplication actor request currentConfirmation.applicationExpectedVersion currentConfirmation.applicationExpectedTargetRevision currentConfirmation.applicationRosterCalendarRevision
                refreshedEntry <- fetch entry.id

                staleApply `shouldBe` Left RosterTemplateApplicationTargetConflict
                currentConfirmation.applicationWarnings `shouldContain` [RosterTemplateApplicationExistingTimesheetsRemain 1]
                applied `shouldSatisfy` isRight
                refreshedEntry.sourceRosterSlotId `shouldBe` Just (unpackId oldSlot.id)

        it "revalidates pay references after concurrent deactivation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Concurrent template pay"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "template-concurrent-pay@example.com" "staff" True
                staff <- createStaffRecord venue Nothing "Concurrent" "Pay"
                awardLevel <- createPayLevelRecord venue "Concurrent Level"
                configuredStaff <- staff
                    |> set #payAssignmentMode AwardRate
                    |> set #defaultAwardLevelId (Just awardLevel.id)
                    |> updateRecord
                shiftType <- ensureVenueDefaultShiftType venue
                let actor = rosterTemplateActor manager venue True
                Right draft <- startBlankRosterTemplateDraft actor rosterGroup Day "Pay day"
                Right () <- replaceRosterTemplateDraftContent actor draft.draftDesign.id RosterTemplateContent
                    { contentDays = [RosterTemplateDayInput 0 Nothing False 1]
                    , contentColumns = [RosterTemplateColumnInput "Only" 0]
                    , contentShifts = [RosterTemplateShiftInput 0 0 0 540 1020 shiftType.id (StaffAssignment configuredStaff.id)]
                    }
                Right saved <- saveRosterTemplateDraft actor draft.draftDesign.id
                Just savedAggregate <- fetchSavedRosterTemplate actor saved.savedTemplate.id
                let templateShiftId = (savedAggregate.savedShifts !! 0).id
                targetWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 23 False
                _ <- createRosterDayRecord targetWeek 0
                let request = applicationRequestForTestWindow saved.savedTemplate.id targetWeek (Just 0) noShiftCopyOccurrenceSelections
                Right confirmation <- previewRosterTemplateApplication actor request
                payChangeStarted <- newEmptyMVar
                let deactivatePayReference = withTransaction do
                        _ <- awardLevel |> set #isActive False |> updateRecord
                        putMVar payChangeStarted ()
                        threadDelay 200000
                let confirmAfterPayChangeStarts = do
                        takeMVar payChangeStarted
                        applyRosterTemplateApplication actor request confirmation.applicationExpectedVersion confirmation.applicationExpectedTargetRevision confirmation.applicationRosterCalendarRevision

                (_, applied) <- concurrently deactivatePayReference confirmAfterPayChangeStarts
                let Right result = applied
                activeSlots <- query @RosterSlot |> filterWhere (#deletedAt, Nothing) |> fetch

                result.appliedWarnings `shouldContain`
                    [RosterTemplateApplicationAssignmentConvertedToOpen templateShiftId RosterTemplateStaffPayInvalid]
                map (.assignmentState) activeSlots `shouldBe` ["open"]

        it "revalidates roster-group membership after a concurrent removal" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Concurrent template membership"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "template-concurrent-membership@example.com" "staff" True
                staff <- createStaffRecord venue Nothing "Concurrent" "Membership"
                shiftType <- ensureVenueDefaultShiftType venue
                let actor = rosterTemplateActor manager venue True
                Right draft <- startBlankRosterTemplateDraft actor rosterGroup Day "Membership day"
                Right () <- replaceRosterTemplateDraftContent actor draft.draftDesign.id RosterTemplateContent
                    { contentDays = [RosterTemplateDayInput 0 Nothing False 1]
                    , contentColumns = [RosterTemplateColumnInput "Only" 0]
                    , contentShifts = [RosterTemplateShiftInput 0 0 0 540 1020 shiftType.id (StaffAssignment staff.id)]
                    }
                Right saved <- saveRosterTemplateDraft actor draft.draftDesign.id
                Just savedAggregate <- fetchSavedRosterTemplate actor saved.savedTemplate.id
                let templateShiftId = (savedAggregate.savedShifts !! 0).id
                assignment <- query @StaffRosterGroup
                    |> filterWhere (#staffId, unpackId staff.id)
                    |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetchOne
                targetWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 21 False
                _ <- createRosterDayRecord targetWeek 0
                let request = applicationRequestForTestWindow saved.savedTemplate.id targetWeek (Just 0) noShiftCopyOccurrenceSelections
                Right confirmation <- previewRosterTemplateApplication actor request
                removalStarted <- newEmptyMVar
                let removeMembership = withTransaction do
                        now <- getCurrentTime
                        _ <- assignment
                            |> set #deletedAt (Just now)
                            |> set #deleteReason (Just "concurrent_membership_removal")
                            |> updateRecord
                        putMVar removalStarted ()
                        threadDelay 200000
                let confirmAfterRemovalStarts = do
                        takeMVar removalStarted
                        applyRosterTemplateApplication actor request confirmation.applicationExpectedVersion confirmation.applicationExpectedTargetRevision confirmation.applicationRosterCalendarRevision

                (_, applied) <- concurrently removeMembership confirmAfterRemovalStarts
                let Right result = applied
                activeSlots <- query @RosterSlot |> filterWhere (#deletedAt, Nothing) |> fetch

                result.appliedWarnings `shouldContain`
                    [RosterTemplateApplicationAssignmentConvertedToOpen templateShiftId RosterTemplateStaffOutsideGroup]
                map (.assignmentState) activeSlots `shouldBe` ["open"]

        it "serializes concurrent confirmations without partial template or target writes" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Concurrent template confirmation"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "template-concurrent-confirmation@example.com" "staff" True
                staff <- createStaffRecord venue Nothing "Concurrent" "Worker"
                shiftType <- ensureVenueDefaultShiftType venue
                let actor = rosterTemplateActor manager venue True
                Right draft <- startBlankRosterTemplateDraft actor rosterGroup Day "Concurrent day"
                Right () <- replaceRosterTemplateDraftContent actor draft.draftDesign.id RosterTemplateContent
                    { contentDays = [RosterTemplateDayInput 0 Nothing False 1]
                    , contentColumns = [RosterTemplateColumnInput "Only" 0]
                    , contentShifts = [RosterTemplateShiftInput 0 0 0 540 1020 shiftType.id (StaffAssignment staff.id)]
                    }
                Right saved <- saveRosterTemplateDraft actor draft.draftDesign.id
                _ <- staff |> set #isActive False |> updateRecord
                targetWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 19 False
                _ <- createRosterDayRecord targetWeek 0
                let request = applicationRequestForTestWindow saved.savedTemplate.id targetWeek (Just 0) noShiftCopyOccurrenceSelections
                Right confirmation <- previewRosterTemplateApplication actor request

                (firstResult, secondResult) <- concurrently
                    (applyRosterTemplateApplication actor request confirmation.applicationExpectedVersion confirmation.applicationExpectedTargetRevision confirmation.applicationRosterCalendarRevision)
                    (applyRosterTemplateApplication actor request confirmation.applicationExpectedVersion confirmation.applicationExpectedTargetRevision confirmation.applicationRosterCalendarRevision)
                let results = [firstResult, secondResult]
                refreshedTemplate <- fetch saved.savedTemplate.id
                activeSlots <- query @RosterSlot |> filterWhere (#deletedAt, Nothing) |> fetch

                length (filter isRight results) `shouldBe` 1
                length (filter isLeft results) `shouldBe` 1
                results `shouldContain` [Left (RosterTemplateApplicationVersionConflict 2)]
                refreshedTemplate.currentVersion `shouldBe` 2
                map (.assignmentState) activeSlots `shouldBe` ["open"]

        it "rejects a stale target confirmation before destructive replacement" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Stale target confirmation"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "template-stale-target@example.com" "staff" True
                shiftType <- ensureVenueDefaultShiftType venue
                let actor = rosterTemplateActor manager venue True
                Right draft <- startBlankRosterTemplateDraft actor rosterGroup Day "Target revision day"
                Right () <- replaceRosterTemplateDraftContent actor draft.draftDesign.id (oneOpenShiftContent shiftType.id 540 1020)
                Right saved <- saveRosterTemplateDraft actor draft.draftDesign.id
                targetWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 20 False
                targetDay <- createRosterDayRecord targetWeek 0
                definition <- createDefinition targetWeek "Existing" 0
                oldSlot <- createSlot targetDay definition shiftType OpenAssignment 0
                let request = applicationRequestForTestWindow saved.savedTemplate.id targetWeek (Just 0) noShiftCopyOccurrenceSelections
                Right confirmation <- previewRosterTemplateApplication actor request
                _ <- targetDay |> set #rowCount 9 |> updateRecord

                applied <- applyRosterTemplateApplication actor request confirmation.applicationExpectedVersion confirmation.applicationExpectedTargetRevision confirmation.applicationRosterCalendarRevision
                refreshedSlot <- fetch oldSlot.id

                applied `shouldBe` Left RosterTemplateApplicationTargetConflict
                refreshedSlot.deletedAt `shouldBe` Nothing

        it "rejects a stale confirmation before changing the target" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Stale template confirmation"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                firstManager <- createUserRecord "template-stale-confirmation-a@example.com" "staff" True
                secondManager <- createUserRecord "template-stale-confirmation-b@example.com" "staff" True
                shiftType <- ensureVenueDefaultShiftType venue
                let firstActor = rosterTemplateActor firstManager venue True
                let secondActor = rosterTemplateActor secondManager venue True
                Right draft <- startBlankRosterTemplateDraft firstActor rosterGroup Day "Versioned day"
                Right () <- replaceRosterTemplateDraftContent firstActor draft.draftDesign.id (oneOpenShiftContent shiftType.id 540 1020)
                Right saved <- saveRosterTemplateDraft firstActor draft.draftDesign.id
                targetWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 18 False
                targetDay <- createRosterDayRecord targetWeek 0
                definition <- createDefinition targetWeek "Existing" 0
                oldSlot <- createSlot targetDay definition shiftType OpenAssignment 0
                let request = applicationRequestForTestWindow saved.savedTemplate.id targetWeek (Just 0) noShiftCopyOccurrenceSelections
                Right confirmation <- previewRosterTemplateApplication firstActor request
                Right editDraft <- startRosterTemplateEditDraft secondActor saved.savedTemplate.id
                Right _ <- saveRosterTemplateDraft secondActor editDraft.draftDesign.id

                applied <- applyRosterTemplateApplication firstActor request confirmation.applicationExpectedVersion confirmation.applicationExpectedTargetRevision confirmation.applicationRosterCalendarRevision
                refreshedSlot <- fetch oldSlot.id

                applied `shouldBe` Left (RosterTemplateApplicationVersionConflict 2)
                refreshedSlot.deletedAt `shouldBe` Nothing

        it "applies Week template weekdays in the current venue window order" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Rotated Week template"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "rotated-week-template@example.com" "staff" True
                shiftType <- ensureVenueDefaultShiftType venue
                let actor = rosterTemplateActor manager venue True
                Right draft <- startBlankRosterTemplateDesignerDraft actor rosterGroup Week "Calendar weekdays"
                Right () <- replaceRosterTemplateDraftContent actor draft.draftDesign.id RosterTemplateContent
                    { contentDays =
                        [ RosterTemplateDayInput dayIndex (Just weekdayIndex) False weekdayIndex
                        | (dayIndex, weekdayIndex) <- zip [0 .. 6] [1, 2, 3, 4, 5, 6, 0]
                        ]
                    , contentColumns = [RosterTemplateColumnInput "Only" 0]
                    , contentShifts = [RosterTemplateShiftInput 0 0 0 540 1020 shiftType.id OpenAssignment]
                    }
                Right saved <- saveRosterTemplateDraft actor draft.draftDesign.id
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                _ <- venueConfig
                    |> set #rosterWeekStartsOn 4
                    |> set #rosterCalendarRevision (venueConfig.rosterCalendarRevision + 1)
                    |> updateRecord
                let rotatedWindowStart = fromGregorian 2025 5 8
                targetWeek <- createRosterWindowRecordForRosterGroupAt venue rosterGroup rotatedWindowStart False
                targetDays <- forM [0 .. 6] \dayOffset -> createNativeRosterDayRecord venue rosterGroup (addDays dayOffset rotatedWindowStart) (fromInteger dayOffset)
                let request = (applicationRequestForTestWindow saved.savedTemplate.id targetWeek Nothing noShiftCopyOccurrenceSelections)
                        { applicationTargetWindowStart = rotatedWindowStart
                        , applicationTargetWindowEnd = addDays 7 rotatedWindowStart
                        }

                Right confirmation <- previewRosterTemplateApplication actor request
                Right _ <- applyRosterTemplateApplication actor request confirmation.applicationExpectedVersion confirmation.applicationExpectedTargetRevision confirmation.applicationRosterCalendarRevision
                refreshedDays <- query @RosterDay
                    |> filterWhereIn (#id, map (.id) targetDays)
                    |> orderByAsc #operationalDate
                    |> fetch
                activeSlots <- query @RosterSlot
                    |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) refreshedDays)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetch

                map (.rowCount) refreshedDays `shouldBe` [4, 5, 6, 0, 1, 2, 3]
                map (.rosterDayId) activeSlots `shouldBe` [unpackId (refreshedDays !! 4).id]

        it "replaces the complete Week column order, day states, rows, and shifts" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Complete Week template"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "complete-week-template@example.com" "staff" True
                shiftType <- ensureVenueDefaultShiftType venue
                let actor = rosterTemplateActor manager venue True
                Right draft <- startBlankRosterTemplateDraft actor rosterGroup Week "Standard week"
                Right () <- replaceRosterTemplateDraftContent actor draft.draftDesign.id RosterTemplateContent
                    { contentDays =
                        [RosterTemplateDayInput dayIndex (Just ((dayIndex + 1) `mod` 7)) (dayIndex == 6) (dayIndex + 1) | dayIndex <- [0 .. 6]]
                    , contentColumns =
                        [ RosterTemplateColumnInput "Late" 0
                        , RosterTemplateColumnInput "Early" 1
                        ]
                    , contentShifts =
                        [ RosterTemplateShiftInput 0 1 0 540 1020 shiftType.id OpenAssignment
                        , RosterTemplateShiftInput 6 0 2 600 1080 shiftType.id OpenAssignment
                        ]
                    }
                Right saved <- saveRosterTemplateDraft actor draft.draftDesign.id
                targetWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 17 False
                targetDays <- forM [0 .. 6] (createRosterDayRecord targetWeek)
                oldDefinition <- createDefinition targetWeek "Old" 0
                oldSlot <- createSlot (targetDays !! 4) oldDefinition shiftType OpenAssignment 0
                let request = applicationRequestForTestWindow saved.savedTemplate.id targetWeek Nothing noShiftCopyOccurrenceSelections
                Right confirmation <- previewRosterTemplateApplication actor request

                result <- applyRosterTemplateApplication actor request confirmation.applicationExpectedVersion confirmation.applicationExpectedTargetRevision confirmation.applicationRosterCalendarRevision
                refreshedDays <- query @RosterDay
                    |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
                    |> filterWhereGreaterThanOrEqualTo (#operationalDate, targetWeek.fixtureWindowStart)
                    |> filterWhereLessThan (#operationalDate, addDays 7 targetWeek.fixtureWindowStart)
                    |> orderByAsc #operationalDate
                    |> fetch
                firstDayLanes <- query @RosterLane
                    |> filterWhere (#rosterDayId, unpackId (targetDays !! 0).id)
                    |> filterWhere (#deletedAt, Nothing)
                    |> orderByAsc #sortOrder
                    |> fetch
                activeSlots <- query @RosterSlot
                    |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) refreshedDays)
                    |> filterWhere (#deletedAt, Nothing)
                    |> orderByAsc #rowIndex
                    |> fetch
                replacedSlot <- fetch oldSlot.id

                result `shouldSatisfy` isRight
                map (.name) firstDayLanes `shouldBe` ["Late", "Early"]
                map (\day -> (day.isClosed, day.rowCount)) refreshedDays
                    `shouldBe` [(False, 1), (False, 2), (False, 3), (False, 4), (False, 5), (False, 6), (True, 7)]
                map (.rowIndex) activeSlots `shouldBe` [0, 2]
                replacedSlot.deletedAt `shouldSatisfy` isJust

        it "rejects an incomplete Week template without changing the target" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Incomplete Week template"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "incomplete-week-template@example.com" "staff" True
                shiftType <- ensureVenueDefaultShiftType venue
                let actor = rosterTemplateActor manager venue True
                Right draft <- startBlankRosterTemplateDraft actor rosterGroup Week "Incomplete week"
                Right () <- replaceRosterTemplateDraftContent actor draft.draftDesign.id RosterTemplateContent
                    { contentDays = [RosterTemplateDayInput 0 (Just 1) True 1]
                    , contentColumns = [RosterTemplateColumnInput "Only" 0]
                    , contentShifts = [RosterTemplateShiftInput 0 0 0 540 1020 shiftType.id OpenAssignment]
                    }
                Right saved <- saveRosterTemplateDraft actor draft.draftDesign.id
                targetWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 11 False
                targetDays <- forM [0 .. 6] (createRosterDayRecord targetWeek)
                definition <- createDefinition targetWeek "Existing" 0
                oldSlot <- createSlot (targetDays !! 0) definition shiftType OpenAssignment 0
                let request = applicationRequestForTestWindow saved.savedTemplate.id targetWeek Nothing noShiftCopyOccurrenceSelections

                preview <- previewRosterTemplateApplication actor request
                refreshedSlot <- fetch oldSlot.id

                preview `shouldBe` Left (RosterTemplateApplicationInvalidStructure "Week templates must contain all seven weekdays.")
                refreshedSlot.deletedAt `shouldBe` Nothing

applicationRequestForTestWindow :: Id RosterTemplate -> TestRosterWindow -> Maybe Int -> ShiftCopyOccurrenceSelections -> RosterTemplateApplicationRequest
applicationRequestForTestWindow templateId targetWeek targetDayOffset occurrenceSelections =
    RosterTemplateApplicationRequest
        { applicationTemplateId = templateId
        , applicationTargetRosterGroupId = Id targetWeek.fixtureRosterGroupId
        , applicationTargetWindowStart = windowStart
        , applicationTargetWindowEnd = addDays 7 windowStart
        , applicationTargetOperationalDate = (`addDays` windowStart) . toInteger <$> targetDayOffset
        , applicationOccurrenceSelections = occurrenceSelections
        }
  where
    windowStart = targetWeek.fixtureWindowStart

oneOpenShiftContent :: Id ShiftType -> Int -> Int -> RosterTemplateContent
oneOpenShiftContent shiftTypeId startMinute endMinute =
    RosterTemplateContent
        { contentDays = [RosterTemplateDayInput 0 Nothing False 1]
        , contentColumns = [RosterTemplateColumnInput "Only" 0]
        , contentShifts = [RosterTemplateShiftInput 0 0 0 startMinute endMinute shiftTypeId OpenAssignment]
        }

isBoundaryFailure :: Either RosterTemplateApplicationError value -> Bool
isBoundaryFailure Left { } = True
isBoundaryFailure _        = False

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
    let startsAt = UTCTime (fromGregorian 2026 3 2) (secondsToDiffTime 0)
    let endsAt = UTCTime (fromGregorian 2026 3 2) (secondsToDiffTime (8 * 60 * 60))
    newRecord @RosterSlot
        |> set #rosterDayId (unpackId rosterDay.id)
        |> set #rosterLaneId (unpackId rosterLane.id)
        |> set #slotSortOrder definition.definitionSortOrder
        |> set #rowIndex rowIndex
        |> set #startsAt (Just startsAt)
        |> set #endsAt (Just endsAt)
        |> set #timezone "Australia/Melbourne"
        |> set #shiftTypeId (Just (unpackId shiftType.id))
        |> applyRosterShiftAssignment assignment
        |> createRecord
