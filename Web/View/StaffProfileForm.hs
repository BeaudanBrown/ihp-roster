module Web.View.StaffProfileForm where

import Application.Helper.StaffShiftPreferences
import Web.View.Prelude

renderPersonalProfileFields :: Staff -> Maybe Text -> Html
renderPersonalProfileFields staff maybeEmail = [hsx|
    <div class="row g-3 profile-field-grid">
        <div class="col-12 col-lg-6">
            <label for="firstName" class="form-label">First Name</label>
            <input
                id="firstName"
                name="firstName"
                type="text"
                class={inputClass staff "firstName"}
                value={staff.firstName}
                required="required"
                autofocus="autofocus"
            />
            {renderStaffFieldError staff "firstName"}
        </div>
        <div class="col-12 col-lg-6">
            <label for="lastName" class="form-label">Last Name</label>
            <input
                id="lastName"
                name="lastName"
                type="text"
                class={inputClass staff "lastName"}
                value={staff.lastName}
                required="required"
            />
            {renderStaffFieldError staff "lastName"}
        </div>
        <div class="col-12 col-lg-6">
            <label for="preferredName" class="form-label">Preferred Name</label>
            <input
                id="preferredName"
                name="preferredName"
                type="text"
                class={inputClass staff "preferredName"}
                value={fromMaybe "" staff.preferredName}
                placeholder="Optional"
            />
            {renderStaffFieldError staff "preferredName"}
        </div>
        <div class="col-12 col-lg-6">
            <label for="email" class="form-label">Email</label>
            <input
                id="email"
                type="email"
                class="form-control"
                value={fromMaybe "" maybeEmail}
                readonly="readonly"
                disabled="disabled"
            />
            <div class="form-text">Login email is read-only here for now.</div>
        </div>
        <div class="col-12 col-lg-6">
            <label for="phone" class="form-label">Phone</label>
            <input
                id="phone"
                name="phone"
                type="text"
                class={inputClass staff "phone"}
                value={staff.phone}
                required="required"
            />
            {renderStaffFieldError staff "phone"}
        </div>
        <div class="col-12 col-lg-6">
            <label for="idealShiftsPerWeek" class="form-label">Ideal Shifts Per Week</label>
            <input
                id="idealShiftsPerWeek"
                name="idealShiftsPerWeek"
                type="number"
                min="0"
                max="7"
                class={inputClass staff "idealShiftsPerWeek"}
                value={tshow staff.idealShiftsPerWeek}
                required="required"
            />
            {renderStaffFieldError staff "idealShiftsPerWeek"}
        </div>
        <div class="col-12 col-lg-6">
            <label for="emergencyContactName" class="form-label">Emergency Contact Name</label>
            <input
                id="emergencyContactName"
                name="emergencyContactName"
                type="text"
                class={inputClass staff "emergencyContactName"}
                value={staff.emergencyContactName}
                required="required"
            />
            {renderStaffFieldError staff "emergencyContactName"}
        </div>
        <div class="col-12 col-lg-6">
            <label for="emergencyContactPhone" class="form-label">Emergency Contact Number</label>
            <input
                id="emergencyContactPhone"
                name="emergencyContactPhone"
                type="text"
                class={inputClass staff "emergencyContactPhone"}
                value={staff.emergencyContactPhone}
                required="required"
            />
            {renderStaffFieldError staff "emergencyContactPhone"}
        </div>
    </div>
|]

