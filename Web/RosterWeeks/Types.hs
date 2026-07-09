module Web.RosterWeeks.Types
    ( RosterAssignmentFilters (..)
    , RosterAssignmentOptionState (..)
    , RosterDayRenderModel (..)
    , RosterGridRenderModel (..)
    , RosterGridViewMode (..)
    , RosterProjectionFragment (..)
    , RosterProjectionScope (..)
    , RosterRenderData (..)
    , RosterRenderIndexes (..)
    , RosterRowRenderModel (..)
    , RosterStaffPanelScope (..)
    , RosterStaffSelfServicePanel (..)
    , RosterStaffPanelEntry (..)
    , RosterViewCapabilities (..)
    , RosterWeekOverviewDay (..)
    , ShowView (..)
    ) where

import Application.Helper.Conflict (RosterConflict)
import Application.Helper.LiveUpdate
import Application.Helper.RosterWagePrediction (RosterWagePrediction)
import Data.Map.Strict (Map)
import Data.Time.Calendar (Day)
import Data.UUID (UUID)
import Generated.Types
import IHP.Prelude
import Web.Types (PasskeySetupPromptMode)

data ShowView = ShowView
    { rosterWeek             :: Maybe RosterWeek
    , rosterDays             :: [RosterDay]
    , weekOffset             :: Int
    , rosterGroups           :: [RosterGroup]
    , currentRosterGroup     :: RosterGroup
    , weekStartDate          :: Day
    , weekEndDate            :: Day
    , assignmentFilters      :: RosterAssignmentFilters
    , staffMembers           :: [Staff]
    , panelStaff             :: [RosterStaffPanelEntry]
    , staffSelfServicePanel  :: Maybe RosterStaffSelfServicePanel
    , slotNames              :: [RosterWeekSlotDefinition]
    , allSlots               :: [RosterSlot]
    , slotConflicts          :: [(Id RosterSlot, [RosterConflict])]
    , renderIndexes          :: RosterRenderIndexes
    , surfaceScope           :: Maybe SurfaceScope
    , viewCapabilities       :: RosterViewCapabilities
    , rosterLayoutMode       :: RosterLayoutModeEnum
    , rosterEndTimesEnabled  :: Bool
    , rosterWagePrediction   :: Maybe RosterWagePrediction
    , showWageEstimates      :: Bool
    , showRosterWarnings     :: Bool
    , publicHolidays         :: Map Day Text
    , shiftTypes             :: [ShiftType]
    , passkeySetupPrompt     :: Maybe PasskeySetupPromptMode
    , rosterGridViewMode     :: RosterGridViewMode
    , rosterTimelineTodayUrl :: Maybe Text
    }

data RosterGridViewMode
    = RosterWeekGridView
    | RosterDayTimelineGridView { timelineDayOffset :: !Int }
    deriving (Eq, Show)

