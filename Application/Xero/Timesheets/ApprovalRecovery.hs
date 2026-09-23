module Application.Xero.Timesheets.ApprovalRecovery (recoverPreparationApprovals) where

import Application.Error.Domain (projectDomainError)
import Application.Error.Transaction (withAppResultTransaction)
import Application.Helper.Audit (currentRequestAuditPayload)
import Application.Helper.ControllerContext (authenticatedCurrentUser, currentVenueId)
import Application.Helper.Htmx (requestAuditSourceChannel)
import Application.Helper.TimesheetSelection
import Application.Helper.XeroTimesheetReadiness
import Application.TimesheetApproval
import Application.Xero.Timesheets.Prepare.Helpers (preparationReadinessForRun, preparationReadinessRequest)
import Application.Xero.Timesheets.Selection (fetchPreparationSelectionCandidates)
import qualified Control.Exception as Exception
import Control.Monad (foldM, guard)
import qualified Data.Aeson as Aeson
import qualified Data.List as List
import qualified Hasql.Errors as Hasql
import Generated.Types
import IHP.ControllerPrelude

-- Explicit preparation commands only. Passive view loads must not recalculate
-- approvals. Each repair and its replacement selection identity commit together;
-- an incomplete replacement leaves both the sealed ledger and selection intact.
recoverPreparationApprovals ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroTimesheetPreparationRun -> IO XeroTimesheetPreparationRun
recoverPreparationApprovals run
    | run.venueId /= unpackId currentVenueId || isNothing run.selectedEntriesJson || isJust run.completedAt || isJust run.xeroSubmissionRunId = pure run
    | otherwise = preparationReadinessForRun run [] >>= \case
        Left _ -> pure run
        Right readiness -> do
            let entryIds = List.sort $ List.nub $ mapMaybe (.xeroBlockerTimesheetEntryId) $
                    filter (\issue -> issue.xeroBlockerCode `elem` ["wage_publication_failed", "wage_source_policy", "earnings_mapping_not_verified", "managed_pay_item_not_ready"]) readiness.xeroReadinessBlockers
            foldM recoverEntry run entryIds
  where
    recoverEntry expectedRun entryId = do
        attempt <- Exception.tryJust (guard . lockTimedOut) $ withAppResultTransaction do
            unsafeSqlExecDiscardResult "SET LOCAL lock_timeout = '5s'" ()
            (_ :: [Only UUID]) <- unsafeSqlQuery
                "SELECT id FROM xero_timesheet_preparation_runs WHERE id = ? AND venue_id = ? FOR UPDATE"
                (unpackId expectedRun.id, unpackId currentVenueId)
            latest <- fetch expectedRun.id
            if latest.updatedAt /= expectedRun.updatedAt || isJust latest.completedAt || isJust latest.xeroSubmissionRunId
                then pure (Left (projectDomainError ApprovalControlStale))
                else case preparationReadinessRequest latest [] of
                    Left _ -> pure (Left (projectDomainError ApprovalControlStale))
                    Right request -> do
                        candidates <- fetchPreparationSelectionCandidates latest
                        case validateTimesheetSelection latest.venueId request.readinessPeriodStart request.readinessPeriodEnd request.readinessSelection candidates of
                            Left _ -> pure (Left (projectDomainError ApprovalControlStale))
                            Right selected -> case List.find ((== entryId) . unpackId . (.id)) selected of
                                Nothing -> pure (Left (projectDomainError ApprovalEntryUnavailable))
                                Just entry -> case (entry.activePayCalculationId, entry.approvedAt) of
                                    (Just calculationId, Just approvedAt) -> do
                                        let expected = ExpectedApprovalIdentity (unpackId calculationId) approvedAt
                                        runApprovalEngineInCurrentTransaction authenticatedCurrentUser.id (RefreshProblemApproval expected) currentRequestAuditPayload requestAuditSourceChannel entry >>= \case
                                            Left failure -> pure (Left (projectDomainError failure))
                                            Right result -> do
                                                let identities = map (timesheetSelectionIdentity . (\candidate -> if candidate.id == entry.id then result.approvalEngineEntry else candidate)) selected
                                                Right <$> (latest
                                                    |> set #selectedEntriesJson (Just (Aeson.toJSON identities))
                                                    |> set #previewPayloadJson (Aeson.object [])
                                                    |> set #readinessSnapshotJson (Aeson.object [])
                                                    |> updateRecord)
                                    _ -> pure (Left (projectDomainError ApprovalEntryUnavailable))
        case attempt of
            Right (Right repaired) -> pure repaired
            Right (Left _) -> fetch expectedRun.id -- The original blocker remains visible.
            Left () -> fetch expectedRun.id -- Only a lock timeout is recoverable.

lockTimedOut :: HasqlSessionError -> Bool
lockTimedOut (HasqlSessionError sessionError) = case sessionError of
    Hasql.StatementSessionError _ _ _ _ _ (Hasql.ServerStatementError (Hasql.ServerError code _ _ _ _)) -> code == "55P03"
    Hasql.ScriptSessionError _ (Hasql.ServerError code _ _ _ _) -> code == "55P03"
    _ -> False
