module Application.Xero.Timesheets.LateBindings
    ( LateXeroBindingProposal (..)
    , persistLateXeroBindings
    ) where

import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (unsafeSqlQuery, unpackId)

-- | A fully resolved provider-routing decision for one immutable sealed
-- earnings component. Proposal construction is pure; persistence revalidates
-- the component under lock before recording the append-only decision.
data LateXeroBindingProposal = LateXeroBindingProposal
    { proposalComponentId        :: !(Id TimesheetPayEarningsComponent)
    , proposalLocalBucketKey     :: !Text
    , proposalXeroEarningsRateId :: !Text
    , proposalResolutionSource   :: !Text
    }
    deriving (Eq, Show)

persistLateXeroBindings ::
    (?modelContext :: ModelContext) =>
    Id XeroConnection ->
    [LateXeroBindingProposal] ->
    IO (Either Text [TimesheetPayComponentXeroBinding])
persistLateXeroBindings connectionId proposals =
    withTransaction do
        let orderedProposals = List.sortOn (unpackId . (.proposalComponentId)) proposals
            componentIds = map (unpackId . (.proposalComponentId)) orderedProposals
        lockedIds :: [Only UUID] <-
            if null componentIds
                then pure []
                else unsafeSqlQuery
                    "SELECT id FROM timesheet_pay_earnings_components WHERE id = ANY(?) ORDER BY id FOR UPDATE"
                    (Only componentIds)
        if map (\(Only value) -> value) lockedIds /= componentIds
            then pure (Left "A sealed earnings component changed while Xero routing was being prepared.")
            else do
                components <- query @TimesheetPayEarningsComponent
                    |> filterWhereIn (#id, map (.proposalComponentId) orderedProposals)
                    |> fetch
                existing <- query @TimesheetPayComponentXeroBinding
                    |> filterWhere (#xeroConnectionId, unpackId connectionId)
                    |> filterWhereIn (#timesheetPayEarningsComponentId, componentIds)
                    |> fetch
                let componentById = Map.fromList [(unpackId component.id, component) | component <- components]
                    existingByComponentId = Map.fromList [(binding.timesheetPayEarningsComponentId, binding) | binding <- existing]
                fmap sequence $ forM orderedProposals \proposal ->
                    case Map.lookup (unpackId proposal.proposalComponentId) existingByComponentId of
                        Just binding
                            | binding.localBucketKey == proposal.proposalLocalBucketKey
                                && binding.xeroEarningsRateId == proposal.proposalXeroEarningsRateId
                                && binding.resolutionSource == proposal.proposalResolutionSource -> pure (Right binding)
                            | otherwise -> pure (Left "An immutable late Xero binding already exists with different routing.")
                        Nothing ->
                            case Map.lookup (unpackId proposal.proposalComponentId) componentById of
                                Nothing -> pure (Left "A sealed earnings component was not loaded while Xero routing was being prepared.")
                                Just component
                                    | isJust component.xeroLocalBucketKey
                                        || isJust component.xeroEarningsRateId
                                        || component.xeroMappingLegacyFallback ->
                                            pure (Left "Late Xero routing is only valid for components with no approval-time routing.")
                                    | otherwise ->
                                        Right
                                            <$> ( newRecord @TimesheetPayComponentXeroBinding
                                                    |> set #timesheetPayEarningsComponentId (unpackId proposal.proposalComponentId)
                                                    |> set #xeroConnectionId (unpackId connectionId)
                                                    |> set #localBucketKey proposal.proposalLocalBucketKey
                                                    |> set #xeroEarningsRateId proposal.proposalXeroEarningsRateId
                                                    |> set #resolutionSource proposal.proposalResolutionSource
                                                    |> createRecord
                                                )
