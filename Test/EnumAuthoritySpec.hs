module Test.EnumAuthoritySpec where

import Application.Helper.FeedbackType
import Application.Helper.InvitationStatus
import Application.Helper.JobStatus
import Application.Helper.ShiftTypeColours
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

    it "projects persisted feedback and shift-colour enums exhaustively" do
        map feedbackTypeLabel [Bug, Suggestion, Other]
            `shouldBe` ["bug", "suggestion", "other"]
        map shiftTypeColourKeyCssValue [NoColour, Palette1, Palette2, Palette3, Palette4, Palette5, Palette6, Palette7, Palette8, Palette9, Palette10]
            `shouldBe` ["", "palette-1", "palette-2", "palette-3", "palette-4", "palette-5", "palette-6", "palette-7", "palette-8", "palette-9", "palette-10"]

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
