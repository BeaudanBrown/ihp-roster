{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeApplications #-}

module Web.View.StaffProfileForm where

import Application.Helper.Controller (assignableVenueRolesFor,
                                      currentUserIsUnimpersonatedSuperAdmin,
                                      effectiveVenueRoleOrNothing,
                                      venueRoleLabel, venueRoleToText)
import Application.Helper.FrontendContract.OrderedRange.Runtime
import qualified Application.Helper.FrontendContract.Surface.Profile as Surface
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.StaffShiftPreferences
import Application.PayAssignment (StaffPayAssignment (..),
                                  staffPayAssignmentRequiresRemediation)
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import Web.View.Prelude

data StaffManagementFieldData = StaffManagementFieldData
    { managementStaff                  :: Staff
    , managementRosterGroups           :: [RosterGroup]
    , managementAwardLevels            :: [AwardLevel]
    , managementAwardLevelBaseRates    :: [AwardLevelBaseRate]
    , managementImportedPayItems       :: [XeroImportedPayItem]
    , managementSelectedRosterGroupIds :: [Id RosterGroup]
    , managementVenueMembership        :: Maybe VenueMembership
    , managementWeekOffset             :: Maybe Int
    , managementRosterGroupId          :: Maybe (Id RosterGroup)
    }

data StaffProfileDetailsSurfaceValues = StaffProfileDetailsSurfaceValues
    { profileDetailsFirstName             :: !Text
    , profileDetailsLastName              :: !Text
    , profileDetailsPreferredName         :: !Text
    , profileDetailsPhone                 :: !Text
    , profileDetailsIdealShiftsPerWeek    :: !Int
    , profileDetailsEmergencyContactName  :: !Text
    , profileDetailsEmergencyContactPhone :: !Text
    , profileDetailsSection               :: !Text
    , profileDetailsVenueRole             :: !(Maybe Text)
    , profileDetailsEmploymentBasis       :: !(Maybe Text)
    , profileDetailsPayRateSelection      :: !(Maybe Text)
    , profileDetailsRosterGroupIds        :: !(Maybe [UUID.UUID])
    }

staffProfileDetailsSurfaceValues :: Text -> Staff -> Maybe StaffManagementFieldData -> StaffProfileDetailsSurfaceValues
staffProfileDetailsSurfaceValues section staff maybeManagement =
    StaffProfileDetailsSurfaceValues
        { profileDetailsFirstName = staff.firstName
        , profileDetailsLastName = staff.lastName
        , profileDetailsPreferredName = fromMaybe "" staff.preferredName
        , profileDetailsPhone = staff.phone
        , profileDetailsIdealShiftsPerWeek = staff.idealShiftsPerWeek
        , profileDetailsEmergencyContactName = staff.emergencyContactName
        , profileDetailsEmergencyContactPhone = staff.emergencyContactPhone
        , profileDetailsSection = section
        , profileDetailsVenueRole = venueRoleToText . (.venueRole) <$> (maybeManagement >>= (.managementVenueMembership))
        , profileDetailsEmploymentBasis = inputValue . (.employmentBasis) . (.managementStaff) <$> maybeManagement
        , profileDetailsPayRateSelection = staffPayRateSelectionValue . (.managementStaff) <$> maybeManagement
        , profileDetailsRosterGroupIds = fmap (map unpackId . (.managementSelectedRosterGroupIds)) maybeManagement
        }

data StaffShiftPreferencesSurfaceValues = StaffShiftPreferencesSurfaceValues
    { shiftPreferencesSection :: !Text
    , shiftPreferenceKeys     :: !(Maybe [Text])
    }

staffShiftPreferencesSurfaceValues :: Text -> [ShiftPreferenceSelection] -> StaffShiftPreferencesSurfaceValues
staffShiftPreferencesSurfaceValues section selectedShiftPreferences =
    StaffShiftPreferencesSurfaceValues
        { shiftPreferencesSection = section
        , shiftPreferenceKeys = Just (map (encodeShiftPreferenceKey . (.weekdayIndex)) selectedShiftPreferences)
        }

staffPayRateSelectionValue :: Staff -> Text
staffPayRateSelectionValue staff =
    case staff.payAssignmentMode of
        XeroRate -> maybe "" ("xero:" <>) (inputValue <$> staff.importedXeroPayItemId)
        AwardRate -> maybe "" ("award:" <>) (inputValue <$> staff.defaultAwardLevelId)
        RosterOnly -> ""
        LegacyUnresolved -> "legacy-unresolved"
        StaffDefault -> "legacy-unresolved"

renderPersonalProfileFields :: SurfaceFieldBundleOf Surface.StaffProfileFields fields => fields -> Staff -> Maybe Text -> Html
renderPersonalProfileFields fields = renderPersonalProfileFieldsWithEmailId fields "email"

renderPersonalProfileFieldsWithEmailId :: SurfaceFieldBundleOf Surface.StaffProfileFields fields => fields -> Text -> Staff -> Maybe Text -> Html
renderPersonalProfileFieldsWithEmailId fields emailFieldId staff maybeEmail =
    renderPersonalProfileFieldsWithEmailSlot fields (renderReadonlyEmailField emailFieldId maybeEmail) staff

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

renderPersonalProfileFieldsWithEmailSlot :: SurfaceFieldBundleOf Surface.StaffProfileFields fields => fields -> Html -> Staff -> Html
renderPersonalProfileFieldsWithEmailSlot fields emailField staff = [hsx|
    <div class="row g-3 profile-field-grid">
        <div class="col-12 col-lg-6">
            <label for="firstName" class="form-label">First Name</label>
            <input
                id="firstName"
                name={surfaceFieldNameFrom @Surface.FirstNameField fields}
                type="text"
                class={inputClass staff (surfaceFieldNameFrom @Surface.FirstNameField fields)}
                value={staff.firstName}
                required="required"
            />
            {renderStaffFieldError staff (surfaceFieldNameFrom @Surface.FirstNameField fields)}
        </div>
        <div class="col-12 col-lg-6">
            <label for="lastName" class="form-label">Last Name</label>
            <input
                id="lastName"
                name={surfaceFieldNameFrom @Surface.LastNameField fields}
                type="text"
                class={inputClass staff (surfaceFieldNameFrom @Surface.LastNameField fields)}
                value={staff.lastName}
                required="required"
            />
            {renderStaffFieldError staff (surfaceFieldNameFrom @Surface.LastNameField fields)}
        </div>
        <div class="col-12 col-lg-6">
            <label for="preferredName" class="form-label">Preferred Name</label>
            <input
                id="preferredName"
                name={surfaceFieldNameFrom @Surface.PreferredNameField fields}
                type="text"
                class={inputClass staff (surfaceFieldNameFrom @Surface.PreferredNameField fields)}
                value={fromMaybe "" staff.preferredName}
                placeholder="Optional"
            />
            {renderStaffFieldError staff (surfaceFieldNameFrom @Surface.PreferredNameField fields)}
        </div>
        {emailField}
        <div class="col-12 col-lg-6">
            <label for="phone" class="form-label">Phone #</label>
            <input
                id="phone"
                name={surfaceFieldNameFrom @Surface.PhoneField fields}
                type="text"
                class={inputClass staff (surfaceFieldNameFrom @Surface.PhoneField fields)}
                value={staff.phone}
                required="required"
            />
            {renderStaffFieldError staff (surfaceFieldNameFrom @Surface.PhoneField fields)}
        </div>
        <div class="col-12 col-lg-6">
            <label for="idealShiftsPerWeek" class="form-label">Ideal # Shifts</label>
            <select
                id="idealShiftsPerWeek"
                name={surfaceFieldNameFrom @Surface.IdealShiftsPerWeekField fields}
                class={selectClass staff (surfaceFieldNameFrom @Surface.IdealShiftsPerWeekField fields)}
                required="required"
            >
                {forEach [0 :: Int .. 7] (renderIdealShiftsOption staff.idealShiftsPerWeek)}
            </select>
            {renderStaffFieldError staff (surfaceFieldNameFrom @Surface.IdealShiftsPerWeekField fields)}
        </div>
        <div class="col-12 col-lg-6">
            <label for="emergencyContactName" class="form-label">Emergency Contact Name</label>
            <input
                id="emergencyContactName"
                name={surfaceFieldNameFrom @Surface.EmergencyContactNameField fields}
                type="text"
                class={inputClass staff (surfaceFieldNameFrom @Surface.EmergencyContactNameField fields)}
                value={staff.emergencyContactName}
                required="required"
            />
            {renderStaffFieldError staff (surfaceFieldNameFrom @Surface.EmergencyContactNameField fields)}
        </div>
        <div class="col-12 col-lg-6">
            <label for="emergencyContactPhone" class="form-label">Emergency Contact Number</label>
            <input
                id="emergencyContactPhone"
                name={surfaceFieldNameFrom @Surface.EmergencyContactPhoneField fields}
                type="text"
                class={inputClass staff (surfaceFieldNameFrom @Surface.EmergencyContactPhoneField fields)}
                value={staff.emergencyContactPhone}
                required="required"
            />
            {renderStaffFieldError staff (surfaceFieldNameFrom @Surface.EmergencyContactPhoneField fields)}
        </div>
    </div>
|]

renderIdealShiftsOption :: Int -> Int -> Html
renderIdealShiftsOption selectedValue optionValue = [hsx|
    <option value={tshow optionValue} selected={optionValue == selectedValue}>{optionValue}</option>
|]

renderShiftPreferenceSections :: SurfaceFieldBundleOf Surface.StaffShiftPreferenceFields fields => fields -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Html
renderShiftPreferenceSections fields weekdays selectedShiftPreferences =
    if null weekdays
        then [hsx|<p class="app-muted mb-0">Shift preferences will appear once the venue calendar is configured.</p>|]
        else [hsx|
    <section class={appSurfaceClasses "p-3"}>
        {renderShiftPreferenceRows fields weekdays selectedShiftPreferences}
    </section>
|]

renderShiftPreferenceRows :: SurfaceFieldBundleOf Surface.StaffShiftPreferenceFields fields => fields -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Html
renderShiftPreferenceRows fields weekdays selectedShiftPreferences = [hsx|
    <table class="table table-sm align-middle shift-preference-table mb-0">
        <thead>
            <tr>
                <th scope="col" class="shift-preference-table__available">Available</th>
            </tr>
        </thead>
        <tbody>
            {forEach weekdays (renderShiftPreferenceDayRow fields selectedShiftPreferences)}
        </tbody>
    </table>
|]

renderShiftPreferenceDayRow :: SurfaceFieldBundleOf Surface.StaffShiftPreferenceFields fields => fields -> [ShiftPreferenceSelection] -> PreferenceWeekday -> Html
renderShiftPreferenceDayRow fields selectedShiftPreferences weekday =
    let key = encodeShiftPreferenceKey weekday.weekdayIndex
        selectedPreference = findSelectedShiftPreference weekday.weekdayIndex selectedShiftPreferences
        isSelected = isJust selectedPreference
        startHour = maybe defaultPreferenceStartHour (.startHour) selectedPreference
        endHour = maybe defaultPreferenceEndHour (.endHour) selectedPreference
        weekdayLabel = abbreviateWeekdayLabel weekday.label
        rangeConfig = shiftPreferenceOrderedRangeConfig
        rangeState = OrderedRangeBrowserState
            { orderedRangeStartValue = startHour
            , orderedRangeEndValue = endHour
            , orderedRangeAvailable = isSelected
            }
     in [hsx|
        <tr class="shift-preference-window"
             style={orderedRangePositionStyle rangeConfig rangeState}
             {...orderedRangeRootAttrs rangeConfig rangeState}>
            <th scope="row" class="shift-preference-table__available" {...orderedRangeAvailabilityAttrs}>
                {renderShiftPreferenceAvailabilityToggle fields key weekdayLabel weekday.label isSelected}
            </th>
            <td class="shift-preference-table__start-time">
                <div class="shift-preference-window__controls">
                    <div class="shift-preference-range">
                        <div class="shift-preference-range__labels" aria-hidden="true">
                            <output class="shift-preference-range__bubble shift-preference-range__bubble--start" for={"shiftPreferenceStart-" <> key} aria-hidden="true">{formatPreferenceHour startHour}</output>
                            <output class="shift-preference-range__bubble shift-preference-range__bubble--end" for={"shiftPreferenceEnd-" <> key} aria-hidden="true">{formatPreferenceHour endHour}</output>
                        </div>
                        <div class="shift-preference-range__track" aria-hidden="true">
                            <div class="shift-preference-range__fill"></div>
                        </div>
                        <label class="visually-hidden" for={"shiftPreferenceStart-" <> key}>Earliest preferred start</label>
                        <input
                            id={"shiftPreferenceStart-" <> key}
                            class="shift-preference-range__input"
                            type="range"
                            name={shiftPreferenceStartHourParamName key}
                            value={tshow startHour}
                            disabled={not isSelected}
                            {...orderedRangeStartAttrs rangeConfig}
                        />
                        <label class="visually-hidden" for={"shiftPreferenceEnd-" <> key}>Latest preferred start</label>
                        <input
                            id={"shiftPreferenceEnd-" <> key}
                            class="shift-preference-range__input"
                            type="range"
                            name={shiftPreferenceEndHourParamName key}
                            value={tshow endHour}
                            disabled={not isSelected}
                            {...orderedRangeEndAttrs rangeConfig}
                        />
                    </div>
                </div>
            </td>
        </tr>
    |]

renderShiftPreferenceAvailabilityToggle :: SurfaceFieldBundleOf Surface.StaffShiftPreferenceFields fields => fields -> Text -> Text -> Text -> Bool -> Html
renderShiftPreferenceAvailabilityToggle fields key weekdayLabel fullWeekdayLabel isSelected =
    renderAppToggleButton $
        ( defaultAppToggleButtonConfig
            ("shiftPreferenceAvailable-" <> key)
            (surfaceToggleListItemField @Surface.ShiftPreferenceKeysField fields key)
            isSelected
            [hsx|
                <span>{weekdayLabel}</span>
                <span class="visually-hidden">{fullWeekdayLabel} available</span>
            |]
        )
            { appToggleButtonClass = "btn-sm timesheet-approval-toggle shift-preference-availability-button" }

abbreviateWeekdayLabel :: Text -> Text
abbreviateWeekdayLabel = Text.take 3

shiftPreferenceOrderedRangeConfig :: OrderedRangeBrowserConfig
shiftPreferenceOrderedRangeConfig = OrderedRangeBrowserConfig
    { orderedRangeMinimumValue = preferenceMinimumHour
    , orderedRangeMaximumValue = preferenceMaximumHour
    , orderedRangeStepValue = 1
    , orderedRangeDefaultStartValue = defaultPreferenceStartHour
    , orderedRangeDefaultEndValue = defaultPreferenceEndHour
    , orderedRangeValueLabels = map formatPreferenceHour preferenceHourOptions
    , orderedRangeCrossingPolicy = ClampOtherEndpoint
    }

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

renderStaffManagementFields :: SurfaceFieldBundleOf Surface.StaffProfileFields fields => fields -> StaffManagementFieldData -> Html
renderStaffManagementFields fields StaffManagementFieldData { managementStaff = staff, managementRosterGroups = rosterGroups, managementAwardLevels = awardLevels, managementAwardLevelBaseRates = awardLevelBaseRates, managementImportedPayItems = importedPayItems, managementSelectedRosterGroupIds = selectedRosterGroupIds, managementVenueMembership = maybeMembership, managementWeekOffset = maybeWeekOffset, managementRosterGroupId = maybeRosterGroupId } = [hsx|
    {maybe mempty renderWeekOffsetHiddenInput maybeWeekOffset}
    {renderRosterGroupHiddenInput maybeRosterGroupId}
    {when currentUserIsAdmin (renderStaffRoleField fields maybeMembership)}
    {when currentUserIsAdmin (renderStaffPayFields fields staff awardLevels awardLevelBaseRates importedPayItems)}
    <div class="mt-3">
        <label class="form-label d-block">Roster Groups</label>
        <div class="row g-2">
            {forEach rosterGroups (renderRosterGroupCheckbox fields selectedRosterGroupIds)}
        </div>
    </div>
|]

renderWeekOffsetHiddenInput :: Int -> Html
renderWeekOffsetHiddenInput weekOffset = [hsx|<input type="hidden" name="weekOffset" value={tshow weekOffset} />|]

renderStaffRoleField :: SurfaceFieldBundleOf Surface.StaffProfileFields fields => fields -> Maybe VenueMembership -> Html
renderStaffRoleField _ Nothing = [hsx|
    <div class="mt-3">
        <div class="form-label">Staff Role</div>
        <div class="alert alert-secondary py-2 mb-0" role="note">
            A venue access role can be assigned after this staff profile is linked to a user account. For eligible trial staff, send an invitation from the roster staff list first.
        </div>
    </div>
|]
renderStaffRoleField fields (Just membership) = [hsx|
    <div class="mt-3">
        <label for="venueRole" class="form-label">Staff Role</label>
        <select name={surfaceFieldNameFrom @Surface.VenueRoleField fields} id="venueRole" class="form-select">
            {forEach assignableVenueRoles (renderVenueRoleOption membership)}
        </select>
        <div class="form-text">Controls this person's access level in the current venue.</div>
    </div>
|]

assignableVenueRoles :: (?context :: ControllerContext) => [VenueRoleEnum]
assignableVenueRoles =
    assignableVenueRolesFor currentUserIsUnimpersonatedSuperAdmin effectiveVenueRoleOrNothing

renderVenueRoleOption :: VenueMembership -> VenueRoleEnum -> Html
renderVenueRoleOption membership venueRole = [hsx|
    <option value={venueRoleToText venueRole} selected={membership.venueRole == venueRole}>{venueRoleLabel venueRole}</option>
|]

renderStaffPayFields :: SurfaceFieldBundleOf Surface.StaffProfileFields fields => fields -> Staff -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> Html
renderStaffPayFields fields staff awardLevels awardLevelBaseRates importedPayItems = [hsx|
    <div class="row g-3 mt-3 staff-pay-field-grid">
        <div class="col-12 col-md-6">
            <label for="employmentBasis" class="form-label">Employment Basis</label>
            <select name={surfaceFieldNameFrom @Surface.EmploymentBasisField fields} id="employmentBasis" class={selectClass staff (surfaceFieldNameFrom @Surface.EmploymentBasisField fields)}>
                <option value="permanent" selected={staff.employmentBasis == Permanent}>Part-time</option>
                <option value="casual" selected={staff.employmentBasis == Casual}>Casual</option>
            </select>
            {renderStaffFieldError staff (surfaceFieldNameFrom @Surface.EmploymentBasisField fields)}
        </div>
        <div class="col-12 col-md-6">
            <label for="payRateSelection" class="form-label">Default Pay Rate</label>
            <select name={surfaceFieldNameFrom @Surface.PayRateSelectionField fields} id="payRateSelection" class={selectClass staff "defaultAwardLevelId"}>
                {renderLegacyPaySelectionOption staff}
                <option value="" selected={staff.payAssignmentMode == RosterOnly}>No Timesheets (roster only)</option>
                {renderAwardLevelOptionsGroup staff awardLevels awardLevelBaseRates}
                {renderImportedPayItemOptionsGroup staff.importedXeroPayItemId importedPayItems}
            </select>
            {renderStaffPayAssignmentWarning staff awardLevels importedPayItems}
            {renderStaffFieldError staff "defaultAwardLevelId"}
            {renderStaffFieldError staff "importedXeroPayItemId"}
        </div>
    </div>
|]

renderLegacyPaySelectionOption :: Staff -> Html
renderLegacyPaySelectionOption staff
    | staff.payAssignmentMode == LegacyUnresolved = [hsx|<option value="legacy-unresolved" selected={True} disabled={True}>Pay configuration required — choose a rate or roster-only</option>|]
    | otherwise = mempty

renderStaffPayAssignmentWarning :: Staff -> [AwardLevel] -> [XeroImportedPayItem] -> Html
renderStaffPayAssignmentWarning staff awardLevels importedPayItems
    | not (staffPayAssignmentRequiresRemediation (map (.id) awardLevels) (map (.id) importedPayItems) assignment) = mempty
    | otherwise = [hsx|<div class="form-text text-warning" role="alert">Pay configuration required. Choose a default pay rate or “No Timesheets (roster only).”</div>|]
  where
    assignment = StaffPayAssignment staff.payAssignmentMode staff.defaultAwardLevelId staff.importedXeroPayItemId

renderImportedPayItemOptionsGroup :: Maybe (Id XeroImportedPayItem) -> [XeroImportedPayItem] -> Html
renderImportedPayItemOptionsGroup _ [] = mempty
renderImportedPayItemOptionsGroup selectedImportedPayItemId importedPayItems = [hsx|
    <optgroup label="Xero imported rates">
        {forEach importedPayItems (renderImportedPayItemOption selectedImportedPayItemId)}
    </optgroup>
|]

renderImportedPayItemOption :: Maybe (Id XeroImportedPayItem) -> XeroImportedPayItem -> Html
renderImportedPayItemOption selectedImportedPayItemId importedPayItem = [hsx|
    <option value={"xero:" <> inputValue importedPayItem.id} selected={selectedImportedPayItemId == Just importedPayItem.id}>
        {importedPayItem.name} — {tshow importedPayItem.ratePerUnit}/hr
    </option>
|]

renderAwardLevelOptionsGroup :: Staff -> [AwardLevel] -> [AwardLevelBaseRate] -> Html
renderAwardLevelOptionsGroup _ [] _ = mempty
renderAwardLevelOptionsGroup staff awardLevels awardLevelBaseRates = [hsx|
    <optgroup label="Award rates">
        {forEach awardLevels (renderAwardLevelOption staff awardLevelBaseRates)}
    </optgroup>
|]

renderAwardLevelOption :: Staff -> [AwardLevelBaseRate] -> AwardLevel -> Html
renderAwardLevelOption staff awardLevelBaseRates awardLevel = [hsx|
    <option value={"award:" <> inputValue awardLevel.id} selected={isNothing staff.importedXeroPayItemId && staff.defaultAwardLevelId == Just awardLevel.id}>
        {awardLevelOptionLabel awardLevelBaseRates awardLevel}
    </option>
|]

renderRosterGroupHiddenInput :: Maybe (Id RosterGroup) -> Html
renderRosterGroupHiddenInput maybeRosterGroupId =
    case maybeRosterGroupId of
        Just rosterGroupId -> [hsx|<input type="hidden" name="rosterGroupId" value={tshow rosterGroupId} />|]
        Nothing -> mempty

renderRosterGroupCheckbox :: SurfaceFieldBundleOf Surface.StaffProfileFields fields => fields -> [Id RosterGroup] -> RosterGroup -> Html
renderRosterGroupCheckbox fields selectedRosterGroupIds rosterGroup =
    let isSelected = rosterGroup.id `elem` selectedRosterGroupIds
     in [hsx|
        <div class="col-12 col-md-6">
            {renderRosterGroupToggle fields rosterGroup isSelected}
        </div>
    |]

renderRosterGroupToggle :: SurfaceFieldBundleOf Surface.StaffProfileFields fields => fields -> RosterGroup -> Bool -> Html
renderRosterGroupToggle fields rosterGroup isSelected =
    renderAppToggleButton $
        ( defaultAppToggleButtonConfig
            ("staff-roster-group-" <> tshow rosterGroup.id)
            (surfaceToggleListItemField @Surface.RosterGroupIdsField fields (unpackId rosterGroup.id))
            isSelected
            [hsx|<span>{rosterGroup.name}</span>|]
        )
            { appToggleButtonClass = "btn-sm timesheet-approval-toggle shift-preference-availability-button w-100 d-flex align-items-center justify-content-center gap-1" }

