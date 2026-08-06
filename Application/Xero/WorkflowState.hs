{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

-- | Exhaustive semantic projections for app-owned persisted Xero workflow state.
-- Provider-owned Xero status text does not enter this module.
module Application.Xero.WorkflowState
    ( xeroAccountCodeSelectionIsVerified
    , xeroEarningsRateMappingIsVerified
    , xeroPayItemRequirementIsIgnored
    , xeroPayItemRequirementIsProposed
    , xeroPayItemRequirementIsUsable
    , xeroPayItemRequirementStatusFlags
    , xeroPreparationDecisionIsApplied
    , xeroPreparationDecisionIsPending
    , xeroPreparationDecisionKindFlags
    , xeroPreparationDecisionStatusFlags
    , xeroPreparationKindIsPayItemCreate
    , xeroPreparationKindIsStaffAutoMatch
    , xeroPreparationKindIsStaffMappingDecision
    , xeroPreparationKindIsStaffStepApproval
    , xeroStaffMappingIsNotApplicable
    , xeroStaffMappingIsVerified
    , xeroStaffMappingStatusFlags
    , xeroSubmissionRunPeriodLabel
    , xeroSubmissionTerminalRunStatus
    ) where

import Generated.Types
import IHP.Prelude

xeroStaffMappingStatusFlags :: XeroStaffMappingStatusEnum -> (Bool, Bool)
xeroStaffMappingStatusFlags XeroStaffMappingStatusEnumVerified = (True, False)
xeroStaffMappingStatusFlags NotApplicable = (False, True)
xeroStaffMappingStatusFlags XeroStaffMappingStatusEnumStale = (False, False)

xeroStaffMappingIsVerified :: XeroStaffMappingStatusEnum -> Bool
xeroStaffMappingIsVerified = fst . xeroStaffMappingStatusFlags

xeroStaffMappingIsNotApplicable :: XeroStaffMappingStatusEnum -> Bool
xeroStaffMappingIsNotApplicable = snd . xeroStaffMappingStatusFlags

xeroEarningsRateMappingIsVerified :: XeroEarningsRateMappingStatusEnum -> Bool
xeroEarningsRateMappingIsVerified Unmapped = False
xeroEarningsRateMappingIsVerified XeroEarningsRateMappingStatusEnumVerified = True
xeroEarningsRateMappingIsVerified XeroEarningsRateMappingStatusEnumStale = False

xeroAccountCodeSelectionIsVerified :: XeroPayItemAccountCodeSelectionStatusEnum -> Bool
xeroAccountCodeSelectionIsVerified None = False
xeroAccountCodeSelectionIsVerified XeroPayItemAccountCodeSelectionStatusEnumVerified = True
xeroAccountCodeSelectionIsVerified XeroPayItemAccountCodeSelectionStatusEnumStale = False

-- | @(is proposed, is ignored, is backed by a usable Xero rate)@.
xeroPayItemRequirementStatusFlags :: XeroPayItemRequirementStatusEnum -> (Bool, Bool, Bool)
xeroPayItemRequirementStatusFlags XeroPayItemRequirementStatusEnumProposed = (True, False, False)
xeroPayItemRequirementStatusFlags Matched = (False, False, True)
xeroPayItemRequirementStatusFlags XeroPayItemRequirementStatusEnumCreated = (False, False, True)
xeroPayItemRequirementStatusFlags Ignored = (False, True, False)
xeroPayItemRequirementStatusFlags XeroPayItemRequirementStatusEnumStale = (False, False, False)
xeroPayItemRequirementStatusFlags RateChanged = (False, False, False)

xeroPayItemRequirementIsProposed :: XeroPayItemRequirementStatusEnum -> Bool
xeroPayItemRequirementIsProposed status = let (value, _, _) = xeroPayItemRequirementStatusFlags status in value

xeroPayItemRequirementIsIgnored :: XeroPayItemRequirementStatusEnum -> Bool
xeroPayItemRequirementIsIgnored status = let (_, value, _) = xeroPayItemRequirementStatusFlags status in value

xeroPayItemRequirementIsUsable :: XeroPayItemRequirementStatusEnum -> Bool
xeroPayItemRequirementIsUsable status = let (_, _, value) = xeroPayItemRequirementStatusFlags status in value

-- | @(is pay-item creation, is staff auto-match, is staff-step approval,
-- is a staff mapping choice)@.
xeroPreparationDecisionKindFlags :: XeroTimesheetPreparationDecisionKindEnum -> (Bool, Bool, Bool, Bool)
xeroPreparationDecisionKindFlags StaffAutoMatch = (False, True, False, True)
xeroPreparationDecisionKindFlags StaffManualMapping = (False, False, False, True)
xeroPreparationDecisionKindFlags StaffNotPaid = (False, False, False, True)
xeroPreparationDecisionKindFlags StaffStepApproved = (False, False, True, False)
xeroPreparationDecisionKindFlags PayItemCreate = (True, False, False, False)
xeroPreparationDecisionKindFlags AccountCode = (False, False, False, False)
xeroPreparationDecisionKindFlags CalendarSelection = (False, False, False, False)

xeroPreparationKindIsPayItemCreate :: XeroTimesheetPreparationDecisionKindEnum -> Bool
xeroPreparationKindIsPayItemCreate kind = let (value, _, _, _) = xeroPreparationDecisionKindFlags kind in value

xeroPreparationKindIsStaffAutoMatch :: XeroTimesheetPreparationDecisionKindEnum -> Bool
xeroPreparationKindIsStaffAutoMatch kind = let (_, value, _, _) = xeroPreparationDecisionKindFlags kind in value

xeroPreparationKindIsStaffStepApproval :: XeroTimesheetPreparationDecisionKindEnum -> Bool
xeroPreparationKindIsStaffStepApproval kind = let (_, _, value, _) = xeroPreparationDecisionKindFlags kind in value

xeroPreparationKindIsStaffMappingDecision :: XeroTimesheetPreparationDecisionKindEnum -> Bool
xeroPreparationKindIsStaffMappingDecision kind = let (_, _, _, value) = xeroPreparationDecisionKindFlags kind in value

-- | @(is pending, is applied)@.
xeroPreparationDecisionStatusFlags :: XeroTimesheetPreparationDecisionStatusEnum -> (Bool, Bool)
xeroPreparationDecisionStatusFlags XeroTimesheetPreparationDecisionStatusEnumPending = (True, False)
xeroPreparationDecisionStatusFlags XeroTimesheetPreparationDecisionStatusEnumProposed = (False, False)
xeroPreparationDecisionStatusFlags Applied = (False, True)
xeroPreparationDecisionStatusFlags XeroTimesheetPreparationDecisionStatusEnumBlocked = (False, False)
xeroPreparationDecisionStatusFlags XeroTimesheetPreparationDecisionStatusEnumResolved = (False, False)
xeroPreparationDecisionStatusFlags Dismissed = (False, False)

xeroPreparationDecisionIsPending :: XeroTimesheetPreparationDecisionStatusEnum -> Bool
xeroPreparationDecisionIsPending = fst . xeroPreparationDecisionStatusFlags

xeroPreparationDecisionIsApplied :: XeroTimesheetPreparationDecisionStatusEnum -> Bool
xeroPreparationDecisionIsApplied = snd . xeroPreparationDecisionStatusFlags

xeroSubmissionTerminalRunStatus :: XeroTimesheetSubmissionStatusEnum -> Maybe XeroSubmissionRunStatusEnum
xeroSubmissionTerminalRunStatus XeroTimesheetSubmissionStatusEnumBlocked = Just XeroSubmissionRunStatusEnumBlocked
xeroSubmissionTerminalRunStatus XeroTimesheetSubmissionStatusEnumPending = Nothing
xeroSubmissionTerminalRunStatus XeroTimesheetSubmissionStatusEnumSubmitted = Just XeroSubmissionRunStatusEnumSubmitted
xeroSubmissionTerminalRunStatus XeroTimesheetSubmissionStatusEnumFailed = Just XeroSubmissionRunStatusEnumFailed
xeroSubmissionTerminalRunStatus Skipped = Nothing
xeroSubmissionTerminalRunStatus XeroTimesheetSubmissionStatusEnumSuperseded = Nothing

xeroSubmissionRunPeriodLabel :: XeroSubmissionRunStatusEnum -> Text
xeroSubmissionRunPeriodLabel XeroSubmissionRunStatusEnumPreviewed = " · previewed previously"
xeroSubmissionRunPeriodLabel XeroSubmissionRunStatusEnumBlocked = " · blocked previously"
xeroSubmissionRunPeriodLabel XeroSubmissionRunStatusEnumPending = " · submission pending"
xeroSubmissionRunPeriodLabel XeroSubmissionRunStatusEnumSubmitted = " · submitted already"
xeroSubmissionRunPeriodLabel PartiallyFailed = " · partially submitted"
xeroSubmissionRunPeriodLabel XeroSubmissionRunStatusEnumFailed = " · failed previously"
xeroSubmissionRunPeriodLabel XeroSubmissionRunStatusEnumSuperseded = ""
