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
        "Venue Settings"
        "Roster-wide defaults and opt-in scheduling controls."
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
            <div class="fw-semibold">Roster end times and shift types</div>
            <p class="small app-muted mb-0">Require staffed shifts to have start time, end time, and shift type before going live.</p>
        </div>
        <div class="form-check form-switch mb-0 admin-setting-row-control">
            <input class="form-check-input"
                   type="checkbox"
                   role="switch"
                   id="venue-roster-end-times-enabled"
                   name="rosterEndTimesEnabled"
                   value="true"
                   checked={venueConfig.rosterEndTimesEnabled}
                   onchange="this.form.requestSubmit()" />
            <label class="form-check-label small" for="venue-roster-end-times-enabled">
                {if venueConfig.rosterEndTimesEnabled then ("Enabled" :: Text) else "Disabled"}
            </label>
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
        <div class="form-check form-switch mb-0 admin-setting-row-control">
            <input class="form-check-input"
                   type="checkbox"
                   role="switch"
                   id="venue-auto-timesheet-creation-enabled"
                   name="autoTimesheetCreationEnabled"
                   value="true"
                   checked={venueConfig.autoTimesheetCreationEnabled}
                   onchange="this.form.requestSubmit()" />
            <label class="form-check-label small" for="venue-auto-timesheet-creation-enabled">
                {if venueConfig.autoTimesheetCreationEnabled then ("Enabled" :: Text) else "Disabled"}
            </label>
        </div>
    </form>
|]

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