data RosterViewCapabilities = RosterViewCapabilities
    { canToggleRosterLive       :: Bool
    , canCopyRosterWeek         :: Bool
    , canExportRosterImage      :: Bool
    , canManageAssignmentFilter :: Bool
    , canManageRosterColumns    :: Bool
    , canViewLeaveMetrics       :: Bool
    , canViewWageEstimates      :: Bool
    , canManageRosterWarnings   :: Bool
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

data RosterStaffPanelScope
    = RosterStaffPanelCurrentGroup
    | RosterStaffPanelAllVenue
    deriving (Eq, Show)

data RosterStaffPanelEntry = RosterStaffPanelEntry
    { staff              :: Staff
    , assignedShiftCount :: Int
    , userRole           :: Text
    }

data RosterStaffSelfServicePanel = RosterStaffSelfServicePanel
    { quickToolsLeaveRequest            :: LeaveRequest
    , quickToolsVenueId                 :: Id Venue
    , quickToolsRosterGroupId           :: Id RosterGroup
    , quickToolsRosterWeekOffset        :: Int
    , quickToolsTimesheetEntries        :: [TimesheetEntry]
    , quickToolsStaffMembers            :: [Staff]
    , quickToolsShiftTypes              :: [ShiftType]
    , quickToolsOperationalDay          :: Day
    , quickToolsTimesheetWeekOffset     :: Int
    , quickToolsTimesheetWeekStartDate  :: Day
    , quickToolsTimesheetEditWindowDays :: Int
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
    , rosterGroups          :: [RosterGroup]
    , currentRosterGroup    :: RosterGroup
    , rosterDays            :: [RosterDay]
    , weekStartDate         :: Day
    , assignmentFilters     :: RosterAssignmentFilters
    , staffMembers          :: [Staff]
    , panelStaff            :: [RosterStaffPanelEntry]
    , staffSelfServicePanel :: Maybe RosterStaffSelfServicePanel
    , orderedSlotNames      :: [RosterWeekSlotDefinition]
    , shiftTypes            :: [ShiftType]
    , allSlots              :: [RosterSlot]
    , slotConflicts         :: [(Id RosterSlot, [RosterConflict])]
    , renderIndexes         :: RosterRenderIndexes
    , rosterLayoutMode      :: RosterLayoutModeEnum
    , rosterEndTimesEnabled :: Bool
    , rosterWagePrediction  :: Maybe RosterWagePrediction
    , showWageEstimates     :: Bool
    , showRosterWarnings    :: Bool
    , rosterPublicHolidays  :: Map Day Text
}

data RosterGridRenderModel = RosterGridRenderModel
    { gridRosterWeek            :: Maybe RosterWeek
    , gridRosterDays            :: [RosterDay]
    , gridWeekOffset            :: Int
    , gridRosterGroups          :: [RosterGroup]
    , gridCurrentRosterGroup    :: RosterGroup
    , gridAssignmentFilters     :: RosterAssignmentFilters
    , gridStaffMembers          :: [Staff]
    , gridPanelStaff            :: [RosterStaffPanelEntry]
    , gridStaffSelfServicePanel :: Maybe RosterStaffSelfServicePanel
    , gridSlotNames             :: [RosterWeekSlotDefinition]
    , gridShiftTypes            :: [ShiftType]
    , gridWeekStartDate         :: Day
    , gridAllSlots              :: [RosterSlot]
    , gridSlotConflicts         :: [(Id RosterSlot, [RosterConflict])]
    , gridRenderIndexes         :: RosterRenderIndexes
    , gridViewCapabilities      :: RosterViewCapabilities
    , gridRosterLayoutMode      :: RosterLayoutModeEnum
    , gridRosterEndTimesEnabled :: Bool
    , gridRosterWagePrediction  :: Maybe RosterWagePrediction
    , gridShowWageEstimates     :: Bool
    , gridShowRosterWarnings    :: Bool
    , gridPublicHolidays        :: Map Day Text
    , gridPublishAttempted      :: Bool
    , gridViewMode              :: RosterGridViewMode
    , gridTimelineTodayUrl      :: Maybe Text
    }

data RosterDayRenderModel = RosterDayRenderModel
    { dayIsEditable            :: Bool
    , daySlotNames             :: [RosterWeekSlotDefinition]
    , dayAssignmentFilters     :: RosterAssignmentFilters
    , dayStaffMembers          :: [Staff]
    , dayShiftTypes            :: [ShiftType]
    , dayWeekStartDate         :: Day
    , dayTimelineContext       :: Maybe (Int, Id RosterGroup)
    , dayAllSlots              :: [RosterSlot]
    , daySlotConflicts         :: [(Id RosterSlot, [RosterConflict])]
    , dayRenderIndexes         :: RosterRenderIndexes
    , dayRosterLayoutMode      :: RosterLayoutModeEnum
    , dayRosterEndTimesEnabled :: Bool
    , dayRosterWagePrediction  :: Maybe RosterWagePrediction
    , dayShowWageEstimates     :: Bool
    , dayShowRosterWarnings    :: Bool
    , dayPublicHolidays        :: Map Day Text
    , dayPublishAttempted      :: Bool
    }

data RosterRowRenderModel = RosterRowRenderModel
    { rowIsEditable            :: Bool
    , rowSlotNames             :: [RosterWeekSlotDefinition]
    , rowAssignmentFilters     :: RosterAssignmentFilters
    , rowStaffMembers          :: [Staff]
    , rowShiftTypes            :: [ShiftType]
    , rowDate                  :: Day
    , rowRosterDay             :: RosterDay
    , rowCount                 :: Int
    , rowLastRowIndex          :: Int
    , rowRenderIndexes         :: RosterRenderIndexes
    , rowRosterLayoutMode      :: RosterLayoutModeEnum
    , rowRosterEndTimesEnabled :: Bool
    , rowPublishAttempted      :: Bool
    }

data RosterProjectionScope = RosterProjectionScope
    { rosterProjectionGroupId    :: !(Id RosterGroup)
    , rosterProjectionWeekOffset :: !Int
    }
    deriving (Eq, Show)

data RosterProjectionFragment
    = RosterProjectionContent
    | RosterProjectionGridToolbar
    | RosterProjectionGridFrame
    | RosterProjectionDayColumns
    | RosterProjectionDayRail
    | RosterProjectionWageRail
    | RosterProjectionSlotsGrid
    | RosterProjectionStaffPanel
    | RosterProjectionDaySection !UUID
    | RosterProjectionRow !UUID !Int
    deriving (Eq, Show)
