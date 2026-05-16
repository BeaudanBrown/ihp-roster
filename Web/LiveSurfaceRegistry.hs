module Web.LiveSurfaceRegistry
    ( authorizeRegisteredLiveSurfaceScope
    ) where

import Application.Support.LiveUpdates (supportLiveSurfaceDefinition)
import Application.Helper.LiveSurface (authorizeTypedLiveSurfaceWireScope)
import Application.Helper.LiveUpdate (LiveUpdateScope)
import Web.Controller.Prelude
import Web.Billing.LiveUpdates (billingLiveSurfaceDefinition)
import Web.LeaveRequests.Projection (leaveRequestsLiveSurfaceDefinition)
import Web.Profiles.LiveUpdates (profileContentLiveSurfaceDefinition,
                                 profileLeaveRequestsLiveSurfaceDefinition)
import Web.RosterWeeks.RenderData (rosterLiveSurfaceDefinition)
import Web.Timesheets.Projection (timesheetLiveSurfaceDefinition)
import Web.View.Admin.Compliance (staffComplianceLiveSurfaceDefinition)
import Web.View.Admin.Exports (adminExportsLiveSurfaceDefinition)
import Web.View.Admin.Invites (adminInvitesLiveSurfaceDefinition)
import Web.View.Admin.RosterGroups (adminRosterGroupsLiveSurfaceDefinition)
import Web.View.Admin.ShiftTypes (adminShiftTypesLiveSurfaceDefinition)
import Web.View.Admin.Xero (adminXeroLiveSurfaceDefinition)

authorizeRegisteredLiveSurfaceScope ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    LiveUpdateScope ->
    IO Bool
authorizeRegisteredLiveSurfaceScope scope = do
    authorizations <-
        catMaybes
            <$> sequence
                [ authorizeTypedLiveSurfaceWireScope supportLiveSurfaceDefinition scope
                , authorizeTypedLiveSurfaceWireScope adminInvitesLiveSurfaceDefinition scope
                , authorizeTypedLiveSurfaceWireScope adminExportsLiveSurfaceDefinition scope
                , authorizeTypedLiveSurfaceWireScope adminShiftTypesLiveSurfaceDefinition scope
                , authorizeTypedLiveSurfaceWireScope adminRosterGroupsLiveSurfaceDefinition scope
                , authorizeTypedLiveSurfaceWireScope adminXeroLiveSurfaceDefinition scope
                , authorizeTypedLiveSurfaceWireScope billingLiveSurfaceDefinition scope
                , authorizeTypedLiveSurfaceWireScope staffComplianceLiveSurfaceDefinition scope
                , authorizeTypedLiveSurfaceWireScope leaveRequestsLiveSurfaceDefinition scope
                , authorizeTypedLiveSurfaceWireScope profileContentLiveSurfaceDefinition scope
                , authorizeTypedLiveSurfaceWireScope profileLeaveRequestsLiveSurfaceDefinition scope
                , authorizeTypedLiveSurfaceWireScope timesheetLiveSurfaceDefinition scope
                , authorizeTypedLiveSurfaceWireScope rosterLiveSurfaceDefinition scope
                ]
    pure (or authorizations)
