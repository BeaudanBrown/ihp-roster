module Application.Helper.XeroTimesheetReadiness
    ( XeroReadinessBlocker (..)
    , XeroReadinessSeverity (..)
    , XeroTimesheetReadiness (..)
    , XeroTimesheetReadinessRequest (..)
    , deriveXeroPayrollCalendarPeriod
    , readinessBlockerCodes
    , validateXeroTimesheetReadiness
    , xeroReadinessSeverityText
    ) where

import Application.Helper.VenueScopedQueries
import Application.Helper.Xero
import Application.Helper.XeroAdminTypes
import Application.Helper.XeroPayItems
import Application.Xero.Timesheets.Buckets
import Control.Monad (guard)
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.List as List
import qualified Data.Text as Text
import Data.Time.Calendar (Day, addDays, diffDays)
import Generated.Types
import IHP.ControllerPrelude

data XeroReadinessSeverity
    = XeroReadinessBlocker
    | XeroReadinessWarning
    deriving (Eq, Show)

xeroReadinessSeverityText :: XeroReadinessSeverity -> Text
xeroReadinessSeverityText XeroReadinessBlocker = "blocker"
xeroReadinessSeverityText XeroReadinessWarning = "warning"

data XeroReadinessBlocker = XeroReadinessBlockerDetail
    { xeroBlockerCode             :: !Text
    , xeroBlockerSeverity         :: !XeroReadinessSeverity
    , xeroBlockerMessage          :: !Text
    , xeroBlockerAffectedStaffId  :: !(Maybe UUID)
    , xeroBlockerTimesheetEntryId :: !(Maybe UUID)
    , xeroBlockerLocalBucketKey   :: !(Maybe Text)
    , xeroBlockerXeroObjectId     :: !(Maybe Text)
    , xeroBlockerActionHint       :: !(Maybe Text)
    }
    deriving (Eq, Show)

data XeroTimesheetReadiness = XeroTimesheetReadiness
    { xeroTimesheetReady          :: !Bool
    , xeroReadinessPeriodStart    :: !Day
    , xeroReadinessPeriodEnd      :: !Day
    , xeroReadinessBlockers       :: ![XeroReadinessBlocker]
    , xeroReadinessWarnings       :: ![XeroReadinessBlocker]
    , xeroReadinessStaffCount     :: !Int
    , xeroReadinessEntryCount     :: !Int
    , xeroReadinessPayBucketCount :: !Int
    }
    deriving (Eq, Show)

data XeroTimesheetReadinessRequest = XeroTimesheetReadinessRequest
    { readinessVenueId            :: !(Id Venue)
    , readinessPayrollCalendarId  :: !(Maybe Text)
    , readinessPayrollCalendarName :: !(Maybe Text)
    , readinessSelectedPeriodKey  :: !(Maybe Text)
    , readinessPeriodStart        :: !Day
    , readinessPeriodEnd          :: !Day
    , readinessPaymentDate        :: !(Maybe Day)
    , readinessXeroPayRunId       :: !(Maybe Text)
    , readinessXeroPayRunStatus   :: !(Maybe Text)
    , readinessRemoteTimesheets   :: ![XeroTimesheetRef]
    , readinessSkippedStaffIds    :: ![UUID]
    }
    deriving (Eq, Show)

validateXeroTimesheetReadiness ::
    (?modelContext :: ModelContext) =>
    XeroTimesheetReadinessRequest ->
    IO XeroTimesheetReadiness
