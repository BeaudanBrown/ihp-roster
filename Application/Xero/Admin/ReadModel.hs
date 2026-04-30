module Application.Xero.Admin.ReadModel
    ( XeroEmployeeSuggestionResult (..)
    , adminXeroScope
    , attachXeroStaffMappingSuggestions
    , bestXeroEmployeeSuggestion
    , buildXeroReadyChecklist
    , currentVenueLocalXeroEarningsBuckets
    , fetchActiveCurrentVenueXeroConnection
    , fetchCurrentVenueXeroAdminSectionData
    , fetchCurrentVenueXeroEarningsBucketRows
    , fetchCurrentVenueXeroEarningsRates
    , fetchCurrentVenueXeroEmployees
    , fetchCurrentVenueXeroPayItemAccountCodeOptions
    , fetchCurrentVenueXeroPayItemAccountCodeSelection
    , fetchCurrentVenueXeroPayItemRequirements
    , fetchCurrentVenueXeroPayrollCalendarSelection
    , fetchCurrentVenueXeroPayrollCalendars
    , fetchCurrentVenueXeroStaffMappingRows
    , fetchCurrentVenueXeroConnection
    , fetchCurrentVenueXeroTimesheetPanelData
    , fetchLatestCurrentVenueXeroSyncRun
    , currentVenueXeroTimesheetReadinessRequest
    , fetchXeroConnectedByUser
    , staffFullNameText
    , xeroEmployeeAvailableForStaff
    , xeroEarningsRateMappingCountsFor
    , xeroStaffMappingCountsFor
    ) where

import Application.Helper.Controller
import Application.Helper.LiveUpdate
import Application.Helper.Profiling
import Application.Helper.VenueScopedQueries
import Application.Helper.XeroAdminTypes
import Application.Helper.XeroPayItems
import Application.Helper.XeroTimesheetReadiness
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.Char as Char
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Data.Scientific (Scientific)
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import Generated.Types
import IHP.ControllerPrelude

adminXeroScope :: Id Venue -> LiveUpdateScope
adminXeroScope venueId =
    AdminXeroScope
        { venueId = unpackId venueId
        }

fetchActiveCurrentVenueXeroConnection :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO (Maybe XeroConnection)
fetchActiveCurrentVenueXeroConnection =
    query @XeroConnection
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#connectionStatus, "active" :: Text)
        |> orderByDesc #connectedAt
        |> fetchOneOrNothing

