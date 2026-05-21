{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Web.RosterWeeks.DirectReadModel
    ( RosterBaseFacts (..)
    , fetchRosterBaseFactsDirect
    ) where

import Application.Helper.Profiling
import Application.Helper.RosterGroups
import Data.Coerce (coerce)
import Data.List (nubBy)
import qualified Database.PostgreSQL.Simple as PG
import IHP.ModelSupport (sqlQuery)
import Web.Controller.Prelude
import Web.RosterWeeks.Rows
import Web.RosterWeeks.Service
import Web.RosterWeeks.StaffOptions

-- Database-near base facts for the roster SQL read-model trial. These reads do
-- not touch the cross-request surface projection cache.
data RosterBaseFacts = RosterBaseFacts
    { baseRosterWeek             :: !RosterWeek
    , baseRosterDays             :: ![RosterDay]
    , baseAllSlots               :: ![RosterSlot]
    , baseVisibleSlots           :: ![RosterSlot]
    , baseOrderedSlotDefinitions :: ![RosterWeekSlotDefinition]
    , baseShiftTypes             :: ![ShiftType]
    , baseEligibleStaff          :: ![Staff]
    , baseAssignedStaff          :: ![Staff]
    , baseStaffMembers           :: ![Staff]
    }

fetchRosterBaseFactsDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> IO (Maybe RosterBaseFacts)
fetchRosterBaseFactsDirect rosterGroupId weekOffset = do
    rosterGroupInVenue <- query @RosterGroup
        |> filterWhere (#id, rosterGroupId)
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> fetchExists
    if not rosterGroupInVenue
        then pure Nothing
        else do
            _ <- profileActionSpan "roster.direct.ensure_week_exists" (ensureRosterWeekExists rosterGroupId weekOffset)
            rosterWeekOrNothing <- query @RosterWeek
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
                |> filterWhere (#weekOffset, weekOffset)
                |> fetchOneOrNothing
            buildRosterBaseFacts rosterGroupId rosterWeekOrNothing

buildRosterBaseFacts :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Maybe RosterWeek -> IO (Maybe RosterBaseFacts)
buildRosterBaseFacts rosterGroupId rosterWeekOrNothing =
    case rosterWeekOrNothing of
        Nothing -> pure Nothing
        Just rosterWeek -> do
            rosterDays <- profileActionSpan "roster.direct.fetch_days" do
                query @RosterDay
                    |> filterWhere (#rosterWeekId, coerce (get #id rosterWeek))
                    |> orderBy #dayOffset
                    |> fetch

            allSlots <- profileActionSpan "roster.direct.fetch_slots" do
                sqlQuery
                    "SELECT roster_slots.* \
                    \FROM roster_slots \
                    \JOIN roster_days ON roster_days.id = roster_slots.roster_day_id \
                    \WHERE roster_days.roster_week_id = ? \
                    \AND roster_slots.deleted_at IS NULL \
                    \ORDER BY roster_days.day_offset, roster_slots.row_index, roster_slots.slot_sort_order, roster_slots.created_at"
                    (PG.Only (unpackId rosterWeek.id))

            orderedSlotDefinitions <- profileActionSpan "roster.direct.fetch_slot_definitions" do
                query @RosterWeekSlotDefinition
                    |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
                    |> filterWhere (#deletedAt, Nothing)
                    |> orderByAsc #sortOrder
                    |> orderByAsc #createdAt
                    |> fetch

            let visibleSlots = filterVisibleRosterSlots rosterDays allSlots
            eligibleStaffMembers <- profileActionSpan "roster.direct.fetch_eligible_staff" (fetchEligibleRosterGroupStaff rosterGroupId)
            assignedStaffMembers <- profileActionSpan "roster.direct.fetch_assigned_staff" (fetchAssignedRosterWeekStaff visibleSlots)
            shiftTypes <- profileActionSpan "roster.direct.fetch_shift_types" fetchCurrentVenueRosterShiftTypesDirect
            let staffMembers = nubBy (\left right -> left.id == right.id) (eligibleStaffMembers <> assignedStaffMembers)
            pure $ Just RosterBaseFacts
                { baseRosterWeek = rosterWeek
                , baseRosterDays = rosterDays
                , baseAllSlots = allSlots
                , baseVisibleSlots = visibleSlots
                , baseOrderedSlotDefinitions = orderedSlotDefinitions
                , baseShiftTypes = shiftTypes
                , baseEligibleStaff = eligibleStaffMembers
                , baseAssignedStaff = assignedStaffMembers
                , baseStaffMembers = staffMembers
                }

fetchCurrentVenueRosterShiftTypesDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [ShiftType]
fetchCurrentVenueRosterShiftTypesDirect =
    query @ShiftType
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#archivedAt, Nothing)
        |> orderByAsc #sortOrder
        |> orderByAsc #createdAt
        |> fetch
