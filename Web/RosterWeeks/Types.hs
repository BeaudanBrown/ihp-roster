module Web.RosterWeeks.Types
    ( RosterAssignmentFilters (..)
    , RosterAssignmentOptionState (..)
    , RosterDayRenderModel (..)
    , RosterGridRenderModel (..)
    , RosterProjectionFragment (..)
    , RosterProjectionScope (..)
    , RosterRenderData (..)
    , RosterRenderIndexes (..)
    , RosterRowRenderModel (..)
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
import Web.Types (PasskeySetupPromptMode)

data ShowView = ShowView
    { rosterWeek            :: Maybe RosterWeek
    , rosterDays            :: [RosterDay]
    , weekOffset            :: Int
    , rosterGroups          :: [RosterGroup]
    , currentRosterGroup    :: RosterGroup
    , weekStartDate         :: Day
    , weekEndDate           :: Day
    , assignmentFilters     :: RosterAssignmentFilters
    , staffMembers          :: [Staff]
    , staffOptionStates     :: Map (UUID, UUID) RosterAssignmentOptionState
    , panelStaff            :: [RosterStaffPanelEntry]
    , slotNames             :: [RosterWeekSlotDefinition]
    , allSlots              :: [RosterSlot]
    , slotConflicts         :: [(Id RosterSlot, [RosterConflict])]
    , renderIndexes         :: RosterRenderIndexes
    , liveUpdateScope       :: Maybe LiveUpdateScope
    , viewCapabilities      :: RosterViewCapabilities
    , rosterLayoutMode      :: RosterLayoutModeEnum
    , rosterEndTimesEnabled :: Bool
    , shiftTypes            :: [ShiftType]
    , passkeySetupPrompt    :: Maybe PasskeySetupPromptMode
    }

data RosterViewCapabilities = RosterViewCapabilities
    { canToggleRosterLive       :: Bool
    , canCopyRosterWeek         :: Bool
    , canExportRosterImage      :: Bool
    , canManageAssignmentFilter :: Bool
    , canManageRosterColumns    :: Bool
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
    { rosterWeek            :: RosterWeek
    , rosterDays            :: [RosterDay]
    , weekStartDate         :: Day
    , assignmentFilters     :: RosterAssignmentFilters
    , staffMembers          :: [Staff]
    , staffOptionStates     :: Map (UUID, UUID) RosterAssignmentOptionState
    , panelStaff            :: [RosterStaffPanelEntry]
    , orderedSlotNames      :: [RosterWeekSlotDefinition]
    , shiftTypes            :: [ShiftType]
    , allSlots              :: [RosterSlot]
    , slotConflicts         :: [(Id RosterSlot, [RosterConflict])]
    , renderIndexes         :: RosterRenderIndexes
    , rosterLayoutMode      :: RosterLayoutModeEnum
    , rosterEndTimesEnabled :: Bool
    }

data RosterGridRenderModel = RosterGridRenderModel
    { gridRosterWeek            :: Maybe RosterWeek
    , gridRosterDays            :: [RosterDay]
    , gridWeekOffset            :: Int
    , gridRosterGroups          :: [RosterGroup]
    , gridCurrentRosterGroup    :: RosterGroup
    , gridAssignmentFilters     :: RosterAssignmentFilters
    , gridStaffMembers          :: [Staff]
    , gridStaffOptionStates     :: Map (UUID, UUID) RosterAssignmentOptionState
    , gridPanelStaff            :: [RosterStaffPanelEntry]
    , gridSlotNames             :: [RosterWeekSlotDefinition]
    , gridShiftTypes            :: [ShiftType]
    , gridWeekStartDate         :: Day
    , gridAllSlots              :: [RosterSlot]
    , gridSlotConflicts         :: [(Id RosterSlot, [RosterConflict])]
    , gridRenderIndexes         :: RosterRenderIndexes
    , gridViewCapabilities      :: RosterViewCapabilities
    , gridRosterLayoutMode      :: RosterLayoutModeEnum
    , gridRosterEndTimesEnabled :: Bool
    }

data RosterDayRenderModel = RosterDayRenderModel
    { dayIsEditable            :: Bool
    , daySlotNames             :: [RosterWeekSlotDefinition]
    , dayAssignmentFilters     :: RosterAssignmentFilters
    , dayStaffMembers          :: [Staff]
    , dayStaffOptionStates     :: Map (UUID, UUID) RosterAssignmentOptionState
    , dayShiftTypes            :: [ShiftType]
    , dayWeekStartDate         :: Day
    , dayAllSlots              :: [RosterSlot]
    , daySlotConflicts         :: [(Id RosterSlot, [RosterConflict])]
    , dayRenderIndexes         :: RosterRenderIndexes
    , dayRosterLayoutMode      :: RosterLayoutModeEnum
    , dayRosterEndTimesEnabled :: Bool
    }

data RosterRowRenderModel = RosterRowRenderModel
    { rowIsEditable            :: Bool
    , rowSlotNames             :: [RosterWeekSlotDefinition]
    , rowAssignmentFilters     :: RosterAssignmentFilters
    , rowStaffMembers          :: [Staff]
    , rowStaffOptionStates     :: Map (UUID, UUID) RosterAssignmentOptionState
    , rowShiftTypes            :: [ShiftType]
    , rowDate                  :: Day
    , rowRosterDay             :: RosterDay
    , rowCount                 :: Int
    , rowLastRowIndex          :: Int
    , rowRenderIndexes         :: RosterRenderIndexes
    , rowRosterLayoutMode      :: RosterLayoutModeEnum
    , rowRosterEndTimesEnabled :: Bool
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
