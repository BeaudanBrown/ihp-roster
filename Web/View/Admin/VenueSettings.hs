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

adminVenueSettingsLiveSurfaceDefinition :: (?context :: ControllerContext) => TypedLiveSurfaceDefinition AdminVenueSettingsSurface () AdminVenueSettingsLiveFragment EmptyInteractionLayer EmptyInteractionSession EmptyInteractionIntent
adminVenueSettingsLiveSurfaceDefinition =
    adminVenueSettingsLiveSurfaceDefinitionForVenue currentVenueScopeId

adminVenueSettingsLiveSurfaceDefinitionForVenue :: UUID -> TypedLiveSurfaceDefinition AdminVenueSettingsSurface () AdminVenueSettingsLiveFragment EmptyInteractionLayer EmptyInteractionSession EmptyInteractionIntent
adminVenueSettingsLiveSurfaceDefinitionForVenue surfaceVenueId =
    descriptorToTypedLiveSurfaceDefinition
        ( liveSurfaceDescriptor
            "admin-venue-config"
            (const (SurfaceScope AdminVenueConfigScope { venueId = surfaceVenueId }))
            (\case
                AdminVenueConfigScope { venueId } | venueId == surfaceVenueId -> Just ()
                _ -> Nothing)
            (liveSurfaceAuthorizationByRequirement (const (RequireCurrentVenueAdmin surfaceVenueId)))
            [ liveFragmentDescriptor
                adminVenueSettingsFragment
                (const (adminVenueSettingsLiveFragmentRef adminVenueSettingsFragment))
                (const (liveFragmentDependsOn (AdminVenueSettingsResource surfaceVenueId) []))
            ]
        )

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
            <div class="fw-semibold">Show shift end times in roster</div>
            <p class="small app-muted mb-0">Shift end times are always collected; this controls whether they appear in the roster.</p>
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

