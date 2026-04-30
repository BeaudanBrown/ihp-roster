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
    { payItemRequirementKey          :: Text
    , payItemRequirementName         :: Text
    , payItemRequirementPenaltyKind  :: Maybe Text
    , payItemRequirementEarningsType :: Text
    , payItemRequirementRateType     :: Text
    , payItemRequirementMultiplier   :: Maybe Scientific
    , payItemRequirementRatePerUnit  :: Maybe Scientific
    , payItemRequirementValue        :: Maybe Text
    , payItemRequirementSource       :: Text
    , payItemRequirementEffectiveFrom :: Maybe Day
    , payItemRequirementEffectiveTo   :: Maybe Day
    , payItemRequirementIsActive      :: Bool
    , payItemRequirementMatch        :: Maybe XeroEarningsRate
    , payItemRequirementRecord       :: Maybe XeroPayItemRequirementRecord
    , payItemRequirementStatus       :: Text
    }

data XeroReadyChecklist = XeroReadyChecklist
    { xeroReadyConnection         :: Bool
    , xeroReadyReferenceSync      :: Bool
    , xeroReadyStaffMappings      :: Bool
    , xeroReadyEarningsMappings   :: Bool
    , xeroReadyManagedPayItems    :: Bool
    , xeroReadyPayItemAccountCode :: Bool
    , xeroReadyPayrollCalendar    :: Bool
    , xeroReadyStaffVerifiedCount :: Int
    , xeroReadyStaffTotalCount    :: Int
    , xeroReadyEarningsVerifiedCount :: Int
    , xeroReadyEarningsTotalCount :: Int
    , xeroReadyManagedPayItemReadyCount :: Int
    , xeroReadyManagedPayItemTotalCount :: Int
    }

data XeroAdminSectionData = XeroAdminSectionData
    { xeroConnection                  :: Maybe XeroConnection
    , xeroConnectedByUser             :: Maybe User
    , xeroLatestSyncRun               :: Maybe XeroSyncRun
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
    }