renderShiftPreferenceSections :: [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Html
renderShiftPreferenceSections weekdays selectedShiftPreferences =
    if null weekdays
        then [hsx|<p class="app-muted mb-0">Shift preferences will appear once the venue calendar is configured.</p>|]
        else [hsx|
    <section class={appSurfaceClasses "p-3"}>
        <div class="d-flex justify-content-between align-items-start gap-3 mb-3">
            <div>
                <p class="app-muted mb-0 small">Tick available days and choose the preferred shift start window. A day left unticked counts as unavailable for roster highlights.</p>
            </div>
        </div>
        {renderShiftPreferenceRows weekdays selectedShiftPreferences}
    </section>
|]

renderShiftPreferenceRows :: [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Html
renderShiftPreferenceRows weekdays selectedShiftPreferences = [hsx|
    <div class="vstack gap-3">
        {forEach weekdays (renderShiftPreferenceDayRow selectedShiftPreferences)}
    </div>
|]

renderShiftPreferenceDayRow :: [ShiftPreferenceSelection] -> PreferenceWeekday -> Html
renderShiftPreferenceDayRow selectedShiftPreferences weekday =
    let key = encodeShiftPreferenceKey weekday.weekdayIndex
        selectedPreference = findSelectedShiftPreference weekday.weekdayIndex selectedShiftPreferences
        isSelected = isJust selectedPreference
        startHour = maybe defaultPreferenceStartHour (.startHour) selectedPreference
        endHour = maybe defaultPreferenceEndHour (.endHour) selectedPreference
     in [hsx|
        <div class="shift-preference-window"
             data-shift-preference-window="true"
             data-min-hour={tshow preferenceMinimumHour}
             data-max-hour={tshow preferenceMaximumHour}>
            <div class="shift-preference-window__inner">
                <label class="form-check d-flex align-items-center gap-2 mb-0 shift-preference-window__available">
                    <input
                        class="form-check-input mt-0"
                        type="checkbox"
                        name="shiftPreferenceKeys"
                        value={key}
                        checked={isSelected}
                        data-shift-preference-available="true"
                    />
                    <span class="form-check-label fw-semibold">{weekday.label}</span>
                </label>
                <div class="shift-preference-window__controls">
                    <div class="shift-preference-window__caption small app-muted">Preferred start window</div>
                    <div class="shift-preference-range">
                        <div class="shift-preference-range__labels" aria-hidden="true">
                            <span class="shift-preference-range__bubble" data-shift-preference-start-label="true">{formatPreferenceHour startHour}</span>
                            <span class="shift-preference-range__bubble" data-shift-preference-end-label="true">{formatPreferenceHour endHour}</span>
                        </div>
                        <div class="shift-preference-range__track" aria-hidden="true">
                            <div class="shift-preference-range__fill" data-shift-preference-fill="true"></div>
                        </div>
                        <label class="visually-hidden" for={"shiftPreferenceStart-" <> key}>Earliest preferred start</label>
                        <input
                            id={"shiftPreferenceStart-" <> key}
                            class="shift-preference-range__input"
                            type="range"
                            min={tshow preferenceMinimumHour}
                            max={tshow preferenceMaximumHour}
                            step="1"
                            name={shiftPreferenceStartHourParamName key}
                            value={tshow startHour}
                            data-shift-preference-start="true"
                        />
                        <label class="visually-hidden" for={"shiftPreferenceEnd-" <> key}>Latest preferred start</label>
                        <input
                            id={"shiftPreferenceEnd-" <> key}
                            class="shift-preference-range__input"
                            type="range"
                            min={tshow preferenceMinimumHour}
                            max={tshow preferenceMaximumHour}
                            step="1"
                            name={shiftPreferenceEndHourParamName key}
                            value={tshow endHour}
                            data-shift-preference-end="true"
                        />
                    </div>
                </div>
            </div>
        </div>
    |]

findSelectedShiftPreference :: Int -> [ShiftPreferenceSelection] -> Maybe ShiftPreferenceSelection
findSelectedShiftPreference weekdayIndex =
    find (\selection -> selection.weekdayIndex == weekdayIndex)

inputClass :: Staff -> Text -> Text
inputClass staff fieldName =
    classes [("form-control", True), ("is-invalid", hasStaffErrorFor staff fieldName)]

selectClass :: Staff -> Text -> Text
selectClass staff fieldName =
    classes [("form-select", True), ("is-invalid", hasStaffErrorFor staff fieldName)]

renderStaffFieldError :: Staff -> Text -> Html
renderStaffFieldError staff fieldName =
    case lookup fieldName staff.meta.annotations of
        Just (TextViolation messageText) -> [hsx|<div class="invalid-feedback d-block">{messageText}</div>|]
        Just (HtmlViolation messageHtml) -> [hsx|<div class="invalid-feedback d-block">{messageHtml}</div>|]
        Nothing -> mempty

hasStaffErrorFor :: Staff -> Text -> Bool
hasStaffErrorFor staff fieldName = isJust (lookup fieldName staff.meta.annotations)
