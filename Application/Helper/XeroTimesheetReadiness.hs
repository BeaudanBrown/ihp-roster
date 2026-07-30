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
import Application.VenueTime.Model (requireMelbourneDateRangeUTC)
import Application.WageSourceEnforcement (WageEntryFailure (..),
                                          enforceFinalWageEntries,
                                          renderWageEntryFailure)
import Application.Xero.ReferenceTrust (xeroReferenceSnapshotMaxAge)
import Application.Xero.Timesheets.Buckets
import Control.Monad (guard)
import qualified Data.Aeson.Types as AesonTypes
import Data.Either (fromRight)
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
    { readinessVenueId             :: !(Id Venue)
    , readinessPayrollCalendarId   :: !(Maybe Text)
    , readinessPayrollCalendarName :: !(Maybe Text)
    , readinessSelectedPeriodKey   :: !(Maybe Text)
    , readinessPeriodStart         :: !Day
    , readinessPeriodEnd           :: !Day
    , readinessPaymentDate         :: !(Maybe Day)
    , readinessXeroPayRunId        :: !(Maybe Text)
    , readinessXeroPayRunStatus    :: !(Maybe Text)
    , readinessRemoteTimesheets    :: ![XeroTimesheetRef]
    , readinessSkippedStaffIds     :: ![UUID]
    }
    deriving (Eq, Show)

validateXeroTimesheetReadiness ::
    (?modelContext :: ModelContext) =>
    XeroTimesheetReadinessRequest ->
    IO XeroTimesheetReadiness
