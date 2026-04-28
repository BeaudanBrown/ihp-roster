module Web.View.Admin.RosterGroups
    ( renderRosterGroupsSectionFragment
    , renderRosterGroupSlotNamesFragment
    ) where

import Application.Helper.Controller (currentVenueOrNothing)
import Application.Helper.LiveSurface (LiveSurfaceConfig (..), liveSurfaceConfigJson, mkLiveSurface)
import Application.Helper.LiveUpdate (LiveFragmentKey (..), LiveFragmentProtection (..), LiveFragmentRef (..), LiveUpdateScope (..), mkLiveFragmentRef)
import Web.View.Admin.Common
import Web.View.Prelude

renderRosterGroupsSection :: [RosterGroup] -> [SlotName] -> Bool -> Html
renderRosterGroupsSection rosterGroups slotNames showInactive =
    renderConfigSection
        "roster-groups"
        "Roster Groups"
        "Define the roster lanes inside this venue. Slot names are managed inside each roster group."
        (renderInactiveToggleSummary "showInactiveRosterGroups" (pathTo ShowAdminRosterGroupsFragmentAction) "admin-roster-groups-fragment" rosterGroups showInactive)
        [hsx|
            {renderRosterGroupCreateForm showInactive}
        |]
        (renderRosterGroupRows rosterGroups slotNames showInactive)

renderRosterGroupsSectionFragment :: [RosterGroup] -> [SlotName] -> Bool -> Html
renderRosterGroupsSectionFragment rosterGroups slotNames showInactive = [hsx|
    <div id="admin-roster-groups-fragment"
         data-live-update-surface={liveSurfaceConfigJson <$> adminRosterGroupsLiveSurface}>
        {renderRosterGroupsSection rosterGroups slotNames showInactive}
        {forEach (visibleRosterGroupsForAdmin rosterGroups showInactive) renderSlotNamesLiveUpdateOwner}
    </div>
|]

renderRosterGroupSlotNamesFragment :: RosterGroup -> [SlotName] -> Html
renderRosterGroupSlotNamesFragment rosterGroup slotNames = [hsx|
    <div id={slotNameFragmentId rosterGroup.id} class="mt-3 pt-3 border-top">
        <div class="d-flex flex-wrap align-items-center justify-content-between gap-2 mb-2">
            <h3 class="h6 mb-0">Slot Names</h3>
            <span class="small app-muted">{tshow (length slotNames)} active</span>
        </div>
        {renderSlotNameCreateForm rosterGroup.id}
        <div class="mt-2">
            {renderSlotNameRows rosterGroup.id slotNames}
        </div>
    </div>
|]

renderSlotNameRows :: Id RosterGroup -> [SlotName] -> Html
renderSlotNameRows rosterGroupId slotNames
    | null slotNames = renderEmptyState "No slot names yet for this roster group."
    | otherwise = [hsx|
        <div class="d-flex flex-column gap-2">
            {forEach (zip [0 :: Int ..] slotNames) (renderSlotNameRow rosterGroupId (length slotNames))}
        </div>
    |]

renderSlotNamesLiveUpdateOwner :: RosterGroup -> Html
renderSlotNamesLiveUpdateOwner rosterGroup =
    let scope = adminSlotNamesScopeForRosterGroup rosterGroup
     in [hsx|
        <div data-live-update-surface={liveSurfaceConfigJson (adminSlotNamesLiveSurface rosterGroup scope)}
             hidden="hidden"></div>
    |]

adminSlotNamesScopeForRosterGroup :: RosterGroup -> LiveUpdateScope
adminSlotNamesScopeForRosterGroup rosterGroup =
    AdminSlotNamesScope
        { venueId = rosterGroup.venueId
        , rosterGroupId = unpackId rosterGroup.id
        }

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

adminSlotNamesLiveSurface :: (?context :: ControllerContext) => RosterGroup -> LiveUpdateScope -> LiveSurfaceConfig
adminSlotNamesLiveSurface rosterGroup scope =
    (mkLiveSurface
        "admin-slot-names"
        scope
        [ mkLiveFragmentRef
            (AdminSlotNamesFragment { rosterGroupId = unpackId rosterGroup.id })
            (slotNameFragmentId rosterGroup.id)
            (appendQueryParams (pathTo ShowAdminSlotNamesFragmentAction) [("rosterGroupId", tshow rosterGroup.id)])
        ])
        { decorateRequestsWithin = ["#" <> slotNameFragmentId rosterGroup.id] }

