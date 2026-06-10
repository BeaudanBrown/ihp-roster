module Web.RosterWeeks.Capabilities
    ( buildRosterViewCapabilities
    ) where

import Application.Helper.View (ViewAudience (ManagerAudience),
                                currentUserIsAdmin,
                                currentUserMatchesAudience)
import Generated.Types
import IHP.Controller.Context (ControllerContext)
import IHP.Prelude
import Web.RosterWeeks.Types

buildRosterViewCapabilities :: (?context :: ControllerContext) => Maybe RosterWeek -> RosterViewCapabilities
buildRosterViewCapabilities maybeRosterWeek =
    let managerAudience = currentUserMatchesAudience ManagerAudience
        draftWeek = maybe False (not . (.isLive)) maybeRosterWeek
     in RosterViewCapabilities
            { canToggleRosterLive = managerAudience && isJust maybeRosterWeek
            , canCopyRosterWeek = managerAudience
            , canExportRosterImage = managerAudience
            , canManageAssignmentFilter = managerAudience
            , canManageRosterColumns = managerAudience && draftWeek
            , canViewLeaveMetrics = managerAudience
            , canViewWageEstimates = currentUserIsAdmin
            , canManageRosterWarnings = managerAudience
            }
