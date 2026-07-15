{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.View.Admin.RosterGroups
    ( renderRosterGroupsSectionFragment
    ) where

import Application.Helper.Controller (currentVenueOrNothing)
import qualified Application.Helper.FrontendContract.Surface.Admin as Surface
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceAction,
                                                            FrontendSurfaceActionRoute (..),
                                                            FrontendSurfaceCustomHtmxAttrs (..),
                                                            frontendSurfaceAction,
                                                            renderFrontendSurfaceActionForm,
                                                            renderFrontendSurfaceActionLink,
                                                            renderFrontendSurfaceActionSubmitButton,
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
        (renderRosterGroupsInactiveSummary rosterGroups showInactive)
        [hsx|
            {renderRosterGroupCreateForm showInactive}
        |]
        (renderRosterGroupRows rosterGroups showInactive)

renderRosterGroupsSectionFragment :: [RosterGroup] -> Bool -> Html
renderRosterGroupsSectionFragment rosterGroups showInactive =
    renderFrontendSurfaceMount (adminRosterGroupsSurfaceImpl AdminVenueScopeValue { adminVenueId = currentVenueScopeId, adminRosterGroupId = Nothing }) [hsx|
        <div id={surfaceFragmentTargetId @Surface.AdminRosterGroupsSurface @Surface.AdminRosterGroupsFragment NoSurfaceFields}>
            {renderRosterGroupsSection rosterGroups showInactive}
        </div>
    |]

currentVenueScopeId :: (?context :: ControllerContext) => UUID
currentVenueScopeId =
    case currentVenueOrNothing of
        Just venue -> unpackId venue.id
        Nothing -> error "Admin roster groups live surface requires a current venue"

renderRosterGroupsInactiveSummary :: [RosterGroup] -> Bool -> Html
renderRosterGroupsInactiveSummary rosterGroups showInactive = [hsx|
    <div class="d-flex flex-wrap align-items-center justify-content-between gap-2 mb-3">
        <p class="small app-muted mb-0">
            {tshow (length rosterGroups)} rows total, {tshow activeCount} active, {tshow inactiveCount} inactive.
        </p>
        <div>
            {renderFrontendSurfaceActionLink toggleAction toggleRoute toggleLabel}
        </div>
    </div>
|]
    where
        activeCount = countActiveRows rosterGroups
        inactiveCount = length rosterGroups - activeCount
        toggleLabel = [hsx|<span class="small">Show disabled</span>|]
        toggleHref = appendQueryParams (pathTo ShowadminRosterGroupsLiveFragmentAction) [(surfaceFieldNameFrom @Surface.ShowInactiveRosterGroups toggleFields, if showInactive then "false" else "true")]
        toggleFields = surfaceField @Surface.ShowInactiveRosterGroups (not showInactive) :& NoSurfaceFields
        toggleAction = frontendSurfaceAction @Surface.AdminRosterGroupsSurface @Surface.ToggleInactiveRosterGroups toggleFields
        toggleRoute = FrontendSurfaceActionRoute
            { actionRouteUrl = toggleHref
            , actionRouteCustomHtmx = []
            , actionRouteStandardUrl = Just toggleHref
            , actionRouteExtraAttrs = [("class", toggleClass), ("role", "switch"), ("aria-checked", if showInactive then "true" else "false")]
            }
        toggleClass = classes
            [ ("btn app-toggle-button btn-sm", True)
            , ("btn-success", showInactive)
            , ("btn-outline-success", not showInactive)
            ]

renderRosterGroupCreateForm :: Bool -> Html
renderRosterGroupCreateForm showInactive =
    renderFrontendSurfaceActionForm (frontendSurfaceAction @Surface.AdminRosterGroupsSurface @Surface.CreateRosterGroup fields) route [hsx|
        <input type="hidden" name={surfaceFieldNameFrom @Surface.ShowInactiveRosterGroups fields} value={boolParam showInactive} />
        <div class="row g-2 align-items-end">
            <div class="col-12 col-md-8">
                <label class="form-label" for="new-roster-group-name">Name</label>
                <input id="new-roster-group-name" class="form-control" type="text" name={surfaceFieldNameFrom @Surface.Name fields} placeholder="Front of House" />
            </div>
            <div class="col-12 col-md-2">
                <label class="form-label" for="new-roster-group-active">Status</label>
                {renderAdminActiveToggle "new-roster-group-active" (surfaceFieldNameFrom @Surface.IsActive fields) Nothing "admin-roster-groups-fragment" True}
            </div>
            <div class="col-12 col-md-2">
                <button class="btn btn-outline-primary w-100" type="submit">Add Group</button>
            </div>
        </div>
    |]
    where
        fields =
            surfaceField @Surface.ShowInactiveRosterGroups showInactive
                :& surfaceField @Surface.Name ""
                :& surfaceField @Surface.IsActive True
                :& NoSurfaceFields
        route = FrontendSurfaceActionRoute
            { actionRouteUrl = pathTo CreateRosterGroupAction
            , actionRouteCustomHtmx = []
            , actionRouteStandardUrl = Just (pathTo CreateRosterGroupAction)
            , actionRouteExtraAttrs = [("class", appSurfaceClasses "p-3")]
            }

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
        {renderFrontendSurfaceActionForm (frontendSurfaceAction @Surface.AdminRosterGroupsSurface @Surface.UpdateRosterGroup fields) updateRoute rowFormBody}
    </div>
|]
    where
        updateUrl = appendQueryParams (pathTo (UpdateRosterGroupAction (get #id rosterGroup))) [("rosterGroupId", tshow rosterGroup.id)]
        fields =
            surfaceField @Surface.ShowInactiveRosterGroups showInactive
                :& surfaceField @Surface.Name rosterGroup.name
                :& surfaceField @Surface.IsActive rosterGroup.isActive
                :& NoSurfaceFields
        updateRoute = FrontendSurfaceActionRoute
            { actionRouteUrl = updateUrl
            , actionRouteCustomHtmx = []
            , actionRouteStandardUrl = Just updateUrl
            , actionRouteExtraAttrs = []
            }
        rowFormBody = [hsx|
            <input type="hidden" name={surfaceFieldNameFrom @Surface.ShowInactiveRosterGroups fields} value={boolParam showInactive} />
            <div class="d-flex justify-content-between align-items-center mb-2 gap-2 flex-wrap">
                <div class="d-flex align-items-center gap-2">
                    <span class="fw-semibold">Roster Group</span>
                    {renderActiveBadge rosterGroup.isActive}
                </div>
                <div class="btn-group btn-group-sm" role="group" aria-label="Reorder roster group">
                    {renderRosterGroupMoveButton (not rosterGroup.isActive || rosterGroupIndex == 0) (frontendSurfaceAction @Surface.AdminRosterGroupsSurface @Surface.MoveRosterGroupUp moveFields) (pathTo (MoveRosterGroupUpAction rosterGroup.id)) "Up"}
                    {renderRosterGroupMoveButton (not rosterGroup.isActive || rosterGroupIndex == activeCount - 1) (frontendSurfaceAction @Surface.AdminRosterGroupsSurface @Surface.MoveRosterGroupDown moveFields) (pathTo (MoveRosterGroupDownAction rosterGroup.id)) "Down"}
                </div>
            </div>
            <div class="row g-2 align-items-end">
                <div class="col-12 col-md-8">
                    <label class="form-label">Name</label>
                    <input class="form-control" type="text" name={surfaceFieldNameFrom @Surface.Name fields} value={rosterGroup.name} />
                </div>
                <div class="col-12 col-md-2">
                    <label class="form-label" for={"roster-group-active-" <> tshow rosterGroup.id}>Status</label>
                    {renderAdminActiveToggle ("roster-group-active-" <> tshow rosterGroup.id) (surfaceFieldNameFrom @Surface.IsActive fields) Nothing "admin-roster-groups-fragment" rosterGroup.isActive}
                </div>
                <div class="col-12 col-md-2">
                    <button class="btn btn-outline-secondary w-100" type="submit">Update</button>
                </div>
            </div>
        |]
        moveFields = surfaceField @Surface.ShowInactiveRosterGroups showInactive :& NoSurfaceFields

renderRosterGroupMoveButton :: Bool -> FrontendSurfaceAction -> Text -> Text -> Html
renderRosterGroupMoveButton isDisabled action actionUrl label =
    if isDisabled
        then [hsx|
            <button class="btn btn-outline-secondary" type="button" disabled={True}>{label}</button>
        |]
        else renderFrontendSurfaceActionSubmitButton action route [hsx|{label}|]
    where
        route = FrontendSurfaceActionRoute
            { actionRouteUrl = actionUrl
            , actionRouteCustomHtmx = [FrontendSurfaceCustomHtmxAttrs "closest-form-custom-htmx" [("hx-include", "closest form")]]
            , actionRouteStandardUrl = Just actionUrl
            , actionRouteExtraAttrs = [("class", "btn btn-outline-secondary")]
            }
