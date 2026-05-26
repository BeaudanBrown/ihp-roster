module Application.Helper.XeroAdminTypes where

import Data.Scientific (Scientific)
import Data.Time.Calendar (Day)
import Generated.Types
import IHP.Prelude

data XeroStaffMappingRow = XeroStaffMappingRow
    { mappingRowStaff             :: Staff
    , mappingRowUser              :: Maybe User
    , mappingRowMapping           :: XeroStaffMapping
    , mappingRowSuggestedEmployee :: Maybe XeroEmployee
    }

data XeroStaffMappingCounts = XeroStaffMappingCounts
    { xeroStaffVerifiedCount      :: Int
    , xeroStaffNotApplicableCount :: Int
    , xeroStaffStaleCount         :: Int
    , xeroStaffPossibleMatchCount :: Int
    }

data XeroLocalEarningsBucket = XeroLocalEarningsBucket
    { localBucketKey   :: Text
    , localBucketLabel :: Text
    }

data XeroEarningsBucketRow = XeroEarningsBucketRow
    { earningsBucketRowBucket  :: XeroLocalEarningsBucket
    , earningsBucketRowMapping :: Maybe XeroEarningsRateMapping
    }

data XeroEarningsRateMappingCounts = XeroEarningsRateMappingCounts
    { xeroEarningsVerifiedCount :: Int
    , xeroEarningsUnmappedCount :: Int
    , xeroEarningsStaleCount    :: Int
    }

data XeroUsedAwardPayScope = XeroUsedAwardPayScope
    { usedAwardLevelId    :: UUID
    , usedEmploymentBasis :: StaffEmploymentBasisEnum
    }
    deriving (Eq)

data XeroPayItemRequirement = XeroPayItemRequirement
    { payItemRequirementKey           :: Text
    , payItemRequirementName          :: Text
    , payItemRequirementPenaltyKind   :: Maybe Text
    , payItemRequirementEarningsType  :: Text
    , payItemRequirementRateType      :: Text
    , payItemRequirementMultiplier    :: Maybe Scientific
    , payItemRequirementRatePerUnit   :: Maybe Scientific
    , payItemRequirementValue         :: Maybe Text
    , payItemRequirementSource        :: Text
    , payItemRequirementEffectiveFrom :: Maybe Day
    , payItemRequirementEffectiveTo   :: Maybe Day
    , payItemRequirementIsActive      :: Bool
    , payItemRequirementMatch         :: Maybe XeroEarningsRate
    , payItemRequirementRecord        :: Maybe XeroPayItemRequirementRecord
    , payItemRequirementStatus        :: Text
    }

data XeroReadyChecklist = XeroReadyChecklist
    { xeroReadyConnection               :: Bool
    , xeroReadyReferenceSync            :: Bool
    , xeroReadyStaffMappings            :: Bool
    , xeroReadyEarningsMappings         :: Bool
    , xeroReadyManagedPayItems          :: Bool
    , xeroReadyPayItemAccountCode       :: Bool
    , xeroReadyPayrollCalendar          :: Bool
    , xeroReadyStaffVerifiedCount       :: Int
    , xeroReadyStaffTotalCount          :: Int
    , xeroReadyEarningsVerifiedCount    :: Int
    , xeroReadyEarningsTotalCount       :: Int
    , xeroReadyManagedPayItemReadyCount :: Int
    , xeroReadyManagedPayItemTotalCount :: Int
    }

data XeroTimesheetIssueView = XeroTimesheetIssueView
    { timesheetIssueSeverity :: Text
    , timesheetIssueMessage  :: Text
    , timesheetIssueHint     :: Maybe Text
    }
    deriving (Eq, Show)

data XeroTimesheetReadinessView = XeroTimesheetReadinessView
    { timesheetReadinessReady       :: Bool
    , timesheetReadinessPeriodStart :: Day
    , timesheetReadinessPeriodEnd   :: Day
    , timesheetReadinessStaffCount  :: Int
    , timesheetReadinessEntryCount  :: Int
    , timesheetReadinessBucketCount :: Int
    , timesheetReadinessBlockers    :: [XeroTimesheetIssueView]
    , timesheetReadinessWarnings    :: [XeroTimesheetIssueView]
    }
    deriving (Eq, Show)

data XeroTimesheetPreviewLineView = XeroTimesheetPreviewLineView
    { previewLineViewLocalBucketKey     :: Text
    , previewLineViewXeroEarningsRateId :: Text
    , previewLineViewEarningsRateName   :: Text
    , previewLineViewTotalUnits         :: Scientific
    }
    deriving (Eq, Show)

data XeroTimesheetPreviewRowView = XeroTimesheetPreviewRowView
    { previewRowXeroEmployeeId :: Text
    , previewRowEmployeeName   :: Text
    , previewRowPeriodStart    :: Day
    , previewRowPeriodEnd      :: Day
    , previewRowTotalUnits     :: Scientific
    , previewRowLines          :: [XeroTimesheetPreviewLineView]
    , previewRowSourceCount    :: Int
    }
    deriving (Eq, Show)

data XeroTimesheetSubmissionRowView = XeroTimesheetSubmissionRowView
    { submissionRowSubmission :: XeroTimesheetSubmission
    , submissionRowStaff      :: Maybe Staff
    , submissionRowEmployee   :: Maybe XeroEmployee
    }

data XeroTimesheetRunView = XeroTimesheetRunView
    { timesheetRun                 :: XeroSubmissionRun
    , timesheetRunPreviewRows      :: [XeroTimesheetPreviewRowView]
    , timesheetRunSubmissionRows   :: [XeroTimesheetSubmissionRowView]
    , timesheetRunSubmittedBy      :: Maybe User
    , timesheetRunHasHistoricalSib :: Bool
    }

