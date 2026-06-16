module Web.View.StaffProfileForm where

import Application.Helper.StaffShiftPreferences
import qualified Data.Text as Text
import Numeric (showFFloat)
import Web.View.Prelude

data StaffManagementFieldData = StaffManagementFieldData
    { managementStaff                  :: Staff
    , managementRosterGroups           :: [RosterGroup]
    , managementAwardLevels            :: [AwardLevel]
    , managementAwardLevelBaseRates    :: [AwardLevelBaseRate]
    , managementImportedPayItems       :: [XeroImportedPayItem]
    , managementSelectedRosterGroupIds :: [Id RosterGroup]
    , managementWeekOffset             :: Maybe Int
    , managementRosterGroupId          :: Maybe (Id RosterGroup)
    }

renderPersonalProfileFields :: Staff -> Maybe Text -> Html
renderPersonalProfileFields = renderPersonalProfileFieldsWithEmailId "email"

renderPersonalProfileFieldsWithEmailId :: Text -> Staff -> Maybe Text -> Html
renderPersonalProfileFieldsWithEmailId emailFieldId staff maybeEmail =
    renderPersonalProfileFieldsWithEmailSlot (renderReadonlyEmailField emailFieldId maybeEmail) staff

renderReadonlyEmailField :: Text -> Maybe Text -> Html
renderReadonlyEmailField emailFieldId maybeEmail = [hsx|
    <div class="col-12 col-lg-6">
        <label for={emailFieldId} class="form-label">Email</label>
        <input
            id={emailFieldId}
            type="email"
            class="form-control"
            value={fromMaybe "" maybeEmail}
            readonly="readonly"
            disabled="disabled"
        />
    </div>
|]

