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
    , RosterWindowState (..)
    , ShowView (..)
    , NoRosterGroupView (..)
    ) where

import Application.Helper.Conflict (RosterConflict)
import Application.Helper.FrontendContract.Passkey.Runtime (PasskeySetupPromptMode)
import Application.Helper.RosterWagePrediction (RosterWagePrediction)
import Application.RosterNotification (RosterNotificationPanelData)
import Application.RosterTemplates (RosterTemplateLibrary)
import Application.VenueTime.Model (RosterShiftIntegrityError,
                                    TimesheetIntegrityError,
                                    ValidatedRosterShiftTiming,
                                    ValidatedTimesheetTiming)
import Generated.Types
import IHP.Prelude
import Web.RosterWeeks.DateRange (RosterWindowLane, RosterWindowScope,
                                  RosterWindowState (..))

data NoRosterGroupView = NoRosterGroupView
    { noRosterGroupPasskeySetupPrompt :: Maybe PasskeySetupPromptMode
    , noRosterGroupPasskeyStrongAuthenticationRequired :: Bool
    }

data ShowView = ShowView
    { rosterPageGridModel                 :: RosterGridRenderModel
    , passkeySetupPrompt                  :: Maybe PasskeySetupPromptMode
    , passkeyStrongAuthenticationRequired :: Bool
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
    , rosterTimingBySlotId       :: Map UUID (Either RosterShiftIntegrityError ValidatedRosterShiftTiming)
    }

data RosterWeekOverviewDay = RosterWeekOverviewDay
    { overviewDate               :: Day
    , leaveRequestCount          :: Int
    , overviewAssignedShiftCount :: Int
    , scheduledElapsedSeconds    :: NominalDiffTime
    , overviewInvalidTimingCount :: Int
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
    { staffPanelRosterWeek             :: Maybe RosterWindowState
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
    , staffPanelNotificationPanelData  :: Maybe RosterNotificationPanelData
    }

data RosterStaffSelfServicePanel = RosterStaffSelfServicePanel
    { quickToolsLeaveRequest            :: LeaveRequest
    , quickToolsVenueId                 :: Id Venue
    , quickToolsRosterGroupId           :: Id RosterGroup
    , quickToolsRosterGroups            :: [RosterGroup]
    , quickToolsRosterWeekStartDate     :: Day
    , quickToolsTimesheetEntries        :: [TimesheetEntry]
    , quickToolsTimesheetTimingByEntryId :: Map UUID (Either TimesheetIntegrityError ValidatedTimesheetTiming)
    , quickToolsStaffMembers            :: [Staff]
    , quickToolsShiftTypes              :: [ShiftType]
    , quickToolsOperationalDay          :: Day
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
    { rosterWeek            :: Maybe RosterWindowState
    , rosterWindowScope     :: RosterWindowScope
    , rosterGroups          :: [RosterGroup]
    , currentRosterGroup    :: RosterGroup
    , rosterDays            :: [RosterDay]
    , weekStartDate         :: Day
    , rosterCalendarRevision :: Int
    , assignmentFilters     :: RosterAssignmentFilters
    , staffMembers          :: [Staff]
    , panelStaff            :: [RosterStaffPanelEntry]
    , templateLibrary       :: Maybe RosterTemplateLibrary
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
    { gridRosterWeek            :: Maybe RosterWindowState
    , gridRosterDays            :: [RosterDay]
    , gridWindowScope           :: RosterWindowScope
    , gridRosterGroups          :: [RosterGroup]
    , gridCurrentRosterGroup    :: RosterGroup
    , gridAssignmentFilters     :: RosterAssignmentFilters
    , gridStaffMembers          :: [Staff]
    , gridPanelStaff            :: [RosterStaffPanelEntry]
    , gridTemplateLibrary       :: Maybe RosterTemplateLibrary
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
    , rowDayIndex              :: Int
    , rowRosterDay             :: RosterDay
    , rowCalendarRevision      :: Int
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
