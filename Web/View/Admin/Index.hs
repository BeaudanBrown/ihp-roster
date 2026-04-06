module Web.View.Admin.Index where

import Data.Time.Format (defaultTimeLocale, formatTime)
import Web.View.Prelude

data IndexView = IndexView
    { latestSnapshot   :: Maybe PayConfigSnapshot
    , recentSnapshots  :: [PayConfigSnapshot]
    , rosterGroups     :: [RosterGroup]
    , currentRosterGroup :: RosterGroup
    , payLevels        :: [PayLevel]
    , payLevelDayRules :: [PayLevelDayRule]
    , shiftTypes       :: [ShiftType]
    , slotNames        :: [SlotName]
    , dayNames         :: [DayName]
    }

instance View IndexView where
    html IndexView { .. } = [hsx|
        <div class="row g-3">
            <div class="col-12 col-xl-8">
                {renderConfigSectionsAccordion rosterGroups currentRosterGroup payLevels shiftTypes payLevelDayRules slotNames dayNames}
            </div>
            <div class="col-12 col-xl-4">
                <div class="app-panel mb-3">
                    <div class="app-panel-body">
                        <h2 class="h5 mb-2">Pay/Config Snapshots</h2>
                        <p class="app-muted mb-3">
                            Payroll-relevant config changes are versioned automatically so approvals and exports remain historically explainable.
                        </p>
                        <div class="small app-muted mb-3">
                            Historical approvals and exports stay pinned to the snapshot version they were bound to when the work happened.
                        </div>
                        {renderSnapshotSummary latestSnapshot}
                    </div>
                </div>
                <div class="app-panel">
                    <div class="app-panel-body">
                        <h2 class="h5 mb-2">Exports</h2>
                        <p class="app-muted mb-3">
                            Generate approved-timesheet CSV exports with explicit scope, expiry, and audit logging.
                        </p>
                        <a href={ExportJobsAction} class="btn btn-primary">Manage Exports</a>
                    </div>
                </div>
            </div>
            <div class="col-12">
                <div class="app-panel">
                    <div class="app-panel-body">
                        <h2 class="h5 mb-3">Recent Versions</h2>
                        {renderSnapshotTable recentSnapshots}
                    </div>
                </div>
            </div>
        </div>
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
        (if null slotNames then renderEmptyState "No slot names yet for this roster group." else forEach slotNames (renderSlotNameRow currentRosterGroup.id))

renderDayNamesSection :: [DayName] -> Html
renderDayNamesSection dayNames =
    renderConfigSection
        "day-names"
        "Day Names"
        "Weekday labels can be customised per venue and toggled active/inactive."
        (renderRowCountSummary dayNames)
        renderDayNameCreateForm
        (if null dayNames then renderEmptyState "No day names yet." else forEach dayNames renderDayNameRow)

renderConfigSectionsAccordion :: [RosterGroup] -> RosterGroup -> [PayLevel] -> [ShiftType] -> [PayLevelDayRule] -> [SlotName] -> [DayName] -> Html
renderConfigSectionsAccordion rosterGroups currentRosterGroup payLevels shiftTypes payLevelDayRules slotNames dayNames = [hsx|
    <div class="accordion admin-config-accordion" id="admin-config-sections">
        {renderAccordionItem "roster-groups" "Roster Groups" True (renderRosterGroupsSection rosterGroups currentRosterGroup)}
        {renderAccordionItem "pay-levels" "Pay Levels" False (renderPayLevelsSection payLevels)}
        {renderAccordionItem "shift-types" "Shift Types" False (renderShiftTypesSection shiftTypes payLevels)}
        {renderAccordionItem "pay-level-day-rules" "Pay Level Day Rules" False (renderPayLevelDayRulesSection payLevelDayRules shiftTypes payLevels dayNames)}
        {renderAccordionItem "slot-names" "Slot Names" False (renderSlotNamesSection currentRosterGroup slotNames)}
        {renderAccordionItem "day-names" "Day Names" False (renderDayNamesSection dayNames)}
    </div>
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
    <form method="POST" action={appendQueryParams (pathTo CreateSlotNameAction) [("rosterGroupId", tshow rosterGroupId)]} class="border rounded p-3" data-disable-javascript-submission="true">
        <div class="row g-2 align-items-end">
            <div class="col-12 col-md-6">
                <label class="form-label" for="new-slot-name">Name</label>
                <input id="new-slot-name" class="form-control" type="text" name="name" placeholder="Early" />
            </div>
            <div class="col-12 col-md-3">
                <label class="form-label" for="new-slot-active">Status</label>
                <select id="new-slot-active" class="form-select" name="isActive">
                    <option value="true" selected={True}>Active</option>
                    <option value="false">Inactive</option>
                </select>
            </div>
            <div class="col-12 col-md-3">
                <button class="btn btn-outline-primary w-100" type="submit">Add Slot</button>
            </div>
        </div>
    </form>
|]

renderSlotNameRow :: Id RosterGroup -> SlotName -> Html
renderSlotNameRow rosterGroupId slotName = [hsx|
    <form method="POST" action={appendQueryParams (pathTo (UpdateSlotNameAction (get #id slotName))) [("rosterGroupId", tshow rosterGroupId)]} class="border rounded p-3 mb-2" data-disable-javascript-submission="true">
        <div class="d-flex justify-content-between align-items-center mb-2">
            <span class="fw-semibold">Slot Name</span>
            {renderActiveBadge slotName.isActive}
        </div>
        <div class="row g-2 align-items-end">
            <div class="col-12 col-md-6">
                <label class="form-label">Name</label>
                <input class="form-control" type="text" name="name" value={slotName.name} />
            </div>
            <div class="col-12 col-md-3">
                <label class="form-label">Status</label>
                <select class="form-select" name="isActive">
                    <option value="true" selected={slotName.isActive}>Active</option>
                    <option value="false" selected={not slotName.isActive}>Inactive</option>
                </select>
            </div>
            <div class="col-12 col-md-3">
                <button class="btn btn-outline-secondary w-100" type="submit">Update</button>
            </div>
        </div>
    </form>
|]

renderDayNameCreateForm :: Html
renderDayNameCreateForm = [hsx|
    <form method="POST" action={CreateDayNameAction} class="border rounded p-3" data-disable-javascript-submission="true">
        <div class="row g-2 align-items-end">
            <div class="col-12 col-md-4">
                <label class="form-label" for="new-day-weekday">Weekday</label>
                <select id="new-day-weekday" class="form-select" name="weekdayIndex">
                    {forEach weekdayOptions renderWeekdayOption}
                </select>
            </div>
            <div class="col-12 col-md-4">
                <label class="form-label" for="new-day-name">Name</label>
                <input id="new-day-name" class="form-control" type="text" name="name" placeholder="Monday" />
            </div>
            <div class="col-12 col-md-2">
                <label class="form-label" for="new-day-active">Status</label>
                <select id="new-day-active" class="form-select" name="isActive">
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

renderDayNameRow :: DayName -> Html
renderDayNameRow dayName = [hsx|
    <form method="POST" action={UpdateDayNameAction (get #id dayName)} class="border rounded p-3 mb-2" data-disable-javascript-submission="true">
        <div class="d-flex justify-content-between align-items-center mb-2">
            <span class="fw-semibold">Day Name</span>
            {renderActiveBadge dayName.isActive}
        </div>
        <div class="row g-2 align-items-end">
            <div class="col-12 col-md-4">
                <label class="form-label">Weekday</label>
                <select class="form-select" name="weekdayIndex">
                    {forEach weekdayOptions (renderSelectedWeekdayOption dayName.weekdayIndex)}
                </select>
            </div>
            <div class="col-12 col-md-4">
                <label class="form-label">Name</label>
                <input class="form-control" type="text" name="name" value={dayName.name} />
            </div>
            <div class="col-12 col-md-2">
                <label class="form-label">Status</label>
                <select class="form-select" name="isActive">
                    <option value="true" selected={dayName.isActive}>Active</option>
                    <option value="false" selected={not dayName.isActive}>Inactive</option>
                </select>
            </div>
            <div class="col-12 col-md-2">
                <button class="btn btn-outline-secondary w-100" type="submit">Update</button>
            </div>
        </div>
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

renderWeekdayOption :: (Int, Text) -> Html
renderWeekdayOption (weekdayIndex, label) = [hsx|
    <option value={tshow weekdayIndex}>{label}</option>
|]

renderSelectedWeekdayOption :: Int -> (Int, Text) -> Html
renderSelectedWeekdayOption selectedWeekdayIndex (weekdayIndex, label) = [hsx|
    <option value={tshow weekdayIndex} selected={weekdayIndex == selectedWeekdayIndex}>{label}</option>
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
    let baseLabel = dayName.name <> " (" <> renderWeekdayName dayName.weekdayIndex <> ")"
     in if dayName.isActive
            then baseLabel
            else baseLabel <> " (inactive)"

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

formatTimestamp :: UTCTime -> Text
formatTimestamp = cs . formatTime defaultTimeLocale "%Y-%m-%d %H:%M UTC"
