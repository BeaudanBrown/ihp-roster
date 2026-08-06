module Test.EnumAuthoritySpec where

import Application.Helper.InvitationStatus
import Application.Helper.JobStatus
import Application.Helper.RosterTemplateScale
import Application.Helper.UserPreferences
import Application.Helper.View.Status
import Generated.Types
import IHP.Job.Types (JobStatus (..))
import IHP.Prelude
import Test.Hspec

tests :: Spec
tests = describe "generated enum authority" do
    it "projects every roster layout mode without rendered-text branching" do
        map rosterLayoutModeLabel [DayRows, DayColumns]
            `shouldBe` ["Day rows", "Day columns"]
        map rosterLayoutModeIsDayColumns [DayRows, DayColumns]
            `shouldBe` [False, True]

    it "projects every roster template scale through generated constructors" do
        map rosterTemplateScaleValue [Day, Week] `shouldBe` ["day", "week"]
        map rosterTemplateScaleLabel [Day, Week] `shouldBe` ["Day", "Week"]
        map rosterTemplateScaleIsWeek [Day, Week] `shouldBe` [False, True]
        map parseRosterTemplateScale ["day", "week", "month"]
            `shouldBe` [Just Day, Just Week, Nothing]

    it "projects every app job status through one typed presentation" do
        let statuses =
                [ JobStatusNotStarted
                , JobStatusRunning
                , JobStatusRetry
                , JobStatusSucceeded
                , JobStatusFailed
                , JobStatusTimedOut
                ]
        map jobStatusLabel statuses
            `shouldBe` ["queued", "running", "retrying", "succeeded", "failed", "timed out"]
        map jobStatusHasDiagnostic statuses
            `shouldBe` [False, False, True, False, True, True]
        map jobStatusBadgeClass statuses
            `shouldBe`
                [ "badge text-bg-secondary"
                , "badge text-bg-secondary"
                , "badge text-bg-warning"
                , "badge text-bg-success"
                , "badge text-bg-danger"
                , "badge text-bg-danger"
                ]

    it "projects every invitation status and delivery status nominally" do
        map invitationStatusAllowsRenewal [InvitationStatusEnumPending, Accepted, Revoked]
            `shouldBe` [True, False, False]
        map invitationLifecycleStatus [InvitationStatusEnumPending, Accepted, Revoked]
            `shouldBe`
                [ (AppStatusWarning, "Pending")
                , (AppStatusSuccess, "Accepted")
                , (AppStatusNeutral, "Revoked")
                ]
        map invitationDeliveryStatus [Queued, Sent, InvitationDeliveryStatusEnumFailed]
            `shouldBe`
                [ (AppStatusWarning, "Queued")
                , (AppStatusSuccess, "Sent")
                , (AppStatusDanger, "Send Failed")
                ]
