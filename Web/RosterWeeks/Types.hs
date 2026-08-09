module Web.RosterWeeks.Types
    ( RosterAssignmentFilters (..)
    , RosterAssignmentOptionState (..)
    , RosterDayRenderModel (..)
    , RosterGridRenderModel (..)
    , RosterGridViewMode (..)
    , RosterProjectionFragment (..)
    , RosterRenderData (..)
    , RosterRenderIndexes (..)
    , RosterRowRenderModel (..)
    , RosterStaffPanelScope (..)
    , RosterStaffPanelRenderModel (..)
    , RosterStaffSelfServicePanel (..)
    , RosterStaffPanelEntry (..)
    , RosterViewCapabilities (..)
    , RosterWeekOverviewDay (..)
    , ShowView (..)
    , NoRosterGroupView (..)
    ) where

import Application.Helper.Conflict (RosterConflict)
import Application.Helper.FrontendContract.Passkey.Runtime (PasskeySetupPromptMode)
import Application.Helper.RosterWagePrediction (RosterWagePrediction)
import Application.RosterNotification (RosterNotificationPanelData)
import Application.RosterTemplates (RosterTemplateLibrary)
import Data.Map.Strict (Map)
import Data.Time.Calendar (Day)
import Data.Time.Clock (NominalDiffTime)
import Data.UUID (UUID)
import Generated.Types
import IHP.Prelude
import Web.RosterWeeks.DateRange (RosterWindowLane)

data NoRosterGroupView = NoRosterGroupView
    { noRosterGroupPasskeySetupPrompt :: Maybe PasskeySetupPromptMode
    , noRosterGroupPasskeyStrongAuthenticationRequired :: Bool
    }

data ShowView = ShowView
    { rosterWeek             :: Maybe RosterWeek
    , rosterDays             :: [RosterDay]
    , weekOffset             :: Int
    , rosterGroups           :: [RosterGroup]
    , currentRosterGroup     :: RosterGroup
    , weekStartDate          :: Day
    , weekEndDate            :: Day
    , rosterCalendarRevision :: Int
    , assignmentFilters      :: RosterAssignmentFilters
    , staffMembers           :: [Staff]
    , panelStaff             :: [RosterStaffPanelEntry]
    , templateLibrary        :: Maybe RosterTemplateLibrary
    , showNotificationPanelData :: Maybe RosterNotificationPanelData
    , templateLibraryUserId  :: Maybe (Id User)
    , staffSelfServicePanel  :: Maybe RosterStaffSelfServicePanel
    , slotNames              :: [RosterWindowLane]
    , allSlots               :: [RosterSlot]
    , slotConflicts          :: [(Id RosterSlot, [RosterConflict])]
    , renderIndexes          :: RosterRenderIndexes
    , viewCapabilities       :: RosterViewCapabilities
    , rosterLayoutMode       :: RosterLayoutModeEnum
    , rosterEndTimesEnabled              :: Bool
    , rosterTimePickerStartMinute        :: Int
    , rosterTimePickerFinalSelectableMinute :: Int
    , rosterWagePrediction               :: Maybe RosterWagePrediction
    , showWageEstimates      :: Bool
    , showRosterWarnings     :: Bool
    , highlightOwnLiveShifts :: Bool
    , currentViewerStaffKey  :: Maybe Text
    , publicHolidays         :: Map Day Text
    , shiftTypes             :: [ShiftType]
    , passkeySetupPrompt     :: Maybe PasskeySetupPromptMode
    , passkeyStrongAuthenticationRequired :: Bool
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
    , scheduledElapsedSeconds    :: NominalDiffTime
    , overviewIsClosed           :: Bool
    }

data RosterStaffPanelScope
    = RosterStaffPanelCurrentGroup
    | RosterStaffPanelAllVenue
    deriving (Eq, Show)

data RosterStaffPanelEntry = RosterStaffPanelEntry
    { staff                         :: Staff
    , assignedShiftCount            :: Int
    , userRole                      :: Text
    , staffPayConfigurationRequired :: Bool
    }

data RosterStaffPanelRenderModel = RosterStaffPanelRenderModel
    { staffPanelRosterWeek             :: Maybe RosterWeek
    , staffPanelWeekOffset             :: Int
    , staffPanelWeekStartDate          :: Day
    , staffPanelCalendarRevision       :: Int
    , staffPanelRosterGroups           :: [RosterGroup]
    , staffPanelCurrentRosterGroup     :: RosterGroup
    , staffPanelAssignmentFilters      :: RosterAssignmentFilters
    , staffPanelViewCapabilities       :: RosterViewCapabilities
    , staffPanelRosterLayoutMode       :: RosterLayoutModeEnum
    , staffPanelShowWageEstimates      :: Bool
    , staffPanelShowRosterWarnings     :: Bool
    , staffPanelHighlightOwnLiveShifts :: Bool
    , staffPanelViewMode               :: RosterGridViewMode
    , staffPanelScope                  :: RosterStaffPanelScope
    , staffPanelEntries                :: [RosterStaffPanelEntry]
    , staffPanelTemplateLibrary        :: Maybe RosterTemplateLibrary
    , staffPanelTemplateUserId         :: Maybe (Id User)
    , staffPanelNotificationPanelData  :: Maybe RosterNotificationPanelData
    }

