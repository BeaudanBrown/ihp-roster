{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Application.Helper.XeroAdminTypes where

import Application.Xero.ReferenceTrust
import Control.Monad (guard)
import qualified Data.List as List
import Data.Scientific (Scientific)
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import Generated.Types
import IHP.Prelude

data XeroStaffMappingRow = XeroStaffMappingRow
    { mappingRowStaff             :: Staff
    , mappingRowUser              :: Maybe User
    , mappingRowMapping           :: XeroStaffMapping
    , mappingRowSuggestedEmployee :: Maybe XeroEmployee
    }

data XeroLocalEarningsBucket = XeroLocalEarningsBucket
    { localBucketKey   :: Text
    , localBucketLabel :: Text
    }

data XeroUsedAwardPayScope = XeroUsedAwardPayScope
    { usedAwardLevelId    :: UUID
    , usedEmploymentBasis :: StaffEmploymentBasisEnum
    }
    deriving (Eq)

data XeroPayItemAccountCodeOption = XeroPayItemAccountCodeOption
    { accountCodeOptionValue :: Text
    , accountCodeOptionLabel :: Text
    }
    deriving (Eq, Show)

xeroPayItemAccountCodeOptionsFromAccounts :: [XeroAccount] -> [XeroPayItemAccountCodeOption]
xeroPayItemAccountCodeOptionsFromAccounts xeroAccounts =
    xeroAccounts
        |> filter isSelectableExpenseAccount
        |> mapMaybe accountCodePair
        |> List.sortOn (\(accountCode, name) -> (accountCode, name))
        |> List.groupBy (\(leftCode, _) (rightCode, _) -> leftCode == rightCode)
        |> mapMaybe accountCodeOptionFromGroup
    where
        accountCodePair account = do
            accountCode <- Text.strip <$> account.code
            guard (not (Text.null accountCode))
            let name = Text.strip account.name
            pure (accountCode, name)

isSelectableExpenseAccount :: XeroAccount -> Bool
isSelectableExpenseAccount account =
    account.accountType == Just "EXPENSE"
        && maybe False ((== "ACTIVE") . Text.toUpper . Text.strip) account.status

accountCodeOptionFromGroup :: [(Text, Text)] -> Maybe XeroPayItemAccountCodeOption
accountCodeOptionFromGroup [] = Nothing
accountCodeOptionFromGroup ((accountCode, name) : _) =
    Just
        XeroPayItemAccountCodeOption
            { accountCodeOptionValue = accountCode
            , accountCodeOptionLabel =
                if Text.null name
                    then accountCode
                    else accountCode <> ": " <> name
            }

xeroPayItemAccountCodeOptionValues :: [XeroPayItemAccountCodeOption] -> [Text]
xeroPayItemAccountCodeOptionValues =
    map (.accountCodeOptionValue)

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
    , payItemRequirementStatus        :: XeroPayItemRequirementStatusEnum
    }

data XeroTimesheetIssueView = XeroTimesheetIssueView
    { timesheetIssueCode     :: Text
    , timesheetIssueSeverity :: Text
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
    { previewRowXeroEmployeeId  :: Text
    , previewRowEmployeeName    :: Text
    , previewRowOperation       :: Text
    , previewRowXeroTimesheetId :: Maybe Text
    , previewRowPeriodStart     :: Day
    , previewRowPeriodEnd       :: Day
    , previewRowTotalUnits      :: Scientific
    , previewRowLines           :: [XeroTimesheetPreviewLineView]
    , previewRowSourceCount     :: Int
    }
    deriving (Eq, Show)

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
    , periodOptionWithinDefaultWindow    :: Bool
    , periodOptionLatestSubmissionStatus :: Maybe XeroSubmissionRunStatusEnum
    , periodOptionLatestSubmissionRunId  :: Maybe (Id XeroSubmissionRun)
    }
    deriving (Eq, Show)

data XeroPreparationStaffRow = XeroPreparationStaffRow
    { preparationStaffMappingRow    :: XeroStaffMappingRow
    , preparationStaffDecision      :: Maybe XeroTimesheetPreparationDecision
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

xeroPreparationStateFromStatus :: XeroTimesheetPreparationRunStatusEnum -> XeroTimesheetPreparationState
xeroPreparationStateFromStatus Started = XeroPreparationPreparing
xeroPreparationStateFromStatus Preparing = XeroPreparationPreparing
xeroPreparationStateFromStatus NeedsReconnect = XeroPreparationNeedsReconnect
xeroPreparationStateFromStatus NeedsApproval = XeroPreparationNeedsDecision
xeroPreparationStateFromStatus XeroTimesheetPreparationRunStatusEnumBlocked = XeroPreparationBlocked
xeroPreparationStateFromStatus XeroTimesheetPreparationRunStatusEnumResolved = XeroPreparationNeedsDecision
xeroPreparationStateFromStatus ReadyForPreview = XeroPreparationReadyForPreview
xeroPreparationStateFromStatus XeroTimesheetPreparationRunStatusEnumPreviewed = XeroPreparationPreviewed
xeroPreparationStateFromStatus XeroTimesheetPreparationRunStatusEnumSubmitted = XeroPreparationSubmitted
xeroPreparationStateFromStatus XeroTimesheetPreparationRunStatusEnumFailed = XeroPreparationFailed
xeroPreparationStateFromStatus Cancelled = XeroPreparationFailed

data XeroTimesheetPreparationView = XeroTimesheetPreparationView
    { preparationRun                         :: XeroTimesheetPreparationRun
    , preparationState                       :: XeroTimesheetPreparationState
    , preparationConnection                  :: XeroConnection
    , preparationPeriodOption                :: Maybe XeroTimesheetPeriodOption
    , preparationPeriodOptions               :: [XeroTimesheetPeriodOption]
    , preparationReadiness                   :: XeroTimesheetReadinessView
    , preparationPayrollCalendars            :: [XeroPayrollCalendar]
    , preparationStaffRows                   :: [XeroPreparationStaffRow]
    , preparationEmployees                   :: [XeroEmployee]
    , preparationPayItemRows                 :: [XeroPreparationPayItemRow]
    , preparationPayItemAccountCodeOptions   :: [XeroPayItemAccountCodeOption]
    , preparationPayItemAccountCodeSelection :: Maybe XeroPayItemAccountCodeSelection
    , preparationPendingDecisionCount        :: Int
    , preparationManualStaffDecisionCount    :: Int
    , preparationStaffStepApproved           :: Bool
    , preparationPostedPayRunBlocked         :: Bool
    , preparationCanSubmit                   :: Bool
    , preparationPreviewRows                 :: [XeroTimesheetPreviewRowView]
    , preparationSubmissionRun               :: Maybe XeroSubmissionRun
    }

data XeroReferenceSyncDiagnostics = XeroReferenceSyncDiagnostics
    { referenceSyncLastSucceededAt :: !(Maybe UTCTime)
    , referenceSyncActivity        :: !XeroReferenceSyncActivity
    , referenceSyncProgress        :: !XeroReferenceSyncProgressFacts
    , referenceSyncSanitizedError  :: !(Maybe Text)
    }

data XeroAdminSectionData = XeroAdminSectionData
    { xeroConnection               :: Maybe XeroConnection
    , xeroConnectionActionsAllowed :: Bool
    , xeroReferenceRefreshAllowed  :: Bool
    , xeroReferenceSyncDiagnostics :: Maybe XeroReferenceSyncDiagnostics
    }
