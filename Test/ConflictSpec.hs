module Test.ConflictSpec where

import Application.Helper.Conflict
import Application.Helper.Controller (unsafeEnumFromText)
import Data.Time.Calendar (fromGregorian)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ModelSupport (unpackId)
import IHP.Prelude
import Test.Hspec

tests :: Spec
tests = describe "Conflict Engine" do
    let mockDate = fromGregorian 2025 1 6 -- A Monday

    let mockRosterDay = RosterDay
            { id = def
            , rosterWeekId = def
            , dayOffset = 0
            , isClosed = False
            , createdAt = def
            , updatedAt = def
            , meta = def
            }

    let mockSlot = RosterSlot
            { id = def
            , rosterDayId = def
            , staffId = Nothing
            , slotNameId = def
            , slotSortOrder = 0
            , rowIndex = 0
            , startTime = def
            , durationMinutes = Nothing
            , note = Nothing
            , deletedAt = Nothing
            , deletedByUserId = Nothing
            , deleteReason = Nothing
            , createdAt = def
            , updatedAt = def
            , meta = def
            }

    let mkContext slotOverrides =
            slotOverrides ConflictContext
                { slot = mockSlot
                , rosterGroupId = "00000000-0000-0000-0000-0000000000ff"
                , weekSlots = [mockSlot]
                , daySlots = [mockSlot]
                , weekRosterDays = [mockRosterDay]
                , leaveRequests = []
                , shiftPreferences = []
                , rosterDayDate = mockDate
                , lateToEarlyMinStartGapMinutes = 600
                , staffIdealShifts = Nothing
                }

    let mockLeaveRequest = LeaveRequest
            { id = def
            , venueId = def
            , staffId = def
            , startDate = fromGregorian 2025 1 5
            , endDate = fromGregorian 2025 1 7
            , status = unsafeEnumFromText @LeaveRequestStatusEnum "approved"
            , notes = Nothing
            , deletedAt = Nothing
            , deletedByUserId = Nothing
            , deleteReason = Nothing
            , createdAt = def
            , updatedAt = def
            , meta = def
            }

    let mockShiftPreference = StaffShiftPreference
            { id = def
            , venueId = def
            , staffId = "00000000-0000-0000-0000-0000000000aa"
            , rosterGroupId = "00000000-0000-0000-0000-0000000000ff"
            , weekdayIndex = 1
            , preferredStartHour = 0
            , preferredEndHour = 23
            , deletedAt = Nothing
            , deletedByUserId = Nothing
            , deleteReason = Nothing
            , createdAt = def
            , updatedAt = def
            , meta = def
            }

    let mkShiftPreference staffUuid weekdayIndex = StaffShiftPreference
            { id = def
            , venueId = def
            , staffId = staffUuid
            , rosterGroupId = "00000000-0000-0000-0000-0000000000ff"
            , weekdayIndex = weekdayIndex
            , preferredStartHour = 0
            , preferredEndHour = 23
            , deletedAt = Nothing
            , deletedByUserId = Nothing
            , deleteReason = Nothing
            , createdAt = def
            , updatedAt = def
            , meta = def
            }

    it "detects duplicate assignments on the same day" do
        let ctx = mkContext \base ->
                base
                    { weekSlots = [mockSlot, mockSlot]
                    , daySlots = [mockSlot, mockSlot]
                    }
        let conflicts = evaluateConflicts ctx
        length conflicts `shouldBe` 1
        map conflictType conflicts `shouldBe` [DuplicateAssignment]

    it "detects leave conflicts for approved leave on the given day" do
        let ctx = mkContext \base ->
                base { leaveRequests = [mockLeaveRequest] }
        let conflicts = evaluateConflicts ctx
        length conflicts `shouldBe` 1
        map conflictType conflicts `shouldBe` [LeaveConflict]

    it "does not treat available-again date as unavailable" do
        let ctx = mkContext \base ->
                base
                    { rosterDayDate = fromGregorian 2025 1 7
                    , leaveRequests = [mockLeaveRequest]
                    }
        let conflicts = evaluateConflicts ctx
        map conflictType conflicts `shouldBe` []

    it "detects ideal-shift threshold exceeded" do
        let ctx = mkContext \base ->
                base
                    { weekSlots = [mockSlot, mockSlot, mockSlot]
                    , staffIdealShifts = Just 2
                    }
        let conflicts = evaluateConflicts ctx
        length conflicts `shouldBe` 1
        map conflictType conflicts `shouldBe` [IdealShiftThresholdExceeded]

    it "warns when no preferred shifts exist for the day in the roster group" do
        let assignedSlot =
                (mockSlot :: RosterSlot)
                    { staffId = Just "00000000-0000-0000-0000-0000000000aa"
                    }
        let ctx = mkContext \base ->
                base
                    { slot = assignedSlot
                    , weekSlots = [assignedSlot]
                    , daySlots = [assignedSlot]
                    }
        let conflicts = evaluateConflicts ctx
        map conflictType conflicts `shouldBe` [ShiftPreferenceDayUnavailable]

    it "warns when the assigned start time is outside the preferred start window" do
        let assignedSlot =
                (mockSlot :: RosterSlot)
                    { staffId = Just "00000000-0000-0000-0000-0000000000aa"
                    , startTime = Just (TimeOfDay 8 0 0)
                    }
        let narrowPreference = mockShiftPreference
                { preferredStartHour = 12
                , preferredEndHour = 20
                }
        let ctx = mkContext \base ->
                base
                    { slot = assignedSlot
                    , weekSlots = [assignedSlot]
                    , daySlots = [assignedSlot]
                    , shiftPreferences = [narrowPreference]
                    }
        let conflicts = evaluateConflicts ctx
        map conflictType conflicts `shouldBe` [ShiftPreferenceSlotMismatch]

    it "does not warn when the assigned start time is inside the preferred start window" do
        let assignedSlot =
                (mockSlot :: RosterSlot)
                    { staffId = Just "00000000-0000-0000-0000-0000000000aa"
                    , startTime = Just (TimeOfDay 17 0 0)
                    }
        let narrowPreference = mockShiftPreference
                { preferredStartHour = 12
                , preferredEndHour = 20
                }
        let ctx = mkContext \base ->
                base
                    { slot = assignedSlot
                    , weekSlots = [assignedSlot]
                    , daySlots = [assignedSlot]
                    , shiftPreferences = [narrowPreference]
                    }
        let conflicts = evaluateConflicts ctx
        conflicts `shouldBe` []

    it "sorts multiple conflicts by severity/priority" do
        let ctx = mkContext \base ->
                base
                    { weekSlots = [mockSlot, mockSlot, mockSlot]
                    , daySlots = [mockSlot, mockSlot] -- duplicate
                    , staffIdealShifts = Just 2 -- ideal exceeded
                    }
        let conflicts = evaluateConflicts ctx
        length conflicts `shouldBe` 2
        map conflictType conflicts `shouldBe` [DuplicateAssignment, IdealShiftThresholdExceeded]

    it "detects late-to-early when start-to-start gap is below threshold" do
        let day0 = mockRosterDay { id = "00000000-0000-0000-0000-000000000000", dayOffset = 0 }
        let day1 = mockRosterDay { id = "00000000-0000-0000-0000-000000000001", dayOffset = 1 }
        let lateSlot = mockSlot
                { id = "00000000-0000-0000-0000-000000000010"
                , rosterDayId = unpackId day0.id
                , staffId = Just "00000000-0000-0000-0000-0000000000aa"
                , startTime = Just (TimeOfDay 22 0 0)
                }
        let earlySlot = mockSlot
                { id = "00000000-0000-0000-0000-000000000011"
                , rosterDayId = unpackId day1.id
                , staffId = Just "00000000-0000-0000-0000-0000000000aa"
                , startTime = Just (TimeOfDay 5 0 0)
                }
        let ctx = mkContext \base ->
                base
                    { slot = earlySlot
                    , weekSlots = [lateSlot, earlySlot]
                    , daySlots = [earlySlot]
                    , weekRosterDays = [day0, day1]
                    , rosterDayDate = fromGregorian 2025 1 7
                    , shiftPreferences =
                        [ mkShiftPreference "00000000-0000-0000-0000-0000000000aa" 2
                        ]
                    , lateToEarlyMinStartGapMinutes = 600
                    }
        let conflicts = evaluateConflicts ctx
        map conflictType conflicts `shouldBe` [LateToEarlyConflict]

    it "does not detect late-to-early when gap equals threshold" do
        let day0 = mockRosterDay { id = "00000000-0000-0000-0000-000000000000", dayOffset = 0 }
        let day1 = mockRosterDay { id = "00000000-0000-0000-0000-000000000001", dayOffset = 1 }
        let lateSlot = mockSlot
                { id = "00000000-0000-0000-0000-000000000020"
                , rosterDayId = unpackId day0.id
                , staffId = Just "00000000-0000-0000-0000-0000000000bb"
                , startTime = Just (TimeOfDay 22 0 0)
                }
        let earlySlot = mockSlot
                { id = "00000000-0000-0000-0000-000000000021"
                , rosterDayId = unpackId day1.id
                , staffId = Just "00000000-0000-0000-0000-0000000000bb"
                , startTime = Just (TimeOfDay 8 0 0)
                }
        let ctx = mkContext \base ->
                base
                    { slot = earlySlot
                    , weekSlots = [lateSlot, earlySlot]
                    , daySlots = [earlySlot]
                    , weekRosterDays = [day0, day1]
                    , rosterDayDate = fromGregorian 2025 1 7
                    , shiftPreferences =
                        [ mkShiftPreference "00000000-0000-0000-0000-0000000000bb" 2
                        ]
                    , lateToEarlyMinStartGapMinutes = 600
                    }
        let conflicts = evaluateConflicts ctx
        map conflictType conflicts `shouldBe` []

    it "selects duplicate-assignment as primary conflict in multi-rule scenarios" do
        let day0 = mockRosterDay { id = "00000000-0000-0000-0000-000000000100", dayOffset = 0 }
        let day1 = mockRosterDay { id = "00000000-0000-0000-0000-000000000101", dayOffset = 1 }
        let staffUuid = "00000000-0000-0000-0000-0000000000cc"
        let previousLateSlot = mockSlot
                { id = "00000000-0000-0000-0000-000000000110"
                , rosterDayId = unpackId day0.id
                , staffId = Just staffUuid
                , startTime = Just (TimeOfDay 22 0 0)
                }
        let currentEarlySlot = mockSlot
                { id = "00000000-0000-0000-0000-000000000111"
                , rosterDayId = unpackId day1.id
                , staffId = Just staffUuid
                , startTime = Just (TimeOfDay 5 0 0)
                }
        let duplicateSameDaySlot = mockSlot
                { id = "00000000-0000-0000-0000-000000000112"
                , rosterDayId = unpackId day1.id
                , staffId = Just staffUuid
                , startTime = Just (TimeOfDay 10 0 0)
                }
        let ctx = mkContext \base ->
                base
                    { slot = currentEarlySlot
                    , weekSlots = [previousLateSlot, currentEarlySlot, duplicateSameDaySlot]
                    , daySlots = [currentEarlySlot, duplicateSameDaySlot]
                    , weekRosterDays = [day0, day1]
                    , rosterDayDate = fromGregorian 2025 1 7
                    , lateToEarlyMinStartGapMinutes = 600
                    , shiftPreferences =
                        [ mkShiftPreference staffUuid 2
                        ]
                    , staffIdealShifts = Just 2
                    }
        let conflicts = evaluateConflicts ctx
        map conflictType conflicts `shouldBe` [DuplicateAssignment, LateToEarlyConflict, IdealShiftThresholdExceeded]
        (conflictType <$> primaryConflict conflicts) `shouldBe` Just DuplicateAssignment
