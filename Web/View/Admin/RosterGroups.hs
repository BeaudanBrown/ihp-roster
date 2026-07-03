{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.View.Admin.RosterGroups
    ( AdminRosterGroupsLiveFragment (..)
    , adminRosterGroupsFragment
    , adminRosterGroupsLiveSurfaceDefinition
    , adminRosterGroupsLiveSurfaceDefinitionForVenue
    , renderRosterGroupsSectionFragment
    , renderRosterGroupsSectionFragmentWithSwap
    ) where

import Application.Helper.Controller (currentVenueOrNothing)
import Application.Helper.FrontendSurface.Runtime (renderFrontendSurfaceMount)
import Application.Helper.LiveResource (LiveResource (..))
import Application.Helper.LiveSurface
import Application.Helper.LiveUpdate (LiveFragmentKey (..),
                                      LiveUpdateScope (..))
import Web.Admin.FrontendSurface (AdminVenueScopeValue (..),
                                  adminRosterGroupsSurfaceImpl)
import Web.View.Admin.Common
import Web.View.Prelude

renderRosterGroupsSection :: [RosterGroup] -> Bool -> Html
renderRosterGroupsSection rosterGroups showInactive =
    renderConfigSection
        "admin-roster-groups-section"
        (renderInactiveToggleSummary "showInactiveRosterGroups" (pathTo ShowAdminRosterGroupsFragmentAction) "admin-roster-groups-fragment" rosterGroups showInactive)
        [hsx|
            {renderRosterGroupCreateForm showInactive}
        |]
        (renderRosterGroupRows rosterGroups showInactive)

renderRosterGroupsSectionFragment :: [RosterGroup] -> Bool -> Html
renderRosterGroupsSectionFragment =
    renderRosterGroupsSectionFragmentWithSwap Nothing

renderRosterGroupsSectionFragmentWithSwap :: Maybe Text -> [RosterGroup] -> Bool -> Html
renderRosterGroupsSectionFragmentWithSwap maybeSwapOob rosterGroups showInactive =
    renderFrontendSurfaceMount (adminRosterGroupsSurfaceImpl AdminVenueScopeValue { adminVenueId = currentVenueScopeId, adminRosterGroupId = Nothing }) [hsx|
        <div id="admin-roster-groups-fragment"
             hx-swap-oob={maybeSwapOob}>
            {renderRosterGroupsSection rosterGroups showInactive}
        </div>
    |]

data AdminRosterGroupsSurface

data AdminRosterGroupsLiveFragment
    = AdminRosterGroupsLiveFragment
    deriving (Eq, Show)

adminRosterGroupsFragment :: AdminRosterGroupsLiveFragment
adminRosterGroupsFragment =
    AdminRosterGroupsLiveFragment

adminRosterGroupsLiveSurface :: (?context :: ControllerContext) => Maybe LiveSurfaceConfig
adminRosterGroupsLiveSurface =
    Just (mkTypedDefinedLiveSurface adminRosterGroupsLiveSurfaceDefinition ())

adminRosterGroupsLiveSurfaceDefinition :: (?context :: ControllerContext) => TypedLiveSurfaceDefinition AdminRosterGroupsSurface () AdminRosterGroupsLiveFragment EmptyInteractionLayer EmptyInteractionSession EmptyInteractionIntent
adminRosterGroupsLiveSurfaceDefinition =
    adminRosterGroupsLiveSurfaceDefinitionForVenue currentVenueScopeId

adminRosterGroupsLiveSurfaceDefinitionForVenue :: UUID -> TypedLiveSurfaceDefinition AdminRosterGroupsSurface () AdminRosterGroupsLiveFragment EmptyInteractionLayer EmptyInteractionSession EmptyInteractionIntent
adminRosterGroupsLiveSurfaceDefinitionForVenue surfaceVenueId =
    currentVenueUnitScopeSurfaceForVenue
        "admin-roster-groups"
        surfaceVenueId
        adminRosterGroupsVenueScope
        RequireCurrentVenueAdmin
        [ staticLiveFragmentDescriptor
            adminRosterGroupsFragment
            AdminRosterGroupsFragment
            "admin-roster-groups-fragment"
            (pathTo ShowAdminRosterGroupsFragmentAction)
            (const (liveFragmentDependsOn (AdminRosterGroupsResource surfaceVenueId) []))
        ]

adminRosterGroupsVenueScope :: VenueLiveUpdateScope
adminRosterGroupsVenueScope =
    venueLiveUpdateScope
        AdminRosterGroupsScope
        (\case
            AdminRosterGroupsScope { venueId } -> Just venueId
            _ -> Nothing)

currentVenueScopeId :: (?context :: ControllerContext) => UUID
currentVenueScopeId =
    case currentVenueOrNothing of
        Just venue -> unpackId venue.id
        Nothing -> error "Admin roster groups live surface requires a current venue"

renderRosterGroupCreateForm :: Bool -> Html
renderRosterGroupCreateForm showInactive = [hsx|
    <form method="POST"
          action={CreateRosterGroupAction}
          class={appSurfaceClasses "p-3"}
          data-disable-javascript-submission="true"
          hx-post={CreateRosterGroupAction}
          hx-target="#admin-roster-groups-fragment"
          hx-swap="none">
        <input type="hidden" name="showInactiveRosterGroups" value={boolParam showInactive} />
        <div class="row g-2 align-items-end">
            <div class="col-12 col-md-8">
                <label class="form-label" for="new-roster-group-name">Name</label>
                <input id="new-roster-group-name" class="form-control" type="text" name="name" placeholder="Front of House" />
            </div>
            <div class="col-12 col-md-2">
                <label class="form-label" for="new-roster-group-active">Status</label>
                {renderAdminActiveToggle "new-roster-group-active" Nothing "admin-roster-groups-fragment" True}
            </div>
            <div class="col-12 col-md-2">
                <button class="btn btn-outline-primary w-100" type="submit">Add Group</button>
            </div>
        </div>
    </form>
|]

renderRosterGroupRows :: [RosterGroup] -> Bool -> Html
renderRosterGroupRows rosterGroups showInactive
    | null visibleRows = renderEmptyState "No roster groups yet."
    | otherwise = [hsx|
        <div class="d-flex flex-column gap-2">
            {forEach (zip [0 :: Int ..] visibleRows) (renderRosterGroupRow showInactive activeCount)}
        </div>
    |]
    where
        activeRows = filter (.isActive) rosterGroups
        activeCount = length activeRows
        visibleRows = visibleRosterGroupsForAdmin rosterGroups showInactive

renderRosterGroupRow :: Bool -> Int -> (Int, RosterGroup) -> Html
renderRosterGroupRow showInactive activeCount (rosterGroupIndex, rosterGroup) = [hsx|
    <div class={appSurfaceClasses "p-3 mb-2"}>
        <form method="POST"
              action={appendQueryParams (pathTo (UpdateRosterGroupAction (get #id rosterGroup))) [("rosterGroupId", tshow rosterGroup.id)]}
              data-disable-javascript-submission="true"
              hx-post={appendQueryParams (pathTo (UpdateRosterGroupAction (get #id rosterGroup))) [("rosterGroupId", tshow rosterGroup.id)]}
              hx-target="#admin-roster-groups-fragment"
              hx-swap="none">
            <input type="hidden" name="showInactiveRosterGroups" value={boolParam showInactive} />
            <div class="d-flex justify-content-between align-items-center mb-2 gap-2 flex-wrap">
                <div class="d-flex align-items-center gap-2">
                    <span class="fw-semibold">Roster Group</span>
                    {renderActiveBadge rosterGroup.isActive}
                </div>
                <div class="btn-group btn-group-sm" role="group" aria-label="Reorder roster group">
                    {renderMoveButton (not rosterGroup.isActive || rosterGroupIndex == 0) (MoveRosterGroupUpAction rosterGroup.id) "admin-roster-groups-fragment" "Up"}
                    {renderMoveButton (not rosterGroup.isActive || rosterGroupIndex == activeCount - 1) (MoveRosterGroupDownAction rosterGroup.id) "admin-roster-groups-fragment" "Down"}
                </div>
            </div>
            <div class="row g-2 align-items-end">
                <div class="col-12 col-md-8">
                    <label class="form-label">Name</label>
                    <input class="form-control" type="text" name="name" value={rosterGroup.name} />
                </div>
                <div class="col-12 col-md-2">
                    <label class="form-label" for={"roster-group-active-" <> tshow rosterGroup.id}>Status</label>
                    {renderAdminActiveToggle ("roster-group-active-" <> tshow rosterGroup.id) Nothing "admin-roster-groups-fragment" rosterGroup.isActive}
                </div>
                <div class="col-12 col-md-2">
                    <button class="btn btn-outline-secondary w-100" type="submit">Update</button>
                </div>
            </div>
        </form>
    </div>
|]
