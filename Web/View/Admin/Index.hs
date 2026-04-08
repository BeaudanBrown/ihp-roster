module Web.View.Admin.Index where

import Application.Helper.Export (ReportWeekSelection (..),
                                  VenueReportDefinition (..))
import Application.Helper.LiveUpdate (LiveUpdateScope (..))
import Data.Time.Format (defaultTimeLocale, formatTime)
import Web.View.Prelude

data IndexView = IndexView
    { latestSnapshot                  :: Maybe PayConfigSnapshot
    , recentSnapshots                 :: [PayConfigSnapshot]
    , rosterGroups                    :: [RosterGroup]
    , currentRosterGroup              :: RosterGroup
    , payLevels                       :: [PayLevel]
    , payLevelDayRules                :: [PayLevelDayRule]
    , shiftTypes                      :: [ShiftType]
    , slotNames                       :: [SlotName]
    , weekdays                        :: [DayName]
    , staffPayReportDefinition        :: Maybe VenueReportDefinition
    , hourlyBreakdownReportDefinition :: Maybe VenueReportDefinition
    , reportWeekSelection             :: ReportWeekSelection
    , invitations                     :: [VenueInvitation]
    , slotNamesLiveUpdateScope        :: Maybe LiveUpdateScope
    , invitesLiveUpdateScope          :: Maybe LiveUpdateScope
    }

instance View IndexView where
    html IndexView { .. } = [hsx|
        <div class="row g-3">
            <div class="col-12">
                {renderConfigSectionsAccordion rosterGroups currentRosterGroup payLevels shiftTypes payLevelDayRules slotNames weekdays invitations staffPayReportDefinition hourlyBreakdownReportDefinition reportWeekSelection}
            </div>
        </div>
        <div data-live-update-owner="true"
             data-live-update-feature="admin-slot-names"
             data-live-updates-path="/live-updates"
             data-live-update-content-url={appendQueryParams (pathTo ShowAdminSlotNamesFragmentAction) [("rosterGroupId", tshow currentRosterGroup.id)]}
             data-live-update-client-enabled={isJust slotNamesLiveUpdateScope}
             data-live-update-client-id=""
             data-live-update-scope-kind={liveUpdateScopeKind <$> slotNamesLiveUpdateScope}
             data-live-update-venue-id={liveUpdateVenueId <$> slotNamesLiveUpdateScope}
             data-live-update-roster-group-id={liveUpdateRosterGroupIdText =<< slotNamesLiveUpdateScope}
             hidden="hidden"></div>
        <div data-live-update-owner="true"
             data-live-update-feature="admin-invites"
             data-live-updates-path="/live-updates"
             data-live-update-content-url={appendQueryParams (pathTo ShowAdminInvitesFragmentAction) [("rosterGroupId", tshow currentRosterGroup.id)]}
             data-live-update-client-enabled={isJust invitesLiveUpdateScope}
             data-live-update-client-id=""
             data-live-update-scope-kind={liveUpdateScopeKind <$> invitesLiveUpdateScope}
             data-live-update-venue-id={liveUpdateVenueId <$> invitesLiveUpdateScope}
             hidden="hidden"></div>
    |]

renderPayLevelsSection :: [PayLevel] -> Html
renderPayLevelsSection payLevels =
    renderConfigSection
        "pay-levels"
        "Pay Levels"
        "Configure venue pay level names, rates, penalties, and day multipliers."
        (renderRowCountSummary payLevels)
        renderPayLevelCreateForm
        (if null payLevels then renderEmptyState "No pay levels yet." else forEach payLevels renderPayLevelRow)

renderShiftTypesSection :: [ShiftType] -> [PayLevel] -> Html
renderShiftTypesSection shiftTypes payLevels =
    renderConfigSection
        "shift-types"
        "Shift Types"
        "Each shift type points to a default pay level used by pay resolution and report ordering."
        (renderRowCountSummary shiftTypes)
        (renderShiftTypeCreateForm payLevels)
        (if null shiftTypes then renderEmptyState "No shift types yet." else forEach shiftTypes (renderShiftTypeRow payLevels))

renderPayLevelDayRulesSection :: [PayLevelDayRule] -> [ShiftType] -> [PayLevel] -> [DayName] -> Html
renderPayLevelDayRulesSection payLevelDayRules shiftTypes payLevels dayNames =
    renderConfigSection
        "pay-level-day-rules"
        "Pay Level Day Rules"
        "Override the effective pay level for a shift type on specific weekdays."
        (renderRuleCountSummary payLevelDayRules)
        (renderPayLevelDayRuleCreateForm shiftTypes payLevels dayNames)
        (if null payLevelDayRules then renderEmptyState "No pay overrides yet." else forEach payLevelDayRules (renderPayLevelDayRuleRow shiftTypes payLevels dayNames))

renderRosterGroupsSection :: [RosterGroup] -> RosterGroup -> Html
renderRosterGroupsSection rosterGroups currentRosterGroup =
    renderConfigSection
        "roster-groups"
        "Roster Groups"
        "Define the scheduling lanes inside this venue. Slot names below are edited for the selected roster group."
        (renderRowCountSummary rosterGroups)
        [hsx|
            <div class="mb-3">
                <div class="small text-uppercase app-muted mb-2">Selected roster group</div>
                <div class="d-flex flex-wrap gap-2">
                    {forEach rosterGroups (renderRosterGroupSelector currentRosterGroup.id)}
                </div>
            </div>
            {renderRosterGroupCreateForm}
        |]
        (if null rosterGroups then renderEmptyState "No roster groups yet." else forEach rosterGroups (renderRosterGroupRow currentRosterGroup.id))

