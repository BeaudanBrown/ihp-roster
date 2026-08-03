{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.View.Admin.VenueSettings
    ( renderVenueSettingsSection
    , renderVenueSettingsSectionFragment
    , renderVenueSettingsSectionFragmentWithSwap
    ) where

import Application.Helper.Controller (currentVenueOrNothing)
import qualified Application.Helper.FrontendContract.Surface.Admin as Surface
import qualified Application.Helper.FrontendContract.Surface.Admin.Action as AdminAction
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            FrontendSurfaceCustomHtmxAttrs (..),
                                                            renderFrontendSurfaceActionForm,
                                                            renderFrontendSurfaceMount)
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.TimeRules (venueTimePickerFinalSelectableTimeText,
                                     venueTimePickerStartTimeText)
import Web.Admin.FrontendSurface (AdminVenueScopeValue (..),
                                  adminVenueSettingsSurfaceImpl)
import Web.View.Admin.Common
import Web.View.Prelude

adminVenueSettingsFragmentId :: Text
adminVenueSettingsFragmentId = surfaceFragmentTargetId @Surface.AdminVenueSettingsSurface @Surface.AdminVenueSettingsFragment noSurfaceFields

currentVenueScopeId :: (?context :: ControllerContext) => UUID
currentVenueScopeId =
    case currentVenueOrNothing of
        Just venue -> unpackId venue.id
        Nothing -> error "Admin venue settings live surface requires a current venue"

renderVenueSettingsSectionFragment :: (?context :: ControllerContext) => VenueConfig -> Html
renderVenueSettingsSectionFragment =
    renderVenueSettingsSectionFragmentWithSwap Nothing

renderVenueSettingsSectionFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> VenueConfig -> Html
renderVenueSettingsSectionFragmentWithSwap maybeSwapOob venueConfig =
    renderFrontendSurfaceMount (adminVenueSettingsSurfaceImpl AdminVenueScopeValue { adminVenueId = currentVenueScopeId, adminRosterGroupId = Nothing }) [hsx|
        <div id={adminVenueSettingsFragmentId}
             hx-swap-oob={maybeSwapOob}>
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
                {renderRosterTimePickerWindowForm venueConfig}
                {renderMinutePrecisionShiftTimesForm venueConfig}
                {renderUnavailableStaffWarningThresholdForm venueConfig}
                {renderRosterEndTimesForm venueConfig}
            </div>
        |]

renderRosterTimePickerWindowForm :: VenueConfig -> Html
renderRosterTimePickerWindowForm venueConfig =
    renderFrontendSurfaceActionForm
        (AdminAction.updateVenueConfigAction fields)
        venueTimePickerSettingRoute
        [hsx|
        <input type="hidden" name={surfaceFieldNameFrom @Surface.ConfigFieldField fields} value="timePickerWindow" />
        <div class="admin-setting-row-copy">
            <div class="fw-semibold">Valid shift window</div>
            <p class="small app-muted mb-0">Controls the selectable roster and timesheet shift times. Existing saved times outside this window remain allowed.</p>
        </div>
        <div class="admin-setting-row-control admin-setting-row-control-wide">
            <div class="row g-2 align-items-end justify-content-end">
                <div class="col-6 col-sm-auto">
                    <label class="form-label small mb-1" for="venue-time-picker-start">Start</label>
                    {renderTimePickerField (defaultTimePickerConfig (surfaceFieldNameFrom @Surface.TimePickerStart fields) (venueTimePickerStartTimeText venueConfig) "00:00" "23:45" False)
                        { timePickerFieldClasses = ["admin-time-picker-field", "w-100"]
                        , timePickerAriaLabel = "Select valid shift window start"
                        }}
                </div>
                <div class="col-6 col-sm-auto">
                    <label class="form-label small mb-1" for="venue-time-picker-end">End</label>
                    {renderTimePickerField (defaultTimePickerConfig (surfaceFieldNameFrom @Surface.TimePickerEnd fields) (venueTimePickerFinalSelectableTimeText venueConfig) "00:00" "23:45" False)
                        { timePickerFieldClasses = ["admin-time-picker-field", "w-100"]
                        , timePickerAriaLabel = "Select valid shift window end"
                        }}
                </div>
            </div>
        </div>
    |]
  where
    fields =
        AdminAction.updateVenueConfigActionFields
            "timePickerWindow"
            Nothing
            Nothing
            Nothing
            (Just (venueTimePickerStartTimeText venueConfig))
            (Just (venueTimePickerFinalSelectableTimeText venueConfig))
            Nothing
            Nothing

renderMinutePrecisionShiftTimesForm :: VenueConfig -> Html
renderMinutePrecisionShiftTimesForm venueConfig =
    renderFrontendSurfaceActionForm
        (AdminAction.updateVenueConfigAction fields)
        venueToggleSettingRoute
        [hsx|
        <input type="hidden" name={surfaceFieldNameFrom @Surface.ConfigFieldField fields} value="minutePrecisionShiftTimesEnabled" />
        <div class="admin-setting-row-copy">
            <div class="fw-semibold">Minute-precision shift times</div>
            <p class="small app-muted mb-0">Use native minute entry for roster shifts and timesheets, including breaks. Timeline dragging remains on 15-minute intervals.</p>
        </div>
        <div class="admin-setting-row-control">
            {renderMinutePrecisionSettingToggle fields "venue-minute-precision-shift-times-enabled" venueConfig.minutePrecisionShiftTimesEnabled}
        </div>
    |]
  where
    fields =
        AdminAction.updateVenueConfigActionFields
            "minutePrecisionShiftTimesEnabled"
            Nothing
            Nothing
            (Just venueConfig.minutePrecisionShiftTimesEnabled)
            Nothing
            Nothing
            Nothing
            Nothing