renderRosterGroupCreateForm :: Bool -> Html
renderRosterGroupCreateForm showInactive = [hsx|
    <form method="POST"
          action={CreateRosterGroupAction}
          class="border rounded p-3"
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

renderRosterGroupRows :: [RosterGroup] -> [SlotName] -> Bool -> Html
renderRosterGroupRows rosterGroups slotNames showInactive
    | null visibleRows = renderEmptyState "No roster groups yet."
    | otherwise = [hsx|
        <div class="d-flex flex-column gap-2">
            {forEach (zip [0 :: Int ..] visibleRows) (renderRosterGroupRow showInactive activeCount slotNames)}
        </div>
    |]
    where
        activeRows = filter (.isActive) rosterGroups
        activeCount = length activeRows
        visibleRows = visibleRosterGroupsForAdmin rosterGroups showInactive

renderRosterGroupRow :: Bool -> Int -> [SlotName] -> (Int, RosterGroup) -> Html
renderRosterGroupRow showInactive activeCount slotNames (rosterGroupIndex, rosterGroup) = [hsx|
    <div class="border rounded p-3 mb-2">
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
        {renderRosterGroupSlotNamesFragment rosterGroup (slotNamesForRosterGroup rosterGroup.id slotNames)}
    </div>
|]

renderSlotNameCreateForm :: Id RosterGroup -> Html
renderSlotNameCreateForm rosterGroupId = [hsx|
    <form method="POST"
          action={appendQueryParams (pathTo CreateSlotNameAction) [("rosterGroupId", tshow rosterGroupId)]}
          class="admin-slot-name-create-form border rounded p-3"
          data-disable-javascript-submission="true"
          hx-post={appendQueryParams (pathTo CreateSlotNameAction) [("rosterGroupId", tshow rosterGroupId)]}
          hx-target={slotNameTarget rosterGroupId}
          hx-swap="outerHTML">
        <div class="admin-slot-name-create-controls">
            <div class="admin-slot-name-create-field">
                <label class="form-label" for={"new-slot-name-" <> tshow rosterGroupId}>Name</label>
                <input id={"new-slot-name-" <> tshow rosterGroupId} class="form-control" type="text" name="name" placeholder="Early" />
            </div>
            <div class="admin-slot-add-action">
                <button class="btn btn-outline-primary admin-slot-add-button" type="submit">Add Slot</button>
            </div>
        </div>
    </form>
|]

renderSlotNameRow :: Id RosterGroup -> Int -> (Int, SlotName) -> Html
renderSlotNameRow rosterGroupId slotCount (slotIndex, slotName) = [hsx|
    <div class="admin-slot-name-row border rounded p-2">
        <div class="admin-slot-name-controls">
            <div class="admin-slot-move-group" role="group" aria-label="Reorder slot">
                {renderSlotMoveButton rosterGroupId (slotIndex == 0) (appendQueryParams (pathTo (MoveSlotNameUpAction (get #id slotName))) [("rosterGroupId", tshow rosterGroupId)]) "Up"}
                {renderSlotMoveButton rosterGroupId (slotIndex == slotCount - 1) (appendQueryParams (pathTo (MoveSlotNameDownAction (get #id slotName))) [("rosterGroupId", tshow rosterGroupId)]) "Down"}
            </div>
            <form class="admin-slot-name-edit-form m-0" data-disable-javascript-submission="true">
                <input class="form-control admin-slot-name-input"
                       type="text"
                       name="name"
                       value={slotName.name}
                       aria-label="Slot name"
                       hx-post={appendQueryParams (pathTo (UpdateSlotNameAction (get #id slotName))) [("rosterGroupId", tshow rosterGroupId)]}
                       hx-trigger="input changed delay:1200ms"
                       hx-include="closest form"
                       hx-sync="#admin-config-sections:queue last"
                       hx-swap="none" />
            </form>
            <form method="POST"
                  action={appendQueryParams (pathTo (DeleteSlotNameAction (get #id slotName))) [("rosterGroupId", tshow rosterGroupId)]}
                  class="admin-slot-delete-form m-0"
                  data-disable-javascript-submission="true"
                  hx-delete={appendQueryParams (pathTo (DeleteSlotNameAction (get #id slotName))) [("rosterGroupId", tshow rosterGroupId)]}
                  hx-target={slotNameTarget rosterGroupId}
                  hx-swap="outerHTML">
                <input type="hidden" name="_method" value="DELETE" />
                <button class="btn btn-outline-danger admin-slot-delete-button" type="submit">Delete</button>
            </form>
        </div>
    </div>
|]

renderSlotMoveButton :: Id RosterGroup -> Bool -> Text -> Text -> Html
renderSlotMoveButton rosterGroupId isDisabled action label =
    if isDisabled
        then [hsx|
            <button class="btn btn-outline-secondary admin-slot-move-button" type="button" disabled={True}>{label}</button>
        |]
        else [hsx|
            <form method="POST"
                  action={action}
                  class="admin-slot-move-form"
                  data-disable-javascript-submission="true"
                  hx-post={action}
                  hx-target={slotNameTarget rosterGroupId}
                  hx-swap="outerHTML">
                <button class="btn btn-outline-secondary admin-slot-move-button" type="submit">{label}</button>
            </form>
        |]