renderSlotNamesSection :: RosterGroup -> [SlotName] -> Html
renderSlotNamesSection currentRosterGroup slotNames =
    renderConfigSection
        "slot-names"
        "Slot Names"
        ("These power the roster sheet block labels for the selected roster group: " <> currentRosterGroup.name <> ".")
        (renderRowCountSummary slotNames)
        (renderSlotNameCreateForm currentRosterGroup.id)
        (if null slotNames then renderEmptyState "No slot names yet for this roster group." else [hsx|
            <div class="d-flex flex-column gap-2">
                {forEach (zip [0 :: Int ..] slotNames) (renderSlotNameRow currentRosterGroup.id (length slotNames))}
            </div>
        |])

renderSlotNamesSectionFragment :: RosterGroup -> [SlotName] -> Html
renderSlotNamesSectionFragment currentRosterGroup slotNames = [hsx|
    <div id="admin-slot-names-fragment">
        {renderSlotNamesSection currentRosterGroup slotNames}
    </div>
|]

renderInvitesSection :: [VenueInvitation] -> Id RosterGroup -> Html
renderInvitesSection invitations rosterGroupId =
    renderConfigSection
        "invites"
        "Invites"
        "Queue an invitation immediately, track delivery status, revoke pending invites, and see when they are accepted."
        (renderInviteSummary invitations)
        (renderInviteCreateForm rosterGroupId)
        [hsx|
            {if null invitations then renderEmptyState "No invites yet." else renderInviteTable invitations rosterGroupId}
        |]

renderInviteSummary :: [VenueInvitation] -> Html
renderInviteSummary invitations = [hsx|
    <p class="small app-muted mb-3">
        {tshow activePendingCount} active pending {inviteLabel}; {tshow sentCount} sent and {tshow acceptedCount} accepted.
    </p>
|]
    where
        activePendingCount = length (filter invitationIsActivePending invitations)
        sentCount = length (filter invitationWasSent invitations)
        acceptedCount = length (filter invitationWasAccepted invitations)
        inviteLabel :: Text
        inviteLabel =
            if activePendingCount == 1
                then "invite"
                else "invites"

renderInviteCreateForm :: Id RosterGroup -> Html
renderInviteCreateForm rosterGroupId = [hsx|
    <form
        method="POST"
        action={appendQueryParams (pathTo CreateVenueInvitationAction) [("rosterGroupId", tshow rosterGroupId)]}
        class="border rounded p-3"
        data-disable-javascript-submission="true"
        hx-post={appendQueryParams (pathTo CreateVenueInvitationAction) [("rosterGroupId", tshow rosterGroupId)]}
        hx-target="#admin-invites-fragment"
        hx-swap="outerHTML"
    >
        <div class="row g-2 align-items-end">
            <div class="col-12 col-md-9">
                <label class="form-label" for="new-invite-email">Email</label>
                <input id="new-invite-email" class="form-control" type="email" name="email" placeholder="new-user@example.com" required="required" />
            </div>
            <div class="col-12 col-md-3">
                <button class="btn btn-outline-primary w-100" type="submit">Queue Invite Email</button>
            </div>
        </div>
    </form>
|]

renderInvitesSectionFragment :: [VenueInvitation] -> Id RosterGroup -> Html
renderInvitesSectionFragment invitations rosterGroupId = [hsx|
    <div id="admin-invites-fragment">
        {renderInvitesSection invitations rosterGroupId}
    </div>
|]

renderInviteTable :: [VenueInvitation] -> Id RosterGroup -> Html
renderInviteTable invitations rosterGroupId = [hsx|
    <div class="table-responsive">
        <table class="table table-striped align-middle mb-0">
            <thead>
                <tr>
                    <th>Email</th>
                    <th>Role</th>
                    <th>Status</th>
                    <th>Expires</th>
                    <th class="text-end">Actions</th>
                </tr>
            </thead>
            <tbody>
                {forEach invitations (renderInviteRow rosterGroupId)}
            </tbody>
        </table>
    </div>
|]

renderInviteRow :: Id RosterGroup -> VenueInvitation -> Html
renderInviteRow rosterGroupId invitation = [hsx|
    <tr id={inviteRowId invitation.id}>
        <td>{invitation.email}</td>
        <td>{invitationRoleLabel invitation.inviteRole}</td>
        <td>{renderInvitationStatusBadge invitation}</td>
        <td>{formatTimestamp (fromMaybe invitation.createdAt invitation.expiresAt)}</td>
        <td class="text-end">{renderInviteRowActions rosterGroupId invitation}</td>
    </tr>
|]

renderExportsSection :: Maybe VenueReportDefinition -> Maybe VenueReportDefinition -> ReportWeekSelection -> Html
renderExportsSection staffPayReportDefinition hourlyBreakdownReportDefinition reportWeekSelection =
    renderConfigSection
        "exports"
        "Exports"
        ("Generate the built-in payroll exports for the current report week: " <> tshow reportWeekSelection.weekStart <> " to " <> tshow reportWeekSelection.weekEnd <> ".")
        (renderExportSummary staffPayReportDefinition hourlyBreakdownReportDefinition)
        mempty
        [hsx|
            <div class="d-flex flex-wrap gap-2">
                {renderExportButton staffPayReportDefinition reportWeekSelection "Generate Staff Pay CSV"}
                {renderExportButton hourlyBreakdownReportDefinition reportWeekSelection "Generate Hourly Breakdown ZIP"}
                <a href={ExportJobsAction} class="btn btn-outline-secondary">Export History</a>
            </div>
        |]

