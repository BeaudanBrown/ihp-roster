module Application.Helper.XeroAdminTypes where

import Generated.Types
import IHP.Prelude
import Data.Scientific (Scientific)

data XeroStaffMappingRow = XeroStaffMappingRow
    { mappingRowStaff   :: Staff
    , mappingRowUser    :: Maybe User
    , mappingRowMapping :: Maybe XeroStaffMapping
    }

data XeroStaffMappingCounts = XeroStaffMappingCounts
    { xeroStaffVerifiedCount      :: Int
    , xeroStaffUnmappedCount      :: Int
    , xeroStaffNotApplicableCount :: Int
    , xeroStaffStaleCount         :: Int
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
    { payItemRequirementKey         :: Text
    , payItemRequirementName        :: Text
    , payItemRequirementPenaltyKind :: Maybe Text
    , payItemRequirementEarningsType :: Text
    , payItemRequirementRateType    :: Text
    , payItemRequirementMultiplier  :: Maybe Scientific
    , payItemRequirementRatePerUnit :: Maybe Scientific
    , payItemRequirementValue       :: Maybe Text
    , payItemRequirementSource      :: Text
    , payItemRequirementMatch       :: Maybe XeroEarningsRate
    , payItemRequirementRecord      :: Maybe XeroPayItemRequirementRecord
    , payItemRequirementStatus      :: Text
    }

data XeroReadyChecklist = XeroReadyChecklist
    { xeroReadyConnection       :: Bool
    , xeroReadyReferenceSync    :: Bool
    , xeroReadyStaffMappings    :: Bool
    , xeroReadyEarningsMappings :: Bool
    , xeroReadyPayItemAccountCode :: Bool
    , xeroReadyPayrollCalendar  :: Bool
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
    , xeroEarningsBucketRows          :: [XeroEarningsBucketRow]
    , xeroEarningsRateMappingCounts   :: XeroEarningsRateMappingCounts
    , xeroPayrollCalendars            :: [XeroPayrollCalendar]
    , xeroPayrollCalendarSelection    :: Maybe XeroPayrollCalendarSelection
    , xeroPayItemAccountCodeSelection :: Maybe XeroPayItemAccountCodeSelection
    , xeroReadyChecklist              :: XeroReadyChecklist
    , xeroConnectionActionsAllowed    :: Bool
    }
