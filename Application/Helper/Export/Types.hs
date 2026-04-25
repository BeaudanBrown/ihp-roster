module Application.Helper.Export.Types where

import Data.Time.Clock (NominalDiffTime)
import Generated.Types
import IHP.ControllerPrelude

data ExportJobType
    = ApprovedTimesheetsCsv
    | StaffPayCsv
    | HourlyBreakdownZip
    | PayrollEarningsCsv
    deriving (Eq, Show)

data ReportDefinitionEngine
    = StaffPayCsvReport
    | HourlyBreakdownZipReport
    | PayrollEarningsCsvReport
    deriving (Eq, Show)

data ExportJobStatus
    = ExportPending
    | ExportReady
    | ExportExpired
    deriving (Eq, Show)

data VenueReportDefinition = VenueReportDefinition
    { definition       :: !ReportDefinition
    , engine           :: !ReportDefinitionEngine
    , shiftTypeFilters :: ![ShiftType]
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
    { staffName   :: !Text
    , label       :: !Text
    , bucketHours :: ![Double]
    , total       :: !Double
    }
    deriving (Eq, Show)

data StaffPayCsvPayload = StaffPayCsvPayload
    { weekSelection         :: !ReportWeekSelection
    , fileName              :: !Text
    , csvContents           :: !Text
    , entryCount            :: !Int
    , rowCount              :: !Int
    , snapshotVersions      :: ![Text]
    , exportSnapshotVersion :: !(Maybe Text)
    }
    deriving (Eq, Show)

data PayrollEarningsCsvRecord = PayrollEarningsCsvRecord
    { staffFirstName      :: !Text
    , staffLastName       :: !Text
    , workDate            :: !Day
    , earningsRateName    :: !Text
    , hours               :: !Double
    , trackingCode        :: !(Maybe Text)
    , description         :: !Text
    , staffId             :: !UUID
    , timesheetEntryIds   :: ![UUID]
    , payConfigSnapshot   :: !(Maybe Text)
    , sourcePenaltyKind   :: !Text
    , sourcePayLevelName  :: !(Maybe Text)
    , sourceShiftTypeName :: !(Maybe Text)
    }
    deriving (Eq, Show)

data PayrollEarningsCsvPayload = PayrollEarningsCsvPayload
    { weekSelection         :: !ReportWeekSelection
    , fileName              :: !Text
    , csvContents           :: !Text
    , entryCount            :: !Int
    , rowCount              :: !Int
    , snapshotVersions      :: ![Text]
    , exportSnapshotVersion :: !(Maybe Text)
    }
    deriving (Eq, Show)

data HourlyBreakdownZipPayload = HourlyBreakdownZipPayload
    { weekSelection         :: !ReportWeekSelection
    , fileName              :: !Text
    , zipContentsBase64     :: !Text
    , entryCount            :: !Int
    , fileCount             :: !Int
    , snapshotVersions      :: ![Text]
    , exportSnapshotVersion :: !(Maybe Text)
    }
    deriving (Eq, Show)

allExportJobTypeValues :: [Text]
allExportJobTypeValues = ["approved_timesheets_csv", "staff_pay_csv", "hourly_breakdown_zip", "payroll_earnings_csv"]

allReportDefinitionEngineValues :: [Text]
allReportDefinitionEngineValues = ["staff_pay_csv", "hourly_breakdown_zip", "payroll_earnings_csv"]

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

reportDefinitionEngineToText :: ReportDefinitionEngine -> Text
reportDefinitionEngineToText StaffPayCsvReport        = "staff_pay_csv"
reportDefinitionEngineToText HourlyBreakdownZipReport = "hourly_breakdown_zip"
reportDefinitionEngineToText PayrollEarningsCsvReport = "payroll_earnings_csv"

parseReportDefinitionEngine :: Text -> Maybe ReportDefinitionEngine
parseReportDefinitionEngine "staff_pay_csv" = Just StaffPayCsvReport
parseReportDefinitionEngine "hourly_breakdown_zip" = Just HourlyBreakdownZipReport
parseReportDefinitionEngine "payroll_earnings_csv" = Just PayrollEarningsCsvReport
parseReportDefinitionEngine _ = Nothing

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
exportSchemaVersion = 1

exportExpirySeconds :: NominalDiffTime
exportExpirySeconds = 60 * 60 * 24
