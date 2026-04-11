{-# LANGUAGE OverloadedRecordDot #-}

module Web.RosterWeeks.Types
    ( RosterAssignmentFilters (..)
    , RosterAssignmentOptionState (..)
    , RosterProjectionFragment (..)
    , RosterProjectionScope (..)
    , RosterRenderData (..)
    , RosterRenderIndexes (..)
    , RosterStaffPanelEntry (..)
    , RosterViewCapabilities (..)
    , RosterWeekOverviewDay (..)
    , ShowView (..)
    ) where

import Application.Helper.Conflict (RosterConflict)
import Application.Helper.LiveUpdate (LiveUpdateScope)
import Data.Map.Strict (Map)
import Data.Time.Calendar (Day)
import Data.UUID (UUID)
import Generated.Types
import IHP.Prelude

data ShowView = ShowView
    { rosterWeek         :: Maybe RosterWeek
    , rosterDays         :: [RosterDay]
    , weekOffset         :: Int
    , rosterGroups       :: [RosterGroup]
    , currentRosterGroup :: RosterGroup
    , weekStartDate      :: Day
    , weekEndDate        :: Day
    , assignmentFilters  :: RosterAssignmentFilters
    , staffMembers       :: [Staff]
    , staffOptionStates  :: Map (UUID, UUID) RosterAssignmentOptionState
    , panelStaff         :: [RosterStaffPanelEntry]
    , slotNames          :: [SlotName]
    , allSlots           :: [RosterSlot]
    , slotConflicts      :: [(Id RosterSlot, [RosterConflict])]
    , renderIndexes      :: RosterRenderIndexes
    , liveUpdateScope    :: Maybe LiveUpdateScope
    , viewCapabilities   :: RosterViewCapabilities
    }

data RosterViewCapabilities = RosterViewCapabilities
    { canToggleRosterLive       :: Bool
    , canCopyRosterWeek         :: Bool
    , canExportRosterImage      :: Bool
    , canManageAssignmentFilter :: Bool
    , canSyncRosterWeekSlots    :: Bool
    , canViewLeaveMetrics       :: Bool
    }

data RosterRenderIndexes = RosterRenderIndexes
    { rosterDayById              :: Map UUID RosterDay
    , rosterDayRowsByDayId       :: Map UUID [(Int, [RosterSlot])]
    , rosterSlotByDayRowSlotName :: Map (UUID, Int, UUID) RosterSlot
    , rosterStaffById            :: Map UUID Staff
    , rosterConflictsBySlotId    :: Map UUID [RosterConflict]
    }

data RosterWeekOverviewDay = RosterWeekOverviewDay
    { overviewDate               :: Day
    , leaveRequestCount          :: Int
    , overviewAssignedShiftCount :: Int
    , scheduledMinutes           :: Int
    , overviewIsClosed           :: Bool
    }

data RosterStaffPanelEntry = RosterStaffPanelEntry
    { staff              :: Staff
    , assignedShiftCount :: Int
    , userRole           :: Text
    }

data RosterAssignmentFilters = RosterAssignmentFilters
    { hideStaffAtIdealShifts        :: Bool
    , hideStaffUnavailable          :: Bool
    , hideStaffOnApprovedLeave      :: Bool
    , hideStaffAlreadyAssignedToday :: Bool
    }

data RosterAssignmentOptionState = RosterAssignmentOptionState
    { optionHidden                :: Bool
    , optionAssignedShiftCount    :: Int
    , optionHiddenByIdeal         :: Bool
    , optionHiddenByUnavailable   :: Bool
    , optionHiddenByLeave         :: Bool
    , optionHiddenByAssignedToday :: Bool
    }

data RosterRenderData = RosterRenderData
    { rosterWeek       :: RosterWeek
    , rosterDays       :: [RosterDay]
    , weekStartDate    :: Day
    , assignmentFilters :: RosterAssignmentFilters
    , staffMembers     :: [Staff]
    , staffOptionStates :: Map (UUID, UUID) RosterAssignmentOptionState
    , panelStaff       :: [RosterStaffPanelEntry]
    , orderedSlotNames :: [SlotName]
    , allSlots         :: [RosterSlot]
    , slotConflicts    :: [(Id RosterSlot, [RosterConflict])]
    , renderIndexes    :: RosterRenderIndexes
    }

data RosterProjectionScope = RosterProjectionScope
    { rosterProjectionGroupId    :: !(Id RosterGroup)
    , rosterProjectionWeekOffset :: !Int
    }
    deriving (Eq, Show)

data RosterProjectionFragment
    = RosterProjectionContent
    | RosterProjectionStaffPanel
    | RosterProjectionDaySection !UUID
    | RosterProjectionRow !UUID !Int
    deriving (Eq, Show)
