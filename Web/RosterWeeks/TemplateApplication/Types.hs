module Web.RosterWeeks.TemplateApplication.Types where

import Application.Helper.FrontendContract.Surface.Resource (SurfaceResourceValue)
import Application.RosterShiftAssignment (RosterShiftAssignment)
import Application.RosterTemplates (RosterTemplateSaved)
import Application.VenueTime.Model (BoundaryModelError,
                                    ShiftCopyOccurrenceSelections)
import Generated.Types
import IHP.ControllerPrelude

data RosterTemplateApplicationRequest = RosterTemplateApplicationRequest
    { applicationTemplateId           :: !(Id RosterTemplate)
    , applicationTargetWeekId         :: !(Id RosterWeek)
    , applicationTargetDayOffset      :: !(Maybe Int)
    , applicationOccurrenceSelections :: !ShiftCopyOccurrenceSelections
    }
    deriving (Eq, Show)

data RosterTemplateApplicationAssignmentIssue
    = RosterTemplateStaffUnavailable
    | RosterTemplateStaffOutsideGroup
    | RosterTemplateStaffPayInvalid
    deriving (Eq, Show)

data RosterTemplateApplicationWarning
    = RosterTemplateApplicationClearsDay !Int
    | RosterTemplateApplicationClearsWeek
    | RosterTemplateApplicationExistingTimesheetsRemain !Int
    | RosterTemplateApplicationAssignmentConvertedToOpen !(Id RosterTemplateShift) !RosterTemplateApplicationAssignmentIssue
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
    , applicationPreviewTargetWeekOffset :: !Int
    , applicationPreviewTargetDayOffset  :: !(Maybe Int)
    , applicationExpectedVersion         :: !Int
    , applicationExpectedTargetRevision  :: !Text
    , applicationReplacementShiftCount   :: !Int
    , applicationExistingShiftCount      :: !Int
    , applicationResolvedShifts          :: ![RosterTemplateApplicationResolvedShift]
    , applicationWarnings                :: ![RosterTemplateApplicationWarning]
    , applicationTouchedResources        :: ![SurfaceResourceValue]
    }
    deriving (Eq, Show)

data RosterTemplateApplicationResult = RosterTemplateApplicationResult
    { appliedRosterWeek       :: !RosterWeek
    , appliedTemplateVersion  :: !Int
    , appliedWarnings         :: ![RosterTemplateApplicationWarning]
    , appliedTouchedResources :: ![SurfaceResourceValue]
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
    | RosterTemplateApplicationVersionConflict !Int
    | RosterTemplateApplicationTargetConflict
    | RosterTemplateApplicationInvalidShiftTypes ![Id ShiftType]
    | RosterTemplateApplicationBoundaryError !(Id RosterTemplateShift) !RosterTemplateApplicationBoundary !BoundaryModelError
    | RosterTemplateApplicationInvalidStructure !Text
    deriving (Eq, Show)

data PreparedApplication = PreparedApplication
    { preparedSaved             :: !RosterTemplateSaved
    , preparedTargetWeek        :: !RosterWeek
    , preparedTargetDays        :: ![RosterDay]
    , preparedFirstTargetDay    :: !RosterDay
    , preparedShiftPlans        :: ![PreparedShift]
    , preparedExistingSlots     :: ![RosterSlot]
    , preparedTargetDefinitions :: ![RosterWeekSlotDefinition]
    , preparedTimesheetEntries  :: ![TimesheetEntry]
    }

data PreparedShift = PreparedShift
    { preparedTemplateShift  :: !RosterTemplateShift
    , preparedTemplateColumn :: !RosterTemplateColumn
    , preparedTargetDay      :: !RosterDay
    , preparedStartsAt       :: !UTCTime
    , preparedEndsAt         :: !UTCTime
    , preparedAssignment     :: !RosterShiftAssignment
    , preparedAssignmentIssue :: !(Maybe RosterTemplateApplicationAssignmentIssue)
    }
