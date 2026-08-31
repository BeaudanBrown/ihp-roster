module Web.View.Admin.Common where

import Application.Error.Runtime (ExternalRuntimeCategory (AuthorizedFrameworkInvariant),
                                  externalRuntimeInvariantFailure)
import Application.Helper.Controller (currentVenueOrNothing)
import Application.Helper.FrontendContract.Surface.Request.Runtime (FrontendSurfaceAction)
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            FrontendSurfaceCustomHtmxAttrs (..),
                                                            defaultFrontendSurfaceActionRoute,
                                                            renderFrontendSurfaceActionLink,
                                                            renderFrontendSurfaceActionSubmitButton)
import Web.View.Prelude

renderConfigSection :: Text -> Html -> Html -> Html -> Html
renderConfigSection anchorId summary createForm rows = [hsx|
    <div class="app-accordion-section" id={anchorId}>
        <div class="app-accordion-section-body pt-0">
            {summary}
            {createForm}
            <div class="mt-3">
                {rows}
            </div>
        </div>
    </div>
|]

formatTimestamp :: UTCTime -> Text
formatTimestamp = formatUtcTimestamp

renderAccordionItem :: Text -> Text -> Bool -> Html -> Html
renderAccordionItem sectionId title isOpen content =
    renderAppAccordionItem AppAccordionItemConfig
        { appAccordionItemId = sectionId
        , appAccordionItemParentId = "admin-config-sections"
        , appAccordionItemTitle = title
        , appAccordionItemIsOpen = isOpen
        , appAccordionItemClass = ""
        , appAccordionItemBodyClass = ""
        , appAccordionItemButtonContent = [hsx|<span class="fw-semibold">{title}</span>|]
        , appAccordionItemBody = content
        }












renderActiveBadge :: Bool -> Html
renderActiveBadge isActive =
    if isActive
        then renderAppStatusBadge AppStatusSuccess "active"
        else renderAppStatusBadge AppStatusNeutral "inactive"

renderAdminActiveToggle :: Text -> ToggleFieldBinding -> Bool -> Html
renderAdminActiveToggle inputId binding isActive =
    renderAdminActiveToggleWithPolicy inputId binding isActive ToggleSubmitDeferred

renderAdminActiveToggleImmediate :: Text -> ToggleFieldBinding -> Bool -> Html
renderAdminActiveToggleImmediate inputId binding isActive =
    renderAdminActiveToggleWithPolicy inputId binding isActive ToggleSubmitImmediate

renderAdminActiveToggleWithPolicy :: Text -> ToggleFieldBinding -> Bool -> ToggleSubmissionPolicy -> Html
renderAdminActiveToggleWithPolicy inputId binding isActive submitPolicy =
    renderAppToggleButton $
        ( defaultAppToggleStateButtonConfig
            inputId
            binding
            isActive
            [hsx|<span class="small">Enabled</span>|]
            [hsx|<span class="small">Disabled</span>|]
        )
            { appToggleButtonClass = "btn-sm w-100"
            , appToggleRoleSwitch = True
            , appToggleSubmitPolicy = submitPolicy
            }

renderEmptyState :: Text -> Html
renderEmptyState message = [hsx|<p class="app-muted mb-0">{message}</p>|]

currentAdminVenueScopeId :: (?context :: ControllerContext) => UUID
currentAdminVenueScopeId =
    case currentVenueOrNothing of
        Just venue -> unpackId venue.id
        Nothing ->
            externalRuntimeInvariantFailure
                AuthorizedFrameworkInvariant
                "Admin Surface rendering requires an authorized current venue in ControllerContext"

renderAdminInactiveSummary :: HasField "isActive" record Bool => [record] -> Bool -> FrontendSurfaceAction -> FrontendSurfaceActionRoute -> Html
renderAdminInactiveSummary rows showInactive toggleAction toggleRoute = [hsx|
    <div class="d-flex flex-wrap align-items-center justify-content-between gap-2 mb-3">
        <p class="small app-muted mb-0">
            {tshow (length rows)} rows total, {tshow activeCount} active, {tshow inactiveCount} inactive.
        </p>
        <div>
            {renderFrontendSurfaceActionLink toggleAction routeWithToggleAttrs toggleLabel}
        </div>
    </div>
|]
    where
        activeCount = countActiveRows rows
        inactiveCount = length rows - activeCount
        toggleLabel = [hsx|<span class="small">Show disabled</span>|]
        routeWithToggleAttrs = toggleRoute
            { actionRouteExtraAttrs =
                [ ("class", classes
                    [ ("btn app-toggle-button btn-sm", True)
                    , ("btn-success", showInactive)
                    , ("btn-outline-success", not showInactive)
                    ])
                , ("role", "switch")
                , ("aria-checked", if showInactive then "true" else "false")
                ]
                    <> toggleRoute.actionRouteExtraAttrs
            }

renderAdminReorderControl :: Bool -> FrontendSurfaceAction -> Text -> Text -> Html
renderAdminReorderControl isDisabled action actionUrl label =
    if isDisabled
        then [hsx|
            <button class="btn btn-outline-secondary" type="button" disabled={True}>{label}</button>
        |]
        else renderFrontendSurfaceActionSubmitButton action route [hsx|{label}|]
    where
        route = ((defaultFrontendSurfaceActionRoute actionUrl)
            { actionRouteCustomHtmx = [FrontendSurfaceCustomHtmxAttrs "closest-form-custom-htmx" [("hx-include", "closest form")]]
            , actionRouteStandardUrl = Just actionUrl
            , actionRouteExtraAttrs = [("class", "btn btn-outline-secondary")]
            })

visibleRosterGroupsForAdmin :: [RosterGroup] -> Bool -> [RosterGroup]
visibleRosterGroupsForAdmin rosterGroups showInactive =
    activeRows <> if showInactive then inactiveRows else []
    where
        activeRows = filter (.isActive) rosterGroups
        inactiveRows = filter (not . (.isActive)) rosterGroups

countActiveRows :: HasField "isActive" record Bool => [record] -> Int
countActiveRows = length . filter (.isActive)
