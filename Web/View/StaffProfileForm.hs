module Web.View.StaffProfileForm where

import Application.Helper.StaffShiftPreferences
import Web.View.Prelude

renderPersonalProfileFields :: Staff -> Maybe Text -> Html
renderPersonalProfileFields staff maybeEmail = [hsx|
    <div class="mb-3">
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
    <div class="mb-3">
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
    <div class="mb-3">
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
    <div class="mb-3">
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
    <div class="mb-3">
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
    <div class="mb-3">
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
    <div class="mb-3">
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
    <div class="mb-3">
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
|]

renderShiftPreferenceSections :: [PreferenceWeekday] -> [StaffPreferenceGroupSection] -> [Text] -> Html
renderShiftPreferenceSections weekdays sections selectedShiftPreferenceKeys =
    if null sections
        then [hsx|<p class="app-muted mb-0">Shift preferences will appear once this staff member is assigned to at least one roster group.</p>|]
        else [hsx|
            <div class="vstack gap-3">
                {forEach sections (renderShiftPreferenceSection weekdays selectedShiftPreferenceKeys)}
            </div>
        |]

renderShiftPreferenceSection :: [PreferenceWeekday] -> [Text] -> StaffPreferenceGroupSection -> Html
renderShiftPreferenceSection weekdays selectedShiftPreferenceKeys StaffPreferenceGroupSection { rosterGroup, slotNames } = [hsx|
    <section class="border rounded p-3">
        <div class="d-flex justify-content-between align-items-start gap-3 mb-3">
            <div>
                <h5 class="mb-1">{rosterGroup.name}</h5>
                <p class="app-muted mb-0 small">Tick the shifts this staff member is happy to work. A day with no selected slots counts as a hard cannot-do-day warning for roster highlights.</p>
            </div>
        </div>
        {renderShiftPreferenceMatrix rosterGroup.id weekdays slotNames selectedShiftPreferenceKeys}
    </section>
|]

renderShiftPreferenceMatrix :: Id RosterGroup -> [PreferenceWeekday] -> [SlotName] -> [Text] -> Html
renderShiftPreferenceMatrix rosterGroupId weekdays slotNames selectedShiftPreferenceKeys
    | null slotNames = [hsx|<p class="app-muted mb-0">This roster group has no active slots yet.</p>|]
    | otherwise = [hsx|
        <div class="table-responsive">
            <table class="table table-sm align-middle mb-0">
                <thead>
                    <tr>
                        <th>Day</th>
                        {forEach slotNames renderShiftPreferenceSlotHeader}
                    </tr>
                </thead>
                <tbody>
                    {forEach weekdays (renderShiftPreferenceDayRow rosterGroupId slotNames selectedShiftPreferenceKeys)}
                </tbody>
            </table>
        </div>
    |]

renderShiftPreferenceSlotHeader :: SlotName -> Html
renderShiftPreferenceSlotHeader slotName = [hsx|<th class="text-center">{slotName.name}</th>|]

renderShiftPreferenceDayRow :: Id RosterGroup -> [SlotName] -> [Text] -> PreferenceWeekday -> Html
renderShiftPreferenceDayRow rosterGroupId slotNames selectedShiftPreferenceKeys weekday = [hsx|
    <tr>
        <th scope="row" class="fw-semibold">{weekday.label}</th>
        {forEach slotNames (renderShiftPreferenceCheckbox rosterGroupId weekday.weekdayIndex selectedShiftPreferenceKeys)}
    </tr>
|]

renderShiftPreferenceCheckbox :: Id RosterGroup -> Int -> [Text] -> SlotName -> Html
renderShiftPreferenceCheckbox rosterGroupId weekdayIndex selectedShiftPreferenceKeys slotName =
    let key =
            encodeShiftPreferenceKey
                ShiftPreferenceSelection
                    { rosterGroupId
                    , weekdayIndex
                    , slotNameId = slotName.id
                    }
     in [hsx|
        <td class="text-center">
            <input
                class="form-check-input"
                type="checkbox"
                name="shiftPreferenceKeys"
                value={key}
                checked={key `elem` selectedShiftPreferenceKeys}
            />
        </td>
    |]

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
