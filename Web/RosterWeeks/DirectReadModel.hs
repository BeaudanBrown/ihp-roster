{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Web.RosterWeeks.DirectReadModel
    ( RosterWindowFacts (..)
    , RosterBaseFacts (..)
    , buildSlotConflictsDirect
    , buildSlotConflictsForSlotsDirect
    , RosterConflictDecodeError (..)
    , decodeRosterConflictType
    , unavailableRosterConflict
    , fetchRosterBaseFactsDirect
    , fetchRosterBaseFactsForAuthorizedScopeDirect
    , fetchRosterBaseFactsForAuthorizedWindowDirect
    , fetchPublishedRosterDayFactsForAuthorizedScopeDirect
    , fetchRosterDisplayFactsForAuthorizedWindowDirect
    , fetchRosterNotificationPanelDataDirect
    , fetchRosterStaffPanelFactsForAuthorizedScopeDirect
    , fetchRosterTemplateLibraryDirect
    , fetchRosterWageSlotsForAuthorizedWindowDirect
    , fetchRosterWindowFactsForAuthorizedScopeDirect
    , fetchRosterNotificationWindowDays
    ) where

import Application.Async.Queue (activeAppJobStatuses)
import Application.Error.Domain
import Application.Error.Runtime (ExternalRuntimeCategory (AuthorizedFrameworkInvariant),
                                  externalRuntimeInvariantFailure)
import Application.Error.Telemetry (recordAppError)
import Application.Helper.Conflict
import Application.Helper.Profiling
import Application.Helper.Staff (sortStaffForDisplay)
import Application.PayAssignment (PayAssignmentScope (..),
                                  PayReferenceRequirement (..),
                                  payAssignmentModesRequiring)
import Application.RosterNotification (RosterNotificationPanelData (..))
import Application.RosterShiftAssignment (rosterShiftIsStaffAssigned)
import Application.RosterTemplates (RosterTemplateActor,
                                    RosterTemplateLibrary (..),
                                    rosterTemplateActorCanEditRosters,
                                    rosterTemplateActorVenueId)
import Data.Coerce (coerce)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import qualified Database.PostgreSQL.Simple as PG
import GHC.Generics (Generic)
import Web.Controller.Prelude
import Web.RosterWeeks.AuthorizedScope (AuthorizedRosterScope,
                                        authorizedRosterWindowScope)
import Web.RosterWeeks.DateRange
import Web.RosterWeeks.Rows
import Web.RosterWeeks.StaffOptions (fetchAssignedRosterWeekStaff,
                                     fetchStaffPayConfigurationRequiredIds)

fetchRosterNotificationWindowDays :: (?modelContext :: ModelContext) => Id Venue -> Id RosterGroup -> Day -> Day -> IO [RosterDay]
fetchRosterNotificationWindowDays venueId rosterGroupId windowStart windowEnd =
    query @RosterDay
        |> filterWhere (#venueId, unpackId venueId)
        |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
        |> filterWhereGreaterThanOrEqualTo (#operationalDate, windowStart)
        |> filterWhereLessThan (#operationalDate, windowEnd)
        |> orderByAsc #operationalDate
        |> fetch

-- Window identity and publication facts are cheap enough for every projection.
-- Slot, Staff, Shift type, conflict, and panel supplements remain demand-driven.
data RosterWindowFacts = RosterWindowFacts
    { windowFactsState         :: !(Maybe RosterWindowState)
    , windowFactsDays          :: ![RosterDay]
    , windowFactsPersistedDays :: ![RosterDay]
    }

-- Database-near grid facts for roster read-model rendering. These reads are
-- request-local and do not use a cross-request HTML/read-model cache.
data RosterBaseFacts = RosterBaseFacts
    { baseRosterWeek                       :: !(Maybe RosterWindowState)
    , baseRosterDays                       :: ![RosterDay]
    , baseAllSlots                         :: ![RosterSlot]
    , baseVisibleSlots                     :: ![RosterSlot]
    , baseOrderedSlotDefinitions           :: ![RosterWindowLane]
    , baseShiftTypes                       :: ![ShiftType]
    , baseEligibleStaff                    :: ![Staff]
    , basePanelStaff                       :: ![Staff]
    , baseAssignedStaff                    :: ![Staff]
    , basePanelPayConfigurationRequiredIds :: !(Set.Set UUID.UUID)
    , baseStaffMembers                     :: ![Staff]
    }

fetchRosterBaseFactsDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterWindowScope -> IO (Maybe RosterBaseFacts)
fetchRosterBaseFactsDirect scope = do
    let rosterGroupId = scope.rosterWindowRosterGroupId
    venueConfig <- query @VenueConfig
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> fetchOne
    rosterGroupInVenue <- profileActionSpan "roster.direct.validate_group_scope" do
        query @RosterGroup
            |> filterWhere (#id, rosterGroupId)
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> fetchExists
    if not (rosterWindowScopeMatchesConfig venueConfig scope) || not rosterGroupInVenue
        then pure Nothing
        else do
            windowFacts <- fetchRosterWindowFactsForScopeDirect scope
            Just <$> fetchRosterBaseFactsForWindowDirect scope windowFacts

-- Only the authorization seam can construct the nominal scope accepted here.
fetchRosterBaseFactsForAuthorizedScopeDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => AuthorizedRosterScope -> IO RosterBaseFacts
fetchRosterBaseFactsForAuthorizedScopeDirect authorizedScope = do
    windowFacts <- fetchRosterWindowFactsForAuthorizedScopeDirect authorizedScope
    fetchRosterBaseFactsForAuthorizedWindowDirect authorizedScope windowFacts

fetchRosterWindowFactsForAuthorizedScopeDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => AuthorizedRosterScope -> IO RosterWindowFacts
fetchRosterWindowFactsForAuthorizedScopeDirect authorizedScope =
    fetchRosterWindowFactsForScopeDirect authorizedScope.authorizedRosterWindowScope

fetchRosterWindowFactsForScopeDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterWindowScope -> IO RosterWindowFacts
fetchRosterWindowFactsForScopeDirect scope =
    profileActionSpan "roster.direct.window_facts" do
        let rosterGroupId = scope.rosterWindowRosterGroupId
        windowFactsPersistedDays <- profileActionSpan "roster.direct.fetch_dated_window_days"
            (fetchRosterNotificationWindowDays scope.rosterWindowVenueId rosterGroupId scope.rosterWindowStart scope.rosterWindowEnd)
        let window = projectRosterWindow scope.rosterWindowStart windowFactsPersistedDays []
        let windowFactsDays =
                map
                    (projectedRosterDay scope.rosterWindowVenueId rosterGroupId)
                    window.rosterWindowProjectedDays
        let windowFactsState = Just RosterWindowState
                { windowRosterGroupId = unpackId rosterGroupId
                , windowIsPublished = rosterWindowIsPublished window
                , windowHasPublishedDays = any ((== Published) . (.publicationState)) windowFactsDays
                }
        pure RosterWindowFacts { .. }

fetchRosterBaseFactsForAuthorizedWindowDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => AuthorizedRosterScope -> RosterWindowFacts -> IO RosterBaseFacts
fetchRosterBaseFactsForAuthorizedWindowDirect authorizedScope =
    fetchRosterBaseFactsForWindowDirect authorizedScope.authorizedRosterWindowScope

fetchRosterBaseFactsForWindowDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterWindowScope -> RosterWindowFacts -> IO RosterBaseFacts
fetchRosterBaseFactsForWindowDirect scope windowFacts =
    profileActionSpan "roster.direct.base_facts" $
        profileActionSpan "roster.direct.base_facts_for_date_range" do
        let rosterGroupId = scope.rosterWindowRosterGroupId
        let windowStartDate = scope.rosterWindowStart
        let windowEndDate = scope.rosterWindowEnd
        let rosterDays = windowFacts.windowFactsDays
        orderedSlotDefinitions <- fetchRosterWindowLanesForFacts scope windowFacts
        allSlots <- profileActionSpan "roster.direct.fetch_dated_slots" $
            unsafeSqlQuery
                ("SELECT " <> fromString (cs (Text.intercalate ", " (map ("roster_slots." <>) (columnNames @RosterSlot)))) <> " \
                \FROM roster_slots \
                \JOIN roster_days ON roster_days.id = roster_slots.roster_day_id \
                \WHERE roster_days.venue_id = ? \
                \AND roster_days.roster_group_id = ? \
                \AND roster_days.operational_date >= ? \
                \AND roster_days.operational_date < ? \
                \AND roster_slots.deleted_at IS NULL \
                \ORDER BY roster_days.operational_date, roster_slots.row_index, roster_slots.slot_sort_order, roster_slots.created_at")
                (unpackId currentVenueId, unpackId rosterGroupId, windowStartDate, windowEndDate)
        let visibleSlots = filterVisibleRosterSlots rosterDays allSlots
        groupStaffMembers <- profileActionSpan "roster.direct.fetch_group_staff" (fetchRosterGroupStaffForPanelDirect rosterGroupId)
        let panelStaffMembers = sortStaffForDisplay groupStaffMembers
        panelPayConfigurationRequiredIds <- profileActionSpan "roster.direct.fetch_staff_pay_remediation" (fetchStaffPayConfigurationRequiredIds panelStaffMembers)
        let eligibleStaffMembers = filter (not . (`Set.member` panelPayConfigurationRequiredIds) . coerce . (.id)) panelStaffMembers
        assignedStaffMembers <- profileActionSpan "roster.direct.fetch_assigned_staff" (fetchAssignedRosterWeekStaff visibleSlots)
        shiftTypes <- profileActionSpan "roster.direct.fetch_shift_types" fetchCurrentVenueRosterShiftTypesDirect
        let staffMembers = uniqueStaffById (eligibleStaffMembers <> assignedStaffMembers)
        pure RosterBaseFacts
            { baseRosterWeek = windowFacts.windowFactsState
            , baseRosterDays = rosterDays
            , baseAllSlots = allSlots
            , baseVisibleSlots = visibleSlots
            , baseOrderedSlotDefinitions = orderedSlotDefinitions
            , baseShiftTypes = shiftTypes
            , baseEligibleStaff = eligibleStaffMembers
            , basePanelStaff = panelStaffMembers
            , baseAssignedStaff = assignedStaffMembers
            , basePanelPayConfigurationRequiredIds = panelPayConfigurationRequiredIds
            , baseStaffMembers = staffMembers
            }

uniqueStaffById :: [Staff] -> [Staff]
uniqueStaffById = go Set.empty
  where
    go _ [] = []
    go seen (staff : rest)
        | staff.id `Set.member` seen = go seen rest
        | otherwise = staff : go (Set.insert staff.id seen) rest

-- IHP innerJoin requires identical field types, but this schema exposes Staff.id
-- as Id Staff and StaffRosterGroup.staffId as UUID. Keep that join SQL-local;
-- return generated-order columns directly, never physical-order SELECT * or an
-- ordered-ID refetch. Membership multiplicity and PostgreSQL name ties survive.
rosterGroupStaffSelect :: PG.Query
rosterGroupStaffSelect =
    "SELECT " <> fromString (cs (Text.intercalate ", " (map ("staff." <>) (columnNames @Staff)))) <>
    " FROM staff \
    \JOIN staff_roster_groups ON staff_roster_groups.staff_id = staff.id \
    \WHERE staff_roster_groups.roster_group_id = ? \
    \AND staff_roster_groups.deleted_at IS NULL \
    \AND staff.venue_id = ? \
    \AND staff.is_active = TRUE \
    \AND staff.archived_at IS NULL"


fetchRosterGroupStaffForPanelDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> IO [Staff]
fetchRosterGroupStaffForPanelDirect rosterGroupId =
    unsafeSqlQuery
        (rosterGroupStaffSelect <> " ORDER BY staff.last_name")
        (unpackId rosterGroupId, unpackId currentVenueId)

fetchRosterDisplayFactsForAuthorizedWindowDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => AuthorizedRosterScope -> RosterWindowFacts -> IO RosterBaseFacts
fetchRosterDisplayFactsForAuthorizedWindowDirect authorizedScope windowFacts =
    profileActionSpan "roster.direct.display_facts" do
        let scope = authorizedScope.authorizedRosterWindowScope
        allSlots <- profileActionSpan "roster.direct.fetch_dated_slots" $
            unsafeSqlQuery
                ("SELECT " <> fromString (cs (Text.intercalate ", " (map ("roster_slots." <>) (columnNames @RosterSlot)))) <> " \
                \FROM roster_slots \
                \JOIN roster_days ON roster_days.id = roster_slots.roster_day_id \
                \WHERE roster_days.venue_id = ? \
                \AND roster_days.roster_group_id = ? \
                \AND roster_days.operational_date >= ? \
                \AND roster_days.operational_date < ? \
                \AND roster_slots.deleted_at IS NULL \
                \ORDER BY roster_days.operational_date, roster_slots.row_index, roster_slots.slot_sort_order, roster_slots.created_at")
                ( unpackId scope.rosterWindowVenueId
                , unpackId scope.rosterWindowRosterGroupId
                , scope.rosterWindowStart
                , scope.rosterWindowEnd
                )
        let visibleSlots = filterVisibleRosterSlots windowFacts.windowFactsDays allSlots
        orderedSlotDefinitions <- fetchRosterWindowLanesForFacts scope windowFacts
        assignedStaffMembers <- profileActionSpan "roster.direct.fetch_referenced_staff" (fetchAssignedRosterWeekStaff visibleSlots)
        shiftTypes <- profileActionSpan "roster.direct.fetch_referenced_shift_types" (fetchReferencedShiftTypes scope (mapMaybe (.shiftTypeId) visibleSlots))
        pure RosterBaseFacts
            { baseRosterWeek = windowFacts.windowFactsState
            , baseRosterDays = windowFacts.windowFactsDays
            , baseAllSlots = allSlots
            , baseVisibleSlots = visibleSlots
            , baseOrderedSlotDefinitions = orderedSlotDefinitions
            , baseShiftTypes = shiftTypes
            , baseEligibleStaff = []
            , basePanelStaff = []
            , baseAssignedStaff = assignedStaffMembers
            , basePanelPayConfigurationRequiredIds = Set.empty
            , baseStaffMembers = assignedStaffMembers
            }

fetchPublishedRosterDayFactsForAuthorizedScopeDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => AuthorizedRosterScope -> RosterWindowFacts -> UUID.UUID -> IO RosterBaseFacts
fetchPublishedRosterDayFactsForAuthorizedScopeDirect authorizedScope windowFacts rosterDayId =
    profileActionSpan "roster.direct.published_day_facts" do
        let scope = authorizedScope.authorizedRosterWindowScope
        let rosterDays = windowFacts.windowFactsDays
        targetSlots <- profileActionSpan "roster.direct.fetch_target_day_slots" $
            unsafeSqlQuery
                ("SELECT " <> fromString (cs (Text.intercalate ", " (map ("roster_slots." <>) (columnNames @RosterSlot)))) <> " \
                \FROM roster_slots \
                \JOIN roster_days ON roster_days.id = roster_slots.roster_day_id \
                \WHERE roster_days.id = ? \
                \AND roster_days.venue_id = ? \
                \AND roster_days.roster_group_id = ? \
                \AND roster_days.operational_date >= ? \
                \AND roster_days.operational_date < ? \
                \AND roster_days.is_closed = FALSE \
                \AND roster_slots.deleted_at IS NULL \
                \ORDER BY roster_slots.row_index, roster_slots.slot_sort_order, roster_slots.created_at")
                ( rosterDayId
                , unpackId scope.rosterWindowVenueId
                , unpackId scope.rosterWindowRosterGroupId
                , scope.rosterWindowStart
                , scope.rosterWindowEnd
                )
        orderedSlotDefinitions <- fetchRosterWindowLanesForFacts scope windowFacts
        assignedStaffMembers <- profileActionSpan "roster.direct.fetch_referenced_staff" (fetchAssignedRosterWeekStaff targetSlots)
        shiftTypes <- profileActionSpan "roster.direct.fetch_referenced_shift_types" (fetchReferencedShiftTypes scope (mapMaybe (.shiftTypeId) targetSlots))
        pure RosterBaseFacts
            { baseRosterWeek = windowFacts.windowFactsState
            , baseRosterDays = rosterDays
            , baseAllSlots = targetSlots
            , baseVisibleSlots = targetSlots
            , baseOrderedSlotDefinitions = orderedSlotDefinitions
            , baseShiftTypes = shiftTypes
            , baseEligibleStaff = []
            , basePanelStaff = []
            , baseAssignedStaff = assignedStaffMembers
            , basePanelPayConfigurationRequiredIds = Set.empty
            , baseStaffMembers = assignedStaffMembers
            }

fetchRosterWindowLanesForFacts :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterWindowScope -> RosterWindowFacts -> IO [RosterWindowLane]
fetchRosterWindowLanesForFacts scope windowFacts =
    profileActionSpan "roster.direct.fetch_window_lanes" do
        window <- fetchRosterWindowFromDays scope.rosterWindowVenueId scope.rosterWindowRosterGroupId scope.rosterWindowStart windowFacts.windowFactsPersistedDays
        pure window.rosterWindowLanes

fetchReferencedShiftTypes :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterWindowScope -> [UUID.UUID] -> IO [ShiftType]
fetchReferencedShiftTypes scope referencedShiftTypeIds
    | null shiftTypeIds = pure []
    | otherwise = query @ShiftType
        |> queryOr
            (filterWhereIn (#payAssignmentMode, payAssignmentModesRequiring ShiftTypePayScope NoPayReference))
            (queryOr
                (filterWhereIn (#payAssignmentMode, payAssignmentModesRequiring ShiftTypePayScope ActiveAwardReference)
                    . filterWhereSql (#overrideAwardLevelId, "IS NOT NULL AND EXISTS (SELECT 1 FROM award_levels WHERE id = shift_types.override_award_level_id AND is_active = TRUE)"))
                (filterWhereIn (#payAssignmentMode, payAssignmentModesRequiring ShiftTypePayScope AvailableXeroReference)
                    . filterWhereSql (#importedXeroPayItemId, "IS NOT NULL AND EXISTS (SELECT 1 FROM xero_imported_pay_items WHERE id = shift_types.imported_xero_pay_item_id AND venue_id = shift_types.venue_id AND archived_at IS NULL AND provider_available = TRUE)")))
        |> filterWhere (#venueId, unpackId scope.rosterWindowVenueId)
        |> filterWhereIn (#id, map Id shiftTypeIds)
        |> filterWhere (#isActive, True)
        |> filterWhere (#archivedAt, Nothing :: Maybe UTCTime)
        |> orderByAsc #sortOrder
        |> orderByAsc #createdAt
        |> fetch
  where
    shiftTypeIds = Set.toList (Set.fromList referencedShiftTypeIds)

fetchRosterTemplateLibraryDirect :: (?modelContext :: ModelContext) => RosterTemplateActor -> RosterGroup -> IO (Maybe RosterTemplateLibrary)
fetchRosterTemplateLibraryDirect actor rosterGroup
    | not (rosterTemplateActorCanEditRosters actor) = pure Nothing
    | rosterGroup.venueId /= unpackId (rosterTemplateActorVenueId actor) = pure Nothing
    | otherwise = do
        templates <- query @RosterTemplate
            |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
            |> filterWhere (#deletedAt, Nothing)
            |> filterWhere (#scale, Week)
            |> orderByAsc #name
            |> fetch
        shiftCounts :: [(UUID.UUID, Int)] <- if null templates
            then pure []
            else unsafeSqlQuery
                "SELECT roster_template_id, COUNT(*)::int \
                \FROM roster_template_shifts \
                \WHERE roster_template_id = ANY(?) \
                \GROUP BY roster_template_id"
                (Only (map (unpackId . (.id)) templates))
        pure (Just RosterTemplateLibrary
            { libraryTemplates = sortOn (Text.toCaseFold . (.name)) templates
            , libraryShiftCounts = Map.fromList [(Id rosterTemplateId, shiftCount) | (rosterTemplateId, shiftCount) <- shiftCounts]
            })

fetchRosterNotificationPanelDataDirect :: (?modelContext :: ModelContext) => AuthorizedRosterScope -> IO RosterNotificationPanelData
fetchRosterNotificationPanelDataDirect authorizedScope = do
    let scope = authorizedScope.authorizedRosterWindowScope
    summaryRows :: [(Int, Bool)] <- unsafeSqlQuery
        "SELECT \
        \    (SELECT COUNT(DISTINCT staff.id)::int \
        \     FROM staff_roster_groups \
        \     JOIN staff ON staff.id = staff_roster_groups.staff_id \
        \     JOIN users ON users.id = staff.user_id \
        \     JOIN venue_memberships ON venue_memberships.user_id = users.id AND venue_memberships.venue_id = ? \
        \     WHERE staff_roster_groups.roster_group_id = ? \
        \     AND staff_roster_groups.deleted_at IS NULL \
        \     AND staff.venue_id = ? \
        \     AND staff.is_active = TRUE \
        \     AND staff.archived_at IS NULL \
        \     AND users.deactivated_at IS NULL \
        \     AND NULLIF(REGEXP_REPLACE(users.email, '[[:space:]]', '', 'g'), '') IS NOT NULL \
        \     AND venue_memberships.is_active = TRUE \
        \     AND venue_memberships.archived_at IS NULL), \
        \    EXISTS ( \
        \        SELECT 1 FROM app_jobs \
        \        WHERE app_jobs.related_table = 'roster_notification_runs' \
        \        AND app_jobs.related_id = ( \
        \            SELECT roster_notification_runs.id \
        \            FROM roster_notification_runs \
        \            WHERE roster_notification_runs.venue_id = ? \
        \            AND roster_notification_runs.roster_group_id = ? \
        \            AND roster_notification_runs.week_start = ? \
        \            AND roster_notification_runs.window_end = ? \
        \            ORDER BY roster_notification_runs.created_at DESC \
        \            LIMIT 1 \
        \        ) \
        \        AND app_jobs.status = ANY(?::job_status[]) \
        \    )"
        ( unpackId scope.rosterWindowVenueId
        , unpackId scope.rosterWindowRosterGroupId
        , unpackId scope.rosterWindowVenueId
        , unpackId scope.rosterWindowVenueId
        , unpackId scope.rosterWindowRosterGroupId
        , scope.rosterWindowStart
        , scope.rosterWindowEnd
        , activeAppJobStatuses
        )
    let (eligibleRecipientCount, notificationInProgress) =
            case summaryRows of
                [summary] -> summary
                _ -> externalRuntimeInvariantFailure AuthorizedFrameworkInvariant "roster notification panel aggregate returned an unexpected row count"
    pure $ if notificationInProgress
        then RosterNotificationInProgress
        else if eligibleRecipientCount == 0
            then RosterNotificationNoEligibleRecipients
            else RosterNotificationReady eligibleRecipientCount

fetchRosterWageSlotsForAuthorizedWindowDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => AuthorizedRosterScope -> RosterWindowFacts -> IO [RosterSlot]
fetchRosterWageSlotsForAuthorizedWindowDirect authorizedScope windowFacts =
    profileActionSpan "roster.direct.fetch_wage_slots" do
        let scope = authorizedScope.authorizedRosterWindowScope
        allSlots <- unsafeSqlQuery
            ("SELECT " <> fromString (cs (Text.intercalate ", " (map ("roster_slots." <>) (columnNames @RosterSlot)))) <> " \
            \FROM roster_slots \
            \JOIN roster_days ON roster_days.id = roster_slots.roster_day_id \
            \WHERE roster_days.venue_id = ? \
            \AND roster_days.roster_group_id = ? \
            \AND roster_days.operational_date >= ? \
            \AND roster_days.operational_date < ? \
            \AND roster_slots.deleted_at IS NULL \
            \ORDER BY roster_days.operational_date, roster_slots.row_index, roster_slots.slot_sort_order, roster_slots.created_at")
            ( unpackId scope.rosterWindowVenueId
            , unpackId scope.rosterWindowRosterGroupId
            , scope.rosterWindowStart
            , scope.rosterWindowEnd
            )
        pure (filterVisibleRosterSlots windowFacts.windowFactsDays allSlots)

fetchRosterStaffPanelFactsForAuthorizedScopeDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => AuthorizedRosterScope -> IO ([Staff], Set.Set UUID.UUID, Map.Map UUID.UUID Int)
fetchRosterStaffPanelFactsForAuthorizedScopeDirect authorizedScope = do
    let scope = authorizedScope.authorizedRosterWindowScope
    groupStaff <- profileActionSpan "roster.direct.fetch_group_staff" (sortStaffForDisplay <$> fetchRosterGroupStaffForPanelDirect scope.rosterWindowRosterGroupId)
    payConfigurationRequiredIds <- profileActionSpan "roster.direct.fetch_staff_pay_remediation" (fetchStaffPayConfigurationRequiredIds groupStaff)
    assignedShiftCounts <- profileActionSpan "roster.direct.fetch_assigned_shift_counts" (fetchRosterAssignedShiftCountsDirect scope)
    pure (groupStaff, payConfigurationRequiredIds, assignedShiftCounts)

fetchRosterAssignedShiftCountsDirect :: (?modelContext :: ModelContext) => RosterWindowScope -> IO (Map.Map UUID.UUID Int)
fetchRosterAssignedShiftCountsDirect scope =
    Map.fromList <$> unsafeSqlQuery
        "SELECT roster_slots.staff_id, COUNT(*)::int \
        \FROM roster_slots \
        \JOIN roster_days ON roster_days.id = roster_slots.roster_day_id \
        \WHERE roster_days.venue_id = ? \
        \AND roster_days.roster_group_id = ? \
        \AND roster_days.operational_date >= ? \
        \AND roster_days.operational_date < ? \
        \AND roster_days.is_closed = FALSE \
        \AND roster_slots.deleted_at IS NULL \
        \AND roster_slots.assignment_state = 'staff' \
        \AND roster_slots.staff_id IS NOT NULL \
        \GROUP BY roster_slots.staff_id"
        ( unpackId scope.rosterWindowVenueId
        , unpackId scope.rosterWindowRosterGroupId
        , scope.rosterWindowStart
        , scope.rosterWindowEnd
        )

fetchCurrentVenueRosterShiftTypesDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [ShiftType]
fetchCurrentVenueRosterShiftTypesDirect =
    -- Keep EXISTS so PostgreSQL can hash reference inventories once. Correlated
    -- IN can rescan an inventory per row. The nullable field anchor is required
    -- by filterWhereSql; its IS NOT NULL guard is implied by the equality below.
    query @ShiftType
        |> queryOr
            (filterWhereIn (#payAssignmentMode, payAssignmentModesRequiring ShiftTypePayScope NoPayReference))
            (queryOr
                (filterWhereIn (#payAssignmentMode, payAssignmentModesRequiring ShiftTypePayScope ActiveAwardReference)
                    . filterWhereSql (#overrideAwardLevelId, "IS NOT NULL AND EXISTS (SELECT 1 FROM award_levels WHERE id = shift_types.override_award_level_id AND is_active = TRUE)"))
                (filterWhereIn (#payAssignmentMode, payAssignmentModesRequiring ShiftTypePayScope AvailableXeroReference)
                    . filterWhereSql (#importedXeroPayItemId, "IS NOT NULL AND EXISTS (SELECT 1 FROM xero_imported_pay_items WHERE id = shift_types.imported_xero_pay_item_id AND venue_id = shift_types.venue_id AND archived_at IS NULL AND provider_available = TRUE)")))
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#archivedAt, Nothing :: Maybe UTCTime)
        |> filterWhere (#isActive, True)
        |> orderByAsc #sortOrder
        |> orderByAsc #createdAt
        |> fetch

buildSlotConflictsDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Int -> [RosterSlot] -> IO [(Id RosterSlot, [RosterConflict])]
buildSlotConflictsDirect lateToEarlyMinStartGapMinutes visibleSlots =
    buildSlotConflictsForSlotsDirect lateToEarlyMinStartGapMinutes visibleSlots visibleSlots

buildSlotConflictsForSlotsDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Int -> [RosterSlot] -> [RosterSlot] -> IO [(Id RosterSlot, [RosterConflict])]
buildSlotConflictsForSlotsDirect lateToEarlyMinStartGapMinutes factSlots targetSlots
    | null assignedSlotIds || null targetSlotIds = pure []
    | otherwise = do
        rows <- (unsafeSqlQuery
            "WITH params AS ( \
            \    SELECT ?::uuid AS venue_id, ?::int AS late_gap_seconds \
            \), assigned_slots AS ( \
            \    SELECT roster_slots.id, roster_slots.roster_day_id, roster_slots.staff_id, roster_slots.starts_at, roster_slots.timezone, COALESCE((roster_slots.starts_at AT TIME ZONE roster_slots.timezone)::date, roster_days.operational_date) AS roster_date, \
            \           EXTRACT(DOW FROM COALESCE((roster_slots.starts_at AT TIME ZONE roster_slots.timezone)::date, roster_days.operational_date))::int AS weekday_index, \
            \           EXTRACT(EPOCH FROM roster_slots.starts_at) AS start_second_of_week \
            \    FROM roster_slots \
            \    JOIN roster_days ON roster_days.id = roster_slots.roster_day_id \
            \    CROSS JOIN params \
            \    WHERE roster_slots.id = ANY(?) AND roster_slots.assignment_state = 'staff' AND roster_slots.staff_id IS NOT NULL AND roster_slots.deleted_at IS NULL \
            \), week_counts AS ( \
            \    SELECT staff_id, COUNT(*)::int AS week_count FROM assigned_slots GROUP BY staff_id \
            \), day_counts AS ( \
            \    SELECT roster_day_id, staff_id, COUNT(*)::int AS day_count FROM assigned_slots GROUP BY roster_day_id, staff_id \
            \), timeline AS ( \
            \    SELECT id, start_second_of_week - LAG(start_second_of_week) OVER (PARTITION BY staff_id ORDER BY start_second_of_week, id) AS previous_gap, \
            \           LEAD(start_second_of_week) OVER (PARTITION BY staff_id ORDER BY start_second_of_week, id) - start_second_of_week AS next_gap \
            \    FROM assigned_slots WHERE starts_at IS NOT NULL \
            \), facts AS ( \
            \    SELECT assigned_slots.id, 'duplicate_assignment'::text AS conflict_type, 1 AS priority \
            \    FROM assigned_slots JOIN day_counts ON day_counts.roster_day_id = assigned_slots.roster_day_id AND day_counts.staff_id = assigned_slots.staff_id \
            \    WHERE day_counts.day_count > 1 \
            \    UNION ALL \
            \    SELECT assigned_slots.id, 'leave_conflict'::text, 2 \
            \    FROM assigned_slots CROSS JOIN params \
            \    WHERE EXISTS ( \
            \        SELECT 1 FROM leave_requests \
            \        WHERE leave_requests.venue_id = params.venue_id AND leave_requests.staff_id = assigned_slots.staff_id AND leave_requests.status = 'approved' \
            \          AND leave_requests.deleted_at IS NULL AND leave_requests.start_date <= assigned_slots.roster_date AND leave_requests.end_date > assigned_slots.roster_date \
            \    ) \
            \    UNION ALL \
            \    SELECT assigned_slots.id, 'late_to_early'::text, 3 \
            \    FROM assigned_slots JOIN timeline ON timeline.id = assigned_slots.id CROSS JOIN params \
            \    WHERE params.late_gap_seconds > 0 AND (COALESCE(timeline.previous_gap, params.late_gap_seconds) < params.late_gap_seconds OR COALESCE(timeline.next_gap, params.late_gap_seconds) < params.late_gap_seconds) \
            \    UNION ALL \
            \    SELECT assigned_slots.id, 'preference_day_unavailable'::text, 4 \
            \    FROM assigned_slots CROSS JOIN params \
            \    WHERE NOT EXISTS ( \
            \        SELECT 1 FROM staff_shift_preferences \
            \        WHERE staff_shift_preferences.venue_id = params.venue_id AND staff_shift_preferences.staff_id = assigned_slots.staff_id \
            \          AND staff_shift_preferences.weekday_index = assigned_slots.weekday_index AND staff_shift_preferences.deleted_at IS NULL \
            \    ) \
            \    UNION ALL \
            \    SELECT assigned_slots.id, 'preference_slot_mismatch'::text, 5 \
            \    FROM assigned_slots CROSS JOIN params \
            \    WHERE assigned_slots.starts_at IS NOT NULL \
            \      AND EXISTS ( \
            \        SELECT 1 FROM staff_shift_preferences \
            \        WHERE staff_shift_preferences.venue_id = params.venue_id AND staff_shift_preferences.staff_id = assigned_slots.staff_id \
            \          AND staff_shift_preferences.weekday_index = assigned_slots.weekday_index AND staff_shift_preferences.deleted_at IS NULL \
            \    ) \
            \      AND NOT EXISTS ( \
            \        SELECT 1 FROM staff_shift_preferences \
            \        WHERE staff_shift_preferences.venue_id = params.venue_id AND staff_shift_preferences.staff_id = assigned_slots.staff_id \
            \          AND staff_shift_preferences.weekday_index = assigned_slots.weekday_index AND staff_shift_preferences.deleted_at IS NULL \
            \          AND (EXTRACT(HOUR FROM (assigned_slots.starts_at AT TIME ZONE assigned_slots.timezone))::int * 60 + EXTRACT(MINUTE FROM (assigned_slots.starts_at AT TIME ZONE assigned_slots.timezone))::int) BETWEEN staff_shift_preferences.preferred_start_hour * 60 AND staff_shift_preferences.preferred_end_hour * 60 \
            \    ) \
            \    UNION ALL \
            \    SELECT assigned_slots.id, 'ideal_shift_threshold'::text, 6 \
            \    FROM assigned_slots \
            \    JOIN week_counts ON week_counts.staff_id = assigned_slots.staff_id \
            \    CROSS JOIN params \
            \    JOIN staff ON staff.id = assigned_slots.staff_id AND staff.venue_id = params.venue_id \
            \    WHERE week_counts.week_count > staff.ideal_shifts_per_week \
            \) \
            \SELECT id, conflict_type FROM facts WHERE id = ANY(?) ORDER BY id, priority"
            ( unpackId currentVenueId
            , lateToEarlyMinStartGapMinutes * 60
            , assignedSlotIds
            , targetSlotIds
            ) :: IO [(UUID.UUID, Text)])
        decodedRows <- forM rows \(slotId, conflictTypeText) ->
            case decodeRosterConflictType conflictTypeText of
                Right conflict -> pure (Id slotId, [conflict])
                Left decodeError -> do
                    recordAppError (projectDomainError decodeError)
                    pure (Id slotId, [unavailableRosterConflict])
        let conflictsBySlot = Map.fromListWith (<>) decodedRows
        pure (Map.toList (Map.map sort conflictsBySlot))
    where
        assignedSlotIds = map (coerce . (.id)) (filter rosterShiftIsStaffAssigned factSlots) :: [UUID.UUID]
        targetSlotIds = map (coerce . (.id)) targetSlots :: [UUID.UUID]

data RosterConflictDecodeError
    = UnknownRosterConflictType
    deriving (Eq, Generic, Show)

instance DomainError RosterConflictDecodeError where
    appErrorProjection UnknownRosterConflictType =
        terminalErrorProjection "Conflict details unavailable"

decodeRosterConflictType :: Text -> Either RosterConflictDecodeError RosterConflict
decodeRosterConflictType "duplicate_assignment" = Right (rosterConflict DuplicateAssignment "Multiple shifts rostered on the same day.")
decodeRosterConflictType "leave_conflict" = Right (rosterConflict LeaveConflict "Staff member has an approved unavailable period.")
decodeRosterConflictType "late_to_early" = Right (rosterConflict LateToEarlyConflict "Start-to-start gap is below venue minimum.")
decodeRosterConflictType "preference_day_unavailable" = Right (rosterConflict ShiftPreferenceDayUnavailable "Preference conflict")
decodeRosterConflictType "preference_slot_mismatch" = Right (rosterConflict ShiftPreferenceSlotMismatch "Preferred start window conflict")
decodeRosterConflictType "ideal_shift_threshold" = Right (rosterConflict IdealShiftThresholdExceeded "Ideal shifts exceeded")
decodeRosterConflictType _ = Left UnknownRosterConflictType

unavailableRosterConflict :: RosterConflict
unavailableRosterConflict = rosterConflict ConflictDetailsUnavailable "Conflict details unavailable"

rosterConflict :: ConflictType -> Text -> RosterConflict
rosterConflict conflictType message =
    RosterConflict
        { conflictType
        , severity = getConflictSeverity conflictType
        , message
        }
