module Web.RosterWeeks.Rows
    ( filterVisibleRosterSlots
    , rosterSlotHasVisibleData
    , impactedRowKeysForSlotUpdate
    ) where

import Data.Coerce (coerce)
import Data.List (nub)
import Data.Maybe (catMaybes)
import qualified Data.UUID as UUID
import Web.Controller.Prelude

rosterSlotHasVisibleData :: RosterSlot -> Bool
rosterSlotHasVisibleData slot =
    isJust slot.staffId
        || isJust slot.startsAt
        || isJust slot.endsAt
        || isJust slot.shiftTypeId

impactedRowKeysForSlotUpdate :: Maybe UUID.UUID -> RosterSlot -> [RosterSlot] -> [(UUID.UUID, Int)]
impactedRowKeysForSlotUpdate previousStaffId updatedSlot relatedSlots =
    nub $
        (updatedSlot.rosterDayId, updatedSlot.rowIndex)
            : map (\slot -> (slot.rosterDayId, slot.rowIndex)) affectedSlots
    where
        impactedStaffIds = catMaybes [previousStaffId, updatedSlot.staffId]
        affectedSlots = filter (\slot -> slot.staffId `elem` map Just impactedStaffIds) relatedSlots

filterVisibleRosterSlots :: [RosterDay] -> [RosterSlot] -> [RosterSlot]
filterVisibleRosterSlots rosterDays allSlots =
    let openRosterDayIds = map (coerce . (.id)) (filter (not . (.isClosed)) rosterDays)
     in filter (\slot -> slot.rosterDayId `elem` openRosterDayIds && isNothing slot.deletedAt) allSlots
