module Application.Xero.Admin.ReadModel
    ( fetchActiveCurrentVenueXeroConnection
    , fetchCurrentVenueXeroAdminSectionData
    , fetchCurrentVenueXeroConnection
    , fetchCurrentVenueXeroEarningsRates
    , fetchCurrentVenueXeroEmployees
    , fetchCurrentVenueXeroPayItemAccountCodeOptions
    , fetchCurrentVenueXeroPayItemAccountCodeSelection
    , fetchCurrentVenueXeroPayItemRequirements
    , fetchCurrentVenueXeroPayrollCalendars
    , fetchCurrentVenueXeroStaffMappingRows
    , fetchCurrentVenueXeroTimesheetPeriodOptions
    , xeroEmployeeAvailableForStaff
    , xeroTimesheetPreviewRowsFromJson
    , xeroTimesheetReadinessView
    ) where

import Application.Helper.Controller
import Application.Helper.Profiling
import Application.Helper.VenueScopedQueries
import Application.Helper.XeroAdminTypes
import Application.Helper.XeroPayItems
import Application.Helper.XeroTimesheetReadiness
import Control.Monad (guard)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.Char as Char
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Data.Ord (Down (..))
import Data.Scientific (Scientific)
import qualified Data.Text as Text
import Data.Time.Calendar (Day, addDays, diffDays)
import Generated.Types
import IHP.ControllerPrelude

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

