module Web.LeaveRequests.Policy
    ( LeavePolicyConflicts (..)
    , PolicyDecision (..)
    , checkLeavePolicy
    , fetchLeaveAuthority
    , recordOverride
    ) where

import Application.Helper.OpaqueToken (hashOpaqueToken)
import Application.UnavailabilityBlackout.Mutations (overlappingUnavailabilityBlackouts)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.UUID as UUID
import qualified Database.PostgreSQL.Simple as PG
import Web.Controller.Prelude

data LeavePolicyConflicts = LeavePolicyConflicts
    { conflictBlackouts :: ![UnavailabilityBlackout]
    , conflictCapacity :: ![(Day, Int, Int)] -- date, projected count, maximum
    } deriving (Eq, Show)

data PolicyDecision = Admit LeavePolicyConflicts | Block LeavePolicyConflicts (Maybe Text) | InvalidConfirmation

-- Revalidate the initialized effective authority after waiting for the venue
-- lock. A concurrent membership change linearizes before or after this write.
fetchLeaveAuthority :: (?context :: ControllerContext, ?modelContext :: ModelContext) => UUID -> IO (Maybe VenueRoleEnum)
fetchLeaveAuthority venueId
    | venueId /= unpackId currentVenueId = pure Nothing
    | currentUserIsUnimpersonatedSuperAdmin = do
        rows :: [PG.Only UUID] <- unsafeSqlQuery
            "SELECT id FROM users WHERE id = ? AND platform_role = 'super_admin' FOR SHARE"
            (PG.Only (unpackId authenticatedCurrentUser.id))
        pure (VenueOwner <$ listToMaybe rows)
    | Just membership <- effectiveVenueMembershipOrNothing = do
        rows :: [PG.Only Text] <- unsafeSqlQuery
            "SELECT venue_role::text FROM venue_memberships WHERE id = ? AND venue_id = ? AND user_id = ? AND is_active AND archived_at IS NULL FOR SHARE"
            (unpackId membership.id, venueId, unpackId effectiveCurrentUser.id)
        pure (listToMaybe [role | PG.Only role <- rows] >>= parseVenueRole)
    | otherwise = pure Nothing

capacityAdditions :: Day -> Int -> LeaveRequest -> [LeaveRequest] -> [(Day, Int, Int)]
capacityAdditions today dailyMax draft counted = sweep Map.empty (Map.toAscList changes)
  where
    -- Fold request endpoints, not every day of every overlapping request.
    -- Multiplicity matters when the same person has overlapping requests.
    -- Expand only actual over-limit intervals into the response's dates.
    changes = Map.fromListWith (Map.unionWith (+))
        [ (boundary, Map.singleton existing.staffId delta)
        | existing <- counted
        , let start = maximum [today, draft.startDate, existing.startDate]
        , let end = min draft.endDate existing.endDate
        , start < end
        , (boundary, delta) <- [(start, 1 :: Int), (end, -1)]
        ]
    sweep _ [] = []
    sweep active ((start, changesOnDate) : remaining) =
        let next = Map.filter (> 0) (Map.unionWith (+) active changesOnDate)
            projected = Map.size next + 1
            blocked = case remaining of
                (end, _) : _ | Map.notMember draft.staffId next && projected > dailyMax ->
                    [(day, projected, dailyMax) | day <- [start .. addDays (-1) end]]
                _ -> []
         in blocked <> sweep next remaining