renderPersonalProfileFieldsWithEmailSlot :: Html -> Staff -> Html
renderPersonalProfileFieldsWithEmailSlot emailField staff = [hsx|
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
        {emailField}
        <div class="col-12 col-lg-6">
            <label for="phone" class="form-label">Phone #</label>
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
            <label for="idealShiftsPerWeek" class="form-label">Ideal # Shifts</label>
            <select
                id="idealShiftsPerWeek"
                name="idealShiftsPerWeek"
                class={selectClass staff "idealShiftsPerWeek"}
                required="required"
            >
                {forEach [0 :: Int .. 7] (renderIdealShiftsOption staff.idealShiftsPerWeek)}
            </select>
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

renderIdealShiftsOption :: Int -> Int -> Html
renderIdealShiftsOption selectedValue optionValue = [hsx|
    <option value={tshow optionValue} selected={optionValue == selectedValue}>{optionValue}</option>
|]

renderShiftPreferenceSections :: [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Html
renderShiftPreferenceSections weekdays selectedShiftPreferences =
    if null weekdays
        then [hsx|<p class="app-muted mb-0">Shift preferences will appear once the venue calendar is configured.</p>|]
        else [hsx|
    <section class={appSurfaceClasses "p-3"}>
        {renderShiftPreferenceRows weekdays selectedShiftPreferences}
    </section>
|]

renderShiftPreferenceRows :: [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Html
renderShiftPreferenceRows weekdays selectedShiftPreferences = [hsx|
    <table class="table table-sm align-middle shift-preference-table mb-0">
        <thead>
            <tr>
                <th scope="col" class="shift-preference-table__available">Available</th>
            </tr>
        </thead>
        <tbody>
            {forEach weekdays (renderShiftPreferenceDayRow selectedShiftPreferences)}
        </tbody>
    </table>
|]

renderShiftPreferenceDayRow :: [ShiftPreferenceSelection] -> PreferenceWeekday -> Html
renderShiftPreferenceDayRow selectedShiftPreferences weekday =
    let key = encodeShiftPreferenceKey weekday.weekdayIndex
        selectedPreference = findSelectedShiftPreference weekday.weekdayIndex selectedShiftPreferences
        isSelected = isJust selectedPreference
        startHour = maybe defaultPreferenceStartHour (.startHour) selectedPreference
        endHour = maybe defaultPreferenceEndHour (.endHour) selectedPreference
        weekdayLabel = abbreviateWeekdayLabel weekday.label
     in [hsx|
        <tr class={shiftPreferenceWindowClass isSelected}
             style={shiftPreferenceWindowStyle startHour endHour}
             data-shift-preference-window="true"
             data-min-hour={tshow preferenceMinimumHour}
             data-max-hour={tshow preferenceMaximumHour}>
            <th scope="row" class="shift-preference-table__available">
                {renderShiftPreferenceAvailabilityToggle key weekdayLabel weekday.label isSelected}
            </th>
            <td class="shift-preference-table__start-time">
                <div class="shift-preference-window__controls">
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
                            disabled={not isSelected}
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
                            disabled={not isSelected}
                            data-shift-preference-end="true"
                        />
                    </div>
                </div>
            </td>
        </tr>
    |]

renderShiftPreferenceAvailabilityToggle :: Text -> Text -> Text -> Bool -> Html
renderShiftPreferenceAvailabilityToggle key weekdayLabel fullWeekdayLabel isSelected =
    renderAppToggleButton $ (defaultAppToggleButtonConfig ("shiftPreferenceAvailable-" <> key) isSelected [hsx|
        <span>{weekdayLabel}</span>
        <span class="visually-hidden">{fullWeekdayLabel} available</span>
    |])
        { appToggleInputName = Just "shiftPreferenceKeys"
        , appToggleInputValue = key
        , appToggleButtonClass = "btn-sm timesheet-approval-toggle shift-preference-availability-button"
        , appToggleShiftPreferenceAvailable = True
        }

abbreviateWeekdayLabel :: Text -> Text
abbreviateWeekdayLabel = Text.take 3

shiftPreferenceWindowClass :: Bool -> Text
shiftPreferenceWindowClass isSelected =
    classes
        [ ("shift-preference-window", True)
        , ("is-unavailable", not isSelected)
        ]

shiftPreferenceWindowStyle :: Int -> Int -> Text
shiftPreferenceWindowStyle startHour endHour =
    "--preference-start: "
        <> preferenceHourPercent startHour
        <> "; --preference-end: "
        <> preferenceHourPercent endHour
        <> ";"

preferenceHourPercent :: Int -> Text
preferenceHourPercent hour =
    cs (showFFloat (Just 3) percent "%")
    where
        spanHours = max 1 (preferenceMaximumHour - preferenceMinimumHour)
        boundedHour = max preferenceMinimumHour (min preferenceMaximumHour hour)
        percent = (fromIntegral (boundedHour - preferenceMinimumHour) / fromIntegral spanHours) * (100 :: Double)

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

renderStaffManagementFields :: StaffManagementFieldData -> Html
renderStaffManagementFields StaffManagementFieldData { managementStaff = staff, managementRosterGroups = rosterGroups, managementAwardLevels = awardLevels, managementAwardLevelBaseRates = awardLevelBaseRates, managementImportedPayItems = importedPayItems, managementSelectedRosterGroupIds = selectedRosterGroupIds, managementWeekOffset = maybeWeekOffset, managementRosterGroupId = maybeRosterGroupId } = [hsx|
    {maybe mempty renderWeekOffsetHiddenInput maybeWeekOffset}
    {renderRosterGroupHiddenInput maybeRosterGroupId}
    {when currentUserIsAdmin (renderStaffPayFields staff awardLevels awardLevelBaseRates importedPayItems)}
    <div class="mt-3">
        <label for="isActive" class="form-label">Status</label>
        <select name="isActive" id="isActive" class={selectClass staff "isActive"}>
            <option value="on" selected={staff.isActive}>Active</option>
            <option value="" selected={not staff.isActive}>Inactive</option>
        </select>
        {renderStaffFieldError staff "isActive"}
    </div>
    <div class="mt-3">
        <label class="form-label d-block">Roster Groups</label>
        <div class="row g-2">
            {forEach rosterGroups (renderRosterGroupCheckbox selectedRosterGroupIds)}
        </div>
    </div>
|]

renderWeekOffsetHiddenInput :: Int -> Html
renderWeekOffsetHiddenInput weekOffset = [hsx|<input type="hidden" name="weekOffset" value={tshow weekOffset} />|]

renderStaffPayFields :: Staff -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> Html
renderStaffPayFields staff awardLevels awardLevelBaseRates importedPayItems = [hsx|
    <div class="row g-3 mt-3 staff-pay-field-grid">
        <div class="col-12 col-md-6">
            <label for="employmentBasis" class="form-label">Employment Basis</label>
            <select name="employmentBasis" id="employmentBasis" class={selectClass staff "employmentBasis"}>
                <option value="permanent" selected={staff.employmentBasis == Permanent}>Permanent</option>
                <option value="casual" selected={staff.employmentBasis == Casual}>Casual</option>
            </select>
            {renderStaffFieldError staff "employmentBasis"}
        </div>
        <div class="col-12 col-md-6">
            <label for="payRateSelection" class="form-label">Default Pay Rate</label>
            <select name="payRateSelection" id="payRateSelection" class={selectClass staff "defaultAwardLevelId"}>
                <option value="" selected={isNothing staff.defaultAwardLevelId && isNothing staff.importedXeroPayItemId}>Not assigned</option>
                {forEach awardLevels (renderAwardLevelOption staff awardLevelBaseRates)}
                {forEach importedPayItems (renderImportedPayItemOption staff.importedXeroPayItemId)}
            </select>
            {renderStaffFieldError staff "defaultAwardLevelId"}
            {renderStaffFieldError staff "importedXeroPayItemId"}
        </div>
    </div>
|]

renderImportedPayItemOption :: Maybe (Id XeroImportedPayItem) -> XeroImportedPayItem -> Html
renderImportedPayItemOption selectedImportedPayItemId importedPayItem = [hsx|
    <option value={"xero:" <> inputValue importedPayItem.id} selected={selectedImportedPayItemId == Just importedPayItem.id}>
        Xero: {importedPayItem.name} — {tshow importedPayItem.ratePerUnit}/hr
    </option>
|]

renderAwardLevelOption :: Staff -> [AwardLevelBaseRate] -> AwardLevel -> Html
renderAwardLevelOption staff awardLevelBaseRates awardLevel = [hsx|
    <option value={"award:" <> inputValue awardLevel.id} selected={isNothing staff.importedXeroPayItemId && staff.defaultAwardLevelId == Just awardLevel.id}>
        FWC: {awardLevelOptionLabel awardLevelBaseRates awardLevel}
    </option>
|]

renderRosterGroupHiddenInput :: Maybe (Id RosterGroup) -> Html
renderRosterGroupHiddenInput maybeRosterGroupId =
    case maybeRosterGroupId of
        Just rosterGroupId -> [hsx|<input type="hidden" name="rosterGroupId" value={tshow rosterGroupId} />|]
        Nothing -> mempty

renderRosterGroupCheckbox :: [Id RosterGroup] -> RosterGroup -> Html
renderRosterGroupCheckbox selectedRosterGroupIds rosterGroup =
    let isSelected = rosterGroup.id `elem` selectedRosterGroupIds
     in [hsx|
        <div class="col-12 col-md-6">
            {renderRosterGroupToggle rosterGroup isSelected}
        </div>
    |]

renderRosterGroupToggle :: RosterGroup -> Bool -> Html
renderRosterGroupToggle rosterGroup isSelected =
    renderAppToggleButton $ (defaultAppToggleButtonConfig ("staff-roster-group-" <> tshow rosterGroup.id) isSelected [hsx|<span>{rosterGroup.name}</span>|])
        { appToggleInputName = Just "rosterGroupIds"
        , appToggleInputValue = tshow rosterGroup.id
        , appToggleButtonClass = "btn-sm timesheet-approval-toggle shift-preference-availability-button w-100 d-flex align-items-center justify-content-center gap-1"
        }

