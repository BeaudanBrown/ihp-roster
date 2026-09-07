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

import Application.Helper.Controller (currentUserIsImpersonating,
                                      currentUserIsSuperAdmin,
                                      effectiveVenueRoleOrNothing, hasRole)
import Application.Helper.ControllerContext (withRequestContext)
import IHP.ControllerSupport (ControllerContext)
import Generated.Types
import IHP.ViewPrelude

-- | True when the current user has at least manager privileges.
-- Use in views for conditional rendering of management UI.
currentUserIsManager :: (?context :: ControllerContext) => Bool
currentUserIsManager = hasRole Manager

-- | True when the current user is an admin.
-- Use in views for conditional rendering of admin-only UI.
currentUserIsAdmin :: (?context :: ControllerContext) => Bool
currentUserIsAdmin = hasRole VenueAdmin

currentUserIsSupportAdmin :: (?context :: ControllerContext) => Bool
currentUserIsSupportAdmin = currentUserIsSuperAdmin

currentUserIsVenueOwner :: (?context :: ControllerContext) => Bool
currentUserIsVenueOwner = effectiveVenueRoleOrNothing == Just VenueOwner

currentUserCanSeeXero :: (?context :: ControllerContext) => Bool
currentUserCanSeeXero = hasRole VenueOwner

data ViewAudience
    = AnySignedInAudience
    | StaffProfileAudience
    | ManagerAudience
    | XeroAudience
    | AdminAudience
    | SupportAudience
    deriving (Eq, Show)

currentUserMatchesAudience :: (?context :: ControllerContext) => ViewAudience -> Bool
currentUserMatchesAudience audience = withRequestContext $
    case audience of
        AnySignedInAudience -> isJust currentUserOrNothing
        StaffProfileAudience -> isJust currentUserOrNothing && (not currentUserIsSupportAdmin || currentUserIsImpersonating)
        ManagerAudience     -> currentUserIsManager
        XeroAudience        -> currentUserCanSeeXero
        AdminAudience       -> currentUserIsAdmin
        SupportAudience     -> currentUserIsSupportAdmin

renderWhenAudience :: (?context :: ControllerContext) => ViewAudience -> Html -> Html
renderWhenAudience audience =
    when (currentUserMatchesAudience audience)