loadCapacity :: (?modelContext :: ModelContext) => Day -> Maybe Int -> LeaveRequest -> IO [(Day, Int, Int)]
loadCapacity today (Just dailyMax) draft | today < draft.endDate = do
    overlapping <- query @LeaveRequest
        |> filterWhere (#venueId, draft.venueId)
        |> filterWhere (#deletedAt, Nothing)
        |> filterWhereIn (#status, [LeaveRequestStatusEnumApproved, LeaveRequestStatusEnumPending])
        |> filterWhereLessThan (#startDate, draft.endDate)
        |> filterWhereGreaterThan (#endDate, max today draft.startDate)
        |> fetch
    let people = Set.toList (Set.fromList (map (.staffId) overlapping))
    active <- query @Staff
        |> filterWhere (#venueId, draft.venueId)
        |> filterWhereIn (#id, map Id people)
        |> filterWhere (#isActive, True)
        |> filterWhere (#archivedAt, Nothing)
        |> fetch
    let eligible = Set.fromList (map (unpackId . (.id)) active)
    pure (capacityAdditions today dailyMax draft (filter (\r -> Set.member r.staffId eligible) overlapping))
loadCapacity _ _ _ = pure []

-- Operation is Nothing on submission; review binds the existing request ID
-- plus its locked source status so a stale approval cannot silently reapply.
checkLeavePolicy :: (?modelContext :: ModelContext, ?context :: ControllerContext) =>
    Maybe Text -> Bool -> Maybe Text -> Day -> Maybe Int -> LeaveRequest -> IO PolicyDecision
checkLeavePolicy operation mayOverride token today dailyMax draft = do
    blackouts <- if isNothing operation
        then overlappingUnavailabilityBlackouts draft.venueId draft.startDate (addDays (-1) draft.endDate) |> fetch
        else pure []
    capacity <- loadCapacity today dailyMax draft
    let current = LeavePolicyConflicts blackouts capacity
    case token of
        Nothing | null blackouts && null capacity -> do
            -- An ordinary write after conflicts disappear also supersedes
            -- previews of this exact operation.
            when mayOverride clearEarlier
            pure (Admit current)
        Nothing -> prompt current
        Just raw | mayOverride, Just uuid <- UUID.fromText raw -> do
            cutoff <- addUTCTime (-1800) <$> getCurrentTime
            confirmation <- scoped |> filterWhere (#id, Id uuid) |> filterWhereGreaterThan (#createdAt, cutoff) |> fetchOneOrNothing
            case confirmation of
                Nothing -> pure InvalidConfirmation
                Just saved -> do
                    deleteRecord saved
                    if acknowledged current saved.conflicts then pure (Admit current) else prompt current
        Just _ -> pure InvalidConfirmation
  where
    binding = hashOpaqueToken (tshow (operation, draft.startDate, draft.endDate, draft.notes, (.impersonationSessionId) <$> currentImpersonationOrNothing))
    scoped = query @LeavePolicyConfirmation
        |> filterWhere (#actorUserId, unpackId authenticatedCurrentUser.id)
        |> filterWhere (#effectiveUserId, unpackId effectiveCurrentUser.id)
        |> filterWhere (#venueId, draft.venueId)
        |> filterWhere (#staffId, draft.staffId)
        |> filterWhere (#binding, binding)
    clearEarlier = do
        earlier <- scoped |> fetch
        mapM_ deleteRecord earlier
    prompt current | not mayOverride = pure (Block current Nothing)
    prompt current = do
        -- Bound stale preview storage. Issuing a fresh preview of this draft
        -- supersedes its previous token, including concurrently opened tabs.
        cutoff <- addUTCTime (-1800) <$> getCurrentTime
        expired <- query @LeavePolicyConfirmation |> filterWhere (#venueId, draft.venueId) |> filterWhereLessThanOrEqualTo (#createdAt, cutoff) |> limit 100 |> fetch
        mapM_ deleteRecord expired
        clearEarlier
        saved <- newRecord @LeavePolicyConfirmation
            |> set #actorUserId (unpackId authenticatedCurrentUser.id)
            |> set #effectiveUserId (unpackId effectiveCurrentUser.id)
            |> set #venueId draft.venueId
            |> set #staffId draft.staffId
            |> set #binding binding
            |> set #conflicts (Aeson.toJSON (conflictSnapshot current))
            |> createRecord
        pure (Block current (Just (UUID.toText (unpackId saved.id))))

type Snapshot = ([(UUID, Day, Day, Text)], [(Day, Int, Int)])

conflictSnapshot :: LeavePolicyConflicts -> Snapshot
conflictSnapshot c = (map (\b -> (unpackId b.id, b.startDate, b.endDate, b.reason)) c.conflictBlackouts, c.conflictCapacity)

acknowledged :: LeavePolicyConflicts -> Aeson.Value -> Bool
acknowledged current saved = case Aeson.fromJSON @Snapshot saved of
    Aeson.Success (oldBlackouts, oldCapacity) ->
        let oldByDay = Map.fromList [(day, (count, dailyMax)) | (day, count, dailyMax) <- oldCapacity]
            covered (day, count, dailyMax) = maybe False (\(oldCount, oldMax) -> count <= oldCount && count - dailyMax <= oldCount - oldMax) (Map.lookup day oldByDay)
         in all (\blackout -> elem blackout oldBlackouts) (fst (conflictSnapshot current)) && all covered current.conflictCapacity
    Aeson.Error _ -> False

recordOverride :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => LeaveRequest -> LeavePolicyConflicts -> IO ()
recordOverride request conflicts = unless (null conflicts.conflictBlackouts && null conflicts.conflictCapacity) $
    void $ recordCurrentUserAuditEvent LeavePolicyOverrideAudit "leave_requests" (unpackId request.id) (Aeson.object
        [ "staffId" Aeson..= request.staffId
        , "startDate" Aeson..= request.startDate
        , "endDate" Aeson..= request.endDate
        , "blackouts" Aeson..= [Aeson.object ["id" Aeson..= unpackId b.id, "startDate" Aeson..= b.startDate, "endDate" Aeson..= b.endDate, "reason" Aeson..= b.reason] | b <- conflicts.conflictBlackouts]
        , "capacity" Aeson..= [Aeson.object ["date" Aeson..= day, "projected" Aeson..= projected, "maximum" Aeson..= dailyMax] | (day, projected, dailyMax) <- conflicts.conflictCapacity]
        ])