renderExportSummary :: Maybe VenueReportDefinition -> Maybe VenueReportDefinition -> Html
renderExportSummary staffPayReportDefinition hourlyBreakdownReportDefinition = [hsx|
    <div class="small app-muted mb-3">
        {availableCount} of 2 built-in exports are currently available for this venue.
    </div>
|]
    where
        availableCount =
            length
                (filter
                    isJust
                    [ staffPayReportDefinition
                    , hourlyBreakdownReportDefinition
                    ]
                )

renderExportButton :: Maybe VenueReportDefinition -> ReportWeekSelection -> Text -> Html
renderExportButton maybeReportDefinition reportWeekSelection label =
    case maybeReportDefinition of
        Just reportDefinition -> [hsx|
            <form method="POST" action={CreateExportJobAction} class="d-inline" data-disable-javascript-submission="true">
                <input type="hidden" name="reportSlug" value={reportDefinition.definition.slug} />
                <input type="hidden" name="weekOffset" value={tshow reportWeekSelection.weekOffset} />
                <button class="btn btn-outline-primary" type="submit">{label}</button>
            </form>
        |]
        Nothing -> [hsx|
            <button class="btn btn-outline-secondary" type="button" disabled={True}>{label <> " unavailable"}</button>
        |]

renderConfigSectionsAccordion :: [RosterGroup] -> RosterGroup -> [PayLevel] -> [ShiftType] -> [PayLevelDayRule] -> [SlotName] -> [DayName] -> [VenueInvitation] -> Maybe VenueReportDefinition -> Maybe VenueReportDefinition -> ReportWeekSelection -> Html
renderConfigSectionsAccordion rosterGroups currentRosterGroup payLevels shiftTypes payLevelDayRules slotNames weekdays invitations staffPayReportDefinition hourlyBreakdownReportDefinition reportWeekSelection = [hsx|
    <div class="accordion admin-config-accordion" id="admin-config-sections">
        {renderAccordionItem "roster-groups" "Roster Groups" True (renderRosterGroupsSection rosterGroups currentRosterGroup)}
        {renderAccordionItem "invites" "Invites" False (renderInvitesSectionFragment invitations currentRosterGroup.id)}
        {renderAccordionItem "pay-levels" "Pay Levels" False (renderPayLevelsSection payLevels)}
        {renderAccordionItem "shift-types" "Shift Types" False (renderShiftTypesSection shiftTypes payLevels)}
        {renderAccordionItem "pay-level-day-rules" "Pay Level Day Rules" False (renderPayLevelDayRulesSection payLevelDayRules shiftTypes payLevels weekdays)}
        {renderAccordionItem "slot-names" "Slot Names" False (renderSlotNamesSectionFragment currentRosterGroup slotNames)}
        {renderAccordionItem "exports" "Exports" False (renderExportsSection staffPayReportDefinition hourlyBreakdownReportDefinition reportWeekSelection)}
    </div>
|]

inviteRowId :: Id VenueInvitation -> Text
inviteRowId invitationId = "invite-row-" <> tshow invitationId

invitationIsActivePending :: VenueInvitation -> Bool
invitationIsActivePending invitation =
    inputValue invitation.status == "pending" && not (invitationWasAccepted invitation)

invitationWasAccepted :: VenueInvitation -> Bool
invitationWasAccepted invitation = inputValue invitation.status == "accepted"

invitationWasSent :: VenueInvitation -> Bool
invitationWasSent invitation = inputValue invitation.deliveryStatus == "sent"

renderInvitationStatusBadge :: VenueInvitation -> Html
renderInvitationStatusBadge invitation = [hsx|
    <span class={badgeClass}>{label}</span>
|]
    where
        (label, badgeClass) =
            case inputValue invitation.status of
                "accepted" -> ("Accepted" :: Text, "badge text-bg-success" :: Text)
                "revoked" -> ("Revoked", "badge text-bg-secondary" :: Text)
                _ ->
                    case inputValue invitation.deliveryStatus of
                        "sent" -> ("Sent", "badge text-bg-success" :: Text)
                        "failed" -> ("Send Failed", "badge text-bg-danger" :: Text)
                        _ -> ("Queued", "badge text-bg-warning text-dark" :: Text)

renderInviteRowActions :: Id RosterGroup -> VenueInvitation -> Html
renderInviteRowActions rosterGroupId invitation
    | inputValue invitation.status /= "pending" = mempty
    | otherwise = [hsx|
        <form
            method="POST"
            action={appendQueryParams (pathTo (RevokeVenueInvitationAction invitation.id)) [("rosterGroupId", tshow rosterGroupId)]}
            class="d-inline"
            data-disable-javascript-submission="true"
            hx-post={appendQueryParams (pathTo (RevokeVenueInvitationAction invitation.id)) [("rosterGroupId", tshow rosterGroupId)]}
            hx-target="#admin-invites-fragment"
            hx-swap="outerHTML"
        >
            <button class="btn btn-sm btn-outline-danger" type="submit">Revoke</button>
        </form>
    |]

renderAccordionItem :: Text -> Text -> Bool -> Html -> Html
renderAccordionItem sectionId title isOpen content = [hsx|
    <div class="accordion-item app-panel mb-3">
        <h2 class="accordion-header" id={sectionId <> "-heading"}>
            <button
                class={accordionButtonClass isOpen}
                type="button"
                data-bs-toggle="collapse"
                data-bs-target={"#" <> sectionId <> "-collapse"}
                aria-expanded={if isOpen then ("true" :: Text) else "false"}
                aria-controls={sectionId <> "-collapse"}
            >
                {title}
            </button>
        </h2>
        <div
            id={sectionId <> "-collapse"}
            class={accordionCollapseClass isOpen}
            aria-labelledby={sectionId <> "-heading"}
            data-bs-parent="#admin-config-sections"
        >
            <div class="accordion-body p-0">
                {content}
            </div>
        </div>
    </div>
|]

