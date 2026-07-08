module Application.Xero.Timesheets.Prepare.Helpers
    ( activePayItemRequirement
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
    , preparationPeriodKey
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
    , staffRowHasApprovedEntry
    , staffStepApprovalApplied
    , xeroConnectionSnapshotJson
    , xeroPayRunRefJson
    ) where

import Application.Helper.Xero
import Application.Helper.XeroAdminTypes
import Application.Helper.XeroTimesheetReadiness
import Application.Xero.Admin.ReadModel
import Application.Xero.Connection (xeroClientErrorText)
import Application.Xero.Timesheets.Preview (xeroReadinessSnapshotJson)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.List as List
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
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
    decision.decisionStatus == "pending" && decision.decisionKind /= "pay_item_create"

pendingPayItemCreateDecision :: XeroTimesheetPreparationDecision -> Bool
pendingPayItemCreateDecision decision =
    decision.decisionStatus == "pending" && decision.decisionKind == "pay_item_create"

isPendingStaffAutoMatch :: XeroTimesheetPreparationDecision -> Bool
isPendingStaffAutoMatch decision =
    decision.decisionStatus == "pending" && decision.decisionKind == "staff_auto_match"

staffStepApprovalApplied :: XeroTimesheetPreparationDecision -> Bool
staffStepApprovalApplied decision =
    decision.decisionStatus == "applied" && decision.decisionKind == "staff_step_approved"

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
    IO XeroTimesheetPreparationRun
refreshPreparationRunStatus run remoteTimesheets = do
    decisions <- fetchPreparationDecisions run
    readiness <- preparationReadinessForRun run remoteTimesheets
    connection <- fetch (Id run.xeroConnectionId :: Id XeroConnection)
    staffRows <- fetchCurrentVenueXeroStaffMappingRows (Just connection)
    let pendingDecisionCount = length (filter pendingManualPreparationDecision decisions)
        manualStaffCount = length (filter staffNeedsXeroDecision staffRows)
        postedBlocked = preparationRunPosted run
        hasSelectedPeriod = preparationRunHasPeriod run
        (status, errorSummary)
            | pendingDecisionCount > 0 || manualStaffCount > 0 = ("needs_approval", Nothing)
            | not hasSelectedPeriod = ("started", Nothing)
            | postedBlocked = ("blocked", Just "The selected Xero pay run is posted. Draft timesheet creation is blocked.")
            | readinessHasMissingPayItemAccountCode readiness = ("needs_approval", Nothing)
            | not (readinessAllowsAutomaticPayItemSubmit readiness) = ("blocked", Just (readinessErrorSummary readiness))
            | otherwise = ("ready_for_preview", Nothing)
    run
        |> set #status (status :: Text)
        |> set #readinessSnapshotJson (xeroReadinessSnapshotJson readiness)
        |> set #proposedActionsJson (preparationProposedActionsJson pendingDecisionCount manualStaffCount)
        |> set #errorSummary errorSummary
        |> updateRecord

markPreparationFailed :: (?modelContext :: ModelContext) => XeroTimesheetPreparationRun -> Text -> IO XeroTimesheetPreparationRun
markPreparationFailed run message =
    run
        |> set #status ("failed" :: Text)
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
                Left err -> pure (Left ("Xero pay-run check failed: " <> xeroClientErrorText err))
                Right refs ->
                    let nextAcc = acc <> refs
                     in if length refs < 100
                            then pure (Right nextAcc)
                            else fetchPage (page + 1) nextAcc

findSelectedPayRun :: XeroTimesheetPreparationRun -> [XeroPayRunRef] -> Maybe XeroPayRunRef
findSelectedPayRun run =
    List.find \payRun ->
        payRun.xeroPayRunCalendarId == fromMaybe "" run.selectedPayrollCalendarId
            && Just payRun.xeroPayRunPeriodStart == run.payPeriodStart
            && Just payRun.xeroPayRunPeriodEnd == run.payPeriodEnd

preparationRunHasPeriod :: XeroTimesheetPreparationRun -> Bool
preparationRunHasPeriod run =
    isJust run.selectedPayrollCalendarId
        && isJust run.selectedPeriodKey
        && isJust run.payPeriodStart
        && isJust run.payPeriodEnd

preparationReadinessForRun :: (?modelContext :: ModelContext) => XeroTimesheetPreparationRun -> [XeroTimesheetRef] -> IO XeroTimesheetReadiness
preparationReadinessForRun run remoteTimesheets =
    if preparationRunHasPeriod run
        then validateXeroTimesheetReadiness (preparationReadinessRequest run remoteTimesheets)
        else do
            today <- utctDay <$> getCurrentTime
            pure
                XeroTimesheetReadiness
                    { xeroTimesheetReady = False
                    , xeroReadinessPeriodStart = today
                    , xeroReadinessPeriodEnd = today
                    , xeroReadinessBlockers = []
                    , xeroReadinessWarnings = []
                    , xeroReadinessStaffCount = 0
                    , xeroReadinessEntryCount = 0
                    , xeroReadinessPayBucketCount = 0
                    }

preparationReadinessRequest :: XeroTimesheetPreparationRun -> [XeroTimesheetRef] -> XeroTimesheetReadinessRequest
preparationReadinessRequest run remoteTimesheets =
    XeroTimesheetReadinessRequest
        { readinessVenueId = Id run.venueId
        , readinessPayrollCalendarId = run.selectedPayrollCalendarId
        , readinessPayrollCalendarName = run.selectedPayrollCalendarName
        , readinessSelectedPeriodKey = run.selectedPeriodKey
        , readinessPeriodStart = fromMaybe (error "preparationReadinessRequest requires payPeriodStart") run.payPeriodStart
        , readinessPeriodEnd = fromMaybe (error "preparationReadinessRequest requires payPeriodEnd") run.payPeriodEnd
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
                            && decision.decisionStatus == "pending"
                            && decision.decisionKind `elem` ["staff_auto_match", "staff_manual_mapping", "staff_not_paid"]
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
                            && decision.decisionKind == "pay_item_create"
                            && decision.decisionStatus `elem` ["pending", "applied"]
                    )
        }

staffRowHasApprovedEntry :: [UUID] -> XeroStaffMappingRow -> Bool
staffRowHasApprovedEntry approvedStaffIds row =
    unpackId row.mappingRowStaff.id `elem` approvedStaffIds

staffNeedsXeroDecision :: XeroStaffMappingRow -> Bool
staffNeedsXeroDecision row =
    not (staffMappingResolved row.mappingRowMapping)

staffMappingResolved :: XeroStaffMapping -> Bool
staffMappingResolved mapping =
    staffMappingVerified mapping
        || (mapping.mappingStatus == "not_applicable" && isJust mapping.updatedByUserId)

staffMappingVerified :: XeroStaffMapping -> Bool
staffMappingVerified mapping =
    mapping.mappingStatus == "verified" && isJust mapping.xeroEmployeeId

activePayItemRequirement :: XeroPayItemRequirement -> Bool
activePayItemRequirement requirement =
    requirement.payItemRequirementStatus /= "ignored"

preparationRunPosted :: XeroTimesheetPreparationRun -> Bool
preparationRunPosted run =
    maybe False ((== "posted") . Text.toCaseFold . Text.strip) run.xeroPayRunStatus

preparationPeriodKey :: Text -> Day -> Day -> Text
preparationPeriodKey calendarId periodStart periodEnd =
    calendarId <> ":" <> tshow periodStart <> ":" <> tshow periodEnd

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
