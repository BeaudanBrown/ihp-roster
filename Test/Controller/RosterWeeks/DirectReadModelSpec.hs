{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedRecordDot #-}

module Test.Controller.RosterWeeks.DirectReadModelSpec where

import Application.Helper.Conflict
import Application.Helper.RosterGroups (createVenueRosterGroupWithDefaults,
                                        ensureVenueDefaultRosterGroup)
import Application.Helper.RosterWagePrediction
import Application.Helper.WeekBoundaries (weekdayIndexForDay)
import Data.Coerce (coerce)
import Data.List (find, sortOn)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromJust, fromMaybe, isNothing)
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import qualified Data.Time.Calendar as Calendar
import Data.Time.Clock (getCurrentTime)
import Data.Time.LocalTime (TimeOfDay (..))
import qualified Data.UUID as UUID
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.Prelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support
import Web.RosterWeeks.DateRange (RosterWindowLane (..), RosterWindowScope (..),
                                  rosterWindowScopeForAnchor)
import Web.RosterWeeks.DirectReadModel
import Web.RosterWeeks.Filters
import Web.RosterWeeks.RenderData
import Web.RosterWeeks.StaffOptions (rosterAssignmentOptionStatesFor)
import Web.RosterWeeks.Types


tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "RosterWeeksController direct read model" do
        it "decodes unknown SQL conflict text as a typed failure with a generic critical warning" $ withContext do
            decodeRosterConflictType "future_conflict"
                `shouldBe` Left UnknownRosterConflictType
            unavailableRosterConflict.conflictType `shouldBe` ConflictDetailsUnavailable
            unavailableRosterConflict.severity `shouldBe` CriticalConflict
            unavailableRosterConflict.message `shouldBe` "Conflict details unavailable"

        it "hides another same-day assignment from a dated shift dialog" $ withContext do
            let dayId = Id (fromMaybe (error "day uuid") (UUID.fromString "10000000-0000-0000-0000-000000000001")) :: Id RosterDay
            let firstSlotId = Id (fromMaybe (error "first slot uuid") (UUID.fromString "20000000-0000-0000-0000-000000000001")) :: Id RosterSlot
            let targetSlotId = Id (fromMaybe (error "target slot uuid") (UUID.fromString "30000000-0000-0000-0000-000000000001")) :: Id RosterSlot
            let staffId = Id (fromMaybe (error "staff uuid") (UUID.fromString "40000000-0000-0000-0000-000000000001")) :: Id Staff
            let day = newRecord @RosterDay |> set #id dayId |> set #operationalDate (Calendar.fromGregorian 2025 1 6)
            let assignedSlot = newRecord @RosterSlot |> set #id firstSlotId |> set #rosterDayId (unpackId dayId) |> set #assignmentState "staff" |> set #staffId (Just (unpackId staffId))
            let targetSlot = newRecord @RosterSlot |> set #id targetSlotId |> set #rosterDayId (unpackId dayId)
            let staff = newRecord @Staff |> set #id staffId |> set #idealShiftsPerWeek 5
            let states = rosterAssignmentOptionStatesFor allAssignmentFilters (Calendar.fromGregorian 2025 1 6) [day] [assignedSlot, targetSlot] [staff] Set.empty Set.empty
            fmap (.optionHiddenByAssignedToday) (Map.lookup (unpackId targetSlotId, unpackId staffId) states) `shouldBe` Just True

        it "reads manager-visible base facts directly" $ withContext do
            withCleanDb do
                fixture <- createDirectReadModelFixture

                facts <- withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    withCurrentControllerContext do
                        fetchRosterBaseFactsDirect fixture.windowScope

                let RosterBaseFacts { baseRosterWeek, baseRosterDays, baseAllSlots, baseVisibleSlots, baseOrderedSlotDefinitions, baseShiftTypes, baseEligibleStaff, baseAssignedStaff, baseStaffMembers } = fromJust facts
                ((.windowRosterGroupId) <$> baseRosterWeek) `shouldBe` Just (unpackId fixture.rosterGroup.id)
                map (.operationalDate) baseRosterDays `shouldBe` map (`Calendar.addDays` fixture.windowScope.rosterWindowStart) [0 .. 6]
                map (.rowIndex) baseVisibleSlots `shouldBe` [3]
                map (.id) baseAllSlots `shouldContain` [fixture.closedDaySlot.id]
                map (.id) baseVisibleSlots `shouldNotContain` [fixture.closedDaySlot.id, fixture.otherGroupSlot.id]
                map (.rosterWindowLaneFirstSeen) baseOrderedSlotDefinitions `shouldBe` sort (map (.rosterWindowLaneFirstSeen) baseOrderedSlotDefinitions)
                map (.name) baseShiftTypes `shouldBe` ["Breakfast", "Dinner"]
                map (.id) baseEligibleStaff `shouldContain` [fixture.eligibleStaff.id]
                map (.id) baseEligibleStaff `shouldNotContain` [fixture.assignedInactiveStaff.id]
                map (.id) baseAssignedStaff `shouldBe` [fixture.assignedInactiveStaff.id]
                map (.id) baseStaffMembers `shouldContain` [fixture.eligibleStaff.id, fixture.assignedInactiveStaff.id]

        it "preserves complete pay-mode eligibility as reference availability changes" $ withContext do
            withCleanDb do
                fixture <- createDirectReadModelFixture
                award <- createPayLevelRecord fixture.venue "Eligibility award"
                imported <- createImportedXeroPayItemRecord fixture.venue fixture.manager "Eligibility rate" "eligibility-rate" 30
                let staffCases = [(AwardRate, Just award.id, Nothing), (XeroRate, Nothing, Just imported.id), (RosterOnly, Nothing, Nothing), (LegacyUnresolved, Nothing, Nothing)]
                    shiftCases = [(AwardRate, Just award.id, Nothing), (XeroRate, Nothing, Just imported.id), (RosterOnly, Nothing, Nothing), (StaffDefault, Nothing, Nothing)]
                staffRows <- forM (zip [0 :: Int ..] staffCases) \(index, (mode, awardId, importedId)) -> do
                    staff <- createStaffRecord fixture.venue Nothing "Eligibility" ("Z" <> tshow index)
                    staff |> set #payAssignmentMode mode |> set #defaultAwardLevelId awardId |> set #importedXeroPayItemId importedId |> updateRecord
                shiftRows <- forM (zip [0 :: Int ..] shiftCases) \(index, (mode, awardId, importedId)) -> do
                    shift <- createShiftTypeRecord fixture.venue award ("Eligibility " <> tshow index)
                    shift |> set #payAssignmentMode mode |> set #overrideAwardLevelId awardId |> set #importedXeroPayItemId importedId |> set #sortOrder (100 + index) |> updateRecord
                now <- getCurrentTime
                forM_ [(active, available, archived) | active <- [False, True], available <- [False, True], archived <- [False, True]] \(active, available, archived) -> do
                    _ <- award |> set #isActive active |> updateRecord
                    _ <- imported
                        |> set #providerAvailable available
                        |> set #providerUnavailableAt (if available then Nothing else Just now)
                        |> set #archivedAt (if archived then Just now else Nothing)
                        |> set #archivedByUserId (if archived then Just (unpackId fixture.manager.id) else Nothing)
                        |> updateRecord
                    facts <- withUserAndCurrentVenue fixture.manager fixture.venue.id do
                        withCurrentControllerContext do
                            fromJust <$> fetchRosterBaseFactsDirect fixture.windowScope
                    let expectedStaff = [staff.id | (staff, include) <- zip staffRows [active, available && not archived, True, False], include]
                        expectedShifts = [shift.id | (shift, include) <- zip shiftRows [active, available && not archived, True, True], include]
                    map (.id) (filter ((== "Eligibility") . (.firstName)) facts.baseEligibleStaff) `shouldBe` expectedStaff
                    map (.id) (filter ((== "Eligibility") . (.firstName)) facts.basePanelStaff) `shouldBe` map (.id) staffRows
                    map (.id) (filter ((>= 100) . (.sortOrder)) facts.baseShiftTypes) `shouldBe` expectedShifts
                let [awardStaff, xeroStaff, rosterStaff, legacyStaff] = staffRows
                    [awardShift, _, rosterShift, _] = shiftRows
                _ <- awardStaff |> set #archivedAt (Just now) |> updateRecord
                _ <- rosterStaff |> set #isActive False |> updateRecord
                membership <- query @StaffRosterGroup |> filterWhere (#staffId, unpackId legacyStaff.id) |> filterWhere (#rosterGroupId, unpackId fixture.rosterGroup.id) |> filterWhere (#deletedAt, Nothing :: Maybe UTCTime) |> fetchOne
                _ <- membership |> set #deletedAt (Just now) |> updateRecord
                _ <- awardShift |> set #archivedAt (Just now) |> updateRecord
                _ <- rosterShift |> set #isActive False |> updateRecord
                -- Deleted membership history must not duplicate a live member.
                _ <- newRecord @StaffRosterGroup
                    |> set #staffId (unpackId xeroStaff.id)
                    |> set #rosterGroupId (unpackId fixture.rosterGroup.id)
                    |> set #deletedAt (Just now)
                    |> createRecord
                ties <- forM ["Eligibility Tie A", "Eligibility Tie B"] \name -> do
                    shift <- createShiftTypeRecord fixture.venue award name
                    shift |> set #payAssignmentMode StaffDefault |> set #overrideAwardLevelId Nothing |> set #sortOrder 200 |> set #createdAt now |> updateRecord
                staffTies <- forM [1 :: Int, 2] \_ ->
                    createStaffRecord fixture.venue Nothing "Eligibility" "Z1"
                foreignVenue <- createVenueWithConfig "Eligibility foreign venue"
                _ <- createStaffRecord foreignVenue Nothing "Eligibility" "A foreign staff"
                foreignShift <- createShiftTypeRecord foreignVenue award "Eligibility foreign shift"
                _ <- foreignShift |> set #sortOrder 200 |> updateRecord
                scopedFacts <- withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    withCurrentControllerContext (fromJust <$> fetchRosterBaseFactsDirect fixture.windowScope)
                map (.id) (filter ((== "Eligibility") . (.firstName)) scopedFacts.baseEligibleStaff) `shouldMatchList` map (.id) staffTies
                map (.id) (filter ((== "Eligibility") . (.firstName)) scopedFacts.basePanelStaff) `shouldMatchList` (xeroStaff.id : map (.id) staffTies)
                -- Equal ordering keys have no extra ID/name ordering contract.
                map (.id) (filter ((== 200) . (.sortOrder)) scopedFacts.baseShiftTypes) `shouldMatchList` map (.id) ties
                map (.id) scopedFacts.baseShiftTypes `shouldNotContain` [awardShift.id, rosterShift.id, foreignShift.id]

        it "rejects malformed or stale explicit roster-window scopes" $ withContext do
            withCleanDb do
                fixture <- createDirectReadModelFixture
                let malformedEnd = fixture.windowScope { rosterWindowEnd = Calendar.addDays 1 fixture.windowScope.rosterWindowEnd }
                let staleRevision = fixture.windowScope { rosterWindowCalendarRevision = fixture.windowScope.rosterWindowCalendarRevision + 1 }

                results <- withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    withCurrentControllerContext do
                        forM [malformedEnd, staleRevision] fetchRosterBaseFactsDirect

                map isNothing results `shouldBe` [True, True]

        it "does not project a sparse explicit window from another dated window" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Sparse Explicit Window Venue"
                manager <- createUserRecord "sparse-explicit-window-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                rosterGroup <- ensureVenueDefaultRosterGroup venue
                _previousWindow <- createRosterWeekRecordForRosterGroup venue rosterGroup (-1) True
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                let scope = rosterWindowScopeForAnchor venueConfig rosterGroup.id (testAnchorForOffset 0)

                facts <- withUserAndCurrentVenue manager venue.id do
                    withCurrentControllerContext do
                        fetchRosterBaseFactsDirect scope

                let projectedWindow = fromJust (fromJust facts).baseRosterWeek
                projectedWindow.windowIsPublished `shouldBe` False
                projectedWindow.windowRosterGroupId `shouldBe` unpackId rosterGroup.id
                map (.operationalDate) (fromJust facts).baseRosterDays
                    `shouldBe` map (\dayIndex -> Calendar.addDays dayIndex (testAnchorForOffset 0)) [0 .. 6]

        it "keeps deployed record decoding independent of physical table order" $ withContext do
            directReadSource <- TextIO.readFile "Web/RosterWeeks/DirectReadModel.hs"
            mutationSource <- TextIO.readFile "Web/Timesheets/Mutations.hs"
            directReadSource `shouldSatisfy` (not . Text.isInfixOf "SELECT roster_slots.*")
            directReadSource `shouldSatisfy` (not . Text.isInfixOf "SELECT staff.*")
            directReadSource `shouldSatisfy` (not . Text.isInfixOf "params.week_start + roster_days.day_offset")
            mutationSource `shouldSatisfy` (not . Text.isInfixOf "SELECT timesheet_entries.*")
            mutationSource `shouldSatisfy` (not . Text.isInfixOf "SELECT roster_slots.*")

        it "builds direct render data with the same base facts used by the roster seam" $ withContext do
            withCleanDb do
                fixture <- createDirectReadModelFixture

                renderData <- withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    withCurrentControllerContext do
                        fetchVisibleRosterReadModel fixture.windowScope

                let rosterData = fromJust renderData
                ((.windowRosterGroupId) <$> rosterData.rosterWeek) `shouldBe` Just fixture.rosterWeek.fixtureRosterGroupId
                map (.id) rosterData.staffMembers `shouldContain` [fixture.eligibleStaff.id, fixture.assignedInactiveStaff.id]
                map (.id) rosterData.allSlots `shouldContain` [fixture.visibleSparseSlot.id, fixture.closedDaySlot.id]
                map (.rosterWindowLaneFirstSeen) rosterData.orderedSlotNames `shouldBe` sortOn (\value -> value) (map (.rosterWindowLaneFirstSeen) rosterData.orderedSlotNames)

        it "reads venue role values for direct staff panel entries" $ withContext do
            withCleanDb do
                fixture <- createDirectReadModelFixture
                membership <- query @VenueMembership
                    |> filterWhere (#venueId, unpackId fixture.venue.id)
                    |> filterWhere (#userId, unpackId fixture.eligibleUser.id)
                    |> fetchOne
                _ <- membership
                    |> set #venueRole Manager
                    |> updateRecord

                entries <- withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    withCurrentControllerContext do
                        fetchRosterStaffPanelEntriesDirect RosterStaffPanelCurrentGroup fixture.windowScope

                let entry = fromJust (find ((== fixture.eligibleStaff.id) . (.staff.id)) entries)
                entry.userRole `shouldBe` "manager"

        it "derives direct assignment option hidden reasons from SQL facts" $ withContext do
            withCleanDb do
                fixture <- createDirectReadModelFixture

                withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    withCurrentControllerContext do
                        initialData <- fromJust <$> fetchVisibleRosterReadModel fixture.windowScope
                        openDay <- fetch (Id fixture.visibleSparseSlot.rosterDayId) :: IO RosterDay
                        _ <- fixture.eligibleStaff |> set #idealShiftsPerWeek 1 |> updateRecord
                        _ <- createRosterSlotRecord openDay fixture.earlySlotName (Just fixture.eligibleStaff) 4
                        _ <- createLeaveRequestRecord fixture.venue fixture.eligibleStaff initialData.weekStartDate (Calendar.addDays 1 initialData.weekStartDate) LeaveRequestStatusEnumApproved

                        facts <- fromJust <$> fetchRosterBaseFactsDirect fixture.windowScope
                        states <- buildRosterStaffOptionStatesDirect allAssignmentFilters initialData.weekStartDate facts.baseVisibleSlots facts.baseStaffMembers

                        let targetState = fromJust (Map.lookup (coerce fixture.visibleSparseSlot.id, coerce fixture.eligibleStaff.id) states)
                        targetState.optionHidden `shouldBe` True
                        targetState.optionHiddenByIdeal `shouldBe` True
                        targetState.optionHiddenByUnavailable `shouldBe` True
                        targetState.optionHiddenByLeave `shouldBe` True
                        targetState.optionHiddenByAssignedToday `shouldBe` True

        it "keys wage prediction days by Operational date when compatibility offsets collide" $ withContext do
            withCleanDb do
                fixture <- createDirectReadModelFixture

                withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    withCurrentControllerContext do
                        initialData <- fromJust <$> fetchVisibleRosterReadModel fixture.windowScope
                        venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId fixture.venue.id) |> fetchOne
                        openDay <- fetch (Id fixture.visibleSparseSlot.rosterDayId) :: IO RosterDay
                        wageLevel <- createPayLevelRecord fixture.venue "Operational Date Wage"
                        wageStaff <- fixture.eligibleStaff
                            |> set #payAssignmentMode AwardRate
                            |> set #defaultAwardLevelId (Just wageLevel.id)
                            |> updateRecord
                        wageSlot <- createCompleteRosterSlotRecord openDay fixture.earlySlotName wageStaff 12
                        let expectedDate = (.operationalDate) (fromJust (find ((== wageSlot.rosterDayId) . unpackId . (.id)) initialData.rosterDays))

                        prediction <- fetchRosterWagePredictionForWindow venueConfig initialData.rosterDays [wageSlot]

                        prediction.predictionCalculationFailures `shouldBe` []
                        sum (map (.predictionDayShiftCount) prediction.predictionDays) `shouldBe` prediction.predictionCompleteShiftCount
                        map (.predictionDayDate) (filter ((> 0) . (.predictionDayShiftCount)) prediction.predictionDays)
                            `shouldBe` [expectedDate]

        it "uses the authoritative local start date for after-midnight preferences" $ withContext do
            withCleanDb do
                fixture <- createDirectReadModelFixture

                withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    withCurrentControllerContext do
                        initialData <- fromJust <$> fetchVisibleRosterReadModel fixture.windowScope
                        openDay <- fetch (Id fixture.visibleSparseSlot.rosterDayId) :: IO RosterDay
                        staff <- createStaffRecord fixture.venue Nothing "After Midnight" "Preference"
                        slot <- createRosterSlotRecord openDay fixture.earlySlotName (Just staff) 8
                            >>= updateRecord
                                . setTestRosterSlotBoundaries initialData.weekStartDate (TimeOfDay 1 0 0) (TimeOfDay 2 0 0)
                        _ <- createStaffShiftPreferenceRecord fixture.venue staff (weekdayIndexForDay (Calendar.addDays 1 initialData.weekStartDate)) 5 6

                        states <- buildRosterStaffOptionStatesForSlotsDirect allAssignmentFilters initialData.weekStartDate [slot] [slot] [staff]
                        let targetState = fromJust (Map.lookup (coerce slot.id, coerce staff.id) states)
                        targetState.optionHiddenByUnavailable `shouldBe` False

                        conflicts <- buildSlotConflictsForSlotsDirect fixture.rosterGroup.id 0 initialData.weekStartDate [slot] [slot]
                        lookup slot.id conflicts `shouldNotSatisfy` hasConflictType ShiftPreferenceDayUnavailable
                        lookup slot.id conflicts `shouldSatisfy` hasConflictType ShiftPreferenceSlotMismatch

        it "derives each direct roster conflict type from SQL facts" $ withContext do
            withCleanDb do
                fixture <- createDirectReadModelFixture

                withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    withCurrentControllerContext do
                        (duplicateSlot, lateSlot, preferenceSlot) <- addDirectReadModelConflictFacts fixture
                        initialData <- fromJust <$> fetchVisibleRosterReadModel fixture.windowScope
                        facts <- fromJust <$> fetchRosterBaseFactsDirect fixture.windowScope
                        conflicts <- buildSlotConflictsDirect fixture.rosterGroup.id 480 initialData.weekStartDate facts.baseVisibleSlots

                        let allTypes = sort (concatMap (map (.conflictType) . snd) conflicts)
                        forM_ [DuplicateAssignment, LeaveConflict, LateToEarlyConflict, ShiftPreferenceDayUnavailable, ShiftPreferenceSlotMismatch, IdealShiftThresholdExceeded] $ \conflictType ->
                            allTypes `shouldContain` [conflictType]
                        lookup fixture.visibleSparseSlot.id conflicts `shouldSatisfy` hasConflictType LateToEarlyConflict
                        lookup duplicateSlot.id conflicts `shouldSatisfy` hasConflictType DuplicateAssignment
                        lookup lateSlot.id conflicts `shouldSatisfy` hasConflictType LateToEarlyConflict
                        lookup preferenceSlot.id conflicts `shouldSatisfy` hasConflictType ShiftPreferenceSlotMismatch

        it "excludes Open shifts from wage estimates and conflict output" $ withContext do
            withCleanDb do
                fixture <- createDirectReadModelFixture

                withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    withCurrentControllerContext do
                        initialData <- fromJust <$> fetchVisibleRosterReadModel fixture.windowScope
                        beforePanelEntries <- fetchRosterStaffPanelEntriesDirect RosterStaffPanelCurrentGroup fixture.windowScope
                        rosterDay <- fetch (Id fixture.visibleSparseSlot.rosterDayId) :: IO RosterDay
                        openSlot <- createRosterSlotRecord rosterDay fixture.earlySlotName Nothing 12
                        venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId fixture.venue.id) |> fetchOne

                        prediction <- fetchRosterWagePredictionForWindow venueConfig initialData.rosterDays [openSlot]
                        prediction.predictionWeekTotal `shouldBe` 0
                        prediction.predictionCompleteShiftCount `shouldBe` 0
                        prediction.predictionIncompleteShiftCount `shouldBe` 0
                        map (.predictionDayShiftCount) prediction.predictionDays `shouldBe` replicate 7 0

                        conflicts <- buildSlotConflictsForSlotsDirect fixture.rosterGroup.id 60 initialData.weekStartDate [openSlot] [openSlot]
                        conflicts `shouldBe` []

                        afterPanelEntries <- fetchRosterStaffPanelEntriesDirect RosterStaffPanelCurrentGroup fixture.windowScope
                        map (\entry -> (entry.staff.id, entry.assignedShiftCount)) afterPanelEntries
                            `shouldBe` map (\entry -> (entry.staff.id, entry.assignedShiftCount)) beforePanelEntries

        it "evaluates late-to-early gaps from exact start instants" $ withContext do
            withCleanDb do
                fixture <- createDirectReadModelFixture

                withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    withCurrentControllerContext do
                        initialData <- fromJust <$> fetchVisibleRosterReadModel fixture.windowScope
                        rosterDay <- fetch (Id fixture.visibleSparseSlot.rosterDayId) :: IO RosterDay
                        firstSlot <- createRosterSlotRecord rosterDay fixture.earlySlotName (Just fixture.eligibleStaff) 9
                            >>= updateRecord
                                . setTestRosterSlotBoundaries initialData.weekStartDate (TimeOfDay 9 0 30) (TimeOfDay 9 30 30)
                        secondSlot <- createRosterSlotRecord rosterDay fixture.earlySlotName (Just fixture.eligibleStaff) 10
                            >>= updateRecord
                                . setTestRosterSlotBoundaries initialData.weekStartDate (TimeOfDay 10 0 0) (TimeOfDay 10 30 0)

                        conflicts <- buildSlotConflictsForSlotsDirect fixture.rosterGroup.id 60 initialData.weekStartDate [firstSlot, secondSlot] [firstSlot, secondSlot]

                        lookup firstSlot.id conflicts `shouldSatisfy` hasConflictType LateToEarlyConflict
                        lookup secondSlot.id conflicts `shouldSatisfy` hasConflictType LateToEarlyConflict

addDirectReadModelConflictFacts :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => DirectReadModelFixture -> IO (RosterSlot, RosterSlot, RosterSlot)
addDirectReadModelConflictFacts fixture = do
    initialData <- fromJust <$> fetchVisibleRosterReadModel fixture.windowScope
    openDay <- fetch (Id fixture.visibleSparseSlot.rosterDayId) :: IO RosterDay
    nextDay <- query @RosterDay
        |> filterWhere (#rosterGroupId, unpackId fixture.rosterGroup.id)
        |> filterWhere (#operationalDate, Calendar.addDays 1 fixture.windowScope.rosterWindowStart)
        |> fetchOne
    _ <- nextDay |> set #isClosed False |> updateRecord
    _ <- fixture.assignedInactiveStaff |> set #idealShiftsPerWeek 1 |> updateRecord
    duplicateSlot <- createRosterSlotRecord openDay fixture.earlySlotName (Just fixture.assignedInactiveStaff) 5 >>= \slot ->
        slot |> setTestStartTime (Just (TimeOfDay 12 0 0)) |> updateRecord
    lateSlot <- createRosterSlotRecord nextDay fixture.earlySlotName (Just fixture.assignedInactiveStaff) 7 >>= \slot ->
        slot
            |> setTestRosterSlotBoundaries (Calendar.addDays 1 initialData.weekStartDate) (TimeOfDay 6 0 0) (TimeOfDay 7 0 0)
            |> updateRecord
    _ <- fixture.visibleSparseSlot
        |> setTestRosterSlotBoundaries initialData.weekStartDate (TimeOfDay 23 0 0) (TimeOfDay 23 30 0)
        |> updateRecord
    _ <- createLeaveRequestRecord fixture.venue fixture.assignedInactiveStaff initialData.weekStartDate (Calendar.addDays 1 initialData.weekStartDate) LeaveRequestStatusEnumApproved
    preferenceStaff <- createStaffRecord fixture.venue Nothing "Pref" "Mismatch"
    preferenceSlot <- createRosterSlotRecord openDay fixture.earlySlotName (Just preferenceStaff) 6 >>= \slot ->
        slot |> setTestStartTime (Just (TimeOfDay 12 0 0)) |> updateRecord
    _ <- createStaffShiftPreferenceRecord fixture.venue preferenceStaff (weekdayIndexForDay initialData.weekStartDate) 9 10
    pure (duplicateSlot, lateSlot, preferenceSlot)

data DirectReadModelFixture = DirectReadModelFixture
    { venue                 :: Venue
    , windowScope           :: RosterWindowScope
    , manager               :: User
    , rosterGroup           :: RosterGroup
    , rosterWeek            :: TestRosterWindow
    , earlySlotName         :: SlotName
    , eligibleUser          :: User
    , eligibleStaff         :: Staff
    , assignedInactiveStaff :: Staff
    , visibleSparseSlot     :: RosterSlot
    , closedDaySlot         :: RosterSlot
    , otherGroupSlot        :: RosterSlot
    }

createDirectReadModelFixture :: (?modelContext :: ModelContext) => IO DirectReadModelFixture
createDirectReadModelFixture = do
    venue <- createVenueWithConfig "Direct Read Venue"
    manager <- createUserRecord "direct-read-manager@example.com" "staff" True
    _ <- createVenueMembershipRecord venue manager Manager
    rosterGroup <- ensureVenueDefaultRosterGroup venue
    venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
    let windowScope = rosterWindowScopeForAnchor venueConfig rosterGroup.id (testAnchorForOffset 0)
    otherRosterGroup <- createVenueRosterGroupWithDefaults venue "Other" 1 True
    earlySlotName <- fetchSlotNameRecordForRosterGroup rosterGroup "Early"
    otherSlotName <- fetchSlotNameRecordForRosterGroup otherRosterGroup "Early"

    awardLevel <- createPayLevelRecord venue "Direct Read Level"
    breakfast <- createShiftTypeRecord venue awardLevel "Breakfast"
    _ <- breakfast |> set #sortOrder 1 |> updateRecord
    dinner <- createShiftTypeRecord venue awardLevel "Dinner"
    _ <- dinner |> set #sortOrder 2 |> updateRecord

    eligibleUser <- createUserRecord "direct-eligible@example.com" "staff" True
    _ <- createVenueMembershipRecord venue eligibleUser Worker
    eligibleStaff <- createStaffRecord venue (Just eligibleUser) "Able" "Eligible"

    inactiveUser <- createUserRecord "direct-inactive@example.com" "staff" True
    _ <- createVenueMembershipRecord venue inactiveUser Worker
    assignedInactiveStaff <- createStaffRecord venue (Just inactiveUser) "Bert" "Inactive"
    assignedInactiveStaff' <- assignedInactiveStaff |> set #isActive False |> updateRecord

    rosterWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 0 False
    rosterDays <- forM [0 :: Int .. 6] (createRosterDayRecord rosterWeek)
    let openDay = fromJust (head rosterDays)
    closedDay <- (rosterDays !! 1) |> set #isClosed True |> updateRecord

    visibleSparseSlot <- createRosterSlotRecord openDay earlySlotName (Just assignedInactiveStaff') 3 >>= \slot ->
        slot
            |> setTestStartTime (Just (TimeOfDay 9 0 0))
            |> set #shiftTypeId (Just (unpackId breakfast.id))
            |> updateRecord
    closedDaySlot <- createRosterSlotRecord closedDay earlySlotName (Just eligibleStaff) 0 >>= \slot ->
        slot
            |> setTestStartTime (Just (TimeOfDay 10 0 0))
            |> set #shiftTypeId (Just (unpackId dinner.id))
            |> updateRecord

    deletedSlot <- createRosterSlotRecord openDay earlySlotName (Just eligibleStaff) 1
    now <- getCurrentTime
    _ <- deletedSlot |> set #deletedAt (Just now) |> set #deleteReason (Just "direct_read_fixture") |> updateRecord

    otherWeek <- createRosterWeekRecordForRosterGroup venue otherRosterGroup 0 False
    otherDay <- createRosterDayRecord otherWeek 0
    otherGroupSlot <- createRosterSlotRecord otherDay otherSlotName (Just eligibleStaff) 0

    pure DirectReadModelFixture { venue, windowScope, manager, rosterGroup, earlySlotName, rosterWeek, eligibleUser, eligibleStaff, assignedInactiveStaff = assignedInactiveStaff', visibleSparseSlot, closedDaySlot, otherGroupSlot }

allAssignmentFilters :: RosterAssignmentFilters
allAssignmentFilters =
    RosterAssignmentFilters
        { hideStaffAtIdealShifts = True
        , hideStaffUnavailable = True
        , hideStaffOnApprovedLeave = True
        , hideStaffAlreadyAssignedToday = True
        }

hasConflictType :: ConflictType -> Maybe [RosterConflict] -> Bool
hasConflictType expected = maybe False (any ((== expected) . (.conflictType)))

createStaffShiftPreferenceRecord :: (?modelContext :: ModelContext) => Venue -> Staff -> Int -> Int -> Int -> IO StaffShiftPreference
createStaffShiftPreferenceRecord venue staff weekdayIndex startHour endHour =
    newRecord @StaffShiftPreference
        |> set #venueId (unpackId venue.id)
        |> set #staffId (unpackId staff.id)
        |> set #weekdayIndex weekdayIndex
        |> set #preferredStartHour startHour
        |> set #preferredEndHour endHour
        |> createRecord
