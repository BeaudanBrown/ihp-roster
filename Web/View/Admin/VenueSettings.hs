{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.View.Admin.VenueSettings
    ( renderVenueSettingsSectionFragment
    , renderRosterWindowStartDayImpactFragment
    , renderRosterWindowStartDaySettingFragment
    , renderVenueSettingsSectionFragmentWithImpact
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
import Application.StaffDefaults (staffAwardRateIsAvailable)
import Web.Admin.FrontendSurface (AdminVenueScopeValue (..),
                                  adminVenueSettingsSurfaceImpl)
import Web.Admin.RosterWindowStartDay (RosterWindowStartDayImpact (..))
import Web.View.Admin.Common
import Web.View.Prelude

adminVenueSettingsFragmentId :: Text
adminVenueSettingsFragmentId = surfaceFragmentTargetId @Surface.AdminVenueSettingsSurface @Surface.AdminVenueSettingsFragment noSurfaceFields

currentVenueScopeId :: (?context :: ControllerContext) => UUID
currentVenueScopeId =
    case currentVenueOrNothing of
        Just venue -> unpackId venue.id
        Nothing -> error "Admin venue settings live surface requires a current venue"

renderVenueSettingsSectionFragment :: (?context :: ControllerContext) => VenueConfig -> [AwardLevel] -> [AwardLevelBaseRate] -> Html
renderVenueSettingsSectionFragment =
    renderVenueSettingsSectionFragmentWithSwap Nothing

renderVenueSettingsSectionFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> VenueConfig -> [AwardLevel] -> [AwardLevelBaseRate] -> Html
renderVenueSettingsSectionFragmentWithSwap maybeSwapOob venueConfig awardLevels awardLevelBaseRates =
    renderVenueSettingsSectionFragmentWithImpact maybeSwapOob venueConfig awardLevels awardLevelBaseRates Nothing

renderVenueSettingsSectionFragmentWithImpact :: (?context :: ControllerContext) => Maybe Text -> VenueConfig -> [AwardLevel] -> [AwardLevelBaseRate] -> Maybe RosterWindowStartDayImpact -> Html
renderVenueSettingsSectionFragmentWithImpact maybeSwapOob venueConfig awardLevels awardLevelBaseRates maybeImpact =
    renderFrontendSurfaceMount (adminVenueSettingsSurfaceImpl AdminVenueScopeValue { adminVenueId = currentVenueScopeId, adminRosterGroupId = Nothing }) [hsx|
        <div id={adminVenueSettingsFragmentId}
             hx-swap-oob={maybeSwapOob}>
            {renderVenueSettingsSectionWithImpact venueConfig awardLevels awardLevelBaseRates maybeImpact}
        </div>
    |]

renderVenueSettingsSectionWithImpact :: VenueConfig -> [AwardLevel] -> [AwardLevelBaseRate] -> Maybe RosterWindowStartDayImpact -> Html
renderVenueSettingsSectionWithImpact venueConfig awardLevels awardLevelBaseRates maybeImpact =
    renderConfigSection
        "admin-venue-settings"
        mempty
        mempty
        [hsx|
            <div class="admin-settings-grid">
                {maybe (renderRosterWindowStartDayForm venueConfig) (renderRosterWindowStartDayConfirmation venueConfig) maybeImpact}
                {renderDefaultStaffPayRateForm venueConfig awardLevels awardLevelBaseRates}
                {renderRosterTimePickerWindowForm venueConfig}
                {renderMinutePrecisionShiftTimesForm venueConfig}
                {renderUnavailableStaffWarningThresholdForm venueConfig}
                {renderRosterEndTimesForm venueConfig}
            </div>
        |]

renderRosterWindowStartDaySettingFragment :: VenueConfig -> Html
renderRosterWindowStartDaySettingFragment = renderRosterWindowStartDayForm

renderRosterWindowStartDayForm :: VenueConfig -> Html
renderRosterWindowStartDayForm venueConfig =
    renderFrontendSurfaceActionForm
        (AdminAction.previewRosterWindowStartDayAction fields)
        rosterWindowStartDayPreviewRoute
        [hsx|
        <div class="admin-setting-row-copy">
            <div class="fw-semibold">Roster window start day</div>
            <p class="small app-muted mb-0">Changes every roster and Timesheet window immediately. Mixed Published windows return to Draft; saved shifts and times remain unchanged.</p>
        </div>
        <div class="admin-setting-row-control admin-setting-row-control-wide d-flex gap-2 justify-content-end">
            <label class="visually-hidden" for="venue-roster-week-start">Roster window start day</label>
            <input type="hidden" name={surfaceFieldNameFrom @Surface.RosterCalendarRevision fields} value={tshow venueConfig.rosterCalendarRevision} />
            <select id="venue-roster-week-start"
                    class="form-select form-select-sm"
                    name={surfaceFieldNameFrom @Surface.RosterWeekStartsOn fields}>
                {forEach rosterWeekdayOptions renderWeekdayOption}
            </select>
            <button type="submit" class="btn btn-outline-warning btn-sm text-nowrap">Preview impact</button>
        </div>
    |]
  where
    fields = AdminAction.previewRosterWindowStartDayActionFields venueConfig.rosterWeekStartsOn venueConfig.rosterCalendarRevision
    renderWeekdayOption (weekdayIndex, label) = [hsx|<option value={tshow weekdayIndex} selected={venueConfig.rosterWeekStartsOn == weekdayIndex}>{label}</option>|]

renderRosterWindowStartDayImpactFragment :: VenueConfig -> RosterWindowStartDayImpact -> Html
renderRosterWindowStartDayImpactFragment = renderRosterWindowStartDayConfirmation

renderRosterWindowStartDayConfirmation :: VenueConfig -> RosterWindowStartDayImpact -> Html
renderRosterWindowStartDayConfirmation _venueConfig impact =
    renderFrontendSurfaceActionForm
        (AdminAction.updateRosterWeekStartsOnAction fields)
        confirmationRoute
        [hsx|
        <div class="admin-setting-row-copy">
            <div class="fw-semibold">Confirm roster window start day</div>
            <p class="small app-muted mb-2">Change to {weekdayLabel impact.proposedRosterWindowStartDay}? Saved shifts, lanes, times, templates, approved payroll, exports, and notification snapshots will not be rewritten.</p>
            <dl class="row small mb-0">
                <dt class="col-8">Mixed Published windows</dt><dd class="col-4 text-end">{impact.mixedPublishedWindowCount}</dd>
                <dt class="col-8">Published days returning to Draft</dt><dd class="col-4 text-end">{impact.affectedPublishedDayCount}</dd>
                <dt class="col-8">Shifts on affected days</dt><dd class="col-4 text-end">{impact.affectedShiftCount}</dd>
            </dl>
        </div>
        <div class="admin-setting-row-control admin-setting-row-control-wide d-flex flex-wrap gap-2 justify-content-end">
            <a href={pathTo AdminAction} class="btn btn-outline-secondary btn-sm">Cancel</a>
            <input type="hidden" name={surfaceFieldNameFrom @Surface.RosterWeekStartsOn fields} value={tshow impact.proposedRosterWindowStartDay} />
            <input type="hidden" name={surfaceFieldNameFrom @Surface.RosterCalendarRevision fields} value={tshow impact.rosterCalendarRevision} />
            <input type="hidden" name={surfaceFieldNameFrom @Surface.CurrentRosterWindowStartDay fields} value={tshow impact.currentRosterWindowStartDay} />
            <input type="hidden" name={surfaceFieldNameFrom @Surface.MixedPublishedWindowCount fields} value={tshow impact.mixedPublishedWindowCount} />
            <input type="hidden" name={surfaceFieldNameFrom @Surface.AffectedPublishedDayCount fields} value={tshow impact.affectedPublishedDayCount} />
            <input type="hidden" name={surfaceFieldNameFrom @Surface.AffectedShiftCount fields} value={tshow impact.affectedShiftCount} />
            <button type="submit" class="btn btn-warning btn-sm">Confirm change</button>
        </div>
    |]
  where
    fields =
        AdminAction.updateRosterWeekStartsOnActionFields
            impact.proposedRosterWindowStartDay
            impact.rosterCalendarRevision
            impact.currentRosterWindowStartDay
            impact.mixedPublishedWindowCount
            impact.affectedPublishedDayCount
            impact.affectedShiftCount
    confirmationRoute = FrontendSurfaceActionRoute
        { actionRouteUrl = pathTo UpdateRosterWeekStartsOnAction
        , actionRouteCustomHtmx = []
        , actionRouteStandardUrl = Just (pathTo UpdateRosterWeekStartsOnAction)
        , actionRouteExtraAttrs = [("class", "admin-setting-row"), ("id", rosterWindowStartDaySettingId)]
        }

weekdayLabel :: Int -> Text
weekdayLabel weekdayIndex = fromMaybe "Unknown" (lookup weekdayIndex rosterWeekdayOptions)

rosterWeekdayOptions :: [(Int, Text)]
rosterWeekdayOptions =
    [ (1, "Monday")
    , (2, "Tuesday")
    , (3, "Wednesday")
    , (4, "Thursday")
    , (5, "Friday")
    , (6, "Saturday")
    , (0, "Sunday")
    ]

renderDefaultStaffPayRateForm :: VenueConfig -> [AwardLevel] -> [AwardLevelBaseRate] -> Html
renderDefaultStaffPayRateForm venueConfig awardLevels awardLevelBaseRates =
    renderFrontendSurfaceActionForm
        (AdminAction.updateDefaultStaffPayRateAction fields)
        defaultStaffPayRateSettingRoute
        [hsx|
        <div class="admin-setting-row-copy">
            <label class="fw-semibold" for="venue-default-staff-pay-rate">Default staff rate</label>
            <p class="small app-muted mb-0">Applied automatically when managers create staff. Venue admins can override it while creating a staff member.</p>
        </div>
        <div class="admin-setting-row-control admin-setting-row-control-wide">
            <select id="venue-default-staff-pay-rate"
                    class="form-select form-select-sm"
                    name={surfaceFieldNameFrom @Surface.DefaultStaffAwardLevelId fields}>
                <option value="" selected={isNothing selectedAwardLevelId}>No Timesheets (roster only)</option>
                {forEach awardLevels renderAwardOption}
            </select>
            {when defaultNeedsRepair renderDefaultRepairWarning}
        </div>
    |]
  where
    selectedAwardLevelId =
        case venueConfig.defaultStaffPayAssignmentMode of
            AwardRate -> venueConfig.defaultStaffAwardLevelId
            _         -> Nothing
    defaultNeedsRepair =
        case venueConfig.defaultStaffPayAssignmentMode of
            AwardRate ->
                case venueConfig.defaultStaffAwardLevelId of
                    Just awardLevelId -> not (staffAwardRateIsAvailable awardLevels awardLevelBaseRates Casual awardLevelId)
                    Nothing -> True
            _ -> False
    fields = AdminAction.updateDefaultStaffPayRateActionFields (unpackId <$> selectedAwardLevelId)
    renderDefaultRepairWarning = [hsx|
        <p class="small text-warning mb-0 mt-1" role="alert">The saved default is unavailable. Choose an active award rate or No Timesheets before managers create staff.</p>
    |]
    renderAwardOption awardLevel = [hsx|
        <option value={inputValue awardLevel.id} selected={selectedAwardLevelId == Just awardLevel.id}>
            {awardLevelOptionLabel awardLevelBaseRates awardLevel}
        </option>
    |]

renderRosterTimePickerWindowForm :: VenueConfig -> Html
renderRosterTimePickerWindowForm venueConfig =
    renderFrontendSurfaceActionForm
        (AdminAction.updateRosterTimePickerWindowAction fields)
        rosterTimePickerWindowSettingRoute
        [hsx|
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
        AdminAction.updateRosterTimePickerWindowActionFields
            (venueTimePickerStartTimeText venueConfig)
            (venueTimePickerFinalSelectableTimeText venueConfig)

renderMinutePrecisionShiftTimesForm :: VenueConfig -> Html
renderMinutePrecisionShiftTimesForm venueConfig =
    renderFrontendSurfaceActionForm
        (AdminAction.updateMinutePrecisionShiftTimesEnabledAction fields)
        minutePrecisionSettingRoute
        [hsx|
        <div class="admin-setting-row-copy">
            <div class="fw-semibold">Minute-precision shift times</div>
            <p class="small app-muted mb-0">Use native minute entry for roster shifts and timesheets, including breaks. Timeline dragging remains on 15-minute intervals.</p>
        </div>
        <div class="admin-setting-row-control">
            {renderMinutePrecisionSettingToggle fields "venue-minute-precision-shift-times-enabled" venueConfig.minutePrecisionShiftTimesEnabled}
        </div>
    |]
  where
    fields = AdminAction.updateMinutePrecisionShiftTimesEnabledActionFields venueConfig.minutePrecisionShiftTimesEnabled

renderUnavailableStaffWarningThresholdForm :: VenueConfig -> Html
renderUnavailableStaffWarningThresholdForm venueConfig =
    renderFrontendSurfaceActionForm
        (AdminAction.updateUnavailableStaffWarningThresholdAction fields)
        unavailableStaffWarningThresholdSettingRoute
        [hsx|
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
    fields = AdminAction.updateUnavailableStaffWarningThresholdActionFields venueConfig.unavailableStaffWarningThreshold

renderRosterEndTimesForm :: VenueConfig -> Html
renderRosterEndTimesForm venueConfig =
    renderFrontendSurfaceActionForm
        (AdminAction.updateRosterEndTimesEnabledAction fields)
        rosterEndTimesSettingRoute
        [hsx|
        <div class="admin-setting-row-copy">
            <div class="fw-semibold">Show shift end times in roster</div>
            <p class="small app-muted mb-0">Shift end times are always collected; this controls whether they appear in the roster.</p>
        </div>
        <div class="admin-setting-row-control">
            {renderVenueSettingToggle fields "venue-roster-end-times-enabled" venueConfig.rosterEndTimesEnabled}
        </div>
    |]
  where
    fields = AdminAction.updateRosterEndTimesEnabledActionFields venueConfig.rosterEndTimesEnabled

renderMinutePrecisionSettingToggle :: ActionFields AdminAction.UpdateMinutePrecisionShiftTimesEnabledActionOperation -> Text -> Bool -> Html
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

renderVenueSettingToggle :: ActionFields AdminAction.UpdateRosterEndTimesEnabledActionOperation -> Text -> Bool -> Html
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

rosterWindowStartDaySettingId :: Text
rosterWindowStartDaySettingId =
    surfaceDomTokenValue @Surface.AdminVenueSettingsSurface @Surface.AdminRosterWindowStartDaySetting

rosterWindowStartDayPreviewRoute :: FrontendSurfaceActionRoute
rosterWindowStartDayPreviewRoute = FrontendSurfaceActionRoute
    { actionRouteUrl = pathTo PreviewRosterWindowStartDayAction
    , actionRouteCustomHtmx = []
    , actionRouteStandardUrl = Just (pathTo PreviewRosterWindowStartDayAction)
    , actionRouteExtraAttrs = [("class", "admin-setting-row"), ("id", rosterWindowStartDaySettingId)]
    }

defaultStaffPayRateSettingRoute :: FrontendSurfaceActionRoute
defaultStaffPayRateSettingRoute = FrontendSurfaceActionRoute
    { actionRouteUrl = pathTo UpdateDefaultStaffPayRateAction
    , actionRouteCustomHtmx = [FrontendSurfaceCustomHtmxAttrs "change-autosave-custom-htmx" [("hx-trigger", "change")]]
    , actionRouteStandardUrl = Just (pathTo UpdateDefaultStaffPayRateAction)
    , actionRouteExtraAttrs = [("class", "admin-setting-row")]
    }

rosterTimePickerWindowSettingRoute :: FrontendSurfaceActionRoute
rosterTimePickerWindowSettingRoute = FrontendSurfaceActionRoute
    { actionRouteUrl = pathTo UpdateRosterTimePickerWindowAction
    , actionRouteCustomHtmx = [FrontendSurfaceCustomHtmxAttrs "change-autosave-custom-htmx" [("hx-trigger", "change")]]
    , actionRouteStandardUrl = Just (pathTo UpdateRosterTimePickerWindowAction)
    , actionRouteExtraAttrs = [("class", "admin-setting-row")]
    }

unavailableStaffWarningThresholdSettingRoute :: FrontendSurfaceActionRoute
unavailableStaffWarningThresholdSettingRoute = FrontendSurfaceActionRoute
    { actionRouteUrl = pathTo UpdateUnavailableStaffWarningThresholdAction
    , actionRouteCustomHtmx = [FrontendSurfaceCustomHtmxAttrs "change-autosave-custom-htmx" [("hx-trigger", "change")]]
    , actionRouteStandardUrl = Just (pathTo UpdateUnavailableStaffWarningThresholdAction)
    , actionRouteExtraAttrs = [("class", "admin-setting-row")]
    }

minutePrecisionSettingRoute :: FrontendSurfaceActionRoute
minutePrecisionSettingRoute = FrontendSurfaceActionRoute
    { actionRouteUrl = pathTo UpdateMinutePrecisionShiftTimesEnabledAction
    , actionRouteCustomHtmx = []
    , actionRouteStandardUrl = Just (pathTo UpdateMinutePrecisionShiftTimesEnabledAction)
    , actionRouteExtraAttrs = [("class", "admin-setting-row")]
    }

rosterEndTimesSettingRoute :: FrontendSurfaceActionRoute
rosterEndTimesSettingRoute = FrontendSurfaceActionRoute
    { actionRouteUrl = pathTo UpdateRosterEndTimesEnabledAction
    , actionRouteCustomHtmx = []
    , actionRouteStandardUrl = Just (pathTo UpdateRosterEndTimesEnabledAction)
    , actionRouteExtraAttrs = [("class", "admin-setting-row")]
    }