renderConfigSection :: Text -> Text -> Text -> Html -> Html -> Html -> Html
renderConfigSection anchorId title description summary createForm rows = [hsx|
    <div id={anchorId} class="app-panel h-100">
        <div class="app-panel-body">
            <div class="mb-2">
                <h2 class="h5 mb-2">{title}</h2>
                <p class="app-muted mb-2">{description}</p>
            </div>
            {summary}
            {createForm}
            <div class="mt-3">
                {rows}
            </div>
        </div>
    </div>
|]

renderPayLevelCreateForm :: Html
renderPayLevelCreateForm = [hsx|
    <form method="POST" action={CreatePayLevelAction} class="border rounded p-3" data-disable-javascript-submission="true">
        <div class="row g-2 align-items-end">
            <div class="col-12 col-md-4">
                <label class="form-label" for="new-pay-level-name">Name</label>
                <input id="new-pay-level-name" class="form-control" type="text" name="name" placeholder="Level 1" />
            </div>
            <div class="col-6 col-md-2">
                <label class="form-label" for="new-pay-level-base-rate">Base Rate</label>
                <input id="new-pay-level-base-rate" class="form-control" type="number" name="baseRate" step="0.01" value="0" />
            </div>
            <div class="col-6 col-md-2">
                <label class="form-label" for="new-pay-level-evening-penalty">Evening Penalty</label>
                <input id="new-pay-level-evening-penalty" class="form-control" type="number" name="eveningPenalty" step="0.01" value="0" />
            </div>
            <div class="col-6 col-md-2">
                <label class="form-label" for="new-pay-level-after12-penalty">After 12 Penalty</label>
                <input id="new-pay-level-after12-penalty" class="form-control" type="number" name="after12Penalty" step="0.01" value="0" />
            </div>
            <div class="col-6 col-md-2">
                <label class="form-label" for="new-pay-level-active">Status</label>
                <select id="new-pay-level-active" class="form-select" name="isActive">
                    <option value="true" selected={True}>Active</option>
                    <option value="false">Inactive</option>
                </select>
            </div>
            <div class="col-4 col-md-2">
                <label class="form-label" for="new-pay-level-weekday-multiplier">Weekday Mult</label>
                <input id="new-pay-level-weekday-multiplier" class="form-control" type="number" name="weekdayMultiplier" step="0.001" value="1" />
            </div>
            <div class="col-4 col-md-2">
                <label class="form-label" for="new-pay-level-saturday-multiplier">Saturday Mult</label>
                <input id="new-pay-level-saturday-multiplier" class="form-control" type="number" name="saturdayMultiplier" step="0.001" value="1" />
            </div>
            <div class="col-4 col-md-2">
                <label class="form-label" for="new-pay-level-sunday-multiplier">Sunday Mult</label>
                <input id="new-pay-level-sunday-multiplier" class="form-control" type="number" name="sundayMultiplier" step="0.001" value="1" />
            </div>
            <div class="col-12 col-md-2">
                <button class="btn btn-outline-primary w-100" type="submit">Add Pay Level</button>
            </div>
        </div>
    </form>
|]

