module Web.View.Admin.Common where

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

visibleRosterGroupsForAdmin :: [RosterGroup] -> Bool -> [RosterGroup]
visibleRosterGroupsForAdmin rosterGroups showInactive =
    activeRows <> if showInactive then inactiveRows else []
    where
        activeRows = filter (.isActive) rosterGroups
        inactiveRows = filter (not . (.isActive)) rosterGroups

countActiveRows :: HasField "isActive" record Bool => [record] -> Int
countActiveRows = length . filter (.isActive)
