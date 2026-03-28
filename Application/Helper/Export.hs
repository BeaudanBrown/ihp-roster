module Application.Helper.Export where

import Application.Helper.Controller
import Application.Helper.Pay (PayTotals (..), TimesheetPayResult (..),
                               ensureCurrentVenuePayConfigSnapshot,
                               fetchTimesheetPayResultsForEntries,
                               timesheetEntryIdKey)
import Application.Helper.View (isTrialStaff)
import qualified Codec.Archive.Zip as Zip
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Base64 as Base64
import qualified Data.ByteString.Lazy as LBS
import Data.Coerce (coerce)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Text.Encoding (decodeUtf8, encodeUtf8)
import Data.Time.Calendar (Day, addDays, diffDays)
import Data.Time.Clock (NominalDiffTime, UTCTime, addUTCTime, getCurrentTime)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Data.Time.LocalTime (TimeOfDay)
import Generated.Types
import IHP.ControllerPrelude
import Text.Printf (printf)
import Text.Read (readMaybe)

data ExportJobType
    = ApprovedTimesheetsCsv
    | StaffPayCsv
    | HourlyBreakdownZip
    deriving (Eq, Show)

data ReportDefinitionEngine
    = StaffPayCsvReport
    | HourlyBreakdownZipReport
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
    { staffName :: !Text
    , label     :: !Text
    , dayHours  :: ![Double]
    , total     :: !Double
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
allExportJobTypeValues = ["approved_timesheets_csv", "staff_pay_csv", "hourly_breakdown_zip"]

allReportDefinitionEngineValues :: [Text]
allReportDefinitionEngineValues = ["staff_pay_csv", "hourly_breakdown_zip"]

allExportJobStatusValues :: [Text]
allExportJobStatusValues = ["pending", "ready", "expired"]

exportJobTypeToText :: ExportJobType -> Text
exportJobTypeToText ApprovedTimesheetsCsv = "approved_timesheets_csv"
exportJobTypeToText StaffPayCsv           = "staff_pay_csv"
exportJobTypeToText HourlyBreakdownZip    = "hourly_breakdown_zip"

parseExportJobType :: Text -> Maybe ExportJobType
parseExportJobType "approved_timesheets_csv" = Just ApprovedTimesheetsCsv
parseExportJobType "staff_pay_csv"           = Just StaffPayCsv
parseExportJobType "hourly_breakdown_zip"    = Just HourlyBreakdownZip
parseExportJobType _                         = Nothing

reportDefinitionEngineToText :: ReportDefinitionEngine -> Text
reportDefinitionEngineToText StaffPayCsvReport        = "staff_pay_csv"
reportDefinitionEngineToText HourlyBreakdownZipReport = "hourly_breakdown_zip"

parseReportDefinitionEngine :: Text -> Maybe ReportDefinitionEngine
parseReportDefinitionEngine "staff_pay_csv" = Just StaffPayCsvReport
parseReportDefinitionEngine "hourly_breakdown_zip" = Just HourlyBreakdownZipReport
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

currentReportWeekOffset ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    IO Int
currentReportWeekOffset = do
    venueConfig <- fetchVenueConfig
    today <- utctDay <$> getCurrentTime
    pure (weekOffsetForDay venueConfig.weekOffsetEpoch today)

fetchReportWeekSelection ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Int ->
    IO ReportWeekSelection
fetchReportWeekSelection selectedWeekOffset = do
    venueConfig <- fetchVenueConfig
    let reportWeekStart = addDays (toInteger (selectedWeekOffset * 7)) venueConfig.weekOffsetEpoch
    storedDayNames <- query @DayName
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#isActive, True)
        |> fetch
    let storedDayNamesByIndex = Map.fromList (map (\dayName -> (dayName.weekdayIndex, dayName.name)) storedDayNames)
    let labels =
            if null storedDayNames
                then fallbackReportDayLabels reportWeekStart
                else
                    [ fromMaybe
                        (fallbackReportDayLabel reportWeekStart dayOffset)
                        (Map.lookup (weekdayIndexForDay (addDays (toInteger dayOffset) reportWeekStart)) storedDayNamesByIndex)
                    | dayOffset <- [0 .. length storedDayNames - 1]
                    ]
    let reportWeekEnd = addDays (toInteger (max 1 (length labels) - 1)) reportWeekStart
    pure
        ReportWeekSelection
            { weekOffset = selectedWeekOffset
            , weekStart = reportWeekStart
            , weekEnd = reportWeekEnd
            , dayLabels = labels
            }

reportDefinitionEngineImplemented :: ReportDefinitionEngine -> Bool
reportDefinitionEngineImplemented StaffPayCsvReport        = True
reportDefinitionEngineImplemented HourlyBreakdownZipReport = True

requestReportDefinitionExport ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Text ->
    Int ->
    IO (Either Text ExportJob)
requestReportDefinitionExport reportSlug selectedWeekOffset = do
    reportDefinitions <- fetchCurrentVenueReportDefinitions
    case List.find (\reportDefinition -> reportDefinition.definition.slug == reportSlug) reportDefinitions of
        Nothing ->
            pure (Left "Report definition not found for the current venue.")
        Just reportDefinition ->
            case reportDefinition.engine of
                StaffPayCsvReport -> requestStaffPayCsvExport reportDefinition selectedWeekOffset
                HourlyBreakdownZipReport -> requestHourlyBreakdownZipExport reportDefinition selectedWeekOffset

fetchCurrentVenueReportDefinitions ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    IO [VenueReportDefinition]
fetchCurrentVenueReportDefinitions = do
    definitions <- fetchCurrentVenueReportDefinitionsIncludingInactive
    pure (filter (.definition.isActive) definitions)

fetchCurrentVenueReportDefinitionsIncludingInactive ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    IO [VenueReportDefinition]
fetchCurrentVenueReportDefinitionsIncludingInactive = do
    bootstrapCurrentVenueReportDefinitionsIfMissing
    definitions <- query @ReportDefinition
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> orderByAsc #sortOrder
        |> orderByAsc #createdAt
        |> fetch
    filtersByDefinitionId <- fetchReportDefinitionShiftTypeFilters definitions
    pure (map (toVenueReportDefinition filtersByDefinitionId) definitions)

bootstrapCurrentVenueReportDefinitionsIfMissing ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    IO ()
bootstrapCurrentVenueReportDefinitionsIfMissing = do
    existingDefinitions <- query @ReportDefinition
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> fetchCount
    when (existingDefinitions == 0) do
        shiftTypes <- query @ShiftType
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#isActive, True)
            |> orderByAsc #createdAt
            |> fetch
        void $ withTransaction do
            wageDefinition <- createReportDefinition "wage" "Wage Report" (Just "Hourly staff count breakdown per day (ZIP of CSVs)") HourlyBreakdownZipReport 10
            _ <- wageDefinition `seq` pure ()
            staffHoursDefinition <- createReportDefinition "staff_hours" "Staff Hours Report" (Just "Staff hours broken down by pay level and day") StaffPayCsvReport 20
            _ <- staffHoursDefinition `seq` pure ()
            forM_ (find (\shiftType -> shiftType.name == "Kitchen") shiftTypes) \kitchenShiftType -> do
                kitchenDefinition <- createReportDefinition "kitchen" "Kitchen Report" (Just "Kitchen staff hours by day") StaffPayCsvReport 30
                newRecord @ReportDefinitionShiftTypeFilter
                    |> set #reportDefinitionId (unpackId (get #id kitchenDefinition))
                    |> set #shiftTypeId (unpackId (get #id kitchenShiftType))
                    |> createRecord
            pure ()
    where
        createReportDefinition slug name description engine sortOrder =
            newRecord @ReportDefinition
                |> set #venueId (unpackId currentVenueId)
                |> set #slug slug
                |> set #name name
                |> set #description description
                |> set #engine (reportDefinitionEngineToText engine)
                |> set #sortOrder sortOrder
                |> createRecord

fetchReportDefinitionShiftTypeFilters ::
    (?modelContext :: ModelContext) =>
    [ReportDefinition] ->
    IO (Map.Map UUID [ShiftType])
fetchReportDefinitionShiftTypeFilters definitions =
    if null definitions
        then pure Map.empty
        else do
            filters <- query @ReportDefinitionShiftTypeFilter
                |> filterWhereIn (#reportDefinitionId, map (coerce . get #id) definitions)
                |> fetch
            let shiftTypeIds = List.nub (map (.shiftTypeId) filters)
            shiftTypes <-
                if null shiftTypeIds
                    then pure []
                    else query @ShiftType |> filterWhereIn (#id, map Id shiftTypeIds) |> fetch
            let shiftTypesById = Map.fromList (map (\shiftType -> (coerce (get #id shiftType), shiftType)) shiftTypes)
            pure $
                foldl'
                    (\acc filterRow ->
                        case Map.lookup filterRow.shiftTypeId shiftTypesById of
                            Just shiftType ->
                                Map.insertWith (<>) filterRow.reportDefinitionId [shiftType] acc
                            Nothing -> acc
                    )
                    Map.empty
                    filters

toVenueReportDefinition :: Map.Map UUID [ShiftType] -> ReportDefinition -> VenueReportDefinition
toVenueReportDefinition filtersByDefinitionId definition =
    VenueReportDefinition
        { definition
        , engine = fromMaybe StaffPayCsvReport (parseReportDefinitionEngine definition.engine)
        , shiftTypeFilters = fromMaybe [] (Map.lookup (coerce (get #id definition)) filtersByDefinitionId)
        }

requestStaffPayCsvExport ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    VenueReportDefinition ->
    Int ->
    IO (Either Text ExportJob)
requestStaffPayCsvExport reportDefinition selectedWeekOffset = do
    payloadResult <- buildStaffPayCsvPayload reportDefinition selectedWeekOffset
    case payloadResult of
        Left err -> pure (Left err)
        Right payload -> do
            exportJob <- withTransaction do
                now <- getCurrentTime
                let expiresAt = addUTCTime exportExpirySeconds now
                let exportType = exportJobTypeToText StaffPayCsv
                let initialScope = buildStaffPayCsvScope reportDefinition payload
                exportJob <-
                    newRecord @ExportJob
                        |> set #venueId (unpackId currentVenueId)
                        |> set #requestedByUserId (unpackId (get #id currentUser))
                        |> set #exportType exportType
                        |> set #status (exportJobStatusToText ExportPending)
                        |> set #schemaVersion exportSchemaVersion
                        |> set #rangeStart (Just payload.weekSelection.weekStart)
                        |> set #rangeEnd (Just payload.weekSelection.weekEnd)
                        |> set #scope initialScope
                        |> set #deliveryMethod browserDownloadMethod
                        |> set #destinationMetadata (Aeson.object ["requestedVia" Aeson..= requestAuditSourceChannel])
                        |> set #expiresAt expiresAt
                        |> createRecord

                exportJob <-
                    exportJob
                        |> set #status (exportJobStatusToText ExportReady)
                        |> set #payConfigSnapshotVersion payload.exportSnapshotVersion
                        |> set #scope initialScope
                        |> set #fileName (Just payload.fileName)
                        |> set #contentType (Just "text/csv; charset=utf-8")
                        |> set #fileEncoding "utf8"
                        |> set #fileContents (Just payload.csvContents)
                        |> updateRecord

                void $ recordCurrentUserAuditEvent
                    "export_generated"
                    "export_jobs"
                    (unpackId (get #id exportJob))
                    (Aeson.object
                        [ "exportType" Aeson..= exportType
                        , "reportSlug" Aeson..= reportDefinition.definition.slug
                        , "reportEngine" Aeson..= reportDefinitionEngineToText reportDefinition.engine
                        , "weekOffset" Aeson..= payload.weekSelection.weekOffset
                        , "weekStart" Aeson..= payload.weekSelection.weekStart
                        , "weekEnd" Aeson..= payload.weekSelection.weekEnd
                        , "entryCount" Aeson..= payload.entryCount
                        , "rowCount" Aeson..= payload.rowCount
                        , "payConfigSnapshotVersion" Aeson..= payload.exportSnapshotVersion
                        , "deliveryMethod" Aeson..= exportJob.deliveryMethod
                        ]
                    )

                pure exportJob

            pure (Right exportJob)

requestHourlyBreakdownZipExport ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    VenueReportDefinition ->
    Int ->
    IO (Either Text ExportJob)
requestHourlyBreakdownZipExport reportDefinition selectedWeekOffset = do
    payloadResult <- buildHourlyBreakdownZipPayload reportDefinition selectedWeekOffset
    case payloadResult of
        Left err -> pure (Left err)
        Right payload -> do
            exportJob <- withTransaction do
                now <- getCurrentTime
                let expiresAt = addUTCTime exportExpirySeconds now
                let exportType = exportJobTypeToText HourlyBreakdownZip
                let initialScope = buildHourlyBreakdownZipScope reportDefinition payload
                exportJob <-
                    newRecord @ExportJob
                        |> set #venueId (unpackId currentVenueId)
                        |> set #requestedByUserId (unpackId (get #id currentUser))
                        |> set #exportType exportType
                        |> set #status (exportJobStatusToText ExportPending)
                        |> set #schemaVersion exportSchemaVersion
                        |> set #rangeStart (Just payload.weekSelection.weekStart)
                        |> set #rangeEnd (Just payload.weekSelection.weekEnd)
                        |> set #scope initialScope
                        |> set #deliveryMethod browserDownloadMethod
                        |> set #destinationMetadata (Aeson.object ["requestedVia" Aeson..= requestAuditSourceChannel])
                        |> set #expiresAt expiresAt
                        |> createRecord

                exportJob <-
                    exportJob
                        |> set #status (exportJobStatusToText ExportReady)
                        |> set #payConfigSnapshotVersion payload.exportSnapshotVersion
                        |> set #scope initialScope
                        |> set #fileName (Just payload.fileName)
                        |> set #contentType (Just "application/zip")
                        |> set #fileEncoding "base64"
                        |> set #fileContents (Just payload.zipContentsBase64)
                        |> updateRecord

                void $ recordCurrentUserAuditEvent
                    "export_generated"
                    "export_jobs"
                    (unpackId (get #id exportJob))
                    (Aeson.object
                        [ "exportType" Aeson..= exportType
                        , "reportSlug" Aeson..= reportDefinition.definition.slug
                        , "reportEngine" Aeson..= reportDefinitionEngineToText reportDefinition.engine
                        , "weekOffset" Aeson..= payload.weekSelection.weekOffset
                        , "weekStart" Aeson..= payload.weekSelection.weekStart
                        , "weekEnd" Aeson..= payload.weekSelection.weekEnd
                        , "entryCount" Aeson..= payload.entryCount
                        , "fileCount" Aeson..= payload.fileCount
                        , "payConfigSnapshotVersion" Aeson..= payload.exportSnapshotVersion
                        , "deliveryMethod" Aeson..= exportJob.deliveryMethod
                        ]
                    )

                pure exportJob

            pure (Right exportJob)

buildStaffPayCsvPayload ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    VenueReportDefinition ->
    Int ->
    IO (Either Text StaffPayCsvPayload)
buildStaffPayCsvPayload reportDefinition selectedWeekOffset = do
    reportWeekSelection <- fetchReportWeekSelection selectedWeekOffset
    entries <- fetchApprovedTimesheetEntries reportWeekSelection.weekStart reportWeekSelection.weekEnd
    staffById <- fetchReportStaffMap entries
    payResultsByEntryId <- fetchTimesheetPayResultsForEntries entries
    snapshotVersionsByEntryId <- fetchSnapshotVersionsForEntries entries
    let filteredEntries = filter (shouldIncludeStaffPayEntry reportDefinition staffById) entries
    let missingEntryIds =
            map (tshow . get #id) $
                filter (\entry -> Map.notMember (timesheetEntryIdKey (get #id entry)) payResultsByEntryId) filteredEntries

    if not (null missingEntryIds)
        then pure (Left "Failed to resolve payroll data for one or more approved timesheet entries.")
        else do
            let records = buildStaffPayCsvRecords reportDefinition reportWeekSelection filteredEntries staffById payResultsByEntryId
            let exportSnapshotVersions =
                    filteredEntries
                        |> mapMaybe (\entry -> entry.payConfigSnapshotId >>= (`Map.lookup` snapshotVersionsByEntryId))
                        |> List.nub
                        |> List.sort
            let exportSnapshotVersion =
                    case exportSnapshotVersions of
                        []             -> Nothing
                        [versionLabel] -> Just versionLabel
                        _              -> Just "mixed"
            pure $
                Right
                    StaffPayCsvPayload
                        { weekSelection = reportWeekSelection
                        , fileName = reportDefinition.definition.slug <> "-" <> tshow reportWeekSelection.weekStart <> ".csv"
                        , csvContents = renderStaffPayCsv reportWeekSelection.dayLabels records
                        , entryCount = length filteredEntries
                        , rowCount = length records
                        , snapshotVersions = exportSnapshotVersions
                        , exportSnapshotVersion
                        }

buildStaffPayCsvScope :: VenueReportDefinition -> StaffPayCsvPayload -> Aeson.Value
buildStaffPayCsvScope reportDefinition payload =
    Aeson.object
        [ "reportDefinitionId" Aeson..= unpackId (get #id reportDefinition.definition)
        , "reportSlug" Aeson..= reportDefinition.definition.slug
        , "reportName" Aeson..= reportDefinition.definition.name
        , "reportEngine" Aeson..= reportDefinitionEngineToText reportDefinition.engine
        , "weekOffset" Aeson..= payload.weekSelection.weekOffset
        , "weekStart" Aeson..= payload.weekSelection.weekStart
        , "weekEnd" Aeson..= payload.weekSelection.weekEnd
        , "dayLabels" Aeson..= payload.weekSelection.dayLabels
        , "entryCount" Aeson..= payload.entryCount
        , "rowCount" Aeson..= payload.rowCount
        , "snapshotVersions" Aeson..= payload.snapshotVersions
        , "filterShiftTypes" Aeson..= map (.name) reportDefinition.shiftTypeFilters
        ]

buildHourlyBreakdownZipPayload ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    VenueReportDefinition ->
    Int ->
    IO (Either Text HourlyBreakdownZipPayload)
buildHourlyBreakdownZipPayload reportDefinition selectedWeekOffset = do
    reportWeekSelection <- fetchReportWeekSelection selectedWeekOffset
    entries <- fetchApprovedTimesheetEntries reportWeekSelection.weekStart reportWeekSelection.weekEnd
    let filteredEntries = filter (shouldIncludeHourlyBreakdownEntry reportDefinition) entries
    snapshotVersionsByEntryId <- fetchSnapshotVersionsForEntries filteredEntries
    shiftTypes <- fetchCurrentVenueReportShiftTypes reportDefinition
    let snapshotVersions =
            filteredEntries
                |> mapMaybe (\entry -> entry.payConfigSnapshotId >>= (`Map.lookup` snapshotVersionsByEntryId))
                |> List.nub
                |> List.sort
    let exportSnapshotVersion =
            case snapshotVersions of
                []             -> Nothing
                [versionLabel] -> Just versionLabel
                _              -> Just "mixed"
    let zipContentsBase64 = renderHourlyBreakdownZipBase64 reportWeekSelection shiftTypes filteredEntries
    pure $
        Right
            HourlyBreakdownZipPayload
                { weekSelection = reportWeekSelection
                , fileName = reportDefinition.definition.slug <> "-" <> tshow reportWeekSelection.weekStart <> ".zip"
                , zipContentsBase64
                , entryCount = length filteredEntries
                , fileCount = length reportWeekSelection.dayLabels
                , snapshotVersions
                , exportSnapshotVersion
                }

buildHourlyBreakdownZipScope :: VenueReportDefinition -> HourlyBreakdownZipPayload -> Aeson.Value
buildHourlyBreakdownZipScope reportDefinition payload =
    Aeson.object
        [ "reportDefinitionId" Aeson..= unpackId (get #id reportDefinition.definition)
        , "reportSlug" Aeson..= reportDefinition.definition.slug
        , "reportName" Aeson..= reportDefinition.definition.name
        , "reportEngine" Aeson..= reportDefinitionEngineToText reportDefinition.engine
        , "weekOffset" Aeson..= payload.weekSelection.weekOffset
        , "weekStart" Aeson..= payload.weekSelection.weekStart
        , "weekEnd" Aeson..= payload.weekSelection.weekEnd
        , "dayLabels" Aeson..= payload.weekSelection.dayLabels
        , "entryCount" Aeson..= payload.entryCount
        , "fileCount" Aeson..= payload.fileCount
        , "snapshotVersions" Aeson..= payload.snapshotVersions
        , "filterShiftTypes" Aeson..= map (.name) reportDefinition.shiftTypeFilters
        ]

fetchReportStaffMap :: (?modelContext :: ModelContext) => [TimesheetEntry] -> IO (Map.Map UUID Staff)
fetchReportStaffMap entries =
    if null staffIds
        then pure Map.empty
        else do
            staffMembers <- query @Staff
                |> filterWhereIn (#id, map Id staffIds)
                |> filterWhere (#isActive, True)
                |> fetch
            pure (Map.fromList (map (\staff -> (coerce (get #id staff), staff)) staffMembers))
    where
        staffIds = List.nub (map (.staffId) entries)

fetchCurrentVenueReportShiftTypes ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    VenueReportDefinition ->
    IO [ShiftType]
fetchCurrentVenueReportShiftTypes reportDefinition =
    if null allowedShiftTypeIds
        then query @ShiftType
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#isActive, True)
            |> orderByAsc #sortOrder
            |> orderByAsc #name
            |> fetch
        else query @ShiftType
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhereIn (#id, map Id allowedShiftTypeIds)
            |> orderByAsc #sortOrder
            |> orderByAsc #name
            |> fetch
    where
        allowedShiftTypeIds = map (coerce . get #id) reportDefinition.shiftTypeFilters

shouldIncludeStaffPayEntry :: VenueReportDefinition -> Map.Map UUID Staff -> TimesheetEntry -> Bool
shouldIncludeStaffPayEntry reportDefinition staffById entry =
    case Map.lookup entry.staffId staffById of
        Nothing -> False
        Just staff ->
            not (isTrialStaff staff)
                && (null allowedShiftTypeIds || entry.shiftTypeId `elem` allowedShiftTypeIds)
    where
        allowedShiftTypeIds = map (coerce . get #id) reportDefinition.shiftTypeFilters

shouldIncludeHourlyBreakdownEntry :: VenueReportDefinition -> TimesheetEntry -> Bool
shouldIncludeHourlyBreakdownEntry reportDefinition entry =
    null allowedShiftTypeIds || entry.shiftTypeId `elem` allowedShiftTypeIds
    where
        allowedShiftTypeIds = map (coerce . get #id) reportDefinition.shiftTypeFilters

buildStaffPayCsvRecords ::
    VenueReportDefinition ->
    ReportWeekSelection ->
    [TimesheetEntry] ->
    Map.Map UUID Staff ->
    Map.Map Text TimesheetPayResult ->
    [StaffPayCsvRecord]
buildStaffPayCsvRecords reportDefinition reportWeekSelection entries staffById payResultsByEntryId =
    aggregated
        |> Map.toList
        |> map toRecord
        |> List.sortOn (\record -> (record.staffName, record.label))
    where
        aggregated =
            foldl' accumulate Map.empty entries

        accumulate acc entry =
            case (Map.lookup entry.staffId staffById, Map.lookup (timesheetEntryIdKey (get #id entry)) payResultsByEntryId) of
                (Just staff, Just payResult) ->
                    case reportDayIndex reportWeekSelection entry.workedOn of
                        Just dayIndex ->
                            let key = (staffPayDisplayName staff, staffPayRecordLabel reportDefinition payResult)
                                hours = paidMinutesToHours payResult.totals.paidMinutes
                             in if hours <= 0
                                    then acc
                                    else Map.alter (Just . addDayHours dayIndex hours . fromMaybe (replicate (length reportWeekSelection.dayLabels) 0)) key acc
                        Nothing -> acc
                _ -> acc

        toRecord ((recordStaffName, recordLabel), recordDayHours) =
            StaffPayCsvRecord
                { staffName = recordStaffName
                , label = recordLabel
                , dayHours = recordDayHours
                , total = sum recordDayHours
                }

renderStaffPayCsv :: [Text] -> [StaffPayCsvRecord] -> Text
renderStaffPayCsv reportDayLabels records =
    Text.unlines (csvHeader : map renderRow records)
    where
        csvHeader =
            Text.intercalate ","
                (map csvCell (["Name", "Type"] <> reportDayLabels <> ["Total"]))

        renderRow record =
            Text.intercalate ","
                ( map csvCell [record.staffName, record.label]
                    <> map formatStaffPayHours record.dayHours
                    <> [formatStaffPayHours record.total]
                )

staffPayDisplayName :: Staff -> Text
staffPayDisplayName staff = staff.firstName

staffPayRecordLabel :: VenueReportDefinition -> TimesheetPayResult -> Text
staffPayRecordLabel reportDefinition payResult
    | null reportDefinition.shiftTypeFilters = fromMaybe "Unknown pay level" payResult.payLevelName
    | otherwise = ""

reportDayIndex :: ReportWeekSelection -> Day -> Maybe Int
reportDayIndex reportWeekSelection workedOnDate =
    let dayIndex = fromInteger (diffDays workedOnDate reportWeekSelection.weekStart)
     in if dayIndex >= 0 && dayIndex < length reportWeekSelection.dayLabels
            then Just dayIndex
            else Nothing

addDayHours :: Int -> Double -> [Double] -> [Double]
addDayHours dayIndex hours existingDayHours =
    [ if index == dayIndex then currentHours + hours else currentHours
    | (index, currentHours) <- zip [0 ..] existingDayHours
    ]

paidMinutesToHours :: Int -> Double
paidMinutesToHours paidMinutes = fromIntegral paidMinutes / 60

formatStaffPayHours :: Double -> Text
formatStaffPayHours value = Text.pack (printf "%.2f" value :: String)

renderHourlyBreakdownZipBase64 :: ReportWeekSelection -> [ShiftType] -> [TimesheetEntry] -> Text
renderHourlyBreakdownZipBase64 reportWeekSelection shiftTypes entries =
    decodeUtf8
        (Base64.encode (LBS.toStrict (Zip.fromArchive archive)))
    where
        archive =
            foldr
                (\(dayOffset, dayLabel) currentArchive ->
                    let fileName = Text.unpack dayLabel <> ".csv"
                        csvContents = encodeUtf8 (renderHourlyBreakdownDayCsv reportWeekSelection dayOffset shiftTypes entries)
                        entry = Zip.toEntry fileName 0 (LBS.fromStrict csvContents)
                     in Zip.addEntryToArchive entry currentArchive
                )
                Zip.emptyArchive
                (zip [0 ..] reportWeekSelection.dayLabels)

renderHourlyBreakdownDayCsv :: ReportWeekSelection -> Int -> [ShiftType] -> [TimesheetEntry] -> Text
renderHourlyBreakdownDayCsv reportWeekSelection dayOffset shiftTypes entries =
    Text.unlines (csvHeader : map renderHourRow [8 .. 27])
    where
        csvHeader =
            Text.intercalate ","
                (map csvCell ("Time" : map (.name) shiftTypes))

        dayEntries =
            filter (\entry -> reportDayIndex reportWeekSelection entry.workedOn == Just dayOffset) entries

        renderHourRow hourOfWindow =
            let windowLabel = formatHourlyWindow hourOfWindow
                hourValues =
                    map
                        (\shiftType ->
                            let hours = sum (map (entryHoursForHourlyWindow hourOfWindow shiftType) dayEntries)
                             in if hours <= 0
                                    then ""
                                    else formatHourlyBreakdownHours hours
                        )
                        shiftTypes
             in Text.intercalate "," (csvCell windowLabel : map csvCell hourValues)

entryHoursForHourlyWindow :: Int -> ShiftType -> TimesheetEntry -> Double
entryHoursForHourlyWindow hourOfWindow shiftType entry
    | entry.shiftTypeId /= unpackId (get #id shiftType) = 0
    | otherwise =
        let windowStart = hourlyWindowStartMinute hourOfWindow
            windowEnd = windowStart + 60
            entryStart = timeOfDayToMinutes entry.startTime
            entryEndRaw = timeOfDayToMinutes entry.endTime
            entryEnd = if entryEndRaw <= entryStart then entryEndRaw + 1440 else entryEndRaw
            overlapMinutes =
                max 0
                    (min entryEnd windowEnd - max entryStart windowStart)
            paidMinutes = max 0 (overlapMinutes - breakOverlapMinutes windowStart windowEnd entry)
         in fromIntegral paidMinutes / 60

breakOverlapMinutes :: Int -> Int -> TimesheetEntry -> Int
breakOverlapMinutes windowStart windowEnd entry
    | not entry.hadBreak = 0
    | entry.breakMinutes <= 0 = 0
    | otherwise =
        case (entry.breakStartTime, entry.breakEndTime) of
            (Just breakStartTime, Just breakEndTime) ->
                let breakStart = timeOfDayToMinutes breakStartTime
                    breakEndRaw = timeOfDayToMinutes breakEndTime
                    breakEnd = if breakEndRaw <= breakStart then breakEndRaw + 1440 else breakEndRaw
                 in max 0 (min breakEnd windowEnd - max breakStart windowStart)
            _ -> 0

hourlyWindowStartMinute :: Int -> Int
hourlyWindowStartMinute hourOfWindow
    | hourOfWindow < 24 = hourOfWindow * 60
    | otherwise = (hourOfWindow - 24) * 60 + 1440

formatHourlyWindow :: Int -> Text
formatHourlyWindow hourOfWindow
    | hourOfWindow < 24 = Text.pack (printf "%02d:00" hourOfWindow :: String)
    | otherwise = Text.pack (printf "%02d:00+1" (hourOfWindow - 24) :: String)

formatHourlyBreakdownHours :: Double -> Text
formatHourlyBreakdownHours value = Text.pack (printf "%.1f" value :: String)

fallbackReportDayLabels :: Day -> [Text]
fallbackReportDayLabels reportWeekStart =
    map (fallbackReportDayLabel reportWeekStart) [0 .. 6]

fallbackReportDayLabel :: Day -> Int -> Text
fallbackReportDayLabel reportWeekStart dayOffset =
    Text.pack (formatTime defaultTimeLocale "%A" (addDays (toInteger dayOffset) reportWeekStart))

weekOffsetForDay :: Day -> Day -> Int
weekOffsetForDay epoch day = fromInteger (diffDays day epoch `div` 7)

weekdayIndexForDay :: Day -> Int
weekdayIndexForDay day = fromMaybe 0 (readMaybe (formatTime defaultTimeLocale "%w" day))

requestApprovedTimesheetsCsvExport ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Day ->
    Day ->
    IO ExportJob
requestApprovedTimesheetsCsvExport rangeStart rangeEnd = withTransaction do
    now <- getCurrentTime
    let expiresAt = addUTCTime exportExpirySeconds now
    let exportType = exportJobTypeToText ApprovedTimesheetsCsv
    _ <- ensureCurrentVenuePayConfigSnapshot
    let initialScope =
            Aeson.object
                [ "rangeStart" Aeson..= rangeStart
                , "rangeEnd" Aeson..= rangeEnd
                , "approvedOnly" Aeson..= True
                ]
    exportJob <-
        newRecord @ExportJob
            |> set #venueId (unpackId currentVenueId)
            |> set #requestedByUserId (unpackId (get #id currentUser))
            |> set #exportType exportType
            |> set #status (exportJobStatusToText ExportPending)
            |> set #schemaVersion exportSchemaVersion
            |> set #rangeStart (Just rangeStart)
            |> set #rangeEnd (Just rangeEnd)
            |> set #scope initialScope
            |> set #deliveryMethod browserDownloadMethod
            |> set #destinationMetadata (Aeson.object ["requestedVia" Aeson..= requestAuditSourceChannel])
            |> set #expiresAt expiresAt
            |> createRecord

    entries <- fetchApprovedTimesheetEntries rangeStart rangeEnd
    staffById <- fetchStaffMap entries
    approversById <- fetchApproverMap entries
    snapshotVersionsByEntryId <- fetchSnapshotVersionsForEntries entries
    let snapshotVersions = List.sort (List.nub (Map.elems snapshotVersionsByEntryId))
    let exportSnapshotVersion =
            case snapshotVersions of
                []             -> Nothing
                [versionLabel] -> Just versionLabel
                _              -> Just "mixed"
    let csvContents = renderApprovedTimesheetCsv entries staffById approversById snapshotVersionsByEntryId
    let fileName = buildApprovedTimesheetExportFileName rangeStart rangeEnd
    let finalScope =
            Aeson.object
                [ "rangeStart" Aeson..= rangeStart
                , "rangeEnd" Aeson..= rangeEnd
                , "approvedOnly" Aeson..= True
                , "entryCount" Aeson..= length entries
                , "snapshotVersions" Aeson..= snapshotVersions
                ]
    exportJob <-
        exportJob
            |> set #status (exportJobStatusToText ExportReady)
            |> set #payConfigSnapshotVersion exportSnapshotVersion
            |> set #scope finalScope
            |> set #fileName (Just fileName)
            |> set #contentType (Just "text/csv; charset=utf-8")
            |> set #fileEncoding "utf8"
            |> set #fileContents (Just csvContents)
            |> updateRecord

    void $ recordCurrentUserAuditEvent
        "export_generated"
        "export_jobs"
        (unpackId (get #id exportJob))
        (Aeson.object
            [ "exportType" Aeson..= exportType
            , "rangeStart" Aeson..= rangeStart
            , "rangeEnd" Aeson..= rangeEnd
            , "entryCount" Aeson..= length entries
            , "payConfigSnapshotVersion" Aeson..= exportSnapshotVersion
            , "deliveryMethod" Aeson..= exportJob.deliveryMethod
            ]
        )

    pure exportJob

expireCurrentVenueExportJobs :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO ()
expireCurrentVenueExportJobs = do
    now <- getCurrentTime
    exportJobs <- query @ExportJob
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> fetch

    forM_ exportJobs \exportJob ->
        when (shouldExpireExportJob now exportJob) do
            exportJob
                |> set #status (exportJobStatusToText ExportExpired)
                |> updateRecordDiscardResult

fetchCurrentVenueExportJobs :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [ExportJob]
fetchCurrentVenueExportJobs = do
    expireCurrentVenueExportJobs
    query @ExportJob
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> orderByDesc #createdAt
        |> fetch

authorizeExportDownload ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Id ExportJob ->
    UUID ->
    IO ExportJob
authorizeExportDownload exportJobId downloadToken = do
    exportJob <- fetch exportJobId
    ensureRecordInCurrentVenue exportJob.venueId
    accessDeniedUnless (exportJob.downloadToken == downloadToken)

    now <- getCurrentTime
    when (shouldExpireExportJob now exportJob) do
        exportJob
            |> set #status (exportJobStatusToText ExportExpired)
            |> updateRecordDiscardResult
        accessDeniedUnless False

    accessDeniedUnless (exportJob.status == exportJobStatusToText ExportReady)
    accessDeniedUnless (isJust exportJob.fileContents)
    pure exportJob

recordExportDownload ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    ExportJob ->
    IO ExportJob
recordExportDownload exportJob = withTransaction do
    now <- getCurrentTime
    exportJob <-
        exportJob
            |> set #downloadedAt (Just now)
            |> set #downloadedByUserId (Just (unpackId (get #id currentUser)))
            |> updateRecord

    void $ recordCurrentUserAuditEvent
        "export_downloaded"
        "export_jobs"
        (unpackId (get #id exportJob))
        (Aeson.object
            [ "exportType" Aeson..= exportJob.exportType
            , "generatedFileId" Aeson..= exportJob.generatedFileId
            , "deliveryMethod" Aeson..= exportJob.deliveryMethod
            ]
        )

    pure exportJob

buildApprovedTimesheetExportFileName :: Day -> Day -> Text
buildApprovedTimesheetExportFileName rangeStart rangeEnd =
    "approved-timesheets-" <> tshow rangeStart <> "-to-" <> tshow rangeEnd <> ".csv"

renderApprovedTimesheetCsv ::
    [TimesheetEntry] ->
    Map.Map UUID Staff ->
    Map.Map UUID User ->
    Map.Map UUID Text ->
    Text
renderApprovedTimesheetCsv entries staffById approversById snapshotVersionsByEntryId =
    Text.unlines (csvHeader : map renderRow entries)
    where
        csvHeader =
            Text.intercalate ","
                [ "worked_on"
                , "staff_name"
                , "start_time"
                , "end_time"
                , "break_minutes"
                , "pay_config_snapshot_version"
                , "approved_at"
                , "approved_by_email"
                ]

        renderRow entry =
            Text.intercalate ","
                [ csvCell (tshow entry.workedOn)
                , csvCell (staffDisplayName entry.staffId)
                , csvCell (formatTimeOfDay entry.startTime)
                , csvCell (formatTimeOfDay entry.endTime)
                , csvCell (tshow entry.breakMinutes)
                , csvCell (fromMaybe "" (entry.payConfigSnapshotId >>= (`Map.lookup` snapshotVersionsByEntryId)))
                , csvCell (maybe "" formatUtc entry.approvedAt)
                , csvCell (maybe "" (.email) (entry.approvedByUserId >>= (`Map.lookup` approversById)))
                ]

        staffDisplayName staffId =
            case Map.lookup staffId staffById of
                Just staff -> staff.lastName <> ", " <> staff.firstName
                Nothing    -> "Unknown staff"

fetchApprovedTimesheetEntries ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Day ->
    Day ->
    IO [TimesheetEntry]
fetchApprovedTimesheetEntries rangeStart rangeEnd =
    query @TimesheetEntry
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#isApproved, True)
        |> filterWhereIn (#workedOn, [rangeStart .. rangeEnd])
        |> orderByAsc #workedOn
        |> orderByAsc #startTime
        |> fetch

fetchStaffMap :: (?modelContext :: ModelContext) => [TimesheetEntry] -> IO (Map.Map UUID Staff)
fetchStaffMap entries =
    if null staffIds
        then pure Map.empty
        else do
            staff <- query @Staff |> filterWhereIn (#id, map Id staffIds) |> fetch
            pure (Map.fromList (map (\staffMember -> (coerce (get #id staffMember), staffMember)) staff))
    where
        staffIds = List.nub (map (.staffId) entries)

fetchApproverMap :: (?modelContext :: ModelContext) => [TimesheetEntry] -> IO (Map.Map UUID User)
fetchApproverMap entries =
    if null approverIds
        then pure Map.empty
        else do
            users <- query @User |> filterWhereIn (#id, map Id approverIds) |> fetch
            pure (Map.fromList (map (\user -> (coerce (get #id user), user)) users))
    where
        approverIds = List.nub (mapMaybe (.approvedByUserId) entries)

fetchSnapshotVersionsForEntries :: (?modelContext :: ModelContext) => [TimesheetEntry] -> IO (Map.Map UUID Text)
fetchSnapshotVersionsForEntries entries =
    if null snapshotIds
        then pure Map.empty
        else do
            snapshots <- query @PayConfigSnapshot |> filterWhereIn (#id, map Id snapshotIds) |> fetch
            pure (Map.fromList (map (\snapshot -> (coerce (get #id snapshot), snapshot.versionLabel)) snapshots))
    where
        snapshotIds = List.nub (mapMaybe (.payConfigSnapshotId) entries)

shouldExpireExportJob :: UTCTime -> ExportJob -> Bool
shouldExpireExportJob now exportJob =
    exportJob.status /= exportJobStatusToText ExportExpired
        && exportJob.expiresAt <= now

formatTimeOfDay :: TimeOfDay -> Text
formatTimeOfDay timeOfDay = Text.pack (formatTime defaultTimeLocale "%H:%M" timeOfDay)

formatUtc :: UTCTime -> Text
formatUtc timestamp = Text.pack (formatTime defaultTimeLocale "%Y-%m-%d %H:%M:%S UTC" timestamp)

csvCell :: Text -> Text
csvCell value
    | Text.any (`elem` [',', '"', '\n', '\r']) value =
        "\"" <> Text.replace "\"" "\"\"" value <> "\""
    | otherwise = value
