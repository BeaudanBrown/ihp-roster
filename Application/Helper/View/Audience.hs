module Application.Helper.View.Audience
    ( ViewAudience (..)
    , currentUserCanSeeXero
    , currentUserIsAdmin
    , currentUserIsManager
    , currentUserIsSupportAdmin
    , currentUserIsVenueOwner
    , currentUserMatchesAudience
    , renderWhenAudience
    ) where

import Application.Helper.Controller (VenueRole (..), currentUserIsSuperAdmin,
                                      currentVenueRoleOrNothing,
                                      hasRole)
import IHP.ViewPrelude

-- | True when the current user has at least manager privileges.
-- Use in views for conditional rendering of management UI.
currentUserIsManager :: (?context :: ControllerContext) => Bool
currentUserIsManager = hasRole ManagerRole'

-- | True when the current user is an admin.
-- Use in views for conditional rendering of admin-only UI.
currentUserIsAdmin :: (?context :: ControllerContext) => Bool
currentUserIsAdmin = hasRole VenueAdminRole

currentUserIsSupportAdmin :: (?context :: ControllerContext) => Bool
currentUserIsSupportAdmin = currentUserIsSuperAdmin

currentUserIsVenueOwner :: (?context :: ControllerContext) => Bool
currentUserIsVenueOwner = currentVenueRoleOrNothing == Just VenueOwnerRole

currentUserCanSeeXero :: (?context :: ControllerContext) => Bool
currentUserCanSeeXero = hasRole VenueOwnerRole

data ViewAudience
    = AnySignedInAudience
    | StaffProfileAudience
    | ManagerAudience
    | XeroAudience
    | AdminAudience
    | SupportAudience
    deriving (Eq, Show)

currentUserMatchesAudience :: (?context :: ControllerContext) => ViewAudience -> Bool
currentUserMatchesAudience audience =
    case audience of
        AnySignedInAudience -> isJust currentUserOrNothing
        StaffProfileAudience -> isJust currentUserOrNothing && not currentUserIsSupportAdmin
        ManagerAudience     -> currentUserIsManager
        XeroAudience        -> currentUserCanSeeXero
        AdminAudience       -> currentUserIsAdmin
        SupportAudience     -> currentUserIsSupportAdmin

renderWhenAudience :: (?context :: ControllerContext) => ViewAudience -> Html -> Html
renderWhenAudience audience =
    when (currentUserMatchesAudience audience)
