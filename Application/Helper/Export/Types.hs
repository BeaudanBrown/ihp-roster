module Application.Helper.Export.Types where

import Data.Time.Clock (NominalDiffTime)
import IHP.ControllerPrelude

data ExportJobType
    = ApprovedTimesheetsCsv
    | StaffPayCsv
    | HourlyBreakdownZip
    | PayrollEarningsCsv
    deriving (Eq, Show, Enum, Bounded)

instance InputValue ExportJobType where
    inputValue = exportJobTypeToText

data ExportJobStatus
    = ExportPending
    | ExportReady
    | ExportExpired
    deriving (Eq, Show)

data FixedExportDefinition = FixedExportDefinition
    { fixedExportType        :: !ExportJobType
    , fixedExportLabel       :: !Text
    , fixedExportDescription :: !Text
    }
    deriving (Eq, Show)

data ReportWeekSelection = ReportWeekSelection
    { weekOffset :: !Int
    , weekStart  :: !Day
    , weekEnd    :: !Day
    , dayLabels  :: ![Text]
    }
    deriving (Eq, Show)

data StaffPayCsvRecord = StaffPayCsvRecord
    { staffFirstName :: !Text
    , staffLastName  :: !Text
    , label          :: !(Maybe Text)
    , bucketHours    :: ![Rational]
    }
    deriving (Eq, Show)

data StaffPayCsvPayload = StaffPayCsvPayload
    { weekSelection         :: !ReportWeekSelection
    , fileName              :: !Text
    , csvContents           :: !Text
    , entryCount            :: !Int
    , rowCount              :: !Int
    , versionManifests      :: ![Text]
    , exportVersionManifest :: !(Maybe Text)
    }
    deriving (Eq, Show)

data PayrollEarningsCsvRecord = PayrollEarningsCsvRecord
    { staffFirstName           :: !Text
    , staffLastName            :: !Text
    , workDate                 :: !Day
    , earningsRateName         :: !Text
    , exactQuantity            :: !Rational
    , quantity                 :: !Rational
    , unit                     :: !Text
    , ratePerUnit              :: !Rational
    , exactAmount              :: !Rational
    , amount                   :: !Rational
    , trackingCode             :: !(Maybe Text)
    , description              :: !Text
    , staffId                  :: !UUID
    , timesheetEntryIds        :: ![UUID]
    , payConfigVersionManifest :: !(Maybe Text)
    , calculationSource        :: !Text
    , calculationVersion       :: !Text
    , rateBookVersion          :: !(Maybe Text)
    , sourceCondition          :: !Text
    , sourceRateIdentity       :: !(Maybe Text)
    , sourcePayLevelName       :: !(Maybe Text)
    , sourceShiftTypeName      :: !(Maybe Text)
    , approvedAt               :: ![UTCTime]
    , approvedByUserIds        :: ![UUID]
    , activePayCalculationIds  :: ![UUID]
    }
    deriving (Eq, Show)

allExportJobTypeValues :: [Text]
allExportJobTypeValues = ["approved_timesheets_csv", "staff_pay_csv", "hourly_breakdown_zip", "payroll_earnings_csv"]

allExportJobStatusValues :: [Text]
allExportJobStatusValues = ["pending", "ready", "expired"]


exportJobTypeToText :: ExportJobType -> Text
exportJobTypeToText ApprovedTimesheetsCsv = "approved_timesheets_csv"
exportJobTypeToText StaffPayCsv           = "staff_pay_csv"
exportJobTypeToText HourlyBreakdownZip    = "hourly_breakdown_zip"
exportJobTypeToText PayrollEarningsCsv    = "payroll_earnings_csv"

parseExportJobType :: Text -> Maybe ExportJobType
parseExportJobType "approved_timesheets_csv" = Just ApprovedTimesheetsCsv
parseExportJobType "staff_pay_csv"           = Just StaffPayCsv
parseExportJobType "hourly_breakdown_zip"    = Just HourlyBreakdownZip
parseExportJobType "payroll_earnings_csv"    = Just PayrollEarningsCsv
parseExportJobType _                         = Nothing

exportJobStatusToText :: ExportJobStatus -> Text
exportJobStatusToText ExportPending = "pending"
exportJobStatusToText ExportReady   = "ready"
exportJobStatusToText ExportExpired = "expired"

parseExportJobStatus :: Text -> Maybe ExportJobStatus
parseExportJobStatus "pending" = Just ExportPending
parseExportJobStatus "ready"   = Just ExportReady
parseExportJobStatus "expired" = Just ExportExpired
parseExportJobStatus _         = Nothing

browserDownloadMethod :: Text
browserDownloadMethod = "browser_download"

exportSchemaVersion :: Int
exportSchemaVersion = 3

exportExpirySeconds :: NominalDiffTime
exportExpirySeconds = 60 * 60 * 24
