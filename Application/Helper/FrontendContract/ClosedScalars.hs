{-# LANGUAGE DataKinds #-}

-- | Registered app-owned finite scalar schemas. Persisted domains reuse their
-- generated PostgreSQL enum types; browser reachability stays explicit here.
module Application.Helper.FrontendContract.ClosedScalars
    ( ClosedScalarContract
    ) where

import Application.Helper.Export.Types (ExportJobType)
import Application.Helper.FrontendContract.DSL hiding (Enum)
import Application.Helper.FrontendContract.Surface.LeaveRequests (LeaveSectionValue)
import Application.Helper.FrontendContract.Surface.Profile (StaffProfileSectionValue)
import Application.Helper.FrontendContract.Surface.Roster (RosterImageExportStyle,
                                                           RosterStaffScopeValue,
                                                           RosterTemplateCaptureAssignmentMode)
import Generated.Types (FeedbackTypeEnum, RosterLayoutModeEnum,
                        ShiftTypeColourKeyEnum, StaffEmploymentBasisEnum,
                        VenueRoleEnum)

data AppClosedScalars

type ClosedScalarContract =
    Global AppClosedScalars
        '[ ServerSchema (ClosedScalar RosterLayoutModeEnum)
         , BrowserInboundSchema (ClosedScalar RosterImageExportStyle)
         , ServerSchema (ClosedScalar FeedbackTypeEnum)
         , ServerSchema (ClosedScalar StaffProfileSectionValue)
         , ServerSchema (ClosedScalar RosterStaffScopeValue)
         , ServerSchema (ClosedScalar RosterTemplateCaptureAssignmentMode)
         , BrowserInboundSchema (ClosedScalar LeaveSectionValue)
         , ServerSchema (ClosedScalar ShiftTypeColourKeyEnum)
         , ServerSchema (ClosedScalar VenueRoleEnum)
         , ServerSchema (ClosedScalar StaffEmploymentBasisEnum)
         , ServerSchema (ClosedScalar ExportJobType)
         ]