renderUnavailableStaffWarningThresholdForm :: VenueConfig -> Html
renderUnavailableStaffWarningThresholdForm venueConfig =
    renderFrontendSurfaceActionForm
        (AdminAction.updateVenueConfigAction fields)
        venueTimePickerSettingRoute
        [hsx|
        <input type="hidden" name={surfaceFieldNameFrom @Surface.ConfigFieldField fields} value="unavailableStaffWarningThreshold" />
        <div class="admin-setting-row-copy">
            <label class="fw-semibold" for="venue-unavailable-staff-warning-threshold">Unavailable-staff warning threshold</label>
            <p class="small app-muted mb-0">Warn managers when this many active staff are unavailable on the same date. Leave blank to keep warnings Disabled.</p>
        </div>
        <div class="admin-setting-row-control">
            <input id="venue-unavailable-staff-warning-threshold"
                   class="form-control form-control-sm"
                   type="number"
                   min="1"
                   max="100"
                   name={surfaceFieldNameFrom @Surface.UnavailableStaffWarningThreshold fields}
                   value={maybe "" tshow venueConfig.unavailableStaffWarningThreshold}
                   placeholder="Disabled" />
        </div>
    |]
  where
    fields =
        AdminAction.updateVenueConfigActionFields
            "unavailableStaffWarningThreshold"
            Nothing
            Nothing
            Nothing
            Nothing
            Nothing
            Nothing
            venueConfig.unavailableStaffWarningThreshold

renderRosterEndTimesForm :: VenueConfig -> Html
renderRosterEndTimesForm venueConfig =
    renderFrontendSurfaceActionForm
        (AdminAction.updateVenueConfigAction fields)
        venueToggleSettingRoute
        [hsx|
        <input type="hidden" name={surfaceFieldNameFrom @Surface.ConfigFieldField fields} value="rosterEndTimesEnabled" />
        <div class="admin-setting-row-copy">
            <div class="fw-semibold">Show shift end times in roster</div>
            <p class="small app-muted mb-0">Shift end times are always collected; this controls whether they appear in the roster.</p>
        </div>
        <div class="admin-setting-row-control">
            {renderVenueSettingToggle fields "venue-roster-end-times-enabled" venueConfig.rosterEndTimesEnabled}
        </div>
    |]
  where
    fields =
        AdminAction.updateVenueConfigActionFields
            "rosterEndTimesEnabled"
            (Just venueConfig.rosterEndTimesEnabled)
            Nothing
            Nothing
            Nothing
            Nothing
            Nothing
            Nothing

renderMinutePrecisionSettingToggle :: SurfaceActionFields Surface.AdminVenueSettingsSurface Surface.UpdateVenueConfig -> Text -> Bool -> Html
renderMinutePrecisionSettingToggle fields inputId isEnabled =
    renderAppToggleButton $
        ( defaultAppToggleStateButtonConfig
            inputId
            (surfaceToggleScalarField @Surface.MinutePrecisionShiftTimesEnabled fields True False)
            isEnabled
            [hsx|<span class="small">Enabled</span>|]
            [hsx|<span class="small">15 minutes</span>|]
        )
            { appToggleButtonClass = "btn-sm"
            , appToggleRoleSwitch = True
            , appToggleSubmitPolicy = ToggleSubmitImmediate
            }

renderVenueSettingToggle :: SurfaceActionFields Surface.AdminVenueSettingsSurface Surface.UpdateVenueConfig -> Text -> Bool -> Html
renderVenueSettingToggle fields inputId isEnabled =
    renderAppToggleButton $
        ( defaultAppToggleStateButtonConfig
            inputId
            (surfaceToggleScalarField @Surface.RosterEndTimesEnabled fields True False)
            isEnabled
            [hsx|<span class="small">Enabled</span>|]
            [hsx|<span class="small">Disabled</span>|]
        )
            { appToggleButtonClass = "btn-sm"
            , appToggleRoleSwitch = True
            , appToggleSubmitPolicy = ToggleSubmitImmediate
            }

venueTimePickerSettingRoute :: FrontendSurfaceActionRoute
venueTimePickerSettingRoute = FrontendSurfaceActionRoute
    { actionRouteUrl = pathTo UpdateVenueConfigAction
    , actionRouteCustomHtmx = [FrontendSurfaceCustomHtmxAttrs "change-autosave-custom-htmx" [("hx-trigger", "change")]]
    , actionRouteStandardUrl = Just (pathTo UpdateVenueConfigAction)
    , actionRouteExtraAttrs = [("class", "admin-setting-row")]
    }

venueToggleSettingRoute :: FrontendSurfaceActionRoute
venueToggleSettingRoute = FrontendSurfaceActionRoute
    { actionRouteUrl = pathTo UpdateVenueConfigAction
    , actionRouteCustomHtmx = []
    , actionRouteStandardUrl = Just (pathTo UpdateVenueConfigAction)
    , actionRouteExtraAttrs = [("class", "admin-setting-row")]
    }

