module Web.RosterWeeks.Capabilities
    ( buildRosterViewCapabilities
    ) where

import Application.Helper.ControllerContext (hasManagementMode)
import Application.Helper.View (ViewAudience (ManagerAudience),
                                currentUserMatchesAudience)
import IHP.ControllerSupport (ControllerContext)
import IHP.Prelude
import Web.RosterWeeks.Types
import Web.RosterWeeks.WageEstimates (rosterPayAudienceForCurrentUser)

buildRosterViewCapabilities :: (?context :: ControllerContext) => Maybe RosterWindowState -> RosterViewCapabilities
buildRosterViewCapabilities maybeRosterWeek =
    let managerAudience = hasManagementMode && currentUserMatchesAudience ManagerAudience
        draftWeek = maybe False (not . (.windowIsPublished)) maybeRosterWeek
     in RosterViewCapabilities
            { canToggleRosterLive = managerAudience && isJust maybeRosterWeek
            , canCopyRosterWeek = managerAudience && draftWeek
            , canExportRosterImage = managerAudience
            , canManageAssignmentFilter = managerAudience
            , canManageRosterColumns = managerAudience && draftWeek
            , canViewLeaveMetrics = managerAudience
            , canViewWageEstimates = isJust rosterPayAudienceForCurrentUser
            , canManageRosterWarnings = managerAudience
            }