validateXeroTimesheetReadiness request = do
    maybeConnection <- fetchActiveXeroConnection request.readinessVenueId
    latestSync <- fetchLatestXeroSyncRun request.readinessVenueId
    periodEntries <- fetchPeriodTimesheetEntries request.readinessVenueId request.readinessPeriodStart request.readinessPeriodEnd
    notPaidStaffIds <- maybe (pure []) fetchNotPaidStaffMappingIds maybeConnection
    let baseSkippedStaffIds = List.nub (request.readinessSkippedStaffIds <> notPaidStaffIds)
    let entriesBeforeCalendarFilter = filter (not . staffIsSkipped baseSkippedStaffIds . (.staffId)) periodEntries
    let approvedEntriesBeforeCalendarFilter = approvedSubmittableEntries entriesBeforeCalendarFilter
    let candidateStaffIds = List.nub (map (.staffId) approvedEntriesBeforeCalendarFilter)
    staffMappings <- maybe (pure []) (fetchVerifiedStaffMappings candidateStaffIds) maybeConnection
    mappedXeroEmployees <- maybe (pure []) (fetchMappedXeroEmployees staffMappings) maybeConnection
    let calendarSkippedStaffIds = employeePayrollCalendarSkippedStaffIds request approvedEntriesBeforeCalendarFilter staffMappings mappedXeroEmployees
    let effectiveSkippedStaffIds = List.nub (baseSkippedStaffIds <> calendarSkippedStaffIds)
    let entries = filter (not . staffIsSkipped effectiveSkippedStaffIds . (.staffId)) periodEntries
    let approvedEntries = approvedSubmittableEntries entries
    let includedStaffIds = List.nub (map (.staffId) approvedEntries)
    buckets <- fetchPeriodXeroLocalEarningsBuckets request.readinessVenueId request.readinessPeriodStart request.readinessPeriodEnd effectiveSkippedStaffIds
    earningsMappings <- maybe (pure []) (fetchVerifiedEarningsMappings buckets) maybeConnection
    allPayItemRequirements <- maybe (pure []) fetchPayItemRequirements maybeConnection
    let bucketKeys = map (.localBucketKey) buckets
        payItemRequirements = filter (\requirement -> requirement.requirementKey `elem` bucketKeys) allPayItemRequirements
    maybeCalendarSelection <- maybe (pure Nothing) fetchVerifiedPayrollCalendarSelection maybeConnection
    maybeCalendar <- fetchRequestPayrollCalendar request maybeConnection maybeCalendarSelection
    maybeAccountCodeSelection <- maybe (pure Nothing) fetchVerifiedPayItemAccountCodeSelection maybeConnection

    let blockers =
            concat
                [ connectionBlockers maybeConnection
                , referenceSyncBlockers latestSync
                , calendarBlockers request maybeCalendarSelection maybeCalendar
                , entryBlockers entries
                , earningsMappingBlockers buckets earningsMappings payItemRequirements
                , payItemRequirementBlockers earningsMappings payItemRequirements maybeAccountCodeSelection
                , duplicateBlockers request entries staffMappings request.readinessRemoteTimesheets
                ]
    let warnings =
            concat
                [ entryWarnings entries
                , staffMappingWarnings entries staffMappings
                , duplicateWarnings request entries staffMappings request.readinessRemoteTimesheets
                ]
    pure XeroTimesheetReadiness
        { xeroTimesheetReady = null blockers
        , xeroReadinessPeriodStart = request.readinessPeriodStart
        , xeroReadinessPeriodEnd = request.readinessPeriodEnd
        , xeroReadinessBlockers = blockers
        , xeroReadinessWarnings = warnings
        , xeroReadinessStaffCount = length includedStaffIds
        , xeroReadinessEntryCount = length approvedEntries
        , xeroReadinessPayBucketCount = length buckets
        }

