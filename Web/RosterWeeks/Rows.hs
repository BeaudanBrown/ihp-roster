module Web.RosterWeeks.Rows
    ( applyOptionalField
    , filterVisibleRosterSlots
    , impactedRowKeysForSlotUpdate
    ) where

import Data.Coerce (coerce)
import Data.List (nub)
import Data.Maybe (catMaybes)
import qualified Data.UUID as UUID
import Web.Controller.Prelude

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

applyOptionalField :: forall field model value. (SetField field model value) => Proxy field -> value -> Maybe Text -> model -> model
applyOptionalField _ parsedValue rawParam model =
    case rawParam of
        Nothing -> model
        Just _  -> setField @field parsedValue model