data XeroTimesheetPanelData = XeroTimesheetPanelData
    { xeroTimesheetActionsAllowed :: Bool
    , xeroTimesheetReadiness      :: Maybe XeroTimesheetReadinessView
    , xeroTimesheetPeriodMessage  :: Maybe Text
    , xeroTimesheetPeriodOptions  :: [XeroTimesheetPeriodOption]
    , xeroTimesheetLatestRun      :: Maybe XeroTimesheetRunView
    }

data XeroTimesheetPeriodOption = XeroTimesheetPeriodOption
    { periodOptionKey                    :: Text
    , periodOptionPayrollCalendarId      :: Text
    , periodOptionPayrollCalendarName    :: Text
    , periodOptionStart                  :: Day
    , periodOptionEnd                    :: Day
    , periodOptionPaymentDate            :: Maybe Day
    , periodOptionXeroPayRunId           :: Maybe Text
    , periodOptionXeroPayRunStatus       :: Maybe Text
    , periodOptionBlocked                :: Bool
    , periodOptionBlockReason            :: Maybe Text
    , periodOptionDerivedFromSyncedXero  :: Bool
    }
    deriving (Eq, Show)

data XeroPreparationStaffRow = XeroPreparationStaffRow
    { preparationStaffMappingRow    :: XeroStaffMappingRow
    , preparationStaffDecision      :: Maybe XeroTimesheetPreparationDecision
    , preparationStaffSkipped       :: Bool
    , preparationStaffNeedsDecision :: Bool
    }

data XeroPreparationPayItemRow = XeroPreparationPayItemRow
    { preparationPayItemRequirement :: XeroPayItemRequirement
    , preparationPayItemDecision    :: Maybe XeroTimesheetPreparationDecision
    }

data XeroTimesheetPreparationState
    = XeroPreparationNeedsReconnect
    | XeroPreparationPreparing
    | XeroPreparationNeedsDecision
    | XeroPreparationBlocked
    | XeroPreparationReadyForPreview
    | XeroPreparationPreviewed
    | XeroPreparationSubmitted
    | XeroPreparationFailed
    deriving (Eq, Show)

xeroPreparationStateFromStatus :: Text -> XeroTimesheetPreparationState
xeroPreparationStateFromStatus status =
    case status of
        "needs_reconnect" -> XeroPreparationNeedsReconnect
        "needs_approval" -> XeroPreparationNeedsDecision
        "resolved" -> XeroPreparationNeedsDecision
        "blocked" -> XeroPreparationBlocked
        "ready_for_preview" -> XeroPreparationReadyForPreview
        "previewed" -> XeroPreparationPreviewed
        "submitted" -> XeroPreparationSubmitted
        "failed" -> XeroPreparationFailed
        "cancelled" -> XeroPreparationFailed
        _ -> XeroPreparationPreparing

data XeroTimesheetPreparationView = XeroTimesheetPreparationView
    { preparationRun                         :: XeroTimesheetPreparationRun
    , preparationState                       :: XeroTimesheetPreparationState
    , preparationConnection                  :: XeroConnection
    , preparationPeriodOption                :: XeroTimesheetPeriodOption
    , preparationReadiness                   :: XeroTimesheetReadinessView
    , preparationPayrollCalendars            :: [XeroPayrollCalendar]
    , preparationPayrollCalendarSelection    :: Maybe XeroPayrollCalendarSelection
    , preparationStaffRows                   :: [XeroPreparationStaffRow]
    , preparationEmployees                   :: [XeroEmployee]
    , preparationPayItemRows                 :: [XeroPreparationPayItemRow]
    , preparationPayItemAccountCodeOptions   :: [Text]
    , preparationPayItemAccountCodeSelection :: Maybe XeroPayItemAccountCodeSelection
    , preparationPendingDecisionCount        :: Int
    , preparationManualStaffDecisionCount    :: Int
    , preparationPostedPayRunBlocked         :: Bool
    , preparationCanPreview                  :: Bool
    , preparationCanSubmit                   :: Bool
    , preparationPreviewRows                 :: [XeroTimesheetPreviewRowView]
    , preparationSubmissionRun               :: Maybe XeroSubmissionRun
    }

data XeroAdminSectionData = XeroAdminSectionData
    { xeroConnection                  :: Maybe XeroConnection
    , xeroConnectedByUser             :: Maybe User
    , xeroLatestSyncRun               :: Maybe XeroSyncRun
    , xeroLatestPayItemSyncRun        :: Maybe XeroSyncRun
    , xeroEmployeeCount               :: Int
    , xeroEarningsRateCount           :: Int
    , xeroPayrollCalendarCount        :: Int
    , xeroEmployees                   :: [XeroEmployee]
    , xeroStaffMappingRows            :: [XeroStaffMappingRow]
    , xeroStaffMappingCounts          :: XeroStaffMappingCounts
    , xeroEarningsRates               :: [XeroEarningsRate]
    , xeroPayItemRequirements         :: [XeroPayItemRequirement]
    , xeroPayrollCalendars            :: [XeroPayrollCalendar]
    , xeroPayrollCalendarSelection    :: Maybe XeroPayrollCalendarSelection
    , xeroPayItemAccountCodeSelection :: Maybe XeroPayItemAccountCodeSelection
    , xeroReadyChecklist              :: XeroReadyChecklist
    , xeroConnectionActionsAllowed    :: Bool
    , xeroTimesheetPanelData          :: XeroTimesheetPanelData
    }
