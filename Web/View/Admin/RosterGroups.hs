module Web.View.Admin.RosterGroups
    ( renderRosterGroupsSectionFragment
    ) where

import Application.Helper.Controller (currentVenueOrNothing)
import Application.Helper.LiveSurface (LiveSurfaceConfig (..),
                                       liveSurfaceConfigJson, mkLiveSurface)
import Application.Helper.LiveUpdate (LiveFragmentKey (..),
                                      LiveUpdateScope (..), mkLiveFragmentRef)
import Web.View.Admin.Common
import Web.View.Prelude

renderRosterGroupsSection :: [RosterGroup] -> Bool -> Html
renderRosterGroupsSection rosterGroups showInactive =
    renderConfigSection
        "roster-groups"
        "Roster Groups"
        "Define the roster lanes inside this venue. Roster columns are managed directly from each draft roster week."
        (renderInactiveToggleSummary "showInactiveRosterGroups" (pathTo ShowAdminRosterGroupsFragmentAction) "admin-roster-groups-fragment" rosterGroups showInactive)
        [hsx|
            {renderRosterGroupCreateForm showInactive}
        |]
        (renderRosterGroupRows rosterGroups showInactive)

renderRosterGroupsSectionFragment :: [RosterGroup] -> Bool -> Html
renderRosterGroupsSectionFragment rosterGroups showInactive = [hsx|
    <div id="admin-roster-groups-fragment"
         data-live-update-surface={liveSurfaceConfigJson <$> adminRosterGroupsLiveSurface}>
        {renderRosterGroupsSection rosterGroups showInactive}
    </div>
|]

adminRosterGroupsLiveSurface :: (?context :: ControllerContext) => Maybe LiveSurfaceConfig
adminRosterGroupsLiveSurface =
    fmap
        (\venue ->
        (mkLiveSurface
            "admin-roster-groups"
            AdminRosterGroupsScope { venueId = unpackId venue.id }
            [ mkLiveFragmentRef
                AdminRosterGroupsFragment
                "admin-roster-groups-fragment"
                (pathTo ShowAdminRosterGroupsFragmentAction)
            ])
            { decorateRequestsWithin = ["#admin-roster-groups-fragment"] }
        )
        currentVenueOrNothing

renderRosterGroupCreateForm :: Bool -> Html
renderRosterGroupCreateForm showInactive = [hsx|
    <form method="POST"
          action={CreateRosterGroupAction}
          class={appSurfaceClasses "p-3"}
          data-disable-javascript-submission="true"
          hx-post={CreateRosterGroupAction}
          hx-target="#admin-roster-groups-fragment"
          hx-swap="outerHTML">
        <input type="hidden" name="showInactiveRosterGroups" value={boolParam showInactive} />
        <div class="row g-2 align-items-end">
            <div class="col-12 col-md-8">
                <label class="form-label" for="new-roster-group-name">Name</label>
                <input id="new-roster-group-name" class="form-control" type="text" name="name" placeholder="Front of House" />
            </div>
            <div class="col-12 col-md-2">
                <label class="form-label" for="new-roster-group-active">Status</label>
                <select id="new-roster-group-active" class="form-select" name="isActive">
                    <option value="true" selected={True}>Active</option>
                    <option value="false">Inactive</option>
                </select>
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
              hx-swap="outerHTML">
            <input type="hidden" name="showInactiveRosterGroups" value={boolParam showInactive} />
            <div class="d-flex justify-content-between align-items-center mb-2 gap-2 flex-wrap">
                <div class="d-flex align-items-center gap-2">
                    <span class="fw-semibold">Roster Group</span>
                    {renderActiveBadge rosterGroup.isActive}
                    {renderRosterGroupDefaultBadge rosterGroup}
                </div>
                <div class="btn-group btn-group-sm" role="group" aria-label="Reorder roster group">
                    {renderMoveButton (not rosterGroup.isActive || rosterGroupIndex == 0) (MoveRosterGroupUpAction rosterGroup.id) "Up"}
                    {renderMoveButton (not rosterGroup.isActive || rosterGroupIndex == activeCount - 1) (MoveRosterGroupDownAction rosterGroup.id) "Down"}
                </div>
            </div>
            <div class="row g-2 align-items-end">
                <div class="col-12 col-md-8">
                    <label class="form-label">Name</label>
                    <input class="form-control" type="text" name="name" value={rosterGroup.name} />
                </div>
                <div class="col-12 col-md-2">
                    <label class="form-label">Status</label>
                    <select class="form-select" name="isActive">
                        <option value="true" selected={rosterGroup.isActive}>Active</option>
                        <option value="false" selected={not rosterGroup.isActive}>Inactive</option>
                    </select>
                </div>
                <div class="col-12 col-md-2">
                    <button class="btn btn-outline-secondary w-100" type="submit">Update</button>
                </div>
            </div>
        </form>
    </div>
|]
