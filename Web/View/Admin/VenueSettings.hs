{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.View.Admin.VenueSettings
    ( AdminVenueSettingsLiveFragment (..)
    , adminVenueSettingsFragment
    , adminVenueSettingsLiveSurfaceDefinition
    , adminVenueSettingsLiveSurfaceDefinitionForVenue
    , renderVenueSettingsSection
    , renderVenueSettingsSectionFragment
    ) where

import Application.Helper.Controller (currentVenueOrNothing)
import Application.Helper.LiveResource (LiveResource (..))
import Application.Helper.LiveSurface
import Application.Helper.LiveUpdate
import Application.Helper.WeekBoundaries (validRosterWeekStartDays)
import Web.View.Admin.Common
import Web.View.Prelude

data AdminVenueSettingsSurface

data AdminVenueSettingsLiveFragment
    = AdminVenueSettingsLiveFragment
    deriving (Eq, Show)

adminVenueSettingsFragment :: AdminVenueSettingsLiveFragment
adminVenueSettingsFragment =
    AdminVenueSettingsLiveFragment

adminVenueSettingsFragmentId :: Text
adminVenueSettingsFragmentId = "admin-venue-settings-fragment"

adminVenueSettingsLiveSurfaceDefinition :: (?context :: ControllerContext) => TypedLiveSurfaceDefinition AdminVenueSettingsSurface () AdminVenueSettingsLiveFragment
adminVenueSettingsLiveSurfaceDefinition =
    adminVenueSettingsLiveSurfaceDefinitionForVenue currentVenueScopeId

adminVenueSettingsLiveSurfaceDefinitionForVenue :: UUID -> TypedLiveSurfaceDefinition AdminVenueSettingsSurface () AdminVenueSettingsLiveFragment
adminVenueSettingsLiveSurfaceDefinitionForVenue surfaceVenueId =
    TypedLiveSurfaceDefinition
        { typedSurfaceFeature = "admin-venue-config"
        , typedSurfaceScope = const (SurfaceScope AdminVenueConfigScope { venueId = surfaceVenueId })
        , typedSurfaceScopeFromWire = \case
            AdminVenueConfigScope { venueId } | venueId == surfaceVenueId -> Just ()
            _ -> Nothing
        , typedSurfaceDefaultFragments = const [adminVenueSettingsFragment]
        , typedSurfaceFragmentContract = \() fragment ->
            mkSurfaceFragmentContract
                (adminVenueSettingsLiveFragmentRef fragment)
                (liveFragmentDependsOn (AdminVenueSettingsResource surfaceVenueId) [])
        , typedSurfaceDecorateRequestsWithin = const ["#" <> adminVenueSettingsFragmentId]
        , typedSurfaceAuthorize = liveSurfaceAuthorizationByRequirement (const (RequireCurrentVenueAdmin surfaceVenueId))
        }

adminVenueSettingsLiveFragmentRef :: AdminVenueSettingsLiveFragment -> SurfaceFragmentRef AdminVenueSettingsSurface
adminVenueSettingsLiveFragmentRef AdminVenueSettingsLiveFragment =
    mkSurfaceFragmentRef
        AdminVenueConfigFragment
        adminVenueSettingsFragmentId
        (pathTo ShowAdminVenueSettingsFragmentAction)

currentVenueScopeId :: (?context :: ControllerContext) => UUID
currentVenueScopeId =
    case currentVenueOrNothing of
        Just venue -> unpackId venue.id
        Nothing -> error "Admin venue settings live surface requires a current venue"

renderVenueSettingsSectionFragment :: (?context :: ControllerContext) => VenueConfig -> Html
renderVenueSettingsSectionFragment venueConfig = [hsx|
    <div id={adminVenueSettingsFragmentId}
         data-live-update-surface={liveSurfaceConfigJson (mkTypedDefinedLiveSurface adminVenueSettingsLiveSurfaceDefinition ())}>
        {renderVenueSettingsSection venueConfig}
    </div>
|]

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
          class="admin-setting-row"
          data-disable-javascript-submission="true"
          hx-post={UpdateVenueConfigAction}
          hx-target={"#" <> adminVenueSettingsFragmentId}
          hx-swap="outerHTML"
          hx-push-url="false">
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
          class="admin-setting-row"
          data-disable-javascript-submission="true"
          hx-post={UpdateVenueConfigAction}
          hx-target={"#" <> adminVenueSettingsFragmentId}
          hx-swap="outerHTML"
          hx-push-url="false">
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
        , appToggleOnChange = Just "if (!window.htmx) this.form.requestSubmit()"
        , appToggleHxPost = Just (pathTo UpdateVenueConfigAction)
        , appToggleHxTrigger = Just "change"
        , appToggleHxInclude = Just "closest form"
        , appToggleHxTarget = Just ("#" <> adminVenueSettingsFragmentId)
        , appToggleHxSwap = Just "outerHTML"
        , appToggleHxPushUrl = Just "false"
        }

renderRosterWeekStartForm :: VenueConfig -> Html
renderRosterWeekStartForm venueConfig = [hsx|
    <form method="POST"
          action={UpdateVenueConfigAction}
          class="admin-setting-row"
          data-disable-javascript-submission="true"
          hx-post={UpdateVenueConfigAction}
          hx-target={"#" <> adminVenueSettingsFragmentId}
          hx-swap="outerHTML"
          hx-push-url="false">
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
                    onchange="if (!window.htmx) this.form.requestSubmit()"
                    hx-post={UpdateVenueConfigAction}
                    hx-trigger="change"
                    hx-include="closest form"
                    hx-target={"#" <> adminVenueSettingsFragmentId}
                    hx-swap="outerHTML"
                    hx-push-url="false">
                {forEach validRosterWeekStartDays (renderRosterWeekStartOption venueConfig.rosterWeekStartsOn)}
            </select>
        </div>
    </form>
|]
