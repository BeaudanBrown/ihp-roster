module Application.Xero.Timesheets.Prepare.Helpers
    ( SelectedPreparationPeriod (..)
    , SelectedPreparationPeriodError (..)
    , activePayItemRequirement
    , fetchPreparationDecisions
    , fetchXeroPayRunsForPreparation
    , findSelectedPayRun
    , isPendingStaffAutoMatch
    , markPreparationFailed
    , payRunsSnapshotJson
    , pendingManualPreparationDecision
    , pendingPayItemCreateDecision
    , periodOptionFromPreparationRun
    , preparationInitialEventsJson
    , preparationPayItemRow
    , preparationProposedActionsJson
    , preparationReadinessForRun
    , preparationReadinessRequest
    , preparationReadinessView
    , preparationRunHasPeriod
    , preparationRunPosted
    , preparationStaffRow
    , readinessAllowsAutomaticPayItemSubmit
    , readinessErrorSummary
    , readinessHasMissingPayItemAccountCode
    , refreshPreparationRunStatus
    , remoteTimesheetsFromRun
    , staffMappingResolved
    , staffMappingVerified
    , staffNeedsXeroDecision
    , selectedPreparationPeriod
    , staffStepApprovalApplied
    , xeroConnectionSnapshotJson
    , xeroPayRunRefJson
    ) where

import Application.Error.Types (AppResult)
import Application.Helper.Xero
import Application.Helper.XeroAdminTypes
import Application.Helper.XeroTimesheetReadiness
import Application.Xero.Admin.ReadModel
import Application.Xero.Connection (durableXeroClientErrorText)
import Application.Xero.Timesheets.Preview (xeroReadinessSnapshotJson)
import Application.Xero.WorkflowState
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.List as List
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude


fetchPreparationDecisions ::
    (?modelContext :: ModelContext) =>
    XeroTimesheetPreparationRun ->
    IO [XeroTimesheetPreparationDecision]
