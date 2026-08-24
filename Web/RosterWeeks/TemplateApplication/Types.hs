module Web.RosterWeeks.TemplateApplication.Types where

import Application.Helper.FrontendContract.Surface.Resource (SurfaceResourceValue)
import Application.RosterShiftAssignment (RosterShiftAssignment)
import Application.RosterTemplates (RosterTemplateContent,
                                    RosterTemplateSnapshot)
import Application.VenueTime.Model (BoundaryModelError)
import qualified Data.Map.Strict as Map
import Generated.Types
import IHP.ControllerPrelude

data RosterTemplateApplicationRequest = RosterTemplateApplicationRequest
    { applicationTemplateId          :: !(Id RosterTemplate)
    , applicationTargetRosterGroupId :: !(Id RosterGroup)
    , applicationTargetWindowStart   :: !Day
    , applicationTargetWindowEnd     :: !Day
    , applicationShiftTypeMappings   :: !(Map.Map (Id ShiftType) (Id ShiftType))
    }
    deriving (Eq, Show)

data RosterTemplateApplicationAssignmentIssue
    = RosterTemplateStaffUnavailable
    | RosterTemplateStaffOutsideGroup
    | RosterTemplateStaffPayInvalid
    | RosterTemplateStaffOnApprovedLeave
    deriving (Eq, Ord, Show)

data RosterTemplateApplicationWarning
    = RosterTemplateApplicationClearsDay !Int
    | RosterTemplateApplicationClearsWeek
    | RosterTemplateApplicationExistingTimesheetsRemain !Int
    | RosterTemplateApplicationAssignmentConvertedToOpen !(Id Staff) !Text !RosterTemplateApplicationAssignmentIssue !Int
    deriving (Eq, Show)

data RosterTemplateApplicationShiftTypeRequirement = RosterTemplateApplicationShiftTypeRequirement
    { applicationStaleShiftTypeId   :: !(Id ShiftType)
    , applicationStaleShiftTypeName :: !Text
    , applicationMappedShiftTypeId  :: !(Maybe (Id ShiftType))
    }
    deriving (Eq, Show)

data RosterTemplateApplicationResolvedShift = RosterTemplateApplicationResolvedShift
    { resolvedTemplateShiftId :: !(Id RosterTemplateShift)
    , resolvedTargetDayOffset :: !Int
    , resolvedStartsAt        :: !UTCTime
    , resolvedEndsAt          :: !UTCTime
    , resolvedAssignment      :: !RosterShiftAssignment
    }
    deriving (Eq, Show)

data RosterTemplateApplicationPreview = RosterTemplateApplicationPreview
    { applicationPreviewTemplateName     :: !Text
    , applicationPreviewScale            :: !RosterTemplateScaleEnum
    , applicationPreviewTargetWindowStart :: !Day
    , applicationPreviewTargetWindowEnd   :: !Day
    , applicationPreviewTargetOperationalDate :: !(Maybe Day)
    , applicationExpectedTargetRevision  :: !Text
    , applicationExpectedTemplateRevision :: !Text
    , applicationRosterCalendarRevision  :: !Int
    , applicationReplacementShiftCount   :: !Int
    , applicationExistingShiftCount      :: !Int
    , applicationResolvedShifts          :: ![RosterTemplateApplicationResolvedShift]
    , applicationShiftTypeRequirements   :: ![RosterTemplateApplicationShiftTypeRequirement]
    , applicationAvailableShiftTypes     :: ![ShiftType]
    , applicationWarnings                :: ![RosterTemplateApplicationWarning]
    , applicationTouchedResources        :: ![SurfaceResourceValue]
    }
    deriving (Eq, Show)

data RosterTemplateApplicationResult = RosterTemplateApplicationResult
    { appliedTargetWindowStart :: !Day
    , appliedTargetWindowEnd   :: !Day
    , appliedTemplateChanged   :: !Bool
    , appliedWarnings          :: ![RosterTemplateApplicationWarning]
    , appliedTouchedResources  :: ![SurfaceResourceValue]
    }
    deriving (Eq, Show)

data RosterTemplateApplicationBoundary
    = RosterTemplateApplicationStartBoundary
    | RosterTemplateApplicationEndBoundary
    deriving (Eq, Show)

data RosterTemplateApplicationError
    = RosterTemplateApplicationForbidden
    | RosterTemplateApplicationNotFound
    | RosterTemplateApplicationScopeMismatch
    | RosterTemplateApplicationTargetLive
    | RosterTemplateApplicationInvalidTargetDay
    | RosterTemplateApplicationScaleMismatch
    | RosterTemplateApplicationTargetConflict
    | RosterTemplateApplicationCalendarConflict
    | RosterTemplateApplicationShiftTypeMappingsRequired ![Id ShiftType]
    | RosterTemplateApplicationInvalidShiftTypeMappings
    | RosterTemplateApplicationBoundaryError !(Id RosterTemplateShift) !RosterTemplateApplicationBoundary !BoundaryModelError
    | RosterTemplateApplicationInvalidStructure !Text
    deriving (Eq, Show)

data PreparedApplication = PreparedApplication
    { preparedSaved             :: !RosterTemplateSnapshot
    , preparedTargetGroup       :: !RosterGroup
    , preparedTargetWindowStart :: !Day
    , preparedTargetWindowEnd   :: !Day
    , preparedTargetDays        :: ![RosterDay]
    , preparedFirstTargetDay    :: !RosterDay
    , preparedShiftPlans        :: ![PreparedShift]
    , preparedExistingSlots     :: ![RosterSlot]
    , preparedTargetLanes       :: ![RosterLane]
    , preparedTimesheetEntries  :: ![TimesheetEntry]
    , preparedCalendarRevision  :: !Int
    , preparedShiftTypeRequirements :: ![RosterTemplateApplicationShiftTypeRequirement]
    , preparedAvailableShiftTypes :: ![ShiftType]
    , preparedStaffNames        :: !(Map.Map (Id Staff) Text)
    , preparedCleanedTemplateContent :: !(Maybe RosterTemplateContent)
    , preparedReferenceRevision :: !Text
    }

data PreparedShift = PreparedShift
    { preparedTemplateShift  :: !RosterTemplateShift
    , preparedTemplateColumn :: !RosterTemplateColumn
    , preparedTargetDay      :: !RosterDay
    , preparedStartsAt       :: !UTCTime
    , preparedEndsAt         :: !UTCTime
    , preparedAssignment     :: !RosterShiftAssignment
    , preparedShiftTypeId    :: !(Id ShiftType)
    , preparedAssignmentIssue :: !(Maybe RosterTemplateApplicationAssignmentIssue)
    }
