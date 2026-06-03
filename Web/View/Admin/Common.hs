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

renderRowCountSummary :: HasField "isActive" record Bool => [record] -> Html
renderRowCountSummary rows = [hsx|
    <p class="small app-muted mb-3">
        {tshow (length rows)} rows total, {tshow (countActiveRows rows)} active, {tshow (length rows - countActiveRows rows)} inactive.
    </p>
|]

renderInactiveToggleSummary :: HasField "isActive" record Bool => Text -> Text -> Text -> [record] -> Bool -> Html
renderInactiveToggleSummary paramName fragmentPath targetId rows showInactive = [hsx|
    <div class="d-flex flex-wrap align-items-center justify-content-between gap-2 mb-3">
        <p class="small app-muted mb-0">
            {tshow (length rows)} rows total, {tshow activeCount} active, {tshow inactiveCount} inactive.
        </p>
        <div>
            {renderShowInactiveToggle (targetId <> "-show-inactive-toggle") targetId toggleHref showInactive}
        </div>
    </div>
|]
    where
        activeCount = countActiveRows rows
        inactiveCount = length rows - activeCount
        toggleHref = appendQueryParams fragmentPath [(paramName, if showInactive then "false" else "true")]

renderShowInactiveToggle :: Text -> Text -> Text -> Bool -> Html
renderShowInactiveToggle inputId targetId toggleHref showInactive =
    renderAppToggleButton $ (defaultAppToggleButtonConfig inputId showInactive [hsx|<span class="small">Show disabled</span>|])
        { appToggleButtonClass = "btn-sm"
        , appToggleRoleSwitch = True
        , appToggleHxGet = Just toggleHref
        , appToggleHxTarget = Just ("#" <> targetId)
        , appToggleHxSwap = Just "outerHTML"
        }

renderRosterGroupDefaultBadge :: RosterGroup -> Html
renderRosterGroupDefaultBadge rosterGroup
    | rosterGroup.isDefault = renderAppStatusBadge AppStatusInfo "Default"
    | otherwise = mempty

renderMoveButton :: Bool -> AdminController -> Text -> Text -> Html
renderMoveButton isDisabled action targetId label =
    if isDisabled
        then [hsx|
            <button class="btn btn-outline-secondary" type="button" disabled={True}>{label}</button>
        |]
        else [hsx|
            <button class="btn btn-outline-secondary"
                    type="submit"
                    formaction={action}
                    hx-post={action}
                    hx-trigger="click"
                    hx-include="closest form"
                    hx-target={"#" <> targetId}
                    hx-swap="outerHTML"
                    hx-push-url="false">{label}</button>
        |]

renderShiftTypeRuleOption :: ShiftType -> Html
renderShiftTypeRuleOption shiftType = [hsx|
    <option value={tshow (unpackId (get #id shiftType))}>{renderShiftTypeLabel shiftType}</option>
|]

renderSelectedShiftTypeRuleOption :: UUID -> ShiftType -> Html
renderSelectedShiftTypeRuleOption selectedShiftTypeId shiftType = [hsx|
    <option value={tshow (unpackId (get #id shiftType))} selected={unpackId (get #id shiftType) == selectedShiftTypeId}>{renderShiftTypeLabel shiftType}</option>
|]

renderDayNameOption :: DayName -> Html
renderDayNameOption dayName = [hsx|
    <option value={tshow (unpackId (get #id dayName))}>{renderDayNameLabel dayName}</option>
|]

renderRosterWeekStartOption :: Int -> Int -> Html
renderRosterWeekStartOption selectedWeekdayIndex weekdayIndex = [hsx|
    <option value={tshow weekdayIndex} selected={weekdayIndex == selectedWeekdayIndex}>{renderWeekdayName weekdayIndex}</option>
|]

renderSelectedDayNameOption :: UUID -> DayName -> Html
renderSelectedDayNameOption selectedDayNameId dayName = [hsx|
    <option value={tshow (unpackId (get #id dayName))} selected={unpackId (get #id dayName) == selectedDayNameId}>{renderDayNameLabel dayName}</option>
|]

renderDayNameLabel :: DayName -> Text
renderDayNameLabel dayName =
    renderWeekdayName dayName.weekdayIndex

renderShiftTypeLabel :: ShiftType -> Text
renderShiftTypeLabel shiftType =
    if shiftType.isActive
        then shiftType.name
        else shiftType.name <> " (inactive)"

renderActiveBadge :: Bool -> Html
renderActiveBadge isActive =
    if isActive
        then renderAppStatusBadge AppStatusSuccess "active"
        else renderAppStatusBadge AppStatusNeutral "inactive"

renderAdminActiveToggle :: Text -> Maybe Text -> Text -> Bool -> Html
renderAdminActiveToggle inputId maybePostPath targetId isActive = [hsx|
    {renderAppToggleButton toggleConfig}
    <input type="hidden" name="isActive" value="false" />
|]
    where
        statusLabel :: Text
        statusLabel = if isActive then "Enabled" else "Disabled"
        toggleConfig = (defaultAppToggleButtonConfig inputId isActive [hsx|<span class="small">{statusLabel}</span>|])
            { appToggleInputName = Just "isActive"
            , appToggleInputValue = "true"
            , appToggleButtonClass = "btn-sm w-100"
            , appToggleRoleSwitch = True
            , appToggleHxPost = maybePostPath
            , appToggleHxTrigger = if isJust maybePostPath then Just "change" else Nothing
            , appToggleHxInclude = if isJust maybePostPath then Just "closest form" else Nothing
            , appToggleHxTarget = if isJust maybePostPath then Just ("#" <> targetId) else Nothing
            , appToggleHxSwap = if isJust maybePostPath then Just "outerHTML" else Nothing
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

weekdayOptions :: [(Int, Text)]
weekdayOptions =
    [ (0, "Sunday")
    , (1, "Monday")
    , (2, "Tuesday")
    , (3, "Wednesday")
    , (4, "Thursday")
    , (5, "Friday")
    , (6, "Saturday")
    ]

renderWeekdayName :: Int -> Text
renderWeekdayName weekdayIndex =
    fromMaybe ("Weekday " <> tshow weekdayIndex) (lookup weekdayIndex weekdayOptions)