fetchPreparationDecisions run =
    query @XeroTimesheetPreparationDecision
        |> filterWhere (#xeroTimesheetPreparationRunId, unpackId run.id)
        |> orderBy #createdAt
        |> fetch

pendingManualPreparationDecision :: XeroTimesheetPreparationDecision -> Bool
pendingManualPreparationDecision decision =
    xeroPreparationDecisionIsPending decision.decisionStatus && not (xeroPreparationKindIsPayItemCreate decision.decisionKind)

pendingPayItemCreateDecision :: XeroTimesheetPreparationDecision -> Bool
pendingPayItemCreateDecision decision =
    xeroPreparationDecisionIsPending decision.decisionStatus && xeroPreparationKindIsPayItemCreate decision.decisionKind

isPendingStaffAutoMatch :: XeroTimesheetPreparationDecision -> Bool
isPendingStaffAutoMatch decision =
    xeroPreparationDecisionIsPending decision.decisionStatus && xeroPreparationKindIsStaffAutoMatch decision.decisionKind

staffStepApprovalApplied :: XeroTimesheetPreparationDecision -> Bool
staffStepApprovalApplied decision =
    xeroPreparationDecisionIsApplied decision.decisionStatus && xeroPreparationKindIsStaffStepApproval decision.decisionKind

readinessAllowsAutomaticPayItemSubmit :: XeroTimesheetReadiness -> Bool
readinessAllowsAutomaticPayItemSubmit readiness =
    all automaticPayItemBlocker readiness.xeroReadinessBlockers
    where
        automaticPayItemBlocker blocker =
            blocker.xeroBlockerCode == "managed_pay_item_not_ready"
                || blocker.xeroBlockerCode == "missing_pay_item_account_code"

readinessHasMissingPayItemAccountCode :: XeroTimesheetReadiness -> Bool
readinessHasMissingPayItemAccountCode readiness =
    any ((== "missing_pay_item_account_code") . (.xeroBlockerCode)) readiness.xeroReadinessBlockers

refreshPreparationRunStatus ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    XeroTimesheetPreparationRun ->
    [XeroTimesheetRef] ->
    IO (AppResult XeroTimesheetPreparationRun)
refreshPreparationRunStatus run remoteTimesheets = do
    decisions <- fetchPreparationDecisions run
    preparationReadinessForRun run remoteTimesheets >>= \case
        Left appError -> pure (Left appError)
        Right readiness -> do
            connection <- fetch (Id run.xeroConnectionId :: Id XeroConnection)
            staffRows <- fetchCurrentVenueXeroStaffMappingRows (Just connection)
            let pendingDecisionCount = length (filter pendingManualPreparationDecision decisions)
                manualStaffCount = length (filter staffNeedsXeroDecision staffRows)
                postedBlocked = preparationRunPosted run
                hasSelectedPeriod = preparationRunHasPeriod run
                (status, errorSummary)
                    | pendingDecisionCount > 0 || manualStaffCount > 0 = (NeedsApproval, Nothing)
                    | not hasSelectedPeriod = (Started, Nothing)
                    | postedBlocked = (XeroTimesheetPreparationRunStatusEnumBlocked, Just "The selected Xero pay run is posted. Draft timesheet creation is blocked.")
                    | readinessHasMissingPayItemAccountCode readiness = (NeedsApproval, Nothing)
                    | not (readinessAllowsAutomaticPayItemSubmit readiness) = (XeroTimesheetPreparationRunStatusEnumBlocked, Just (readinessErrorSummary readiness))
                    | otherwise = (ReadyForPreview, Nothing)
            Right <$> (run
                |> set #status status
                |> set #readinessSnapshotJson (xeroReadinessSnapshotJson readiness)
                |> set #proposedActionsJson (preparationProposedActionsJson pendingDecisionCount manualStaffCount)
                |> set #errorSummary errorSummary
                |> updateRecord)

markPreparationFailed :: (?modelContext :: ModelContext) => XeroTimesheetPreparationRun -> Text -> IO XeroTimesheetPreparationRun
markPreparationFailed run message =
    run
        |> set #status XeroTimesheetPreparationRunStatusEnumFailed
        |> set #errorSummary (Just message)
        |> updateRecord

fetchXeroPayRunsForPreparation :: XeroClient -> Text -> Text -> XeroTimesheetPreparationRun -> IO (Either Text [XeroPayRunRef])
fetchXeroPayRunsForPreparation xeroClient accessToken tenantId run =
    fetchPage 1 []
    where
        fetchPage page acc = do
            let query =
                    XeroPayRunQuery
                        { xeroPayRunIfModifiedSince = Nothing
                        , xeroPayRunWhere = Just ("PayrollCalendarID==Guid(\"" <> fromMaybe "" run.selectedPayrollCalendarId <> "\")")
                        , xeroPayRunOrder = Just "PayRunPeriodStartDate DESC"
                        , xeroPayRunPage = Just page
                        }
            fetchPayRuns xeroClient accessToken tenantId query >>= \case
                Left err -> pure (Left ("Xero pay-run check failed: " <> durableXeroClientErrorText err))
                Right refs ->
                    let nextAcc = acc <> refs
                        selectedFound = isJust (findSelectedPayRun run refs)
                        passedSelectedPeriod =
                            case (run.payPeriodStart, listToMaybe (reverse refs)) of
                                (Just selectedStart, Just oldestOnPage) -> oldestOnPage.xeroPayRunPeriodStart < selectedStart
                                _                                      -> False
                     in if selectedFound || passedSelectedPeriod || length refs < 100
                            then pure (Right nextAcc)
                            else fetchPage (page + 1) nextAcc

findSelectedPayRun :: XeroTimesheetPreparationRun -> [XeroPayRunRef] -> Maybe XeroPayRunRef
findSelectedPayRun run =
    List.find \payRun ->
        payRun.xeroPayRunCalendarId == fromMaybe "" run.selectedPayrollCalendarId
            && Just payRun.xeroPayRunPeriodStart == run.payPeriodStart
            && Just payRun.xeroPayRunPeriodEnd == run.payPeriodEnd

data SelectedPreparationPeriod = SelectedPreparationPeriod
    { selectedPreparationCalendarId   :: !Text
    , selectedPreparationCalendarName :: !(Maybe Text)
    , selectedPreparationPeriodKey    :: !Text
    , selectedPreparationPeriodStart  :: !Day
    , selectedPreparationPeriodEnd    :: !Day
    }
    deriving (Eq, Show)

data SelectedPreparationPeriodError
    = PreparationPeriodNotSelected
    | PreparationPeriodIncomplete
    | PreparationPeriodInvalid
    | PreparationPeriodNotAvailable
    deriving (Eq, Show)

selectedPreparationPeriod :: XeroTimesheetPreparationRun -> Either SelectedPreparationPeriodError SelectedPreparationPeriod
selectedPreparationPeriod run =
    case (run.selectedPayrollCalendarId, run.selectedPeriodKey, run.payPeriodStart, run.payPeriodEnd) of
        (Just rawCalendarId, Just rawPeriodKey, Just periodStart, Just periodEnd)
            | let calendarId = Text.strip rawCalendarId
            , let periodKey = Text.strip rawPeriodKey
            , not (Text.null calendarId)
            , periodStart <= periodEnd
            , periodKey == calendarId <> ":" <> tshow periodStart <> ":" <> tshow periodEnd ->
                Right SelectedPreparationPeriod
                    { selectedPreparationCalendarId = calendarId
                    , selectedPreparationCalendarName = Text.strip <$> run.selectedPayrollCalendarName
                    , selectedPreparationPeriodKey = periodKey
                    , selectedPreparationPeriodStart = periodStart
                    , selectedPreparationPeriodEnd = periodEnd
                    }
        (Just _, Just _, Just _, Just _) -> Left PreparationPeriodInvalid
        (Nothing, Nothing, Nothing, Nothing) -> Left PreparationPeriodNotSelected
        _ -> Left PreparationPeriodIncomplete

preparationRunHasPeriod :: XeroTimesheetPreparationRun -> Bool
preparationRunHasPeriod = either (const False) (const True) . selectedPreparationPeriod

preparationReadinessForRun :: (?modelContext :: ModelContext) => XeroTimesheetPreparationRun -> [XeroTimesheetRef] -> IO (AppResult XeroTimesheetReadiness)
preparationReadinessForRun run remoteTimesheets =
    case preparationReadinessRequest run remoteTimesheets of
        Right request -> validateXeroTimesheetReadiness request
        Left periodError -> do
            today <- utctDay <$> getCurrentTime
            pure $ Right XeroTimesheetReadiness
                { xeroTimesheetReady = False
                , xeroReadinessPeriodStart = today
                , xeroReadinessPeriodEnd = today
                , xeroReadinessBlockers = periodBlockers periodError
                , xeroReadinessWarnings = []
                , xeroReadinessStaffCount = 0
                , xeroReadinessEntryCount = 0
                , xeroReadinessPayBucketCount = 0
                }
  where
    periodBlockers PreparationPeriodNotSelected  = []
    periodBlockers PreparationPeriodIncomplete   = invalidPeriodBlocker
    periodBlockers PreparationPeriodInvalid      = invalidPeriodBlocker
    periodBlockers PreparationPeriodNotAvailable = invalidPeriodBlocker
    invalidPeriodBlocker =
        [ XeroReadinessBlockerDetail
            { xeroBlockerCode = "selected_period_incomplete"
            , xeroBlockerSeverity = XeroReadinessBlocker
            , xeroBlockerMessage = "Choose the Xero pay period again before preparing draft timesheets."
            , xeroBlockerAffectedStaffId = Nothing
            , xeroBlockerTimesheetEntryId = Nothing
            , xeroBlockerLocalBucketKey = Nothing
            , xeroBlockerXeroObjectId = Nothing
            , xeroBlockerActionHint = Just "Return to period selection and choose a synced Xero period."
            }
        ]

preparationReadinessRequest :: XeroTimesheetPreparationRun -> [XeroTimesheetRef] -> Either SelectedPreparationPeriodError XeroTimesheetReadinessRequest
preparationReadinessRequest run remoteTimesheets = do
    period <- selectedPreparationPeriod run
    pure XeroTimesheetReadinessRequest
        { readinessVenueId = Id run.venueId
        , readinessPayrollCalendarId = Just period.selectedPreparationCalendarId
        , readinessPayrollCalendarName = period.selectedPreparationCalendarName
        , readinessSelectedPeriodKey = Just period.selectedPreparationPeriodKey
        , readinessPeriodStart = period.selectedPreparationPeriodStart
        , readinessPeriodEnd = period.selectedPreparationPeriodEnd
        , readinessPaymentDate = run.paymentDate
        , readinessXeroPayRunId = run.xeroPayRunId
        , readinessXeroPayRunStatus = run.xeroPayRunStatus
        , readinessRemoteTimesheets = remoteTimesheets
        , readinessSkippedStaffIds = []
        }

preparationReadinessView :: XeroTimesheetPreparationRun -> XeroTimesheetReadiness -> XeroTimesheetReadinessView
preparationReadinessView run readiness =
    let baseView = xeroTimesheetReadinessView readiness
     in if preparationRunPosted run
            then
                baseView
                    { timesheetReadinessReady = False
                    , timesheetReadinessBlockers =
                        XeroTimesheetIssueView
                            { timesheetIssueCode = "xero_pay_run_posted"
                            , timesheetIssueSeverity = "blocker"
                            , timesheetIssueMessage = "The selected Xero pay run is posted. Draft timesheet creation is blocked."
                            , timesheetIssueHint = Nothing
                            , timesheetIssueTimesheetEntryId = Nothing
                            , timesheetIssueExpectedActiveCalculationId = Nothing
                            , timesheetIssueExpectedApprovalTimestamp = Nothing
                            }
                            : baseView.timesheetReadinessBlockers
                    }
            else baseView

preparationStaffRow :: [XeroTimesheetPreparationDecision] -> XeroStaffMappingRow -> XeroPreparationStaffRow
preparationStaffRow decisions row =
    let maybeDecision =
            decisions
                |> List.find
                    ( \decision ->
                        decision.staffId == Just (unpackId row.mappingRowStaff.id)
                            && xeroPreparationDecisionIsPending decision.decisionStatus
                            && xeroPreparationKindIsStaffMappingDecision decision.decisionKind
                    )
        needsDecision = staffNeedsXeroDecision row && isNothing maybeDecision
     in XeroPreparationStaffRow
            { preparationStaffMappingRow = row
            , preparationStaffDecision = maybeDecision
            , preparationStaffNeedsDecision = needsDecision
            }

preparationPayItemRow :: [XeroTimesheetPreparationDecision] -> XeroPayItemRequirement -> XeroPreparationPayItemRow
preparationPayItemRow decisions requirement =
    XeroPreparationPayItemRow
        { preparationPayItemRequirement = requirement
        , preparationPayItemDecision =
            decisions
                |> List.find
                    ( \decision ->
                        decision.localBucketKey == Just requirement.payItemRequirementKey
                            && xeroPreparationKindIsPayItemCreate decision.decisionKind
                            && (xeroPreparationDecisionIsPending decision.decisionStatus || xeroPreparationDecisionIsApplied decision.decisionStatus)
                    )
        }


staffNeedsXeroDecision :: XeroStaffMappingRow -> Bool
staffNeedsXeroDecision row =
    not (staffMappingResolved row.mappingRowMapping)

staffMappingResolved :: XeroStaffMapping -> Bool
staffMappingResolved mapping =
    staffMappingVerified mapping
        || xeroStaffMappingIsNotApplicable mapping.mappingStatus

staffMappingVerified :: XeroStaffMapping -> Bool
staffMappingVerified mapping =
    xeroStaffMappingIsVerified mapping.mappingStatus && isJust mapping.xeroEmployeeId

activePayItemRequirement :: XeroPayItemRequirement -> Bool
activePayItemRequirement requirement =
    not (xeroPayItemRequirementIsIgnored requirement.payItemRequirementStatus)

preparationRunPosted :: XeroTimesheetPreparationRun -> Bool
preparationRunPosted run =
    maybe False ((== "posted") . Text.toCaseFold . Text.strip) run.xeroPayRunStatus


periodOptionFromPreparationRun :: XeroTimesheetPreparationRun -> Maybe XeroTimesheetPeriodOption
periodOptionFromPreparationRun run = do
    selectedPeriodKey <- run.selectedPeriodKey
    selectedPayrollCalendarId <- run.selectedPayrollCalendarId
    periodStart <- run.payPeriodStart
    periodEnd <- run.payPeriodEnd
    pure
        XeroTimesheetPeriodOption
            { periodOptionKey = selectedPeriodKey
            , periodOptionPayrollCalendarId = selectedPayrollCalendarId
            , periodOptionPayrollCalendarName = fromMaybe selectedPayrollCalendarId run.selectedPayrollCalendarName
            , periodOptionStart = periodStart
            , periodOptionEnd = periodEnd
            , periodOptionPaymentDate = run.paymentDate
            , periodOptionXeroPayRunId = run.xeroPayRunId
            , periodOptionXeroPayRunStatus = run.xeroPayRunStatus
            , periodOptionBlocked = preparationRunPosted run
            , periodOptionBlockReason =
                if preparationRunPosted run
                    then Just "This Xero pay run is posted."
                    else Nothing
            , periodOptionDerivedFromSyncedXero = isJust run.xeroPayRunId
            , periodOptionWithinDefaultWindow = True
            , periodOptionLatestSubmissionStatus = Nothing
            , periodOptionLatestSubmissionRunId = Nothing
            }

remoteTimesheetsFromRun :: XeroTimesheetPreparationRun -> [XeroTimesheetRef]
remoteTimesheetsFromRun run =
    fromMaybe [] $
        AesonTypes.parseMaybe
            (AesonTypes.withObject "Xero duplicate snapshot" \object -> object AesonTypes..: "remoteTimesheets")
            run.remoteTimesheetsJson

xeroConnectionSnapshotJson :: XeroConnection -> Aeson.Value
xeroConnectionSnapshotJson connection =
    Aeson.object
        [ "connectionId" Aeson..= tshow connection.id
        , "tenantId" Aeson..= connection.tenantId
        , "status" Aeson..= connection.connectionStatus
        , "lastSyncAt" Aeson..= connection.lastSyncAt
        , "lastError" Aeson..= connection.lastError
        ]

payRunsSnapshotJson :: [XeroPayRunRef] -> Aeson.Value
payRunsSnapshotJson refs =
    Aeson.object
        [ "remotePayRunCount" Aeson..= length refs
        , "remotePayRuns" Aeson..= map xeroPayRunRefJson refs
        ]

xeroPayRunRefJson :: XeroPayRunRef -> Aeson.Value
xeroPayRunRefJson ref =
    Aeson.object
        [ "PayRunID" Aeson..= ref.xeroPayRunId
        , "PayrollCalendarID" Aeson..= ref.xeroPayRunCalendarId
        , "PayRunPeriodStartDate" Aeson..= ref.xeroPayRunPeriodStart
        , "PayRunPeriodEndDate" Aeson..= ref.xeroPayRunPeriodEnd
        , "PaymentDate" Aeson..= ref.xeroPayRunPaymentDate
        , "PayRunStatus" Aeson..= ref.xeroPayRunStatus
        , "Raw" Aeson..= ref.xeroPayRunRaw
        ]

preparationProposedActionsJson :: Int -> Int -> Aeson.Value
preparationProposedActionsJson pendingDecisionCount manualStaffDecisionCount =
    Aeson.object
        [ "pendingDecisionCount" Aeson..= pendingDecisionCount
        , "manualStaffDecisionCount" Aeson..= manualStaffDecisionCount
        ]

preparationInitialEventsJson :: UTCTime -> Text -> Aeson.Value
preparationInitialEventsJson occurredAt selectedPeriodKey =
    Aeson.toJSON
        [ Aeson.object
            [ "event" Aeson..= ("preparation_started" :: Text)
            , "status" Aeson..= ("preparing" :: Text)
            , "selectedPeriodKey" Aeson..= selectedPeriodKey
            , "occurredAt" Aeson..= occurredAt
            ]
        ]

readinessErrorSummary :: XeroTimesheetReadiness -> Text
readinessErrorSummary readiness =
    readiness.xeroReadinessBlockers
        |> map (.xeroBlockerMessage)
        |> List.nub
        |> Text.intercalate "\n"
