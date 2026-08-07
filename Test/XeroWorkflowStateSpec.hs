module Test.XeroWorkflowStateSpec where

import Application.Helper.XeroAdminTypes (XeroTimesheetPreparationState (..),
                                          xeroPreparationStateFromStatus)
import Application.Xero.WorkflowState
import Generated.Types
import IHP.Prelude
import Test.Hspec

tests :: Spec
tests =
    describe "typed Xero workflow state authority" do
        it "classifies mapping, selection, requirement, and decision capabilities exhaustively" do
            map xeroStaffMappingStatusFlags [XeroStaffMappingStatusEnumVerified, NotApplicable, XeroStaffMappingStatusEnumStale]
                `shouldBe` [(True, False), (False, True), (False, False)]
            map xeroEarningsRateMappingIsVerified [Unmapped, XeroEarningsRateMappingStatusEnumVerified, XeroEarningsRateMappingStatusEnumStale]
                `shouldBe` [False, True, False]
            map xeroAccountCodeSelectionIsVerified [None, XeroPayItemAccountCodeSelectionStatusEnumVerified, XeroPayItemAccountCodeSelectionStatusEnumStale]
                `shouldBe` [False, True, False]
            map xeroPayItemRequirementStatusFlags
                [ XeroPayItemRequirementStatusEnumProposed
                , Matched
                , XeroPayItemRequirementStatusEnumCreated
                , Ignored
                , XeroPayItemRequirementStatusEnumStale
                , RateChanged
                ]
                `shouldBe`
                    [ (True, False, False)
                    , (False, False, True)
                    , (False, False, True)
                    , (False, True, False)
                    , (False, False, False)
                    , (False, False, False)
                    ]
            map xeroPreparationDecisionKindFlags
                [ StaffAutoMatch
                , StaffManualMapping
                , StaffNotPaid
                , StaffStepApproved
                , PayItemCreate
                , AccountCode
                , CalendarSelection
                ]
                `shouldBe`
                    [ (False, True, False, True)
                    , (False, False, False, True)
                    , (False, False, False, True)
                    , (False, False, True, False)
                    , (True, False, False, False)
                    , (False, False, False, False)
                    , (False, False, False, False)
                    ]
            map xeroPreparationDecisionStatusFlags
                [ XeroTimesheetPreparationDecisionStatusEnumPending
                , XeroTimesheetPreparationDecisionStatusEnumProposed
                , Applied
                , XeroTimesheetPreparationDecisionStatusEnumBlocked
                , XeroTimesheetPreparationDecisionStatusEnumResolved
                , Dismissed
                ]
                `shouldBe`
                    [ (True, False)
                    , (False, False)
                    , (False, True)
                    , (False, False)
                    , (False, False)
                    , (False, False)
                    ]

        it "projects every preparation and submission state without text branching" do
            map xeroPreparationStateFromStatus
                [ Started
                , Preparing
                , NeedsReconnect
                , NeedsApproval
                , XeroTimesheetPreparationRunStatusEnumBlocked
                , XeroTimesheetPreparationRunStatusEnumResolved
                , ReadyForPreview
                , XeroTimesheetPreparationRunStatusEnumPreviewed
                , XeroTimesheetPreparationRunStatusEnumSubmitted
                , XeroTimesheetPreparationRunStatusEnumFailed
                , Cancelled
                ]
                `shouldBe`
                    [ XeroPreparationPreparing
                    , XeroPreparationPreparing
                    , XeroPreparationNeedsReconnect
                    , XeroPreparationNeedsDecision
                    , XeroPreparationBlocked
                    , XeroPreparationNeedsDecision
                    , XeroPreparationReadyForPreview
                    , XeroPreparationPreviewed
                    , XeroPreparationSubmitted
                    , XeroPreparationFailed
                    , XeroPreparationFailed
                    ]
            let submissionStatuses =
                    [ XeroTimesheetSubmissionStatusEnumBlocked
                    , XeroTimesheetSubmissionStatusEnumPending
                    , XeroTimesheetSubmissionStatusEnumSubmitted
                    , XeroTimesheetSubmissionStatusEnumFailed
                    , Skipped
                    , XeroTimesheetSubmissionStatusEnumSuperseded
                    ]
            map xeroSubmissionStatusFlags submissionStatuses
                `shouldBe` [(False, False), (True, False), (False, True), (False, False), (False, False), (False, False)]
            map xeroSubmissionIsInProgress submissionStatuses
                `shouldBe` [False, True, False, False, False, False]
            map xeroSubmissionIsSubmitted submissionStatuses
                `shouldBe` [False, False, True, False, False, False]
            map xeroSubmissionTerminalRunStatus submissionStatuses
                `shouldBe`
                    [ Just XeroSubmissionRunStatusEnumBlocked
                    , Nothing
                    , Just XeroSubmissionRunStatusEnumSubmitted
                    , Just XeroSubmissionRunStatusEnumFailed
                    , Nothing
                    , Nothing
                    ]
            map xeroSubmissionRunPeriodLabel
                [ XeroSubmissionRunStatusEnumPreviewed
                , XeroSubmissionRunStatusEnumBlocked
                , XeroSubmissionRunStatusEnumPending
                , XeroSubmissionRunStatusEnumSubmitted
                , PartiallyFailed
                , XeroSubmissionRunStatusEnumFailed
                , XeroSubmissionRunStatusEnumSuperseded
                ]
                `shouldBe`
                    [ " · previewed previously"
                    , " · blocked previously"
                    , " · submission pending"
                    , " · submitted already"
                    , " · partially submitted"
                    , " · failed previously"
                    , ""
                    ]