fetchCurrentVenueXeroAccounts :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe XeroConnection -> IO [XeroAccount]
fetchCurrentVenueXeroAccounts maybeConnection =
    case maybeConnection of
        Nothing -> pure []
        Just connection ->
            query @XeroAccount
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhere (#xeroConnectionId, unpackId connection.id)
                |> orderBy #code
                |> fetch

fetchCurrentVenueXeroPayItemAccountCodeOptions :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe XeroConnection -> IO [XeroPayItemAccountCodeOption]
fetchCurrentVenueXeroPayItemAccountCodeOptions maybeConnection = do
    xeroAccounts <- fetchCurrentVenueXeroAccounts maybeConnection
    pure (xeroPayItemAccountCodeOptionsFromAccounts xeroAccounts)

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

fetchCurrentVenueXeroPayItemAccountCodeSelection :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe XeroConnection -> IO (Maybe XeroPayItemAccountCodeSelection)
fetchCurrentVenueXeroPayItemAccountCodeSelection maybeConnection =
    case maybeConnection of
        Nothing -> pure Nothing
        Just connection ->
            query @XeroPayItemAccountCodeSelection
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhere (#xeroConnectionId, unpackId connection.id)
                |> fetchOneOrNothing

fetchCurrentVenueXeroPayItemRequirements :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Maybe XeroConnection -> [XeroEarningsRate] -> IO [XeroPayItemRequirement]
fetchCurrentVenueXeroPayItemRequirements maybeConnection xeroEarningsRates =
    case maybeConnection of
        Nothing -> pure []
        Just connection -> do
            today <- utctDay <$> getCurrentTime
            venueConfig <- fetchVenueConfig
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
            let requirements = deriveXeroPayItemRequirements venueConfig.rosterWeekStartsOn today usedScopes awardLevels awardLevelBaseRates awardLevelPenaltyRates awardTimePenaltyAllowances xeroEarningsRates
            syncXeroPayItemRequirementRecords connection.id currentVenueId (Just currentUser.id) requirements

currentVenueLocalXeroEarningsBuckets :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [XeroLocalEarningsBucket]
currentVenueLocalXeroEarningsBuckets = do
    today <- utctDay <$> getCurrentTime
    venueConfig <- fetchVenueConfig
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
    pure (deriveXeroLocalEarningsBuckets venueConfig.rosterWeekStartsOn today usedScopes awardLevels awardLevelBaseRates awardLevelPenaltyRates awardTimePenaltyAllowances)

fetchCurrentVenueXeroUsedAwardPayScopes :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [XeroUsedAwardPayScope]
fetchCurrentVenueXeroUsedAwardPayScopes = do
    staffMembers <- fetchLinkedActiveVenueStaff currentVenueId
    shiftTypes <- fetchActiveVenueShiftTypes currentVenueId
    pure (deriveXeroUsedAwardPayScopes staffMembers shiftTypes)

fetchCurrentVenueXeroStaffMappingRows :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe XeroConnection -> IO [XeroStaffMappingRow]
fetchCurrentVenueXeroStaffMappingRows maybeConnection =
    case maybeConnection of
        Nothing -> pure []
        Just connection -> do
            staffMembers <- fetchLinkedActiveVenueStaff currentVenueId
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

fetchCurrentVenueXeroAdminSectionData ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Bool ->
    IO XeroAdminSectionData
fetchCurrentVenueXeroAdminSectionData xeroConnectionActionsAllowed = do
    xeroConnection <- profileActionSpan "admin.xero.fragment.load_connection" fetchCurrentVenueXeroConnection
    pure XeroAdminSectionData { .. }

fetchCurrentVenueXeroTimesheetPeriodOptions ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Maybe XeroConnection ->
    IO [XeroTimesheetPeriodOption]
fetchCurrentVenueXeroTimesheetPeriodOptions Nothing =
    pure []
fetchCurrentVenueXeroTimesheetPeriodOptions (Just connection) = do
    calendars <- fetchCurrentVenueXeroPayrollCalendars (Just connection)
    payRuns <-
        query @XeroPayRun
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> orderByDesc #payPeriodStart
            |> fetch
    approvedEntries <-
        query @TimesheetEntry
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#isApproved, True)
            |> filterWhere (#deletedAt, Nothing)
            |> orderByDesc #workedOn
            |> fetch
    today <- utctDay <$> getCurrentTime
    verifiedMappings <-
        query @XeroStaffMapping
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#mappingStatus, "verified" :: Text)
            |> filterWhereIn (#staffId, List.nub (map (.staffId) approvedEntries))
            |> fetch
    mappedEmployees <-
        query @XeroEmployee
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhereIn (#xeroEmployeeId, List.nub (mapMaybe (.xeroEmployeeId) verifiedMappings))
            |> fetch
    submissionRuns <-
        query @XeroSubmissionRun
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> orderByDesc #updatedAt
            |> fetch
    let approvedWorkedOnDates = List.nub (map (.workedOn) approvedEntries)
        staffCalendarAssignments = staffPayrollCalendarAssignments verifiedMappings mappedEmployees
        calendarPeriodOptions = concatMap (derivedPeriodOptions today payRuns approvedWorkedOnDates) calendars
    pure $
        calendarPeriodOptions
            |> filter (periodOptionHasRelevantApprovedEmployee approvedEntries staffCalendarAssignments)
            |> List.nubBy samePeriodOption
            |> map (attachLatestSubmissionRun submissionRuns)
            |> List.sortOn (Down . (.periodOptionStart))

derivedPeriodOptions :: Day -> [XeroPayRun] -> [Day] -> XeroPayrollCalendar -> [XeroTimesheetPeriodOption]
derivedPeriodOptions today payRuns approvedWorkedOnDates calendar =
    mapMaybe optionForWorkedOn approvedWorkedOnDates
    where
        optionForWorkedOn workedOn = do
            (currentStart, currentEnd) <- deriveXeroPayrollCalendarPeriod calendar today
            let periodLength = max 1 (diffDays currentEnd currentStart + 1)
                offset = diffDays workedOn currentStart `div` periodLength
                periodStart = addDays (offset * periodLength) currentStart
                periodEnd = addDays (periodLength - 1) periodStart
                maybePayRun = findPayRun calendar periodStart periodEnd payRuns
            guard (not (maybe False isPostedPayRun maybePayRun))
            pure (periodOptionFrom calendar periodStart periodEnd maybePayRun True)

staffPayrollCalendarAssignments :: [XeroStaffMapping] -> [XeroEmployee] -> Map.Map UUID Text
staffPayrollCalendarAssignments mappings employees =
    Map.fromList do
        mapping <- mappings
        employeeId <- maybeToList mapping.xeroEmployeeId
        employee <- maybeToList (List.find (\candidate -> candidate.xeroEmployeeId == employeeId) employees)
        calendarId <- maybeToList (xeroEmployeePayrollCalendarId employee)
        pure (mapping.staffId, calendarId)

periodOptionHasRelevantApprovedEmployee :: [TimesheetEntry] -> Map.Map UUID Text -> XeroTimesheetPeriodOption -> Bool
periodOptionHasRelevantApprovedEmployee approvedEntries staffCalendarAssignments option =
    any entryMatches (periodEntries approvedEntries)
    where
        periodEntries =
            filter \entry ->
                entry.workedOn >= option.periodOptionStart && entry.workedOn <= option.periodOptionEnd
        entryMatches entry =
            case Map.lookup entry.staffId staffCalendarAssignments of
                Nothing -> True
                Just employeeCalendarId -> employeeCalendarId == option.periodOptionPayrollCalendarId

xeroEmployeePayrollCalendarId :: XeroEmployee -> Maybe Text
xeroEmployeePayrollCalendarId employee =
    join $ AesonTypes.parseMaybe parser employee.rawPayload
    where
        parser = AesonTypes.withObject "Xero employee" \object ->
            (object AesonTypes..:? "PayrollCalendarID") <|> (object AesonTypes..:? "payrollCalendarID") <|> (object AesonTypes..:? "payrollCalendarId")

attachLatestSubmissionRun :: [XeroSubmissionRun] -> XeroTimesheetPeriodOption -> XeroTimesheetPeriodOption
attachLatestSubmissionRun submissionRuns option =
    case List.find (submissionRunMatchesPeriod option) submissionRuns of
        Nothing -> option
        Just run ->
            option
                { periodOptionLatestSubmissionStatus = Just run.status
                , periodOptionLatestSubmissionRunId = Just run.id
                }

submissionRunMatchesPeriod :: XeroTimesheetPeriodOption -> XeroSubmissionRun -> Bool
submissionRunMatchesPeriod option run =
    run.selectedPeriodKey == Just option.periodOptionKey
        || ( run.selectedPayrollCalendarId == Just option.periodOptionPayrollCalendarId
                && run.payPeriodStart == option.periodOptionStart
                && run.payPeriodEnd == option.periodOptionEnd
           )

periodOptionFrom :: XeroPayrollCalendar -> Day -> Day -> Maybe XeroPayRun -> Bool -> XeroTimesheetPeriodOption
periodOptionFrom calendar periodStart periodEnd maybePayRun derivedFromSyncedXero =
    XeroTimesheetPeriodOption
        { periodOptionKey = xeroPeriodOptionKey calendar.xeroPayrollCalendarId periodStart periodEnd
        , periodOptionPayrollCalendarId = calendar.xeroPayrollCalendarId
        , periodOptionPayrollCalendarName = calendar.name
        , periodOptionStart = periodStart
        , periodOptionEnd = periodEnd
        , periodOptionPaymentDate = (maybePayRun >>= (.paymentDate)) <|> calendar.paymentDate
        , periodOptionXeroPayRunId = (.xeroPayRunId) <$> maybePayRun
        , periodOptionXeroPayRunStatus = maybePayRun >>= (.payRunStatus)
        , periodOptionBlocked = maybe False isPostedPayRun maybePayRun
        , periodOptionBlockReason =
            if maybe False isPostedPayRun maybePayRun
                then Just "This Xero pay run is posted."
                else Nothing
        , periodOptionDerivedFromSyncedXero = derivedFromSyncedXero || isJust maybePayRun
        , periodOptionLatestSubmissionStatus = Nothing
        , periodOptionLatestSubmissionRunId = Nothing
        }

findPayRun :: XeroPayrollCalendar -> Day -> Day -> [XeroPayRun] -> Maybe XeroPayRun
findPayRun calendar periodStart periodEnd =
    List.find \payRun ->
        payRun.xeroPayrollCalendarId == calendar.xeroPayrollCalendarId
            && payRun.payPeriodStart == periodStart
            && payRun.payPeriodEnd == periodEnd

samePeriodOption :: XeroTimesheetPeriodOption -> XeroTimesheetPeriodOption -> Bool
samePeriodOption left right =
    left.periodOptionPayrollCalendarId == right.periodOptionPayrollCalendarId
        && left.periodOptionStart == right.periodOptionStart
        && left.periodOptionEnd == right.periodOptionEnd

xeroPeriodOptionKey :: Text -> Day -> Day -> Text
xeroPeriodOptionKey calendarId periodStart periodEnd =
    calendarId <> ":" <> tshow periodStart <> ":" <> tshow periodEnd

isPostedPayRun :: XeroPayRun -> Bool
isPostedPayRun payRun =
    maybe False ((== "posted") . Text.toLower . Text.strip) payRun.payRunStatus

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
                { timesheetIssueCode = issue.xeroBlockerCode
                , timesheetIssueSeverity = xeroReadinessSeverityText issue.xeroBlockerSeverity
                , timesheetIssueMessage = issue.xeroBlockerMessage
                , timesheetIssueHint = issue.xeroBlockerActionHint
                }

xeroTimesheetPreviewRowsFromJson :: [XeroEmployee] -> [XeroEarningsRate] -> Aeson.Value -> [XeroTimesheetPreviewRowView]
xeroTimesheetPreviewRowsFromJson employees earningsRates value =
    case AesonTypes.parseMaybe parsePreviewRows value of
        Nothing   -> []
        Just rows -> map (toPreviewRow employeeNames earningsRateNames) rows
    where
        employeeNames = Map.fromList (map (\employee -> (employee.xeroEmployeeId, employee.displayName)) employees)
        earningsRateNames = Map.fromList (map (\rate -> (rate.xeroEarningsRateId, rate.name)) earningsRates)

data RawPreviewRow = RawPreviewRow
    { rawPreviewEmployeeId      :: Text
    , rawPreviewOperation       :: Text
    , rawPreviewXeroTimesheetId :: Maybe Text
    , rawPreviewStart           :: Day
    , rawPreviewEnd             :: Day
    , rawPreviewSourceIds       :: [UUID]
    , rawPreviewLines           :: [RawPreviewLine]
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
            <*> object Aeson..:? "operation" AesonTypes..!= ("create" :: Text)
            <*> object Aeson..:? "existingXeroTimesheetId"
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
            , previewRowOperation = row.rawPreviewOperation
            , previewRowXeroTimesheetId = row.rawPreviewXeroTimesheetId
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
