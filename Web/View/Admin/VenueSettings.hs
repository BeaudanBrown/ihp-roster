module Web.View.Admin.VenueSettings
    ( renderVenueSettingsSection
    ) where

import Application.Helper.WeekBoundaries (validRosterWeekStartDays)
import Web.View.Admin.Common
import Web.View.Prelude

renderVenueSettingsSection :: VenueConfig -> Html
renderVenueSettingsSection venueConfig =
    renderConfigSection
        "admin-venue-settings"
        mempty
        mempty
        [hsx|
            <div class="admin-settings-grid">
                {renderRosterEndTimesForm venueConfig}
                {renderAutoTimesheetCreationForm venueConfig}
                {renderRosterWeekStartForm venueConfig}
            </div>
        |]

renderRosterEndTimesForm :: VenueConfig -> Html
renderRosterEndTimesForm venueConfig = [hsx|
    <form method="POST"
          action={UpdateVenueConfigAction}
          class="admin-setting-row">
        <input type="hidden" name="configField" value="rosterEndTimesEnabled" />
        <div class="admin-setting-row-copy">
            <div class="fw-semibold">Roster end times</div>
            <p class="small app-muted mb-0">Require staffed shifts to have start and end times before going live.</p>
        </div>
        <div class="admin-setting-row-control">
            {renderVenueSettingToggle "venue-roster-end-times-enabled" "rosterEndTimesEnabled" venueConfig.rosterEndTimesEnabled}
        </div>
    </form>
|]

renderAutoTimesheetCreationForm :: VenueConfig -> Html
renderAutoTimesheetCreationForm venueConfig = [hsx|
    <form method="POST"
          action={UpdateVenueConfigAction}
          class="admin-setting-row">
        <input type="hidden" name="configField" value="autoTimesheetCreationEnabled" />
        <div class="admin-setting-row-copy">
            <div class="fw-semibold">Auto-create pending timesheets</div>
            <p class="small app-muted mb-0">When a live rostered shift ends, create a pending timesheet after a 2-hour grace period.</p>
        </div>
        <div class="admin-setting-row-control">
            {renderVenueSettingToggle "venue-auto-timesheet-creation-enabled" "autoTimesheetCreationEnabled" venueConfig.autoTimesheetCreationEnabled}
        </div>
    </form>
|]

renderVenueSettingToggle :: Text -> Text -> Bool -> Html
renderVenueSettingToggle inputId fieldName isEnabled =
    renderAppToggleButton $ (defaultAppToggleButtonConfig inputId isEnabled [hsx|<span class="small">{if isEnabled then ("Enabled" :: Text) else "Disabled"}</span>|])
        { appToggleInputName = Just fieldName
        , appToggleInputValue = "true"
        , appToggleButtonClass = "btn-sm"
        , appToggleRoleSwitch = True
        , appToggleOnChange = Just "this.form.requestSubmit()"
        }

renderRosterWeekStartForm :: VenueConfig -> Html
renderRosterWeekStartForm venueConfig = [hsx|
    <form method="POST"
          action={UpdateVenueConfigAction}
          class="admin-setting-row">
        <input type="hidden" name="configField" value="rosterWeekStartsOn" />
        <div class="admin-setting-row-copy">
            <div class="fw-semibold">Roster week starts on</div>
            <p class="small app-muted mb-0">Changing this is locked once roster, timesheet, availability, export, or payroll version data exists.</p>
        </div>
        <div class="admin-setting-row-control admin-setting-row-select">
            <label class="visually-hidden" for="admin-roster-week-starts-on">Roster week starts on</label>
            <select id="admin-roster-week-starts-on"
                    class="form-select form-select-sm"
                    name="rosterWeekStartsOn"
                    onchange="this.form.requestSubmit()">
                {forEach validRosterWeekStartDays (renderRosterWeekStartOption venueConfig.rosterWeekStartsOn)}
            </select>
        </div>
    </form>
|]