data RosterStaffSelfServicePanel = RosterStaffSelfServicePanel
    { quickToolsLeaveRequest            :: LeaveRequest
    , quickToolsVenueId                 :: Id Venue
    , quickToolsRosterGroupId           :: Id RosterGroup
    , quickToolsRosterGroups            :: [RosterGroup]
    , quickToolsRosterWeekOffset        :: Int
    , quickToolsTimesheetEntries        :: [TimesheetEntry]
    , quickToolsStaffMembers            :: [Staff]
    , quickToolsShiftTypes              :: [ShiftType]
    , quickToolsOperationalDay          :: Day
    , quickToolsTimesheetWeekOffset     :: Int
    , quickToolsTimesheetWeekStartDate  :: Day
    , quickToolsCalendarRevision        :: Int
    , quickToolsTimesheetEditWindowDays :: Int
    , quickToolsHighlightOwnLiveShifts  :: Bool
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
    { rosterWeek            :: Maybe RosterWeek
    , weekOffset            :: Int
    , rosterGroups          :: [RosterGroup]
    , currentRosterGroup    :: RosterGroup
    , rosterDays            :: [RosterDay]
    , weekStartDate         :: Day
    , rosterCalendarRevision :: Int
    , assignmentFilters     :: RosterAssignmentFilters
    , staffMembers          :: [Staff]
    , panelStaff            :: [RosterStaffPanelEntry]
    , templateLibrary       :: Maybe RosterTemplateLibrary
    , templateLibraryUserId :: Maybe (Id User)
    , rosterNotificationPanelData :: Maybe RosterNotificationPanelData
    , staffSelfServicePanel :: Maybe RosterStaffSelfServicePanel
    , orderedSlotNames      :: [RosterWindowLane]
    , shiftTypes            :: [ShiftType]
    , allSlots              :: [RosterSlot]
    , slotConflicts         :: [(Id RosterSlot, [RosterConflict])]
    , renderIndexes         :: RosterRenderIndexes
    , rosterLayoutMode      :: RosterLayoutModeEnum
    , rosterEndTimesEnabled              :: Bool
    , rosterTimePickerStartMinute        :: Int
    , rosterTimePickerFinalSelectableMinute :: Int
    , rosterWagePrediction               :: Maybe RosterWagePrediction
    , showWageEstimates     :: Bool
    , showRosterWarnings    :: Bool
    , highlightOwnLiveShifts :: Bool
    , currentViewerStaffKey :: Maybe Text
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
    , gridTemplateLibrary       :: Maybe RosterTemplateLibrary
    , gridTemplateLibraryUserId :: Maybe (Id User)
    , gridNotificationPanelData :: Maybe RosterNotificationPanelData
    , gridStaffSelfServicePanel :: Maybe RosterStaffSelfServicePanel
    , gridSlotNames             :: [RosterWindowLane]
    , gridShiftTypes            :: [ShiftType]
    , gridWeekStartDate         :: Day
    , gridRosterCalendarRevision :: Int
    , gridAllSlots              :: [RosterSlot]
    , gridSlotConflicts         :: [(Id RosterSlot, [RosterConflict])]
    , gridRenderIndexes         :: RosterRenderIndexes
    , gridViewCapabilities      :: RosterViewCapabilities
    , gridRosterLayoutMode      :: RosterLayoutModeEnum
    , gridRosterEndTimesEnabled              :: Bool
    , gridRosterTimePickerStartMinute        :: Int
    , gridRosterTimePickerFinalSelectableMinute :: Int
    , gridRosterWagePrediction               :: Maybe RosterWagePrediction
    , gridShowWageEstimates     :: Bool
    , gridShowRosterWarnings    :: Bool
    , gridHighlightOwnLiveShifts :: Bool
    , gridCurrentViewerStaffKey :: Maybe Text
    , gridPublicHolidays        :: Map Day Text
    , gridPublishAttempted      :: Bool
    , gridViewMode              :: RosterGridViewMode
    , gridTimelineTodayUrl      :: Maybe Text
    }

data RosterDayRenderModel = RosterDayRenderModel
    { dayIsEditable            :: Bool
    , daySlotNames             :: [RosterWindowLane]
    , dayAssignmentFilters     :: RosterAssignmentFilters
    , dayStaffMembers          :: [Staff]
    , dayShiftTypes            :: [ShiftType]
    , dayWeekStartDate         :: Day
    , dayCalendarRevision      :: Int
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
    , rowSlotNames             :: [RosterWindowLane]
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