renderPayLevelRow :: PayLevel -> Html
renderPayLevelRow payLevel = [hsx|
    <form method="POST" action={UpdatePayLevelAction (get #id payLevel)} class="border rounded p-3 mb-2" data-disable-javascript-submission="true">
        <div class="d-flex justify-content-between align-items-center mb-2">
            <span class="fw-semibold">Pay Level</span>
            {renderActiveBadge payLevel.isActive}
        </div>
        <div class="row g-2 align-items-end">
            <div class="col-12 col-md-4">
                <label class="form-label">Name</label>
                <input class="form-control" type="text" name="name" value={payLevel.name} />
            </div>
            <div class="col-6 col-md-2">
                <label class="form-label">Base Rate</label>
                <input class="form-control" type="number" name="baseRate" step="0.01" value={tshow payLevel.baseRate} />
            </div>
            <div class="col-6 col-md-2">
                <label class="form-label">Evening Penalty</label>
                <input class="form-control" type="number" name="eveningPenalty" step="0.01" value={tshow payLevel.eveningPenalty} />
            </div>
            <div class="col-6 col-md-2">
                <label class="form-label">After 12 Penalty</label>
                <input class="form-control" type="number" name="after12Penalty" step="0.01" value={tshow payLevel.after12Penalty} />
            </div>
            <div class="col-6 col-md-2">
                <label class="form-label">Status</label>
                <select class="form-select" name="isActive">
                    <option value="true" selected={payLevel.isActive}>Active</option>
                    <option value="false" selected={not payLevel.isActive}>Inactive</option>
                </select>
            </div>
            <div class="col-4 col-md-2">
                <label class="form-label">Weekday Mult</label>
                <input class="form-control" type="number" name="weekdayMultiplier" step="0.001" value={tshow payLevel.weekdayMultiplier} />
            </div>
            <div class="col-4 col-md-2">
                <label class="form-label">Saturday Mult</label>
                <input class="form-control" type="number" name="saturdayMultiplier" step="0.001" value={tshow payLevel.saturdayMultiplier} />
            </div>
            <div class="col-4 col-md-2">
                <label class="form-label">Sunday Mult</label>
                <input class="form-control" type="number" name="sundayMultiplier" step="0.001" value={tshow payLevel.sundayMultiplier} />
            </div>
            <div class="col-12 col-md-2">
                <button class="btn btn-outline-secondary w-100" type="submit">Update</button>
            </div>
        </div>
    </form>
|]

renderShiftTypeCreateForm :: [PayLevel] -> Html
renderShiftTypeCreateForm payLevels
    | null payLevels = [hsx|
        <div class="alert alert-warning mb-0">
            Add a pay level before creating shift types.
        </div>
    |]
    | otherwise = [hsx|
        <form method="POST" action={CreateShiftTypeAction} class="border rounded p-3" data-disable-javascript-submission="true">
            <div class="row g-2 align-items-end">
                <div class="col-12 col-md-4">
                    <label class="form-label" for="new-shift-type-name">Name</label>
                    <input id="new-shift-type-name" class="form-control" type="text" name="name" placeholder="Standard Shift" />
                </div>
                <div class="col-12 col-md-2">
                    <label class="form-label" for="new-shift-type-sort-order">Sort Order</label>
                    <input id="new-shift-type-sort-order" class="form-control" type="number" name="sortOrder" value="0" />
                </div>
                <div class="col-12 col-md-3">
                    <label class="form-label" for="new-shift-type-pay-level">Default Pay Level</label>
                    <select id="new-shift-type-pay-level" class="form-select" name="defaultPayLevelId">
                        {forEach payLevels renderPayLevelOption}
                    </select>
                </div>
                <div class="col-12 col-md-2">
                    <label class="form-label" for="new-shift-type-active">Status</label>
                    <select id="new-shift-type-active" class="form-select" name="isActive">
                        <option value="true" selected={True}>Active</option>
                        <option value="false">Inactive</option>
                    </select>
                </div>
                <div class="col-12 col-md-2">
                    <button class="btn btn-outline-primary w-100" type="submit">Add</button>
                </div>
            </div>
        </form>
    |]

renderShiftTypeRow :: [PayLevel] -> ShiftType -> Html
renderShiftTypeRow payLevels shiftType = [hsx|
    <form method="POST" action={UpdateShiftTypeAction (get #id shiftType)} class="border rounded p-3 mb-2" data-disable-javascript-submission="true">
        <div class="d-flex justify-content-between align-items-center mb-2">
            <span class="fw-semibold">Shift Type</span>
            {renderActiveBadge shiftType.isActive}
        </div>
        <div class="row g-2 align-items-end">
            <div class="col-12 col-md-4">
                <label class="form-label">Name</label>
                <input class="form-control" type="text" name="name" value={shiftType.name} />
            </div>
            <div class="col-12 col-md-2">
                <label class="form-label">Sort Order</label>
                <input class="form-control" type="number" name="sortOrder" value={tshow shiftType.sortOrder} />
            </div>
            <div class="col-12 col-md-3">
                <label class="form-label">Default Pay Level</label>
                <select class="form-select" name="defaultPayLevelId">
                    {forEach payLevels (renderSelectedPayLevelOption shiftType.defaultPayLevelId)}
                </select>
            </div>
            <div class="col-12 col-md-2">
                <label class="form-label">Status</label>
                <select class="form-select" name="isActive">
                    <option value="true" selected={shiftType.isActive}>Active</option>
                    <option value="false" selected={not shiftType.isActive}>Inactive</option>
                </select>
            </div>
            <div class="col-12 col-md-2">
                <button class="btn btn-outline-secondary w-100" type="submit">Update</button>
            </div>
        </div>
    </form>
|]

renderPayLevelDayRuleCreateForm :: [ShiftType] -> [PayLevel] -> [DayName] -> Html
renderPayLevelDayRuleCreateForm shiftTypes payLevels dayNames
    | null shiftTypes || null payLevels || null dayNames = [hsx|
        <div class="alert alert-warning mb-0">
            Add at least one shift type, pay level, and day name before creating pay overrides.
        </div>
    |]
    | otherwise = [hsx|
        <form method="POST" action={CreatePayLevelDayRuleAction} class="border rounded p-3" data-disable-javascript-submission="true">
            <div class="row g-2 align-items-end">
                <div class="col-12 col-md-4">
                    <label class="form-label" for="new-day-rule-shift-type">Shift Type</label>
                    <select id="new-day-rule-shift-type" class="form-select" name="shiftTypeId">
                        {forEach shiftTypes renderShiftTypeRuleOption}
                    </select>
                </div>
                <div class="col-12 col-md-3">
                    <label class="form-label" for="new-day-rule-day-name">Day Name</label>
                    <select id="new-day-rule-day-name" class="form-select" name="dayNameId">
                        {forEach dayNames renderDayNameOption}
                    </select>
                </div>
                <div class="col-12 col-md-3">
                    <label class="form-label" for="new-day-rule-pay-level">Pay Level</label>
                    <select id="new-day-rule-pay-level" class="form-select" name="payLevelId">
                        {forEach payLevels renderPayLevelOption}
                    </select>
                </div>
                <div class="col-12 col-md-2">
                    <button class="btn btn-outline-primary w-100" type="submit">Add</button>
                </div>
            </div>
        </form>
    |]

renderPayLevelDayRuleRow :: [ShiftType] -> [PayLevel] -> [DayName] -> PayLevelDayRule -> Html
renderPayLevelDayRuleRow shiftTypes payLevels dayNames payLevelDayRule = [hsx|
    <form method="POST" action={UpdatePayLevelDayRuleAction (get #id payLevelDayRule)} class="border rounded p-3 mb-2" data-disable-javascript-submission="true">
        <div class="d-flex justify-content-between align-items-center mb-2">
            <span class="fw-semibold">{renderPayLevelDayRuleHeading shiftTypes payLevels dayNames payLevelDayRule}</span>
            <span class="badge text-bg-info">override</span>
        </div>
        <div class="row g-2 align-items-end">
            <div class="col-12 col-md-4">
                <label class="form-label">Shift Type</label>
                <select class="form-select" name="shiftTypeId">
                    {forEach shiftTypes (renderSelectedShiftTypeRuleOption payLevelDayRule.shiftTypeId)}
                </select>
            </div>
            <div class="col-12 col-md-3">
                <label class="form-label">Day Name</label>
                <select class="form-select" name="dayNameId">
                    {forEach dayNames (renderSelectedDayNameOption payLevelDayRule.dayNameId)}
                </select>
            </div>
            <div class="col-12 col-md-3">
                <label class="form-label">Pay Level</label>
                <select class="form-select" name="payLevelId">
                    {forEach payLevels (renderSelectedPayLevelOption payLevelDayRule.payLevelId)}
                </select>
            </div>
            <div class="col-12 col-md-2">
                <button class="btn btn-outline-secondary w-100" type="submit">Update</button>
            </div>
        </div>
    </form>
|]

renderRosterGroupCreateForm :: Html
renderRosterGroupCreateForm = [hsx|
    <form method="POST" action={CreateRosterGroupAction} class="border rounded p-3" data-disable-javascript-submission="true">
        <div class="row g-2 align-items-end">
            <div class="col-12 col-md-5">
                <label class="form-label" for="new-roster-group-name">Name</label>
                <input id="new-roster-group-name" class="form-control" type="text" name="name" placeholder="Front of House" />
            </div>
            <div class="col-12 col-md-3">
                <label class="form-label" for="new-roster-group-sort-order">Sort Order</label>
                <input id="new-roster-group-sort-order" class="form-control" type="number" name="sortOrder" value="0" />
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

renderRosterGroupRow :: Id RosterGroup -> RosterGroup -> Html
renderRosterGroupRow currentRosterGroupId rosterGroup = [hsx|
    <form method="POST" action={appendQueryParams (pathTo (UpdateRosterGroupAction (get #id rosterGroup))) [("rosterGroupId", tshow rosterGroup.id)]} class="border rounded p-3 mb-2" data-disable-javascript-submission="true">
        <div class="d-flex justify-content-between align-items-center mb-2 gap-2 flex-wrap">
            <div class="d-flex align-items-center gap-2">
                <span class="fw-semibold">Roster Group</span>
                {renderActiveBadge rosterGroup.isActive}
                {renderRosterGroupDefaultBadge rosterGroup}
                {renderRosterGroupSelectedBadge currentRosterGroupId rosterGroup}
            </div>
            {renderRosterGroupDefaultControl rosterGroup}
        </div>
        <div class="row g-2 align-items-end">
            <div class="col-12 col-md-5">
                <label class="form-label">Name</label>
                <input class="form-control" type="text" name="name" value={rosterGroup.name} />
            </div>
            <div class="col-12 col-md-3">
                <label class="form-label">Sort Order</label>
                <input class="form-control" type="number" name="sortOrder" value={tshow rosterGroup.sortOrder} />
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
|]

renderSlotNameCreateForm :: Id RosterGroup -> Html
renderSlotNameCreateForm rosterGroupId = [hsx|
    <form method="POST"
          action={appendQueryParams (pathTo CreateSlotNameAction) [("rosterGroupId", tshow rosterGroupId)]}
          class="border rounded p-3"
          data-disable-javascript-submission="true"
          hx-post={appendQueryParams (pathTo CreateSlotNameAction) [("rosterGroupId", tshow rosterGroupId)]}
          hx-target="#admin-slot-names-fragment"
          hx-swap="outerHTML">
        <div class="row g-2 align-items-end">
            <div class="col-12 col-md-8">
                <label class="form-label" for="new-slot-name">Name</label>
                <input id="new-slot-name" class="form-control" type="text" name="name" placeholder="Early" />
            </div>
            <div class="col-12 col-md-4">
                <button class="btn btn-outline-primary w-100" type="submit">Add Slot</button>
            </div>
        </div>
    </form>
|]

renderSlotNameRow :: Id RosterGroup -> Int -> (Int, SlotName) -> Html
renderSlotNameRow rosterGroupId slotCount (slotIndex, slotName) = [hsx|
    <div class="border rounded p-2">
        <div class="d-flex flex-column flex-md-row gap-2 align-items-stretch align-items-md-center">
            <div class="btn-group" role="group" aria-label="Reorder slot">
                {renderSlotMoveButton (slotIndex == 0) (appendQueryParams (pathTo (MoveSlotNameUpAction (get #id slotName))) [("rosterGroupId", tshow rosterGroupId)]) "Up"}
                {renderSlotMoveButton (slotIndex == slotCount - 1) (appendQueryParams (pathTo (MoveSlotNameDownAction (get #id slotName))) [("rosterGroupId", tshow rosterGroupId)]) "Down"}
            </div>
            <form class="m-0 flex-grow-1" data-disable-javascript-submission="true">
                <input class="form-control"
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
                  class="m-0"
                  data-disable-javascript-submission="true"
                  hx-delete={appendQueryParams (pathTo (DeleteSlotNameAction (get #id slotName))) [("rosterGroupId", tshow rosterGroupId)]}
                  hx-target="#admin-slot-names-fragment"
                  hx-swap="outerHTML">
                <input type="hidden" name="_method" value="DELETE" />
                <button class="btn btn-outline-danger" type="submit">Delete</button>
            </form>
        </div>
    </div>
|]

renderSlotMoveButton :: Bool -> Text -> Text -> Html
renderSlotMoveButton isDisabled action label =
    if isDisabled
        then [hsx|
            <button class="btn btn-outline-secondary" type="button" disabled={True}>{label}</button>
        |]
        else [hsx|
            <form method="POST"
                  action={action}
                  class="m-0"
                  data-disable-javascript-submission="true"
                  hx-post={action}
                  hx-target="#admin-slot-names-fragment"
                  hx-swap="outerHTML">
                <button class="btn btn-outline-secondary" type="submit">{label}</button>
            </form>
        |]

renderSnapshotSummary :: Maybe PayConfigSnapshot -> Html
renderSnapshotSummary maybeSnapshot =
    case maybeSnapshot of
        Nothing -> [hsx|
            <div class="alert alert-warning mb-0">
                No pay/config snapshots exist yet. The first one will be created automatically when payroll-relevant config is saved or when payroll flow first requires it.
            </div>
        |]
        Just snapshot -> [hsx|
            <div class="border rounded p-3">
                <div class="fw-semibold">Active snapshot: {snapshot.versionLabel}</div>
                <div class="small app-muted">Saved {formatTimestamp snapshot.createdAt}</div>
                <div class="small app-muted">Approvals and exports use the snapshot version they were bound to at approval or generation time.</div>
            </div>
        |]

renderConfigTableCard :: HasField "isActive" record Bool => Text -> Text -> [record] -> Html
renderConfigTableCard title anchorId rows = [hsx|
    <div class="col-12 col-md-6 col-xl-4">
        <a href={"#" <> anchorId} class="text-decoration-none">
            <div class="border rounded p-3 h-100">
                <div class="fw-semibold text-body">{title}</div>
                <div class="small app-muted">{tshow (length rows)} rows</div>
                <div class="small app-muted">{tshow (countActiveRows rows)} active</div>
            </div>
        </a>
    </div>
|]

renderCountTableCard :: Text -> Text -> [record] -> Html
renderCountTableCard title anchorId rows = [hsx|
    <div class="col-12 col-md-6 col-xl-4">
        <a href={"#" <> anchorId} class="text-decoration-none">
            <div class="border rounded p-3 h-100">
                <div class="fw-semibold text-body">{title}</div>
                <div class="small app-muted">{tshow (length rows)} rows</div>
            </div>
        </a>
    </div>
|]

renderRowCountSummary :: HasField "isActive" record Bool => [record] -> Html
renderRowCountSummary rows = [hsx|
    <p class="small app-muted mb-3">
        {tshow (length rows)} rows total, {tshow (countActiveRows rows)} active, {tshow (length rows - countActiveRows rows)} inactive.
    </p>
|]

renderRuleCountSummary :: [PayLevelDayRule] -> Html
renderRuleCountSummary rules = [hsx|
    <p class="small app-muted mb-3">
        {tshow (length rules)} shift-type weekday overrides configured for this venue.
    </p>
|]

renderSnapshotTable :: [PayConfigSnapshot] -> Html
renderSnapshotTable snapshots
    | null snapshots = [hsx|<p class="app-muted mb-0">No saved versions yet.</p>|]
    | otherwise = [hsx|
        <div class="table-responsive">
            <table class="table table-striped align-middle mb-0">
                <thead>
                    <tr>
                        <th>Version</th>
                        <th>Saved At</th>
                    </tr>
                </thead>
                <tbody>
                    {forEach snapshots renderSnapshotRow}
                </tbody>
            </table>
        </div>
    |]

renderSnapshotRow :: PayConfigSnapshot -> Html
renderSnapshotRow snapshot = [hsx|
    <tr>
        <td>{snapshot.versionLabel}</td>
        <td>{formatTimestamp snapshot.createdAt}</td>
    </tr>
|]

renderRosterGroupSelector :: Id RosterGroup -> RosterGroup -> Html
renderRosterGroupSelector selectedRosterGroupId rosterGroup = [hsx|
    <a
        href={appendQueryParams (pathTo AdminAction) [("rosterGroupId", tshow rosterGroup.id)]}
        class={rosterGroupSelectorClass selectedRosterGroupId rosterGroup}
    >
        {rosterGroup.name}
    </a>
|]

renderRosterGroupDefaultBadge :: RosterGroup -> Html
renderRosterGroupDefaultBadge rosterGroup
    | rosterGroup.isDefault = [hsx|<span class="badge text-bg-primary">Default</span>|]
    | otherwise = mempty

renderRosterGroupSelectedBadge :: Id RosterGroup -> RosterGroup -> Html
renderRosterGroupSelectedBadge selectedRosterGroupId rosterGroup
    | rosterGroup.id == selectedRosterGroupId = [hsx|<span class="badge text-bg-light">Selected</span>|]
    | otherwise = mempty

renderRosterGroupDefaultControl :: RosterGroup -> Html
renderRosterGroupDefaultControl rosterGroup
    | rosterGroup.isDefault = [hsx|<span class="small app-muted">Used for default roster navigation.</span>|]
    | otherwise = [hsx|
        <button class="btn btn-sm btn-outline-primary" type="submit" formaction={appendQueryParams (pathTo (MakeDefaultRosterGroupAction rosterGroup.id)) [("rosterGroupId", tshow rosterGroup.id)]}>Make Default</button>
    |]

rosterGroupSelectorClass :: Id RosterGroup -> RosterGroup -> Text
rosterGroupSelectorClass selectedRosterGroupId rosterGroup =
    if rosterGroup.id == selectedRosterGroupId
        then "btn btn-sm btn-primary"
        else "btn btn-sm btn-outline-secondary"

renderPayLevelOption :: PayLevel -> Html
renderPayLevelOption payLevel = [hsx|
    <option value={tshow (unpackId (get #id payLevel))}>{renderPayLevelLabel payLevel}</option>
|]

renderSelectedPayLevelOption :: UUID -> PayLevel -> Html
renderSelectedPayLevelOption selectedPayLevelId payLevel = [hsx|
    <option value={tshow (unpackId (get #id payLevel))} selected={unpackId (get #id payLevel) == selectedPayLevelId}>{renderPayLevelLabel payLevel}</option>
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

renderSelectedDayNameOption :: UUID -> DayName -> Html
renderSelectedDayNameOption selectedDayNameId dayName = [hsx|
    <option value={tshow (unpackId (get #id dayName))} selected={unpackId (get #id dayName) == selectedDayNameId}>{renderDayNameLabel dayName}</option>
|]

renderPayLevelLabel :: PayLevel -> Text
renderPayLevelLabel payLevel =
    if payLevel.isActive
        then payLevel.name
        else payLevel.name <> " (inactive)"

renderDayNameLabel :: DayName -> Text
renderDayNameLabel dayName =
    renderWeekdayName dayName.weekdayIndex

renderPayLevelDayRuleHeading :: [ShiftType] -> [PayLevel] -> [DayName] -> PayLevelDayRule -> Text
renderPayLevelDayRuleHeading shiftTypes payLevels dayNames payLevelDayRule =
    shiftTypeLabel <> " -> " <> payLevelLabel <> " on " <> dayNameLabel
    where
        shiftTypeLabel = maybe "Unknown shift type" renderShiftTypeLabel (find (\shiftType -> unpackId (get #id shiftType) == payLevelDayRule.shiftTypeId) shiftTypes)
        payLevelLabel = maybe "Unknown pay level" renderPayLevelLabel (find (\payLevel -> unpackId (get #id payLevel) == payLevelDayRule.payLevelId) payLevels)
        dayNameLabel = maybe "Unknown day name" renderDayNameLabel (find (\dayName -> unpackId (get #id dayName) == payLevelDayRule.dayNameId) dayNames)

renderShiftTypeLabel :: ShiftType -> Text
renderShiftTypeLabel shiftType =
    if shiftType.isActive
        then shiftType.name
        else shiftType.name <> " (inactive)"

renderActiveBadge :: Bool -> Html
renderActiveBadge isActive =
    if isActive
        then [hsx|<span class="badge text-bg-success">active</span>|]
        else [hsx|<span class="badge text-bg-secondary">inactive</span>|]

accordionButtonClass :: Bool -> Text
accordionButtonClass isOpen =
    if isOpen
        then "accordion-button"
        else "accordion-button collapsed"

accordionCollapseClass :: Bool -> Text
accordionCollapseClass isOpen =
    if isOpen
        then "accordion-collapse collapse show"
        else "accordion-collapse collapse"

renderEmptyState :: Text -> Html
renderEmptyState message = [hsx|<p class="app-muted mb-0">{message}</p>|]

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

liveUpdateScopeKind :: LiveUpdateScope -> Text
liveUpdateScopeKind RosterWeekScope {}        = "roster_week"
liveUpdateScopeKind RosterGroupConfigScope {} = "roster_group_config"
liveUpdateScopeKind AdminSlotNamesScope {}    = "admin_slot_names"
liveUpdateScopeKind AdminInvitesScope {}      = "admin_invites"
liveUpdateScopeKind LeaveRequestsScope {}     = "leave_requests"
liveUpdateScopeKind TimesheetWeekScope {}     = "timesheet_week"

liveUpdateVenueId :: LiveUpdateScope -> Text
liveUpdateVenueId RosterWeekScope { venueId }        = tshow venueId
liveUpdateVenueId RosterGroupConfigScope { venueId } = tshow venueId
liveUpdateVenueId AdminSlotNamesScope { venueId }    = tshow venueId
liveUpdateVenueId AdminInvitesScope { venueId }      = tshow venueId
liveUpdateVenueId LeaveRequestsScope { venueId }     = tshow venueId
liveUpdateVenueId TimesheetWeekScope { venueId }     = tshow venueId

liveUpdateRosterGroupIdText :: LiveUpdateScope -> Maybe Text
liveUpdateRosterGroupIdText RosterWeekScope { rosterGroupId }        = Just (tshow rosterGroupId)
liveUpdateRosterGroupIdText RosterGroupConfigScope { rosterGroupId } = Just (tshow rosterGroupId)
liveUpdateRosterGroupIdText AdminSlotNamesScope { rosterGroupId }    = Just (tshow rosterGroupId)
liveUpdateRosterGroupIdText AdminInvitesScope {}                     = Nothing
liveUpdateRosterGroupIdText LeaveRequestsScope {}                    = Nothing
liveUpdateRosterGroupIdText TimesheetWeekScope {}                    = Nothing

formatTimestamp :: UTCTime -> Text
formatTimestamp = cs . formatTime defaultTimeLocale "%Y-%m-%d %H:%M UTC"

invitationRoleLabel :: InputValue value => value -> Text
invitationRoleLabel value =
    case inputValue value of
        "venue_owner" -> "Venue Owner"
        "venue_admin" -> "Venue Admin"
        "manager" -> "Manager"
        _ -> "Worker"
