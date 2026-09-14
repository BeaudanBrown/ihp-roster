module Test.ConflictSpec where

import Application.Helper.Conflict
import IHP.Prelude
import Test.Hspec

tests :: Spec
tests = describe "Conflict ordering" do
    it "retains critical and advisory severity for every shared conflict type" do
        map getConflictSeverity
            [ ConflictDetailsUnavailable, InvalidRosterTiming, DuplicateAssignment
            , LeaveConflict, LateToEarlyConflict, ShiftPreferenceDayUnavailable
            , ShiftPreferenceSlotMismatch, IdealShiftThresholdExceeded
            ] `shouldBe`
            [ CriticalConflict, CriticalConflict, CriticalConflict, CriticalConflict
            , CriticalConflict, AdvisoryConflict, AdvisoryConflict, AdvisoryConflict
            ]

    it "orders shared conflicts by priority and retains equal-priority input order" do
        let conflicts =
                [ RosterConflict IdealShiftThresholdExceeded AdvisoryConflict "ideal"
                , RosterConflict LeaveConflict CriticalConflict "leave"
                , RosterConflict InvalidRosterTiming CriticalConflict "timing"
                , RosterConflict ConflictDetailsUnavailable CriticalConflict "unknown"
                , RosterConflict ShiftPreferenceSlotMismatch AdvisoryConflict "window"
                , RosterConflict DuplicateAssignment CriticalConflict "duplicate"
                , RosterConflict ShiftPreferenceDayUnavailable AdvisoryConflict "day"
                , RosterConflict LateToEarlyConflict CriticalConflict "gap"
                ]
        map (.conflictType) (sort conflicts) `shouldBe`
            [ InvalidRosterTiming, ConflictDetailsUnavailable, DuplicateAssignment
            , LeaveConflict, LateToEarlyConflict, ShiftPreferenceDayUnavailable
            , ShiftPreferenceSlotMismatch, IdealShiftThresholdExceeded
            ]
        primaryConflict conflicts `shouldBe` Just (RosterConflict InvalidRosterTiming CriticalConflict "timing")

    it "has no primary warning for an empty conflict list" do
        primaryConflict [] `shouldBe` Nothing