validateXeroTimesheetReadiness request = do
    maybeConnection <- fetchActiveXeroConnection request.readinessVenueId
    now <- getCurrentTime
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
    wageSourceResult <- enforceFinalWageEntries approvedEntries
    bucketResult <- fetchPeriodXeroLocalEarningsBuckets request.readinessVenueId request.readinessPeriodStart request.readinessPeriodEnd effectiveSkippedStaffIds
    let buckets = fromRight [] bucketResult
    earningsMappings <- maybe (pure []) (fetchVerifiedEarningsMappings buckets) maybeConnection
    allPayItemRequirements <- maybe (pure []) fetchPayItemRequirements maybeConnection
    let bucketKeys = map (.localBucketKey) buckets
        payItemRequirements = filter (\requirement -> requirement.requirementKey `elem` bucketKeys) allPayItemRequirements
    maybeCalendar <- fetchRequestPayrollCalendar request maybeConnection
    maybeAccountCodeSelection <- maybe (pure Nothing) fetchVerifiedPayItemAccountCodeSelection maybeConnection

    let blockers =
            concat
                [ connectionBlockers maybeConnection
                , referenceSyncBlockers now maybeConnection
                , calendarBlockers request maybeCalendar
                , entryBlockers entries
                , wageSourceBlockers wageSourceResult
                , publicationBucketBlockers bucketResult
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

publicationBucketBlockers :: Either Text buckets -> [XeroReadinessBlocker]
publicationBucketBlockers (Right _) = []
publicationBucketBlockers (Left message) =
    [ (blockerWith "wage_publication_failed" ("Approved wage components could not be published: " <> message))
        { xeroBlockerActionHint = Just "Correct the approved pay ledger before preparing payroll."
        }
    ]

wageSourceBlockers :: Either [WageEntryFailure] calculations -> [XeroReadinessBlocker]
wageSourceBlockers (Right _) = []
wageSourceBlockers (Left failures) = map blocker failures
  where
    blocker failure =
        XeroReadinessBlockerDetail
            { xeroBlockerCode = "wage_source_policy"
            , xeroBlockerSeverity = XeroReadinessBlocker
            , xeroBlockerMessage = renderWageEntryFailure failure
            , xeroBlockerAffectedStaffId = Nothing
            , xeroBlockerTimesheetEntryId = Just (failureEntryId failure)
            , xeroBlockerLocalBucketKey = Nothing
            , xeroBlockerXeroObjectId = Nothing
            , xeroBlockerActionHint = Just "Refresh authoritative wage sources or correct the entry before payroll."
            }
    failureEntryId = \case
        WageCalculationFailed entryId _ -> entryId
        WageSourcesBlocked entryId _    -> entryId

fetchActiveXeroConnection :: (?modelContext :: ModelContext) => Id Venue -> IO (Maybe XeroConnection)
fetchActiveXeroConnection venueId =
    query @XeroConnection
        |> filterWhere (#venueId, unpackId venueId)
        |> filterWhere (#connectionStatus, "active" :: Text)
        |> orderByDesc #connectedAt
        |> fetchOneOrNothing

fetchPeriodTimesheetEntries :: (?modelContext :: ModelContext) => Id Venue -> Day -> Day -> IO [TimesheetEntry]
fetchPeriodTimesheetEntries venueId periodStart periodEnd = do
    let (periodStartsAt, periodEndsAt) = requireMelbourneDateRangeUTC periodStart periodEnd
    query @TimesheetEntry
        |> filterWhere (#venueId, unpackId venueId)
        |> filterWhereGreaterThanOrEqualTo (#startsAt, periodStartsAt)
        |> filterWhereLessThan (#startsAt, periodEndsAt)
        |> orderBy #startsAt
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
        |> filterWhere (#providerAvailable, True)
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

fetchRequestPayrollCalendar :: (?modelContext :: ModelContext) => XeroTimesheetReadinessRequest -> Maybe XeroConnection -> IO (Maybe XeroPayrollCalendar)
fetchRequestPayrollCalendar request maybeConnection =
    case (request.readinessPayrollCalendarId, maybeConnection) of
        (Just calendarId, Just connection) ->
            query @XeroPayrollCalendar
                |> filterWhere (#venueId, unpackId request.readinessVenueId)
                |> filterWhere (#xeroConnectionId, unpackId connection.id)
                |> filterWhere (#xeroPayrollCalendarId, calendarId)
                |> filterWhere (#providerAvailable, True)
                |> fetchOneOrNothing
        _ -> pure Nothing

fetchVerifiedPayItemAccountCodeSelection :: (?modelContext :: ModelContext) => XeroConnection -> IO (Maybe XeroPayItemAccountCodeSelection)
fetchVerifiedPayItemAccountCodeSelection connection =
    query @XeroPayItemAccountCodeSelection
        |> filterWhere (#xeroConnectionId, unpackId connection.id)
        |> filterWhere (#selectionStatus, "verified" :: Text)
        |> fetchOneOrNothing

fetchVenueLocalBuckets :: (?modelContext :: ModelContext) => Id Venue -> Day -> IO [XeroLocalEarningsBucket]
fetchVenueLocalBuckets venueId effectiveDay = do
    venueConfig <-
        query @VenueConfig
            |> filterWhere (#venueId, unpackId venueId)
            |> fetchOne
    staffMembers <- fetchActiveVenueStaff venueId
    shiftTypes <- fetchActiveVenueShiftTypes venueId
    awardLevels <-
        query @AwardLevel
            |> filterWhere (#isActive, True)
            |> fetch
    baseRates <- query @AwardLevelBaseRate |> fetch
    penaltyRates <- query @AwardLevelPenaltyRate |> fetch
    timeAllowances <- query @AwardTimePenaltyAllowance |> fetch
    pure (deriveXeroLocalEarningsBuckets venueConfig.rosterWeekStartsOn effectiveDay (deriveXeroUsedAwardPayScopes staffMembers shiftTypes) awardLevels baseRates penaltyRates timeAllowances)

connectionBlockers :: Maybe XeroConnection -> [XeroReadinessBlocker]
connectionBlockers Nothing = [blocker "no_active_xero_connection" "Connect Xero before preparing payroll timesheets."]
connectionBlockers (Just connection)
    | connection.connectionStatus /= "active" =
        [blocker "xero_connection_not_active" "Reconnect Xero before preparing payroll timesheets."]
    | otherwise = []

referenceSyncBlockers :: UTCTime -> Maybe XeroConnection -> [XeroReadinessBlocker]
referenceSyncBlockers _ Nothing = [blocker "missing_reference_sync" "Connect Xero and wait for trusted reference data before preparing timesheets."]
referenceSyncBlockers now (Just connection) =
    case connection.lastSyncAt of
        Nothing -> [blocker "missing_reference_sync" "Wait for the initial Xero reference sync before preparing timesheets."]
        Just lastSyncAt
            | diffUTCTime now lastSyncAt < xeroReferenceSnapshotMaxAge -> []
            | otherwise -> [blocker "stale_reference_snapshot" "Xero reference data is out of date and could not be refreshed. Contact support before preparing timesheets."]

calendarBlockers :: XeroTimesheetReadinessRequest -> Maybe XeroPayrollCalendar -> [XeroReadinessBlocker]
calendarBlockers request maybeCalendar =
    case (request.readinessPayrollCalendarId, maybeCalendar) of
        (Nothing, _) -> [blocker "missing_payroll_calendar_selection" "Select a Xero payroll calendar period."]
        (_, Nothing) -> [blocker "missing_selected_payroll_calendar" "The selected Xero payroll calendar has not been synced."]
        (_, Just calendar) -> selectedCalendarBlockers request calendar

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
            guard (xeroEmployeePayrollCalendarId employee /= Just selectedCalendarId)
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
            if Text.isPrefixOf "xero:imported-pay-item:" bucket.localBucketKey || bucketHasMapping bucket || bucketHasReadyRequirement bucket
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
        |> filter (not . isUpdatableDraftTimesheet)
        |> map \remote ->
            (blockerWith
                "existing_xero_timesheet"
                "Xero already has a non-draft timesheet for this employee and period. Update or delete it in Xero before continuing."
            )
                { xeroBlockerXeroObjectId = remote.xeroTimesheetId }

duplicateWarnings :: XeroTimesheetReadinessRequest -> [TimesheetEntry] -> [XeroStaffMapping] -> [XeroTimesheetRef] -> [XeroReadinessBlocker]
duplicateWarnings request entries mappings remoteTimesheets =
    matchingRemoteTimesheets request entries mappings remoteTimesheets
        |> filter isUpdatableDraftTimesheet
        |> map \remote ->
            (blockerWith
                "existing_xero_draft_timesheet"
                "Existing Xero draft timesheet will be updated."
            )
                { xeroBlockerSeverity = XeroReadinessWarning
                , xeroBlockerXeroObjectId = remote.xeroTimesheetId
                }

isUpdatableDraftTimesheet :: XeroTimesheetRef -> Bool
isUpdatableDraftTimesheet remote =
    isJust remote.xeroTimesheetId
        && maybe False ((== "draft") . Text.toCaseFold) remote.xeroTimesheetStatus

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
