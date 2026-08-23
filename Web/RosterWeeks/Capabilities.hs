module Web.RosterWeeks.Capabilities
    ( buildRosterViewCapabilities
    ) where

import Application.Helper.View (ViewAudience (ManagerAudience),
                                currentUserIsAdmin, currentUserMatchesAudience)
import IHP.Controller.Context (ControllerContext)
import IHP.Prelude
import Web.RosterWeeks.Types

buildRosterViewCapabilities :: (?context :: ControllerContext) => Maybe RosterWindowState -> RosterViewCapabilities
buildRosterViewCapabilities maybeRosterWeek =
    let managerAudience = currentUserMatchesAudience ManagerAudience
        draftWeek = maybe False (not . (.windowIsPublished)) maybeRosterWeek
     in RosterViewCapabilities
            { canToggleRosterLive = managerAudience && isJust maybeRosterWeek
            , canCopyRosterWeek = managerAudience && draftWeek
            , canExportRosterImage = managerAudience
            , canManageAssignmentFilter = managerAudience
            , canManageRosterColumns = managerAudience && draftWeek
            , canViewLeaveMetrics = managerAudience
            , canViewWageEstimates = currentUserIsAdmin
            , canManageRosterWarnings = managerAudience
            }
