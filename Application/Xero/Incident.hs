module Application.Xero.Incident
    ( reconcileXeroConnectionIncident
    , reconcileXeroConnectionIncidentInCurrentTransaction
    , reconcileXeroReferenceSyncIncident
    , reconcileXeroSubmissionIncident
    , reconcileXeroSubmissionIncidentInCurrentTransaction
    ) where

import Application.OperationalIncident.Reconciliation
import Application.OperationalIncident.Types
import Application.Xero.ReferenceCategory (xeroReferenceSyncCategoryLabel)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.Set as Set
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude

-- Exact trigger map:
-- * connection: persisted reauthorization_required only;
-- * reference sync: the retry policy's terminal/exhausted branch only;
-- * submission: persisted failed/blocked after the bounded write/reconciliation path.
-- Pending/transient work is intentionally silent. Submission recovery is tied to
-- that operation becoming submitted, skipped or superseded, never connection health.
reconcileXeroConnectionIncident :: (?modelContext :: ModelContext) => UTCTime -> XeroConnection -> IO ReconciliationResult
reconcileXeroConnectionIncident now connection =
    reconcileOperationalIncident (xeroConnectionObservation now connection)

reconcileXeroConnectionIncidentInCurrentTransaction :: (?modelContext :: ModelContext) => UTCTime -> XeroConnection -> IO ReconciliationResult
reconcileXeroConnectionIncidentInCurrentTransaction now connection =
    reconcileOperationalIncidentInCurrentTransaction (xeroConnectionObservation now connection)

xeroConnectionObservation :: UTCTime -> XeroConnection -> IncidentObservation
xeroConnectionObservation now connection =
    IncidentObservation
        { category = "xero_reauthorization_required"
        , scopeKey = venueScope connection.venueId
        , stableIdentity = tshow (unpackId connection.id)
        , affectedSource = "xero"
        , venueId = Just connection.venueId
        , observedAt = now
        , isActive = connection.connectionStatus == "reauthorization_required"
        , severity = IncidentCritical
        , impactKey = "xero_connection_requires_reauthorization"
        , impactRank = 2
        , symptomCodes = ["reauthorization_required" | connection.connectionStatus == "reauthorization_required"]
        , safeMetadata = Aeson.object
            [ "connectionId" Aeson..= unpackId connection.id
            , "requiredAction" Aeson..= ("reconnect_xero" :: Text)
            ]
        }

reconcileXeroReferenceSyncIncident :: (?modelContext :: ModelContext) => UTCTime -> XeroConnection -> Set.Set XeroReferenceSyncCategoryEnum -> IO ReconciliationResult
reconcileXeroReferenceSyncIncident now connection failedCategories = withTransaction do
    existing <-
        query @OperationalIncident
            |> filterWhere (#category, "xero_reference_sync_exhausted" :: Text)
            |> filterWhere (#scopeKey, venueScope connection.venueId)
            |> filterWhere (#stableIdentity, tshow (unpackId connection.id))
            |> fetchOneOrNothing
    let priorCategories = maybe Set.empty (referenceCategoriesFromMetadata . (.safeMetadata)) existing
        affectedCategories = if Set.null failedCategories then Set.empty else priorCategories <> failedCategories
        categoryLabels = map xeroReferenceSyncCategoryLabel (Set.toAscList affectedCategories)
    reconcileOperationalIncidentInCurrentTransaction
        IncidentObservation
            { category = "xero_reference_sync_exhausted"
            , scopeKey = venueScope connection.venueId
            , stableIdentity = tshow (unpackId connection.id)
            , affectedSource = "xero"
            , venueId = Just connection.venueId
            , observedAt = now
            , isActive = not (Set.null failedCategories)
            , severity = IncidentWarning
            , impactKey = "xero_reference_sync_requires_intervention:" <> Text.intercalate "," categoryLabels
            , impactRank = length categoryLabels
            , symptomCodes = ["reference_sync_retries_exhausted" | not (Set.null failedCategories)]
            , safeMetadata = Aeson.object
                [ "connectionId" Aeson..= unpackId connection.id
                , "affectedCategories" Aeson..= categoryLabels
                , "requiredAction" Aeson..= ("inspect_xero_reference_sync" :: Text)
                ]
            }

referenceCategoriesFromMetadata :: Aeson.Value -> Set.Set XeroReferenceSyncCategoryEnum
referenceCategoriesFromMetadata =
    Set.fromList
        . mapMaybe referenceCategoryFromLabel
        . fromMaybe []
        . AesonTypes.parseMaybe (Aeson.withObject "Xero reference incident metadata" (\object -> object Aeson..:? "affectedCategories" Aeson..!= []))

referenceCategoryFromLabel :: Text -> Maybe XeroReferenceSyncCategoryEnum
referenceCategoryFromLabel = \case
    "staff" -> Just XeroStaff
    "pay_items" -> Just PayItems
    "payroll_calendars" -> Just PayrollCalendars
    "accounts" -> Just Accounts
    _ -> Nothing

reconcileXeroSubmissionIncident :: (?modelContext :: ModelContext) => UTCTime -> XeroTimesheetSubmission -> IO ReconciliationResult
reconcileXeroSubmissionIncident now submission =
    reconcileOperationalIncident (xeroSubmissionObservation now submission)

reconcileXeroSubmissionIncidentInCurrentTransaction :: (?modelContext :: ModelContext) => UTCTime -> XeroTimesheetSubmission -> IO ReconciliationResult
reconcileXeroSubmissionIncidentInCurrentTransaction now submission =
    reconcileOperationalIncidentInCurrentTransaction (xeroSubmissionObservation now submission)

xeroSubmissionObservation :: UTCTime -> XeroTimesheetSubmission -> IncidentObservation
xeroSubmissionObservation now submission =
    let active = submission.status `elem` [XeroTimesheetSubmissionStatusEnumFailed, XeroTimesheetSubmissionStatusEnumBlocked]
        symptom = case submission.status of
            XeroTimesheetSubmissionStatusEnumFailed -> ["submission_retries_exhausted"]
            XeroTimesheetSubmissionStatusEnumBlocked -> ["submission_reconciliation_blocked"]
            _ -> []
     in IncidentObservation
            { category = "xero_submission_requires_intervention"
            , scopeKey = venueScope submission.venueId
            , stableIdentity = tshow (unpackId submission.id)
            , affectedSource = "xero"
            , venueId = Just submission.venueId
            , observedAt = now
            , isActive = active
            , severity = IncidentCritical
            , impactKey = "xero_submission_operation_requires_intervention"
            , impactRank = 2
            , symptomCodes = symptom
            , safeMetadata = Aeson.object
                [ "submissionId" Aeson..= unpackId submission.id
                , "attemptCount" Aeson..= submission.attemptCount
                , "requiredAction" Aeson..= ("check_xero_then_start_fresh_preparation" :: Text)
                ]
            }

venueScope :: UUID -> Text
venueScope venueId = "venue:" <> tshow venueId