fetchCurrentVenueXeroConnection :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO (Maybe XeroConnection)
fetchCurrentVenueXeroConnection =
    query @XeroConnection
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhereIn (#connectionStatus, ["active" :: Text, "reauthorization_required", "error"])
        |> orderByDesc #connectedAt
        |> fetchOneOrNothing

fetchXeroConnectedByUser :: (?modelContext :: ModelContext) => Maybe XeroConnection -> IO (Maybe User)
fetchXeroConnectedByUser maybeConnection =
    case maybeConnection >>= (.connectedByUserId) of
        Nothing -> pure Nothing
        Just userId ->
            query @User
                |> filterWhere (#id, Id userId)
                |> fetchOneOrNothing

fetchLatestCurrentVenueXeroSyncRun :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO (Maybe XeroSyncRun)
fetchLatestCurrentVenueXeroSyncRun =
    query @XeroSyncRun
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#syncKind, "payroll_reference_data" :: Text)
        |> orderByDesc #startedAt
        |> fetchOneOrNothing

fetchCurrentVenueXeroEmployeeCount :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe XeroConnection -> IO Int
fetchCurrentVenueXeroEmployeeCount maybeConnection =
    case maybeConnection of
        Nothing -> pure 0
        Just connection ->
            query @XeroEmployee
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhere (#xeroConnectionId, unpackId connection.id)
                |> fetchCount

fetchCurrentVenueXeroEarningsRateCount :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe XeroConnection -> IO Int
fetchCurrentVenueXeroEarningsRateCount maybeConnection =
    case maybeConnection of
        Nothing -> pure 0
        Just connection ->
            query @XeroEarningsRate
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhere (#xeroConnectionId, unpackId connection.id)
                |> fetchCount

fetchCurrentVenueXeroPayrollCalendarCount :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe XeroConnection -> IO Int
fetchCurrentVenueXeroPayrollCalendarCount maybeConnection =
    case maybeConnection of
        Nothing -> pure 0
        Just connection ->
            query @XeroPayrollCalendar
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhere (#xeroConnectionId, unpackId connection.id)
                |> fetchCount

fetchCurrentVenueXeroEmployees :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe XeroConnection -> IO [XeroEmployee]
fetchCurrentVenueXeroEmployees maybeConnection =
    case maybeConnection of
        Nothing -> pure []
        Just connection ->
            query @XeroEmployee
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhere (#xeroConnectionId, unpackId connection.id)
                |> orderBy #displayName
                |> fetch

fetchCurrentVenueXeroEarningsRates :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe XeroConnection -> IO [XeroEarningsRate]
fetchCurrentVenueXeroEarningsRates maybeConnection =
    case maybeConnection of
        Nothing -> pure []
        Just connection ->
            query @XeroEarningsRate
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhere (#xeroConnectionId, unpackId connection.id)
                |> filterWhere (#isActive, True)
                |> orderBy #name
                |> fetch

fetchCurrentVenueXeroPayItemAccountCodeOptions :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe XeroConnection -> IO [Text]
fetchCurrentVenueXeroPayItemAccountCodeOptions maybeConnection = do
    xeroEarningsRates <- fetchCurrentVenueXeroEarningsRates maybeConnection
    pure
        (xeroEarningsRates
            |> map (.accountCode)
            |> catMaybes
            |> map Text.strip
            |> filter (not . Text.null)
            |> List.nub
            |> List.sort)

fetchCurrentVenueXeroPayrollCalendars :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe XeroConnection -> IO [XeroPayrollCalendar]
fetchCurrentVenueXeroPayrollCalendars maybeConnection =
    case maybeConnection of
        Nothing -> pure []
        Just connection ->
            query @XeroPayrollCalendar
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhere (#xeroConnectionId, unpackId connection.id)
                |> orderBy #name
                |> fetch

fetchCurrentVenueXeroPayrollCalendarSelection :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe XeroConnection -> IO (Maybe XeroPayrollCalendarSelection)
fetchCurrentVenueXeroPayrollCalendarSelection maybeConnection =
    case maybeConnection of
        Nothing -> pure Nothing
        Just connection ->
            query @XeroPayrollCalendarSelection
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhere (#xeroConnectionId, unpackId connection.id)
                |> fetchOneOrNothing

fetchCurrentVenueXeroPayItemAccountCodeSelection :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe XeroConnection -> IO (Maybe XeroPayItemAccountCodeSelection)
fetchCurrentVenueXeroPayItemAccountCodeSelection maybeConnection =
    case maybeConnection of
        Nothing -> pure Nothing
        Just connection ->
            query @XeroPayItemAccountCodeSelection
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhere (#xeroConnectionId, unpackId connection.id)
                |> fetchOneOrNothing

fetchCurrentVenueXeroEarningsBucketRows :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe XeroConnection -> IO [XeroEarningsBucketRow]
fetchCurrentVenueXeroEarningsBucketRows maybeConnection =
    case maybeConnection of
        Nothing -> pure []
        Just connection -> do
            buckets <- currentVenueLocalXeroEarningsBuckets
            mappings <-
                query @XeroEarningsRateMapping
                    |> filterWhere (#venueId, unpackId currentVenueId)
                    |> filterWhere (#xeroConnectionId, unpackId connection.id)
                    |> fetch
            pure $
                buckets
                    |> map (\bucket ->
                        XeroEarningsBucketRow
                            { earningsBucketRowBucket = bucket
                            , earningsBucketRowMapping = List.find (\mapping -> mapping.localBucketKey == bucket.localBucketKey) mappings
                            }
                    )

fetchCurrentVenueXeroPayItemRequirements :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Maybe XeroConnection -> [XeroEarningsRate] -> IO [XeroPayItemRequirement]
fetchCurrentVenueXeroPayItemRequirements maybeConnection xeroEarningsRates =
    case maybeConnection of
        Nothing -> pure []
        Just connection -> do
            today <- utctDay <$> getCurrentTime
            usedScopes <- fetchCurrentVenueXeroUsedAwardPayScopes
            awardLevels <-
                query @AwardLevel
                    |> filterWhere (#isActive, True)
                    |> orderBy #classification
                    |> fetch
            awardLevelBaseRates <-
                query @AwardLevelBaseRate
                    |> orderBy #createdAt
                    |> fetch
            awardLevelPenaltyRates <-
                query @AwardLevelPenaltyRate
                    |> orderBy #createdAt
                    |> fetch
            awardTimePenaltyAllowances <-
                query @AwardTimePenaltyAllowance
                    |> orderBy #createdAt
                    |> fetch
            let requirements = deriveXeroPayItemRequirements today usedScopes awardLevels awardLevelBaseRates awardLevelPenaltyRates awardTimePenaltyAllowances xeroEarningsRates
            syncXeroPayItemRequirementRecords connection.id currentVenueId (Just currentUser.id) requirements

currentVenueLocalXeroEarningsBuckets :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [XeroLocalEarningsBucket]
currentVenueLocalXeroEarningsBuckets = do
    today <- utctDay <$> getCurrentTime
    usedScopes <- fetchCurrentVenueXeroUsedAwardPayScopes
    awardLevels <-
        query @AwardLevel
            |> filterWhere (#isActive, True)
            |> orderBy #classification
            |> fetch
    awardLevelBaseRates <-
        query @AwardLevelBaseRate
            |> orderBy #createdAt
            |> fetch
    awardLevelPenaltyRates <-
        query @AwardLevelPenaltyRate
            |> orderBy #createdAt
            |> fetch
    awardTimePenaltyAllowances <-
        query @AwardTimePenaltyAllowance
            |> orderBy #createdAt
            |> fetch
    pure (deriveXeroLocalEarningsBuckets today usedScopes awardLevels awardLevelBaseRates awardLevelPenaltyRates awardTimePenaltyAllowances)

fetchCurrentVenueXeroUsedAwardPayScopes :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [XeroUsedAwardPayScope]
fetchCurrentVenueXeroUsedAwardPayScopes = do
    staffMembers <- fetchActiveVenueStaff currentVenueId
    shiftTypes <- fetchActiveVenueShiftTypes currentVenueId
    pure (deriveXeroUsedAwardPayScopes staffMembers shiftTypes)

fetchCurrentVenueXeroStaffMappingRows :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe XeroConnection -> IO [XeroStaffMappingRow]
fetchCurrentVenueXeroStaffMappingRows maybeConnection =
    case maybeConnection of
        Nothing -> pure []
        Just connection -> do
            staffMembers <-
                query @Staff
                    |> filterWhere (#venueId, unpackId currentVenueId)
                    |> filterWhere (#isActive, True)
                    |> filterWhere (#archivedAt, Nothing)
                    |> orderBy #lastName
                    |> orderBy #firstName
                    |> fetch
            mappings <-
                query @XeroStaffMapping
                    |> filterWhere (#venueId, unpackId currentVenueId)
                    |> filterWhere (#xeroConnectionId, unpackId connection.id)
                    |> fetch
            xeroEmployees <- fetchCurrentVenueXeroEmployees (Just connection)
            rows <- forM staffMembers \staff -> do
                maybeUser <- fetchStaffLinkedUser staff
                mapping <- ensureDefaultXeroStaffMapping connection staff (List.find (\mapping -> mapping.staffId == unpackId staff.id) mappings)
                pure XeroStaffMappingRow
                    { mappingRowStaff = staff
                    , mappingRowUser = maybeUser
                    , mappingRowMapping = mapping
                    , mappingRowSuggestedEmployee = Nothing
                    }
            pure (attachXeroStaffMappingSuggestions xeroEmployees rows)

ensureDefaultXeroStaffMapping :: (?context :: ControllerContext, ?modelContext :: ModelContext) => XeroConnection -> Staff -> Maybe XeroStaffMapping -> IO XeroStaffMapping
ensureDefaultXeroStaffMapping _ _ (Just mapping) =
    pure mapping
ensureDefaultXeroStaffMapping connection staff Nothing =
    newRecord @XeroStaffMapping
        |> set #venueId (unpackId currentVenueId)
        |> set #staffId (unpackId staff.id)
        |> set #xeroConnectionId (unpackId connection.id)
        |> set #mappingStatus ("not_applicable" :: Text)
        |> createRecord

fetchStaffLinkedUser :: (?modelContext :: ModelContext) => Staff -> IO (Maybe User)
fetchStaffLinkedUser staff =
    case staff.userId of
        Nothing -> pure Nothing
        Just userId ->
            query @User
                |> filterWhere (#id, Id userId)
                |> fetchOneOrNothing

xeroStaffMappingCountsFor :: [XeroStaffMappingRow] -> XeroStaffMappingCounts
xeroStaffMappingCountsFor rows =
    XeroStaffMappingCounts
        { xeroStaffVerifiedCount = countStatus "verified"
        , xeroStaffNotApplicableCount = countStatus "not_applicable"
        , xeroStaffStaleCount = countStatus "stale"
        , xeroStaffPossibleMatchCount = length (filter (isJust . (.mappingRowSuggestedEmployee)) rows)
        }
    where
        mappingStatus row = row.mappingRowMapping.mappingStatus
        countStatus status = length (filter (\row -> mappingStatus row == status) rows)

xeroEarningsRateMappingCountsFor :: [XeroEarningsBucketRow] -> XeroEarningsRateMappingCounts
xeroEarningsRateMappingCountsFor rows =
    XeroEarningsRateMappingCounts
        { xeroEarningsVerifiedCount = countStatus "verified"
        , xeroEarningsUnmappedCount = length (filter isUnmapped rows)
        , xeroEarningsStaleCount = countStatus "stale"
        }
    where
        mappingStatus row = (.mappingStatus) <$> row.earningsBucketRowMapping
        countStatus status = length (filter (\row -> mappingStatus row == Just status) rows)
        isUnmapped row =
            case mappingStatus row of
                Nothing         -> True
                Just "unmapped" -> True
                _               -> False

buildXeroReadyChecklist :: Maybe XeroConnection -> Maybe XeroSyncRun -> [XeroStaffMappingRow] -> [XeroEarningsBucketRow] -> [XeroPayItemRequirement] -> Maybe XeroPayrollCalendarSelection -> Maybe XeroPayItemAccountCodeSelection -> XeroReadyChecklist
buildXeroReadyChecklist maybeConnection maybeSyncRun staffRows earningsRows payItemRequirements maybeCalendarSelection maybePayItemAccountCodeSelection =
    XeroReadyChecklist
        { xeroReadyConnection = maybe False (\connection -> connection.connectionStatus == "active") maybeConnection
        , xeroReadyReferenceSync = maybe False (\syncRun -> syncRun.syncStatus == "succeeded") maybeSyncRun
        , xeroReadyStaffMappings = not (null staffRows) && all staffRowReady staffRows
        , xeroReadyEarningsMappings = not (null earningsRows) && all earningsRowReady earningsRows
        , xeroReadyManagedPayItems = not (null activeRequirements) && all payItemRequirementReady activeRequirements
        , xeroReadyPayItemAccountCode = maybe False (\selection -> selection.selectionStatus == "verified" && maybe False (not . Text.null . Text.strip) selection.accountCode) maybePayItemAccountCodeSelection
        , xeroReadyPayrollCalendar = maybe False (\selection -> selection.calendarStatus == "verified" && isJust selection.xeroPayrollCalendarId) maybeCalendarSelection
        , xeroReadyStaffVerifiedCount = length (filter staffRowReady staffRows)
        , xeroReadyStaffTotalCount = length staffRows
        , xeroReadyEarningsVerifiedCount = length (filter earningsRowReady earningsRows)
        , xeroReadyEarningsTotalCount = length earningsRows
        , xeroReadyManagedPayItemReadyCount = length (filter payItemRequirementReady activeRequirements)
        , xeroReadyManagedPayItemTotalCount = length activeRequirements
        }
    where
        staffRowReady row =
            row.mappingRowMapping.mappingStatus == "verified" || row.mappingRowMapping.mappingStatus == "not_applicable"
        earningsRowReady row =
            maybe False (\mapping -> mapping.mappingStatus == "verified" && isJust mapping.xeroEarningsRateId) row.earningsBucketRowMapping
        activeRequirements = filter (\requirement -> requirement.payItemRequirementStatus /= "ignored") payItemRequirements
        payItemRequirementReady requirement =
            requirement.payItemRequirementStatus `elem` ["matched", "created"]

fetchCurrentVenueXeroAdminSectionData ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Bool ->
    IO XeroAdminSectionData
fetchCurrentVenueXeroAdminSectionData xeroConnectionActionsAllowed = do
    xeroConnection <- profileActionSpan "admin.xero.fragment.load_connection" fetchCurrentVenueXeroConnection
    xeroConnectedByUser <- profileActionSpan "admin.xero.fragment.load_connected_user" (fetchXeroConnectedByUser xeroConnection)
    xeroLatestSyncRun <- profileActionSpan "admin.xero.fragment.load_latest_sync" fetchLatestCurrentVenueXeroSyncRun
    (xeroEmployeeCount, xeroEarningsRateCount, xeroPayrollCalendarCount) <- profileActionSpan "admin.xero.fragment.fetch_reference_counts" do
        (,,)
            <$> fetchCurrentVenueXeroEmployeeCount xeroConnection
            <*> fetchCurrentVenueXeroEarningsRateCount xeroConnection
            <*> fetchCurrentVenueXeroPayrollCalendarCount xeroConnection
    xeroEmployees <- profileActionSpan "admin.xero.staff_mapping.fetch_employees" (fetchCurrentVenueXeroEmployees xeroConnection)
    xeroStaffMappingRows <- profileActionSpan "admin.xero.staff_mapping.fetch_rows" (fetchCurrentVenueXeroStaffMappingRows xeroConnection)
    let xeroStaffMappingCounts = xeroStaffMappingCountsFor xeroStaffMappingRows
    xeroEarningsRates <- profileActionSpan "admin.xero.earnings_mapping.fetch_rates" (fetchCurrentVenueXeroEarningsRates xeroConnection)
    xeroEarningsBucketRows <- profileActionSpan "admin.xero.earnings_mapping.fetch_rows" (fetchCurrentVenueXeroEarningsBucketRows xeroConnection)
    xeroPayItemRequirements <- profileActionSpan "admin.xero.pay_items.fetch_requirements" (fetchCurrentVenueXeroPayItemRequirements xeroConnection xeroEarningsRates)
    xeroPayrollCalendars <- profileActionSpan "admin.xero.calendar.fetch_calendars" (fetchCurrentVenueXeroPayrollCalendars xeroConnection)
    xeroPayrollCalendarSelection <- profileActionSpan "admin.xero.calendar.fetch_selection" (fetchCurrentVenueXeroPayrollCalendarSelection xeroConnection)
    xeroPayItemAccountCodeSelection <- profileActionSpan "admin.xero.pay_item_account_code.fetch_selection" (fetchCurrentVenueXeroPayItemAccountCodeSelection xeroConnection)
    let xeroReadyChecklist = buildXeroReadyChecklist xeroConnection xeroLatestSyncRun xeroStaffMappingRows xeroEarningsBucketRows xeroPayItemRequirements xeroPayrollCalendarSelection xeroPayItemAccountCodeSelection
    xeroTimesheetPanelData <- profileActionSpan "admin.xero.timesheets.fetch_panel" (fetchCurrentVenueXeroTimesheetPanelData xeroConnectionActionsAllowed xeroConnection xeroPayrollCalendarSelection)
    pure XeroAdminSectionData { .. }

fetchCurrentVenueXeroTimesheetPanelData ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Bool ->
    Maybe XeroConnection ->
    Maybe XeroPayrollCalendarSelection ->
    IO XeroTimesheetPanelData
fetchCurrentVenueXeroTimesheetPanelData actionsAllowed maybeConnection maybeCalendarSelection = do
    maybeReadinessRequest <- currentVenueXeroTimesheetReadinessRequest maybeConnection maybeCalendarSelection
    xeroTimesheetReadiness <-
        case maybeReadinessRequest of
            Nothing -> pure Nothing
            Just readinessRequest -> Just . xeroTimesheetReadinessView <$> validateXeroTimesheetReadiness readinessRequest
    xeroTimesheetLatestRun <- fetchCurrentVenueLatestXeroTimesheetRun maybeConnection
    pure XeroTimesheetPanelData
        { xeroTimesheetActionsAllowed = actionsAllowed
        , xeroTimesheetReadiness
        , xeroTimesheetPeriodMessage =
            case (maybeConnection, maybeCalendarSelection, maybeReadinessRequest) of
                (Nothing, _, _) -> Just "Connect Xero before preparing draft timesheets."
                (_, Nothing, _) -> Just "Select and verify a Xero payroll calendar before preparing draft timesheets."
                (_, _, Nothing) -> Just "The selected Xero payroll calendar period could not be derived."
                _ -> Nothing
        , xeroTimesheetLatestRun
        }

currentVenueXeroTimesheetReadinessRequest ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Maybe XeroConnection ->
    Maybe XeroPayrollCalendarSelection ->
    IO (Maybe XeroTimesheetReadinessRequest)
currentVenueXeroTimesheetReadinessRequest Nothing _ = pure Nothing
currentVenueXeroTimesheetReadinessRequest _ Nothing = pure Nothing
currentVenueXeroTimesheetReadinessRequest (Just connection) (Just selection) =
    case selection.xeroPayrollCalendarId of
        Nothing -> pure Nothing
        Just calendarId -> do
            maybeCalendar <-
                query @XeroPayrollCalendar
                    |> filterWhere (#venueId, unpackId currentVenueId)
                    |> filterWhere (#xeroConnectionId, unpackId connection.id)
                    |> filterWhere (#xeroPayrollCalendarId, calendarId)
                    |> fetchOneOrNothing
            today <- utctDay <$> getCurrentTime
            pure do
                calendar <- maybeCalendar
                (periodStart, periodEnd) <- deriveXeroPayrollCalendarPeriod calendar today
                pure XeroTimesheetReadinessRequest
                    { readinessVenueId = currentVenueId
                    , readinessPeriodStart = periodStart
                    , readinessPeriodEnd = periodEnd
                    , readinessRemoteTimesheets = []
                    }

fetchCurrentVenueLatestXeroTimesheetRun ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Maybe XeroConnection ->
    IO (Maybe XeroTimesheetRunView)
fetchCurrentVenueLatestXeroTimesheetRun Nothing = pure Nothing
fetchCurrentVenueLatestXeroTimesheetRun (Just connection) = do
    maybeRun <-
        query @XeroSubmissionRun
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> orderByDesc #createdAt
            |> fetchOneOrNothing
    case maybeRun of
        Nothing  -> pure Nothing
        Just run -> Just <$> buildXeroTimesheetRunView connection run

buildXeroTimesheetRunView ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    XeroConnection ->
    XeroSubmissionRun ->
    IO XeroTimesheetRunView
buildXeroTimesheetRunView connection run = do
    submissions <-
        query @XeroTimesheetSubmission
            |> filterWhere (#xeroSubmissionRunId, unpackId run.id)
            |> orderBy #xeroEmployeeId
            |> fetch
    staffMembers <-
        query @Staff
            |> filterWhereIn (#id, map (Id . (.staffId)) submissions)
            |> fetch
    employees <- fetchCurrentVenueXeroEmployees (Just connection)
    earningsRates <- fetchCurrentVenueXeroEarningsRates (Just connection)
    submittedBy <-
        query @User
            |> filterWhere (#id, Id run.submittedByUserId)
            |> fetchOneOrNothing
    historicalCount <-
        query @XeroSubmissionRun
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> fetchCount
    pure XeroTimesheetRunView
        { timesheetRun = run
        , timesheetRunPreviewRows = previewRowsFromJson employees earningsRates run.previewPayloadJson
        , timesheetRunSubmissionRows = map (submissionRowView staffMembers employees) submissions
        , timesheetRunSubmittedBy = submittedBy
        , timesheetRunHasHistoricalSib = historicalCount > 1
        }

submissionRowView :: [Staff] -> [XeroEmployee] -> XeroTimesheetSubmission -> XeroTimesheetSubmissionRowView
submissionRowView staffMembers employees submission =
    XeroTimesheetSubmissionRowView
        { submissionRowSubmission = submission
        , submissionRowStaff = List.find (\staff -> unpackId staff.id == submission.staffId) staffMembers
        , submissionRowEmployee = List.find (\employee -> employee.xeroEmployeeId == submission.xeroEmployeeId) employees
        }

xeroTimesheetReadinessView :: XeroTimesheetReadiness -> XeroTimesheetReadinessView
xeroTimesheetReadinessView readiness =
    XeroTimesheetReadinessView
        { timesheetReadinessReady = readiness.xeroTimesheetReady
        , timesheetReadinessPeriodStart = readiness.xeroReadinessPeriodStart
        , timesheetReadinessPeriodEnd = readiness.xeroReadinessPeriodEnd
        , timesheetReadinessStaffCount = readiness.xeroReadinessStaffCount
        , timesheetReadinessEntryCount = readiness.xeroReadinessEntryCount
        , timesheetReadinessBucketCount = readiness.xeroReadinessPayBucketCount
        , timesheetReadinessBlockers = map issueView (deduplicateReadinessIssues readiness.xeroReadinessBlockers)
        , timesheetReadinessWarnings = map issueView (deduplicateReadinessIssues readiness.xeroReadinessWarnings)
        }
    where
        deduplicateReadinessIssues =
            List.nubBy \left right ->
                left.xeroBlockerCode == right.xeroBlockerCode
        issueView issue =
            XeroTimesheetIssueView
                { timesheetIssueSeverity = xeroReadinessSeverityText issue.xeroBlockerSeverity
                , timesheetIssueMessage = issue.xeroBlockerMessage
                , timesheetIssueHint = issue.xeroBlockerActionHint
                }

previewRowsFromJson :: [XeroEmployee] -> [XeroEarningsRate] -> Aeson.Value -> [XeroTimesheetPreviewRowView]
previewRowsFromJson employees earningsRates value =
    case AesonTypes.parseMaybe parsePreviewRows value of
        Nothing   -> []
        Just rows -> map (toPreviewRow employeeNames earningsRateNames) rows
    where
        employeeNames = Map.fromList (map (\employee -> (employee.xeroEmployeeId, employee.displayName)) employees)
        earningsRateNames = Map.fromList (map (\rate -> (rate.xeroEarningsRateId, rate.name)) earningsRates)

data RawPreviewRow = RawPreviewRow
    { rawPreviewEmployeeId :: Text
    , rawPreviewStart      :: Day
    , rawPreviewEnd        :: Day
    , rawPreviewSourceIds  :: [UUID]
    , rawPreviewLines      :: [RawPreviewLine]
    }

data RawPreviewLine = RawPreviewLine
    { rawPreviewLineBucket         :: Text
    , rawPreviewLineEarningsRateId :: Text
    , rawPreviewLineUnits          :: [Scientific]
    }

parsePreviewRows :: Aeson.Value -> AesonTypes.Parser [RawPreviewRow]
parsePreviewRows =
    Aeson.withObject "XeroTimesheetPreviewRun" \object -> do
        timesheets <- object Aeson..: "timesheets"
        mapM parsePreviewRow (timesheets :: [Aeson.Value])

parsePreviewRow :: Aeson.Value -> AesonTypes.Parser RawPreviewRow
parsePreviewRow =
    Aeson.withObject "XeroTimesheetPreview" \object ->
        RawPreviewRow
            <$> object Aeson..: "xeroEmployeeId"
            <*> object Aeson..: "periodStart"
            <*> object Aeson..: "periodEnd"
            <*> object Aeson..: "sourceTimesheetEntryIds"
            <*> (object Aeson..: "lines" >>= mapM parsePreviewLine)

parsePreviewLine :: Aeson.Value -> AesonTypes.Parser RawPreviewLine
parsePreviewLine =
    Aeson.withObject "XeroTimesheetPreviewLine" \object ->
        RawPreviewLine
            <$> object Aeson..: "localBucketKey"
            <*> object Aeson..: "xeroEarningsRateId"
            <*> object Aeson..: "numberOfUnits"

toPreviewRow :: Map.Map Text Text -> Map.Map Text Text -> RawPreviewRow -> XeroTimesheetPreviewRowView
toPreviewRow employeeNames earningsRateNames row =
    let lines = map (toPreviewLine earningsRateNames) row.rawPreviewLines
     in XeroTimesheetPreviewRowView
            { previewRowXeroEmployeeId = row.rawPreviewEmployeeId
            , previewRowEmployeeName = Map.findWithDefault row.rawPreviewEmployeeId row.rawPreviewEmployeeId employeeNames
            , previewRowPeriodStart = row.rawPreviewStart
            , previewRowPeriodEnd = row.rawPreviewEnd
            , previewRowTotalUnits = sum (map (.previewLineViewTotalUnits) lines)
            , previewRowLines = lines
            , previewRowSourceCount = length row.rawPreviewSourceIds
            }

toPreviewLine :: Map.Map Text Text -> RawPreviewLine -> XeroTimesheetPreviewLineView
toPreviewLine earningsRateNames line =
    XeroTimesheetPreviewLineView
        { previewLineViewLocalBucketKey = line.rawPreviewLineBucket
        , previewLineViewXeroEarningsRateId = line.rawPreviewLineEarningsRateId
        , previewLineViewEarningsRateName = Map.findWithDefault line.rawPreviewLineEarningsRateId line.rawPreviewLineEarningsRateId earningsRateNames
        , previewLineViewTotalUnits = sum line.rawPreviewLineUnits
        }

data XeroEmployeeSuggestionResult
    = NoXeroEmployeeSuggestion
    | AmbiguousXeroEmployeeSuggestion XeroEmployee XeroEmployee
    | XeroEmployeeSuggestion XeroEmployee

data ScoredXeroEmployeeSuggestion = ScoredXeroEmployeeSuggestion
    { scoredSuggestionEmployee :: XeroEmployee
    , scoredSuggestionScore    :: Double
    }

bestXeroEmployeeSuggestion :: XeroStaffMappingRow -> [XeroEmployee] -> XeroEmployeeSuggestionResult
bestXeroEmployeeSuggestion row employees =
    case List.sortOn (.scoredSuggestionScore) (map (scoreXeroEmployeeSuggestion row) employees) of
        [] -> NoXeroEmployeeSuggestion
        best : second : _
            | scoredSuggestionScore best > xeroEmployeeSuggestionThreshold -> NoXeroEmployeeSuggestion
            | scoredSuggestionScore second <= xeroEmployeeSuggestionThreshold
            , scoredSuggestionScore second - scoredSuggestionScore best < xeroEmployeeSuggestionAmbiguityMargin ->
                AmbiguousXeroEmployeeSuggestion best.scoredSuggestionEmployee second.scoredSuggestionEmployee
            | otherwise -> XeroEmployeeSuggestion best.scoredSuggestionEmployee
        best : _
            | scoredSuggestionScore best <= xeroEmployeeSuggestionThreshold -> XeroEmployeeSuggestion best.scoredSuggestionEmployee
            | otherwise -> NoXeroEmployeeSuggestion

attachXeroStaffMappingSuggestions :: [XeroEmployee] -> [XeroStaffMappingRow] -> [XeroStaffMappingRow]
attachXeroStaffMappingSuggestions employees rows =
    map attach rows
    where
        attach row
            | row.mappingRowMapping.mappingStatus /= "not_applicable" = row { mappingRowSuggestedEmployee = Nothing }
            | otherwise =
                let availableEmployees = filter (xeroEmployeeAvailableForStaff row.mappingRowStaff rows) employees
                 in case bestXeroEmployeeSuggestion row availableEmployees of
                        XeroEmployeeSuggestion employee -> row { mappingRowSuggestedEmployee = Just employee }
                        _ -> row { mappingRowSuggestedEmployee = Nothing }

xeroEmployeeSuggestionThreshold :: Double
xeroEmployeeSuggestionThreshold = 0.25

xeroEmployeeSuggestionAmbiguityMargin :: Double
xeroEmployeeSuggestionAmbiguityMargin = 0.08

scoreXeroEmployeeSuggestion :: XeroStaffMappingRow -> XeroEmployee -> ScoredXeroEmployeeSuggestion
scoreXeroEmployeeSuggestion row employee =
    ScoredXeroEmployeeSuggestion
        { scoredSuggestionEmployee = employee
        , scoredSuggestionScore = minimum (emailScore : nameScores)
        }
    where
        staff = row.mappingRowStaff
        staffNames =
            [ normalizeName (staff.firstName <> " " <> staff.lastName)
            , normalizeName (staff.lastName <> " " <> staff.firstName)
            ]
        employeeName = normalizeName employee.displayName
        nameScores = map (`normalizedLevenshteinDistance` employeeName) staffNames
        emailScore =
            case (row.mappingRowUser >>= normalizedEmail . (.email), employee.email >>= normalizedEmail) of
                (Just staffEmail, Just employeeEmail) | staffEmail == employeeEmail -> 0
                _ -> 1

xeroEmployeeAvailableForStaff :: Staff -> [XeroStaffMappingRow] -> XeroEmployee -> Bool
xeroEmployeeAvailableForStaff staff mappingRows employee =
    employee.xeroEmployeeId `List.notElem` usedByOtherStaff
    where
        currentStaffId = unpackId staff.id
        usedByOtherStaff =
            mappingRows
                |> mapMaybe verifiedEmployeeForOtherStaff

        verifiedEmployeeForOtherStaff row =
            let mapping = row.mappingRowMapping
             in if unpackId row.mappingRowStaff.id /= currentStaffId && mapping.mappingStatus == "verified"
                    then mapping.xeroEmployeeId
                    else Nothing

normalizedNameLength :: Text -> Int
normalizedNameLength =
    Text.length . Text.filter (/= ' ')

normalizedLevenshteinDistance :: Text -> Text -> Double
normalizedLevenshteinDistance left right
    | Text.null left || Text.null right = 1
    | otherwise = fromIntegral distance / fromIntegral denominator
    where
        distance = levenshteinDistance (Text.unpack left) (Text.unpack right)
        denominator = max 1 (max (normalizedNameLength left) (normalizedNameLength right))

levenshteinDistance :: String -> String -> Int
levenshteinDistance source target =
    List.last (List.foldl' transform [0 .. length target] source)
    where
        transform previous sourceChar =
            case previous of
                [] -> []
                firstPrevious : _ ->
                    scanl compute (firstPrevious + 1) (zip3 target previous (List.drop 1 previous))
                    where
                        compute left (targetChar, diagonal, above) =
                            minimum
                                [ left + 1
                                , above + 1
                                , diagonal + if sourceChar == targetChar then 0 else 1
                                ]

normalizeName :: Text -> Text
normalizeName =
    Text.unwords
        . Text.words
        . Text.map normalizeNameChar
        . Text.toLower
        . Text.strip

normalizeNameChar :: Char -> Char
normalizeNameChar char
    | Char.isAlphaNum char = char
    | otherwise = ' '

normalizedEmail :: Text -> Maybe Text
normalizedEmail email =
    let normalized = Text.toLower (Text.strip email)
     in if Text.null normalized then Nothing else Just normalized

staffFullNameText :: Staff -> Text
staffFullNameText staff =
    Text.strip (staff.firstName <> " " <> staff.lastName)
