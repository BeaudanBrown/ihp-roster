module Web.StaffDocuments.LiveUpdates
    ( refreshStaffCompliance
    ) where

import Application.Helper.LiveSurface (broadcastSurfaceFragments)
import Web.Controller.Prelude
import Web.View.Admin.Compliance (staffComplianceFragment,
                                  staffComplianceLiveSurfaceDefinition)

refreshStaffCompliance :: (?context :: ControllerContext, ?request :: Request) => UUID -> IO ()
refreshStaffCompliance _venueId =
    broadcastSurfaceFragments
        staffComplianceLiveSurfaceDefinition
        ()
        [staffComplianceFragment]