fetchActiveXeroConnection :: (?modelContext :: ModelContext) => Id Venue -> IO (Maybe XeroConnection)
fetchActiveXeroConnection venueId =
    query @XeroConnection
        |> filterWhere (#venueId, unpackId venueId)
        |> filterWhere (#connectionStatus, "active" :: Text)
        |> orderByDesc #connectedAt
        |> fetchOneOrNothing

fetchLatestXeroSyncRun :: (?modelContext :: ModelContext) => Id Venue -> IO (Maybe XeroSyncRun)
fetchLatestXeroSyncRun venueId =
    query @XeroSyncRun
        |> filterWhere (#venueId, unpackId venueId)
        |> filterWhere (#syncKind, "payroll_reference_data" :: Text)
        |> orderByDesc #startedAt
        |> fetchOneOrNothing

fetchPeriodTimesheetEntries :: (?modelContext :: ModelContext) => Id Venue -> Day -> Day -> IO [TimesheetEntry]
fetchPeriodTimesheetEntries venueId periodStart periodEnd =
    query @TimesheetEntry
        |> filterWhere (#venueId, unpackId venueId)
        |> filterWhereGreaterThanOrEqualTo (#workedOn, periodStart)
        |> filterWhereLessThanOrEqualTo (#workedOn, periodEnd)
        |> orderBy #workedOn
        |> fetch

fetchVerifiedStaffMappings :: (?modelContext :: ModelContext) => [UUID] -> XeroConnection -> IO [XeroStaffMapping]
fetchVerifiedStaffMappings staffIds connection =
    query @XeroStaffMapping
        |> filterWhere (#xeroConnectionId, unpackId connection.id)
        |> filterWhereIn (#staffId, staffIds)
        |> filterWhere (#mappingStatus, "verified" :: Text)
        |> fetch

fetchMappedXeroEmployees :: (?modelContext :: ModelContext) => [XeroStaffMapping] -> XeroConnection -> IO [XeroEmployee]
fetchMappedXeroEmployees mappings connection =
    query @XeroEmployee
        |> filterWhere (#xeroConnectionId, unpackId connection.id)
        |> filterWhereIn (#xeroEmployeeId, List.nub (mapMaybe (.xeroEmployeeId) mappings))
        |> fetch

fetchNotPaidStaffMappingIds :: (?modelContext :: ModelContext) => XeroConnection -> IO [UUID]
fetchNotPaidStaffMappingIds connection = do
    mappings <-
        query @XeroStaffMapping
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#mappingStatus, "not_applicable" :: Text)
            |> fetch
    pure (map (.staffId) (filter (isJust . (.updatedByUserId)) mappings))

fetchVerifiedEarningsMappings :: (?modelContext :: ModelContext) => [XeroLocalEarningsBucket] -> XeroConnection -> IO [XeroEarningsRateMapping]
fetchVerifiedEarningsMappings buckets connection =
    query @XeroEarningsRateMapping
        |> filterWhere (#xeroConnectionId, unpackId connection.id)
        |> filterWhereIn (#localBucketKey, map (.localBucketKey) buckets)
        |> filterWhere (#mappingStatus, "verified" :: Text)
        |> fetch

fetchPayItemRequirements :: (?modelContext :: ModelContext) => XeroConnection -> IO [XeroPayItemRequirementRecord]
fetchPayItemRequirements connection =
    query @XeroPayItemRequirementRecord
        |> filterWhere (#xeroConnectionId, unpackId connection.id)
        |> fetch

fetchVerifiedPayrollCalendarSelection :: (?modelContext :: ModelContext) => XeroConnection -> IO (Maybe XeroPayrollCalendarSelection)
fetchVerifiedPayrollCalendarSelection connection =
    query @XeroPayrollCalendarSelection
        |> filterWhere (#xeroConnectionId, unpackId connection.id)
        |> filterWhere (#calendarStatus, "verified" :: Text)
        |> fetchOneOrNothing

fetchRequestPayrollCalendar :: (?modelContext :: ModelContext) => XeroTimesheetReadinessRequest -> Maybe XeroConnection -> Maybe XeroPayrollCalendarSelection -> IO (Maybe XeroPayrollCalendar)
fetchRequestPayrollCalendar request maybeConnection maybeSelection =
    case request.readinessPayrollCalendarId of
        Just calendarId ->
            case maybeConnection of
                Nothing -> pure Nothing
                Just connection ->
                    query @XeroPayrollCalendar
                        |> filterWhere (#venueId, unpackId request.readinessVenueId)
                        |> filterWhere (#xeroConnectionId, unpackId connection.id)
                        |> filterWhere (#xeroPayrollCalendarId, calendarId)
                        |> fetchOneOrNothing
        Nothing -> fetchSelectedPayrollCalendar maybeSelection

fetchSelectedPayrollCalendar :: (?modelContext :: ModelContext) => Maybe XeroPayrollCalendarSelection -> IO (Maybe XeroPayrollCalendar)
fetchSelectedPayrollCalendar Nothing = pure Nothing
fetchSelectedPayrollCalendar (Just selection) =
    case selection.xeroPayrollCalendarId of
        Nothing -> pure Nothing
        Just calendarId ->
            query @XeroPayrollCalendar
                |> filterWhere (#xeroConnectionId, selection.xeroConnectionId)
                |> filterWhere (#xeroPayrollCalendarId, calendarId)
                |> fetchOneOrNothing

fetchVerifiedPayItemAccountCodeSelection :: (?modelContext :: ModelContext) => XeroConnection -> IO (Maybe XeroPayItemAccountCodeSelection)
fetchVerifiedPayItemAccountCodeSelection connection =
    query @XeroPayItemAccountCodeSelection
        |> filterWhere (#xeroConnectionId, unpackId connection.id)
        |> filterWhere (#selectionStatus, "verified" :: Text)
        |> fetchOneOrNothing

fetchVenueLocalBuckets :: (?modelContext :: ModelContext) => Id Venue -> Day -> IO [XeroLocalEarningsBucket]
fetchVenueLocalBuckets venueId effectiveDay = do
    staffMembers <- fetchActiveVenueStaff venueId
    shiftTypes <- fetchActiveVenueShiftTypes venueId
    awardLevels <-
        query @AwardLevel
            |> filterWhere (#isActive, True)
            |> fetch
    baseRates <- query @AwardLevelBaseRate |> fetch
    penaltyRates <- query @AwardLevelPenaltyRate |> fetch
    timeAllowances <- query @AwardTimePenaltyAllowance |> fetch
    pure (deriveXeroLocalEarningsBuckets effectiveDay (deriveXeroUsedAwardPayScopes staffMembers shiftTypes) awardLevels baseRates penaltyRates timeAllowances)

connectionBlockers :: Maybe XeroConnection -> [XeroReadinessBlocker]
connectionBlockers Nothing = [blocker "no_active_xero_connection" "Connect Xero before preparing payroll timesheets."]
connectionBlockers (Just connection)
    | connection.connectionStatus /= "active" =
        [blocker "xero_connection_not_active" "Reconnect Xero before preparing payroll timesheets."]
    | otherwise = []

referenceSyncBlockers :: Maybe XeroSyncRun -> [XeroReadinessBlocker]
referenceSyncBlockers (Just syncRun)
    | syncRun.syncStatus == "succeeded" = []
    | otherwise = [blocker "latest_reference_sync_not_successful" "Run a successful Xero payroll reference sync before preparing timesheets."]
referenceSyncBlockers Nothing = [blocker "missing_reference_sync" "Sync Xero payroll reference data before preparing timesheets."]

calendarBlockers :: XeroTimesheetReadinessRequest -> Maybe XeroPayrollCalendarSelection -> Maybe XeroPayrollCalendar -> [XeroReadinessBlocker]
calendarBlockers request maybeSelection maybeCalendar =
    case (request.readinessPayrollCalendarId, maybeSelection, maybeCalendar) of
        (Nothing, Nothing, _) -> [blocker "missing_payroll_calendar_selection" "Select and verify a Xero payroll calendar."]
        (_, _, Nothing) -> [blocker "missing_selected_payroll_calendar" "The selected Xero payroll calendar has not been synced."]
        (_, _, Just calendar) -> selectedCalendarBlockers request calendar

selectedCalendarBlockers :: XeroTimesheetReadinessRequest -> XeroPayrollCalendar -> [XeroReadinessBlocker]
selectedCalendarBlockers request calendar =
    let expectedKey = calendar.xeroPayrollCalendarId <> ":" <> tshow request.readinessPeriodStart <> ":" <> tshow request.readinessPeriodEnd
        keyBlockers =
            case request.readinessSelectedPeriodKey of
                Just selectedKey | selectedKey /= expectedKey ->
                    [ (blockerWith
                        "selected_period_key_mismatch"
                        "The selected Xero period key does not match the selected payroll calendar and dates. Choose the period again."
                      )
                        { xeroBlockerXeroObjectId = Just calendar.xeroPayrollCalendarId }
                    ]
                _ -> []
     in keyBlockers <> case deriveXeroPayrollCalendarPeriod calendar request.readinessPeriodStart of
            Nothing ->
                [blocker "unsupported_payroll_calendar_period" "The selected Xero payroll calendar period cannot be derived."]
            Just (expectedStart, expectedEnd)
                | expectedStart == request.readinessPeriodStart && expectedEnd == request.readinessPeriodEnd -> []
                | otherwise ->
                    [ (blockerWith
                        "payroll_calendar_period_mismatch"
                        ("The selected Xero period must exactly match payroll calendar " <> calendar.xeroPayrollCalendarId <> " for " <> tshow expectedStart <> " to " <> tshow expectedEnd <> ".")
                      )
                        { xeroBlockerXeroObjectId = Just calendar.xeroPayrollCalendarId }
                    ]

employeePayrollCalendarSkippedStaffIds :: XeroTimesheetReadinessRequest -> [TimesheetEntry] -> [XeroStaffMapping] -> [XeroEmployee] -> [UUID]
employeePayrollCalendarSkippedStaffIds request approvedEntries mappings xeroEmployees =
    case request.readinessPayrollCalendarId of
        Nothing -> []
        Just selectedCalendarId ->
            includedStaffIds
                |> mapMaybe (staffSkippedForCalendar selectedCalendarId)
                |> List.nub
    where
        includedStaffIds = List.nub (map (.staffId) approvedEntries)
        staffSkippedForCalendar selectedCalendarId staffId = do
            employeeId <- List.find (mappingMatchesStaff staffId) mappings >>= (.xeroEmployeeId)
            employee <- List.find (\candidate -> candidate.xeroEmployeeId == employeeId) xeroEmployees
            employeeCalendarId <- xeroEmployeePayrollCalendarId employee
            guard (employeeCalendarId /= selectedCalendarId)
            Just staffId
        mappingMatchesStaff staffId mapping =
            mapping.staffId == staffId && isJust mapping.xeroEmployeeId

xeroEmployeePayrollCalendarId :: XeroEmployee -> Maybe Text
xeroEmployeePayrollCalendarId employee =
    join $ AesonTypes.parseMaybe parser employee.rawPayload
    where
        parser = AesonTypes.withObject "Xero employee" \object ->
            (object AesonTypes..:? "PayrollCalendarID") <|> (object AesonTypes..:? "payrollCalendarID") <|> (object AesonTypes..:? "payrollCalendarId")

deriveXeroPayrollCalendarPeriod :: XeroPayrollCalendar -> Day -> Maybe (Day, Day)
deriveXeroPayrollCalendarPeriod calendar localPeriodStart = do
    anchor <- calendar.startDate
    days <- calendarLengthDays calendar.calendarType
    let offset = diffDays localPeriodStart anchor
    guard (days > 0)
    let periodIndex = floorDiv offset days
    let expectedStart = addDays (periodIndex * days) anchor
    pure (expectedStart, addDays (days - 1) expectedStart)

calendarLengthDays :: Maybe Text -> Maybe Integer
calendarLengthDays maybeCalendarType =
    case Text.toCaseFold . Text.strip <$> maybeCalendarType of
        Just "weekly"      -> Just 7
        Just "week"        -> Just 7
        Just "fortnightly" -> Just 14
        Just "biweekly"    -> Just 14
        Just "fourweekly"  -> Just 28
        Just "four weekly" -> Just 28
        _                  -> Nothing

floorDiv :: Integer -> Integer -> Integer
floorDiv numerator denominator =
    let (quotient, remainder) = numerator `quotRem` denominator
     in if remainder < 0 then quotient - 1 else quotient

entryBlockers :: [TimesheetEntry] -> [XeroReadinessBlocker]
entryBlockers [] = [blocker "missing_approved_entries" "There are no timesheet entries in the selected period."]
entryBlockers entries =
    missingApprovedEntryBlocker <> deletedEntryBlockers
    where
        approvedEntries = filter (.isApproved) entries
        missingApprovedEntryBlocker =
            [ blocker "missing_approved_entries" "There are no approved timesheet entries in the selected period."
            | null approvedEntries
            ]
        deletedEntryBlockers =
            approvedEntries
                |> mapMaybe \entry ->
                    if isNothing entry.deletedAt
                        then Nothing
                        else Just (entryBlocker "entry_deleted" "Deleted timesheet entries cannot be submitted to Xero." entry)

entryWarnings :: [TimesheetEntry] -> [XeroReadinessBlocker]
entryWarnings entries =
    [ (blockerWith "entry_not_approved" "Unapproved entries remain in the pay period.")
        { xeroBlockerSeverity = XeroReadinessWarning
        }
    | not (all (.isApproved) entries)
    ]

staffMappingWarnings :: [TimesheetEntry] -> [XeroStaffMapping] -> [XeroReadinessBlocker]
staffMappingWarnings entries mappings =
    [ (blockerWith "staff_mapping_not_verified" "Every approved staff member must be matched.")
        { xeroBlockerSeverity = XeroReadinessWarning
        }
    | any missingVerifiedMapping approvedStaffIds
    ]
    where
        approvedEntries = approvedSubmittableEntries entries
        approvedStaffIds = List.nub (map (.staffId) approvedEntries)
        missingVerifiedMapping staffId =
            not (any (\mapping -> mapping.staffId == staffId && isJust mapping.xeroEmployeeId) mappings)

earningsMappingBlockers :: [XeroLocalEarningsBucket] -> [XeroEarningsRateMapping] -> [XeroPayItemRequirementRecord] -> [XeroReadinessBlocker]
earningsMappingBlockers buckets mappings requirements =
    buckets
        |> mapMaybe \bucket ->
            if bucketHasMapping bucket || bucketHasReadyRequirement bucket
                then Nothing
                else
                    Just
                        ( blockerWith
                            "earnings_mapping_not_verified"
                            "Every pay bucket must have a managed Xero pay item matched or created, or be imported from Xero in admin settings."
                        )
                            { xeroBlockerLocalBucketKey = Just bucket.localBucketKey
                            }
    where
        bucketHasMapping bucket =
            any (\mapping -> mapping.localBucketKey == bucket.localBucketKey && isJust mapping.xeroEarningsRateId) mappings
        bucketHasReadyRequirement bucket =
            any
                (\record ->
                    record.requirementKey == bucket.localBucketKey
                        && record.requirementStatus /= "ignored"
                )
                requirements

payItemRequirementBlockers :: [XeroEarningsRateMapping] -> [XeroPayItemRequirementRecord] -> Maybe XeroPayItemAccountCodeSelection -> [XeroReadinessBlocker]
payItemRequirementBlockers earningsMappings requirements maybeAccountCodeSelection =
    accountCodeBlockers <> requirementBlockers
    where
        activeRequirements = filter (\record -> record.requirementStatus /= "ignored" && not (requirementHasImportedMapping record)) requirements
        proposedRequirements = filter (\record -> record.requirementStatus == "proposed") activeRequirements
        accountCodeReady =
            maybe False (\selection -> selection.selectionStatus == "verified" && maybe False (not . Text.null . Text.strip) selection.accountCode) maybeAccountCodeSelection
        accountCodeBlockers =
            [ blocker "missing_pay_item_account_code" "Select a Xero pay item account code before creating proposed managed pay items."
            | not (null proposedRequirements || accountCodeReady)
            ]
        requirementBlockers =
            activeRequirements
                |> mapMaybe \record ->
                    if record.requirementStatus `elem` ["matched", "created"]
                        then Nothing
                        else
                            Just
                                ( blockerWith
                                    "managed_pay_item_not_ready"
                                    "Managed Xero pay item requirements must be matched or created before timesheet readiness."
                                )
                                    { xeroBlockerLocalBucketKey = Just record.requirementKey
                                    , xeroBlockerXeroObjectId = record.xeroEarningsRateId
                                    }
        requirementHasImportedMapping record =
            any
                (\mapping -> mapping.localBucketKey == record.requirementKey && isJust mapping.xeroEarningsRateId)
                earningsMappings

duplicateBlockers :: XeroTimesheetReadinessRequest -> [TimesheetEntry] -> [XeroStaffMapping] -> [XeroTimesheetRef] -> [XeroReadinessBlocker]
duplicateBlockers request entries mappings remoteTimesheets =
    matchingRemoteTimesheets request entries mappings remoteTimesheets
        |> map \remote ->
            (blockerWith
                "existing_xero_timesheet"
                "Xero already has a timesheet for this employee and period. Create is blocked until update support exists."
            )
                { xeroBlockerXeroObjectId = remote.xeroTimesheetId }

duplicateWarnings :: XeroTimesheetReadinessRequest -> [TimesheetEntry] -> [XeroStaffMapping] -> [XeroTimesheetRef] -> [XeroReadinessBlocker]
duplicateWarnings request entries mappings remoteTimesheets =
    matchingRemoteTimesheets request entries mappings remoteTimesheets
        |> filter (\remote -> maybe False ((== "draft") . Text.toCaseFold) remote.xeroTimesheetStatus)
        |> map \remote ->
            (blockerWith
                "existing_xero_draft_timesheet"
                "An existing Xero draft timesheet can become an update candidate after update support lands."
            )
                { xeroBlockerSeverity = XeroReadinessWarning
                , xeroBlockerXeroObjectId = remote.xeroTimesheetId
                }

matchingRemoteTimesheets :: XeroTimesheetReadinessRequest -> [TimesheetEntry] -> [XeroStaffMapping] -> [XeroTimesheetRef] -> [XeroTimesheetRef]
matchingRemoteTimesheets request entries mappings remoteTimesheets =
    let includedStaffIds =
            approvedSubmittableEntries entries
                |> filter (not . staffIsSkipped request.readinessSkippedStaffIds . (.staffId))
                |> map (.staffId)
                |> List.nub
        mappedEmployeeIds =
            mappings
                |> filter (\mapping -> mapping.staffId `elem` includedStaffIds)
                |> mapMaybe (.xeroEmployeeId)
     in remoteTimesheets
            |> filter \remote ->
                remote.xeroTimesheetStartDate == request.readinessPeriodStart
                    && remote.xeroTimesheetEndDate == request.readinessPeriodEnd
                    && remote.xeroTimesheetEmployeeId `elem` mappedEmployeeIds

approvedSubmittableEntries :: [TimesheetEntry] -> [TimesheetEntry]
approvedSubmittableEntries =
    filter \entry -> entry.isApproved && isNothing entry.deletedAt

staffIsSkipped :: [UUID] -> UUID -> Bool
staffIsSkipped skippedStaffIds staffId =
    staffId `elem` skippedStaffIds

blocker :: Text -> Text -> XeroReadinessBlocker
blocker = blockerWith

entryBlocker :: Text -> Text -> TimesheetEntry -> XeroReadinessBlocker
entryBlocker code message entry =
    (blockerWith code message)
        { xeroBlockerAffectedStaffId = Just entry.staffId
        , xeroBlockerTimesheetEntryId = Just (unpackId entry.id)
        }

blockerWith :: Text -> Text -> XeroReadinessBlocker
blockerWith code message =
    XeroReadinessBlockerDetail
        { xeroBlockerCode = code
        , xeroBlockerSeverity = XeroReadinessBlocker
        , xeroBlockerMessage = message
        , xeroBlockerAffectedStaffId = Nothing
        , xeroBlockerTimesheetEntryId = Nothing
        , xeroBlockerLocalBucketKey = Nothing
        , xeroBlockerXeroObjectId = Nothing
        , xeroBlockerActionHint = Nothing
        }

readinessBlockerCodes :: XeroTimesheetReadiness -> [Text]
readinessBlockerCodes readiness =
    map (.xeroBlockerCode) readiness.xeroReadinessBlockers
