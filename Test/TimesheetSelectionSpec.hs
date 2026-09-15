module Test.TimesheetSelectionSpec where

import Application.Helper.TimesheetSelection
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..), addUTCTime)
import Generated.Types
import IHP.ControllerPrelude
import Test.Hspec

tests :: Spec
tests = describe "Timesheet selection" do
    it "round trips explicit controls without falling back to all" do
        parseExplicitTimesheetSelection [encodeTimesheetSelectionIdentity identity] `shouldBe` Right selection
        parseExplicitTimesheetSelection [] `shouldBe` Left EmptyTimesheetSelection
        parseExplicitTimesheetSelection ["not-json"] `shouldBe` Left InvalidTimesheetSelection
    it "deduplicates identical controls and preserves candidate order" do
        validate (ExplicitSelection [identity, identity]) [entry] `shouldBe` Right [entry]
    it "does not include newly approved candidates" do
        let later = entry |> set #id "00000000-0000-0000-0000-000000000002"
        validate selection [entry, later] `shouldBe` Right [entry]
        validate AllEligible [entry, later] `shouldBe` Right [entry, later]
    it "rejects empty selections and missing entries" do
        validate (ExplicitSelection []) [entry] `shouldBe` Left EmptyTimesheetSelection
        validate selection [] `shouldBe` Left ChangedTimesheetSelection
    it "rejects foreign, unapproved, deleted, moved and edited entries" do
        let changed =
                [ entry |> set #venueId "00000000-0000-0000-0000-000000000099"
                , entry |> set #isApproved False
                , entry |> set #deletedAt (Just clock)
                , entry |> set #operationalDate (addDays 1 day)
                , entry |> set #updatedAt (addUTCTime 1 clock)
                , entry |> set #approvedAt (Just (addUTCTime 1 clock))
                , entry |> set #activePayCalculationId (Just "00000000-0000-0000-0000-000000000003")
                , entry |> set #staffPayVersionId (Just "00000000-0000-0000-0000-000000000004")
                , entry |> set #shiftTypePayVersionId (Just "00000000-0000-0000-0000-000000000005")
                ]
        forM_ changed \candidate -> validate selection [candidate] `shouldBe` Left ChangedTimesheetSelection
    it "includes both operational-date boundaries" do
        validate selection [entry] `shouldBe` Right [entry]
        validateTimesheetSelection entry.venueId (addDays (-1) day) day selection [entry] `shouldBe` Right [entry]
    it "rejects conflicting duplicate controls" do
        let changedIdentity = timesheetSelectionIdentity (entry |> set #updatedAt (addUTCTime 1 clock))
        validate (ExplicitSelection [identity, changedIdentity]) [entry] `shouldBe` Left InvalidTimesheetSelection
  where
    day = fromGregorian 2026 9 14
    clock = UTCTime day 0
    entry = newRecord @TimesheetEntry
        |> set #id "00000000-0000-0000-0000-000000000001"
        |> set #venueId "00000000-0000-0000-0000-000000000010"
        |> set #isApproved True
        |> set #approvedAt (Just clock)
        |> set #updatedAt clock
        |> set #operationalDate day
    identity = timesheetSelectionIdentity entry
    selection = ExplicitSelection [identity]
    validate = validateTimesheetSelection entry.venueId day day
