{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.View.Admin.RosterGroups
    ( renderRosterGroupsSectionFragment
    ) where

import qualified Application.Helper.FrontendContract.Surface.Admin as Surface
import qualified Application.Helper.FrontendContract.Surface.Admin.Action as AdminAction
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            defaultFrontendSurfaceActionRoute,
                                                            renderFrontendSurfaceActionForm,
                                                            renderFrontendSurfaceMount)
import Application.Helper.FrontendContract.Surface.Values
import Web.Admin.FrontendSurface (AdminVenueScopeValue (..),
                                  adminRosterGroupsSurfaceImpl)
import Web.View.Admin.Common
import Web.View.Prelude

renderRosterGroupsSection :: [RosterGroup] -> Bool -> Html
renderRosterGroupsSection rosterGroups showInactive =
    renderConfigSection
        "admin-roster-groups-section"
        (renderAdminInactiveSummary rosterGroups showInactive toggleAction toggleRoute)
        [hsx|
            {renderRosterGroupCreateForm showInactive}
        |]
        (renderRosterGroupRows rosterGroups showInactive)
    where
        toggleHref = appendQueryParams (pathTo ShowadminRosterGroupsLiveFragmentAction) [(surfaceFieldNameFrom @Surface.ShowInactiveRosterGroups toggleFields, if showInactive then "false" else "true")]
        toggleFields = AdminAction.toggleInactiveRosterGroupsActionFields (not showInactive)
        toggleAction = AdminAction.toggleInactiveRosterGroupsAction toggleFields
        toggleRoute = ((defaultFrontendSurfaceActionRoute toggleHref)
            { actionRouteStandardUrl = Just toggleHref
            })

renderRosterGroupsSectionFragment :: [RosterGroup] -> Bool -> Html
renderRosterGroupsSectionFragment rosterGroups showInactive =
    renderFrontendSurfaceMount (adminRosterGroupsSurfaceImpl AdminVenueScopeValue { adminVenueId = currentAdminVenueScopeId, adminRosterGroupId = Nothing }) [hsx|
        <div id={surfaceFragmentTargetId @Surface.AdminRosterGroupsSurface @Surface.AdminRosterGroupsFragment noSurfaceFields}>
            {renderRosterGroupsSection rosterGroups showInactive}
        </div>
    |]

renderRosterGroupCreateForm :: Bool -> Html
renderRosterGroupCreateForm showInactive =
    renderFrontendSurfaceActionForm (AdminAction.createRosterGroupAction fields) route [hsx|
        <input type="hidden" name={surfaceFieldNameFrom @Surface.ShowInactiveRosterGroups fields} value={boolParam showInactive} />
        <div class="row g-2 align-items-end">
            <div class="col-12 col-md-8">
                <label class="form-label" for="new-roster-group-name">Name</label>
                <input id="new-roster-group-name" class="form-control" type="text" name={surfaceFieldNameFrom @Surface.Name fields} placeholder="Front of House" />
            </div>
            <div class="col-12 col-md-2">
                <label class="form-label" for="new-roster-group-active">Status</label>
                {renderAdminActiveToggle "new-roster-group-active" (surfaceToggleScalarField @Surface.IsActive fields True False) True}
            </div>
            <div class="col-12 col-md-2">
                <button class="btn btn-outline-primary w-100" type="submit">Add Group</button>
            </div>
        </div>
    |]
    where
        fields = AdminAction.createRosterGroupActionFields showInactive "" True
        route = ((defaultFrontendSurfaceActionRoute (pathTo CreateRosterGroupAction))
            { actionRouteStandardUrl = Just (pathTo CreateRosterGroupAction)
            , actionRouteExtraAttrs = [("class", appSurfaceClasses "p-3")]
            })

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
        {renderFrontendSurfaceActionForm (AdminAction.updateRosterGroupAction fields) updateRoute rowFormBody}
    </div>
|]
    where
        updateUrl = appendQueryParams (pathTo (UpdateRosterGroupAction (get #id rosterGroup))) [("rosterGroupId", tshow rosterGroup.id)]
        fields = AdminAction.updateRosterGroupActionFields showInactive rosterGroup.name rosterGroup.isActive
        updateRoute = ((defaultFrontendSurfaceActionRoute (updateUrl))
            { actionRouteStandardUrl = Just updateUrl
            })
        rowFormBody = [hsx|
            <input type="hidden" name={surfaceFieldNameFrom @Surface.ShowInactiveRosterGroups fields} value={boolParam showInactive} />
            <div class="d-flex justify-content-between align-items-center mb-2 gap-2 flex-wrap">
                <div class="d-flex align-items-center gap-2">
                    <span class="fw-semibold">Roster Group</span>
                    {renderActiveBadge rosterGroup.isActive}
                </div>
                <div class="btn-group btn-group-sm" role="group" aria-label="Reorder roster group">
                    {renderAdminReorderControl (not rosterGroup.isActive || rosterGroupIndex == 0) (AdminAction.moveRosterGroupUpAction moveUpFields) (pathTo (MoveRosterGroupUpAction rosterGroup.id)) "Up"}
                    {renderAdminReorderControl (not rosterGroup.isActive || rosterGroupIndex == activeCount - 1) (AdminAction.moveRosterGroupDownAction moveDownFields) (pathTo (MoveRosterGroupDownAction rosterGroup.id)) "Down"}
                </div>
            </div>
            <div class="row g-2 align-items-end">
                <div class="col-12 col-md-8">
                    <label class="form-label">Name</label>
                    <input class="form-control" type="text" name={surfaceFieldNameFrom @Surface.Name fields} value={rosterGroup.name} />
                </div>
                <div class="col-12 col-md-2">
                    <label class="form-label" for={"roster-group-active-" <> tshow rosterGroup.id}>Status</label>
                    {renderAdminActiveToggle ("roster-group-active-" <> tshow rosterGroup.id) (surfaceToggleScalarField @Surface.IsActive fields True False) rosterGroup.isActive}
                </div>
                <div class="col-12 col-md-2">
                    <button class="btn btn-outline-secondary w-100" type="submit">Update</button>
                </div>
            </div>
        |]
        moveUpFields = AdminAction.moveRosterGroupUpActionFields showInactive
        moveDownFields = AdminAction.moveRosterGroupDownActionFields showInactive
