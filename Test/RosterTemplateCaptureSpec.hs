module Test.RosterTemplateCaptureSpec where

import Application.Helper.WeekBoundaries (weekdayIndexForDay)
import Application.RosterShiftAssignment (RosterShiftAssignment (..),
                                          applyRosterShiftAssignment)
import Application.RosterTemplates
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Time.Calendar (addDays, fromGregorian)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types hiding (createRosterTemplate)
import IHP.ControllerPrelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support
import Web.RosterWeeks.DateRange (RosterWindowScope, rosterWindowScopeForAnchor)
import Web.RosterWeeks.TemplateCapture

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Roster template date-native capture" do
        it "captures a mixed-publication window without persisting publication state or mutating its source" $ withContext do
            withCleanDb do
                fixture <- captureFixture "Mixed capture"
                let firstDay = fromMaybe (error "first capture day missing") (listToMaybe fixture.days)
                _ <- firstDay |> set #publicationState Published |> set #isClosed True |> updateRecord
                sourceSlot <- createCaptureSlot firstDay fixture.shiftType (StaffAssignment fixture.staff.id) 0
                sourceDaysBefore <- query @RosterDay |> filterWhereIn (#id, map (.id) fixture.days) |> orderByAsc #operationalDate |> fetch
                sourceSlotsBefore <- query @RosterSlot |> filterWhere (#id, sourceSlot.id) |> fetch
                let request = captureRequest fixture "Mixed standard" KeepValidStaffAssignments Map.empty

                Right preview <- previewRosterTemplateCapture fixture.actor request
                created <- confirmRosterTemplateCapture fixture.actor request preview.capturePreviewSourceRevision preview.capturePreviewCalendarRevision True
                sourceDaysAfter <- query @RosterDay |> filterWhereIn (#id, map (.id) fixture.days) |> orderByAsc #operationalDate |> fetch
                sourceSlotsAfter <- query @RosterSlot |> filterWhere (#id, sourceSlot.id) |> fetch

                let Right snapshot = created
                map (.weekdayIndex) snapshot.snapshotDays `shouldBe` map (Just . weekdayIndexForDay . (.operationalDate)) sourceDaysBefore
                map (.isClosed) snapshot.snapshotDays `shouldBe` map (.isClosed) sourceDaysBefore
                map (.name) snapshot.snapshotColumns `shouldBe` ["Early"]
                map (.assignmentState) snapshot.snapshotShifts `shouldBe` ["staff"]
                map (.startMinute) snapshot.snapshotShifts `shouldBe` [540]
                map (.endMinute) snapshot.snapshotShifts `shouldBe` [1020]
                sourceDaysAfter `shouldBe` sourceDaysBefore
                sourceSlotsAfter `shouldBe` sourceSlotsBefore

        it "captures a complete all-Published source without carrying publication into the snapshot" $ withContext do
            withCleanDb do
                fixture <- captureFixture "Published capture"
                publishedDays <- forM fixture.days (\day -> day |> set #publicationState Published |> updateRecord)
                _ <- createCaptureSlot (fixture.days !! 6) fixture.shiftType OpenAssignment 0
                let request = captureRequest fixture "Published standard" KeepValidStaffAssignments Map.empty

                Right preview <- previewRosterTemplateCapture fixture.actor request
                Right snapshot <- confirmRosterTemplateCapture fixture.actor request preview.capturePreviewSourceRevision preview.capturePreviewCalendarRevision False
                retainedDays <- query @RosterDay
                    |> filterWhereIn (#id, map (.id) fixture.days)
                    |> orderByAsc #operationalDate
                    |> fetch

                map (.publicationState) retainedDays `shouldBe` replicate 7 Published
                retainedDays `shouldBe` publishedDays
                map (.weekdayIndex) snapshot.snapshotDays `shouldBe` map (Just . weekdayIndexForDay . (.operationalDate)) retainedDays
                map (.assignmentState) snapshot.snapshotShifts `shouldBe` ["open"]

        it "captures an all-Draft source and makes every assignment Open without consulting durable Staff eligibility" $ withContext do
            withCleanDb do
                fixture <- captureFixture "Open capture"
                sourceSlot <- createCaptureSlot (fixture.days !! 1) fixture.shiftType (StaffAssignment fixture.staff.id) 0
                membership <- query @StaffRosterGroup
                    |> filterWhere (#staffId, unpackId fixture.staff.id)
                    |> filterWhere (#rosterGroupId, unpackId fixture.rosterGroup.id)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetchOne
                let now = captureArchivedAt
                _ <- membership |> set #deletedAt (Just now) |> updateRecord
                let request = captureRequest fixture "Reusable open" MakeEveryShiftOpen Map.empty

                Right preview <- previewRosterTemplateCapture fixture.actor request
                created <- confirmRosterTemplateCapture fixture.actor request preview.capturePreviewSourceRevision preview.capturePreviewCalendarRevision False
                retainedSource <- fetch sourceSlot.id

                preview.capturePreviewWarnings `shouldBe` []
                let Right snapshot = created
                map (.assignmentState) snapshot.snapshotShifts `shouldBe` ["open"]
                map (.staffId) snapshot.snapshotShifts `shouldBe` [Nothing]
                retainedSource.staffId `shouldBe` Just (unpackId fixture.staff.id)

        it "groups durable Staff invalidity and requires renewed confirmation before converting to Open" $ withContext do
            withCleanDb do
                fixture <- captureFixture "Staff warning capture"
                _ <- createCaptureSlot (fixture.days !! 2) fixture.shiftType (StaffAssignment fixture.staff.id) 0
                _ <- createCaptureSlot (fixture.days !! 3) fixture.shiftType (StaffAssignment fixture.staff.id) 0
                membership <- query @StaffRosterGroup
                    |> filterWhere (#staffId, unpackId fixture.staff.id)
                    |> filterWhere (#rosterGroupId, unpackId fixture.rosterGroup.id)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetchOne
                let now = captureArchivedAt
                _ <- membership |> set #deletedAt (Just now) |> updateRecord
                let request = captureRequest fixture "Warned capture" KeepValidStaffAssignments Map.empty

                Right preview <- previewRosterTemplateCapture fixture.actor request
                unconfirmed <- confirmRosterTemplateCapture fixture.actor request preview.capturePreviewSourceRevision preview.capturePreviewCalendarRevision False
                confirmed <- confirmRosterTemplateCapture fixture.actor request preview.capturePreviewSourceRevision preview.capturePreviewCalendarRevision True

                preview.capturePreviewWarnings `shouldBe`
                    [RosterTemplateCaptureWarning fixture.staff.id "Template Worker" CaptureStaffOutsideGroup 2]
                unconfirmed `shouldBe` Left RosterTemplateCaptureConfirmationRequired
                let Right snapshot = confirmed
                map (.assignmentState) snapshot.snapshotShifts `shouldBe` ["open", "open"]

        it "invalidates confirmation when durable Staff eligibility changes after preview" $ withContext do
            withCleanDb do
                fixture <- captureFixture "Concurrent Staff capture"
                _ <- createCaptureSlot (fixture.days !! 3) fixture.shiftType (StaffAssignment fixture.staff.id) 0
                let request = captureRequest fixture "Concurrent Staff" KeepValidStaffAssignments Map.empty
                Right preview <- previewRosterTemplateCapture fixture.actor request
                membership <- query @StaffRosterGroup
                    |> filterWhere (#staffId, unpackId fixture.staff.id)
                    |> filterWhere (#rosterGroupId, unpackId fixture.rosterGroup.id)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetchOne
                let now = captureArchivedAt
                _ <- membership |> set #deletedAt (Just now) |> updateRecord

                stale <- confirmRosterTemplateCapture fixture.actor request preview.capturePreviewSourceRevision preview.capturePreviewCalendarRevision True
                templateCount <- query @RosterTemplate |> fetchCount

                stale `shouldBe` Left RosterTemplateCaptureSourceConflict
                templateCount `shouldBe` 0

        it "rejects capture when the roster group is archived after preview" $ withContext do
            withCleanDb do
                fixture <- captureFixture "Archived group capture"
                let request = captureRequest fixture "Archived group" MakeEveryShiftOpen Map.empty
                Right preview <- previewRosterTemplateCapture fixture.actor request
                _ <- fixture.rosterGroup
                    |> set #isActive False
                    |> set #archivedAt (Just captureArchivedAt)
                    |> updateRecord

                result <- confirmRosterTemplateCapture fixture.actor request preview.capturePreviewSourceRevision preview.capturePreviewCalendarRevision False
                templateCount <- query @RosterTemplate |> fetchCount

                result `shouldBe` Left RosterTemplateCaptureSourceNotFound
                templateCount `shouldBe` 0

        it "requires one explicit mapping for a stale Shift type and changes only the template" $ withContext do
            withCleanDb do
                fixture <- captureFixture "Shift type mapping capture"
                sourceSlot <- createCaptureSlot (fixture.days !! 4) fixture.shiftType OpenAssignment 0
                let now = captureArchivedAt
                staleShiftType <- fixture.shiftType |> set #isActive False |> set #archivedAt (Just now) |> updateRecord
                replacement <- newRecord @ShiftType
                    |> set #venueId (unpackId fixture.venue.id)
                    |> set #name "Replacement"
                    |> set #isActive True
                    |> set #sortOrder 20
                    |> set #payAssignmentMode RosterOnly
                    |> createRecord
                let unmappedRequest = captureRequest fixture "Mapped capture" KeepValidStaffAssignments Map.empty

                Right unmapped <- previewRosterTemplateCapture fixture.actor unmappedRequest
                missing <- confirmRosterTemplateCapture fixture.actor unmappedRequest unmapped.capturePreviewSourceRevision unmapped.capturePreviewCalendarRevision False
                let mappedRequest = unmappedRequest { captureShiftTypeMappings = Map.singleton staleShiftType.id replacement.id }
                Right mapped <- previewRosterTemplateCapture fixture.actor mappedRequest
                created <- confirmRosterTemplateCapture fixture.actor mappedRequest mapped.capturePreviewSourceRevision mapped.capturePreviewCalendarRevision False
                retainedSource <- fetch sourceSlot.id

                map (.captureStaleShiftTypeId) unmapped.capturePreviewShiftTypeRequirements `shouldBe` [staleShiftType.id]
                unmapped.capturePreviewContent `shouldBe` Nothing
                missing `shouldBe` Left (RosterTemplateCaptureShiftTypeMappingsRequired [staleShiftType.id])
                let Right snapshot = created
                map (.shiftTypeId) snapshot.snapshotShifts `shouldBe` [unpackId replacement.id]
                retainedSource.shiftTypeId `shouldBe` Just (unpackId staleShiftType.id)

        it "rejects duplicate normalized column names within one source day" $ withContext do
            withCleanDb do
                fixture <- captureFixture "Duplicate source columns"
                let sourceDay = fixture.days !! 0
                _ <- newRecord @RosterLane
                    |> set #rosterDayId (unpackId sourceDay.id)
                    |> set #name "Early"
                    |> set #sortOrder 0
                    |> createRecord
                _ <- newRecord @RosterLane
                    |> set #rosterDayId (unpackId sourceDay.id)
                    |> set #name " early "
                    |> set #sortOrder 1
                    |> createRecord
                let request = captureRequest fixture "Duplicate columns" KeepValidStaffAssignments Map.empty

                preview <- previewRosterTemplateCapture fixture.actor request

                preview `shouldBe` Left (RosterTemplateCaptureInvalidStructure "The viewed roster contains duplicate column names on one day.")

        it "rejects a stale source confirmation atomically" $ withContext do
            withCleanDb do
                fixture <- captureFixture "Capture conflicts"
                _ <- createCaptureSlot (fixture.days !! 5) fixture.shiftType OpenAssignment 0
                let request = captureRequest fixture "Conflict capture" KeepValidStaffAssignments Map.empty
                Right preview <- previewRosterTemplateCapture fixture.actor request
                _ <- fixture.days !! 5 |> set #isClosed True |> updateRecord

                stale <- confirmRosterTemplateCapture fixture.actor request preview.capturePreviewSourceRevision preview.capturePreviewCalendarRevision False
                templateCount <- query @RosterTemplate |> fetchCount

                stale `shouldBe` Left RosterTemplateCaptureSourceConflict
                templateCount `shouldBe` 0

        it "rejects an incomplete date-native source window" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Incomplete capture"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "incomplete-capture@example.com" "staff" True
                let windowStart = testAnchorForOffset 21
                _ <- forM ([0 .. 5] :: [Int]) (\dayIndex -> createNativeRosterDayRecord venue rosterGroup (addDays (toInteger dayIndex) windowStart) dayIndex)
                let actor = rosterTemplateActor manager venue True
                    request = RosterTemplateCaptureRequest
                        { captureSourceScope = rosterWindowScopeForAnchor venueConfig rosterGroup.id windowStart
                        , captureRequestedName = "Incomplete capture"
                        , captureAssignmentMode = KeepValidStaffAssignments
                        , captureShiftTypeMappings = Map.empty
                        }

                incomplete <- previewRosterTemplateCapture actor request

                incomplete `shouldBe` Left (RosterTemplateCaptureInvalidStructure "The viewed roster window must contain all seven operational days.")

captureArchivedAt :: UTCTime
captureArchivedAt = UTCTime (fromGregorian 2026 8 24) 0

data CaptureFixture = CaptureFixture
    { venue       :: !Venue
    , rosterGroup :: !RosterGroup
    , manager     :: !User
    , staff       :: !Staff
    , shiftType   :: !ShiftType
    , days        :: ![RosterDay]
    , actor       :: !RosterTemplateActor
    , scope       :: !RosterWindowScope
    }

captureFixture :: (?modelContext :: ModelContext) => Text -> IO CaptureFixture
captureFixture label = do
    venue <- createVenueWithConfig label
    venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
    rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
    manager <- createUserRecord (Text.toCaseFold (Text.replace " " "-" label) <> "@example.com") "staff" True
    staff <- createStaffRecord venue Nothing "Template" "Worker"
    shiftType <- ensureVenueDefaultShiftType venue
    let windowStart = testAnchorForOffset 20
    days <- forM ([0 .. 6] :: [Int]) (\dayIndex -> createNativeRosterDayRecord venue rosterGroup (addDays (toInteger dayIndex) windowStart) dayIndex)
    let actor = rosterTemplateActor manager venue True
        scope = rosterWindowScopeForAnchor venueConfig rosterGroup.id windowStart
    pure CaptureFixture { .. }

captureRequest :: CaptureFixture -> Text -> RosterTemplateCaptureAssignmentMode -> Map.Map (Id ShiftType) (Id ShiftType) -> RosterTemplateCaptureRequest
captureRequest fixture name assignmentMode mappings =
    RosterTemplateCaptureRequest
        { captureSourceScope = fixture.scope
        , captureRequestedName = name
        , captureAssignmentMode = assignmentMode
        , captureShiftTypeMappings = mappings
        }

createCaptureSlot :: (?modelContext :: ModelContext) => RosterDay -> ShiftType -> RosterShiftAssignment -> Int -> IO RosterSlot
createCaptureSlot rosterDay shiftType assignment rowIndex = do
    lane <- query @RosterLane
        |> filterWhere (#rosterDayId, unpackId rosterDay.id)
        |> filterWhere (#name, "Early")
        |> filterWhere (#deletedAt, Nothing)
        |> fetchOneOrNothing
        >>= maybe
            (newRecord @RosterLane
                |> set #rosterDayId (unpackId rosterDay.id)
                |> set #name "Early"
                |> set #sortOrder 0
                |> createRecord)
            pure
    newRecord @RosterSlot
        |> set #rosterDayId (unpackId rosterDay.id)
        |> set #rosterLaneId (unpackId lane.id)
        |> set #slotSortOrder 0
        |> set #rowIndex rowIndex
        |> set #shiftTypeId (Just (unpackId shiftType.id))
        |> applyRosterShiftAssignment assignment
        |> setTestRosterSlotBoundaries rosterDay.operationalDate (TimeOfDay 9 0 0) (TimeOfDay 17 0 0)
        |> createRecord
