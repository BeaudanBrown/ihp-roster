{-# LANGUAGE TypeApplications #-}

module Web.View.StaffProfileForm where

import Application.Helper.Controller (VenueRole (..), currentUserIsSuperAdmin,
                                      hasRole, parseVenueRole, venueRoleToText)
import qualified Application.Helper.FrontendContract.Surface.Profile as Surface
import Application.Helper.FrontendContract.Surface.Values (SurfaceFields,
                                                           surfaceFieldNameFrom)
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
    , managementVenueMembership        :: Maybe VenueMembership
    , managementWeekOffset             :: Maybe Int
    , managementRosterGroupId          :: Maybe (Id RosterGroup)
    }

type StaffProfileDetailsSurfaceFieldsBuilder =
    Text ->
    Text ->
    Text ->
    Text ->
    Int ->
    Text ->
    Text ->
    Text ->
    Maybe Text ->
    Maybe Text ->
    Maybe Text ->
    Maybe Bool ->
    Maybe [UUID] ->
    SurfaceFields Surface.StaffProfileFields

buildStaffProfileDetailsSurfaceFields :: StaffProfileDetailsSurfaceFieldsBuilder -> Text -> Staff -> Maybe StaffManagementFieldData -> SurfaceFields Surface.StaffProfileFields
buildStaffProfileDetailsSurfaceFields buildFields section staff maybeManagement =
    buildFields
        submittedFirstName
        submittedLastName
        submittedPreferredName
        submittedPhone
        submittedIdealShiftsPerWeek
        submittedEmergencyContactName
        submittedEmergencyContactPhone
        submittedSection
        submittedVenueRole
        submittedEmploymentBasis
        submittedPayRateSelection
        submittedIsActive
        submittedRosterGroupIds
  where
    submittedFirstName = staff.firstName
    submittedLastName = staff.lastName
    submittedPreferredName = fromMaybe "" staff.preferredName
    submittedPhone = staff.phone
    submittedIdealShiftsPerWeek = staff.idealShiftsPerWeek
    submittedEmergencyContactName = staff.emergencyContactName
    submittedEmergencyContactPhone = staff.emergencyContactPhone
    submittedSection = section
    submittedVenueRole = maybeManagement >>= (.managementVenueMembership) >>= parseVenueRole >>= (Just . venueRoleToText)
    submittedEmploymentBasis = inputValue . (.employmentBasis) . (.managementStaff) <$> maybeManagement
    submittedPayRateSelection = staffPayRateSelectionValue . (.managementStaff) <$> maybeManagement
    submittedIsActive = (.isActive) . (.managementStaff) <$> maybeManagement
    submittedRosterGroupIds = fmap (map unpackId . (.managementSelectedRosterGroupIds)) maybeManagement

type StaffShiftPreferencesSurfaceFieldsBuilder =
    Text ->
    Maybe [Text] ->
    SurfaceFields Surface.StaffShiftPreferenceFields

buildStaffShiftPreferencesSurfaceFields :: StaffShiftPreferencesSurfaceFieldsBuilder -> Text -> [ShiftPreferenceSelection] -> SurfaceFields Surface.StaffShiftPreferenceFields
buildStaffShiftPreferencesSurfaceFields buildFields section selectedShiftPreferences =
    buildFields
        submittedSection
        submittedShiftPreferenceKeys
  where
    submittedSection = section
    submittedShiftPreferenceKeys = Just (map (encodeShiftPreferenceKey . (.weekdayIndex)) selectedShiftPreferences)

staffPayRateSelectionValue :: Staff -> Text
staffPayRateSelectionValue staff =
    case (staff.importedXeroPayItemId, staff.defaultAwardLevelId) of
        (Just importedPayItemId, _)  -> "xero:" <> inputValue importedPayItemId
        (Nothing, Just awardLevelId) -> "award:" <> inputValue awardLevelId
        (Nothing, Nothing)           -> ""

renderPersonalProfileFields :: SurfaceFields Surface.StaffProfileFields -> Staff -> Maybe Text -> Html
renderPersonalProfileFields fields = renderPersonalProfileFieldsWithEmailId fields "email"

renderPersonalProfileFieldsWithEmailId :: SurfaceFields Surface.StaffProfileFields -> Text -> Staff -> Maybe Text -> Html
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

renderPersonalProfileFieldsWithEmailSlot :: SurfaceFields Surface.StaffProfileFields -> Html -> Staff -> Html
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

renderShiftPreferenceSections :: SurfaceFields Surface.StaffShiftPreferenceFields -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Html
renderShiftPreferenceSections fields weekdays selectedShiftPreferences =
    if null weekdays
        then [hsx|<p class="app-muted mb-0">Shift preferences will appear once the venue calendar is configured.</p>|]
        else [hsx|
    <section class={appSurfaceClasses "p-3"}>
        {renderShiftPreferenceRows fields weekdays selectedShiftPreferences}
    </section>
|]

renderShiftPreferenceRows :: SurfaceFields Surface.StaffShiftPreferenceFields -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Html
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

renderShiftPreferenceDayRow :: SurfaceFields Surface.StaffShiftPreferenceFields -> [ShiftPreferenceSelection] -> PreferenceWeekday -> Html
renderShiftPreferenceDayRow fields selectedShiftPreferences weekday =
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
                {renderShiftPreferenceAvailabilityToggle fields key weekdayLabel weekday.label isSelected}
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

renderShiftPreferenceAvailabilityToggle :: SurfaceFields Surface.StaffShiftPreferenceFields -> Text -> Text -> Text -> Bool -> Html
renderShiftPreferenceAvailabilityToggle fields key weekdayLabel fullWeekdayLabel isSelected =
    renderAppToggleButton $ (defaultAppToggleButtonConfig ("shiftPreferenceAvailable-" <> key) isSelected [hsx|
        <span>{weekdayLabel}</span>
        <span class="visually-hidden">{fullWeekdayLabel} available</span>
    |])
        { appToggleInputName = Just (surfaceFieldNameFrom @Surface.ShiftPreferenceKeysField fields)
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

renderStaffManagementFields :: SurfaceFields Surface.StaffProfileFields -> StaffManagementFieldData -> Html
renderStaffManagementFields fields StaffManagementFieldData { managementStaff = staff, managementRosterGroups = rosterGroups, managementAwardLevels = awardLevels, managementAwardLevelBaseRates = awardLevelBaseRates, managementImportedPayItems = importedPayItems, managementSelectedRosterGroupIds = selectedRosterGroupIds, managementVenueMembership = maybeMembership, managementWeekOffset = maybeWeekOffset, managementRosterGroupId = maybeRosterGroupId } = [hsx|
    {maybe mempty renderWeekOffsetHiddenInput maybeWeekOffset}
    {renderRosterGroupHiddenInput maybeRosterGroupId}
    {when currentUserIsAdmin (renderStaffRoleField fields maybeMembership)}
    {when currentUserIsAdmin (renderStaffPayFields fields staff awardLevels awardLevelBaseRates importedPayItems)}
    <div class="mt-3">
        <label for="isActive" class="form-label">Status</label>
        <select name={surfaceFieldNameFrom @Surface.IsActiveField fields} id="isActive" class={selectClass staff (surfaceFieldNameFrom @Surface.IsActiveField fields)}>
            <option value="true" selected={staff.isActive}>Active</option>
            <option value="false" selected={not staff.isActive}>Inactive</option>
        </select>
        {renderStaffFieldError staff (surfaceFieldNameFrom @Surface.IsActiveField fields)}
    </div>
    <div class="mt-3">
        <label class="form-label d-block">Roster Groups</label>
        <div class="row g-2">
            {forEach rosterGroups (renderRosterGroupCheckbox fields selectedRosterGroupIds)}
        </div>
    </div>
|]

renderWeekOffsetHiddenInput :: Int -> Html
renderWeekOffsetHiddenInput weekOffset = [hsx|<input type="hidden" name="weekOffset" value={tshow weekOffset} />|]

renderStaffRoleField :: SurfaceFields Surface.StaffProfileFields -> Maybe VenueMembership -> Html
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

assignableVenueRoles :: (?context :: ControllerContext) => [VenueRole]
assignableVenueRoles =
    [WorkerRole, SupervisorRole, ManagerRole', VenueAdminRole]
        <> [VenueOwnerRole | currentUserIsSuperAdmin || hasRole VenueOwnerRole]

renderVenueRoleOption :: VenueMembership -> VenueRole -> Html
renderVenueRoleOption membership venueRole = [hsx|
    <option value={venueRoleToText venueRole} selected={parseVenueRole membership.venueRole == Just venueRole}>{venueRoleLabel venueRole}</option>
|]

venueRoleLabel :: VenueRole -> Text
venueRoleLabel WorkerRole     = "Worker"
venueRoleLabel SupervisorRole = "Supervisor"
venueRoleLabel ManagerRole'   = "Manager"
venueRoleLabel VenueAdminRole = "Venue Admin"
venueRoleLabel VenueOwnerRole = "Venue Owner"

renderStaffPayFields :: SurfaceFields Surface.StaffProfileFields -> Staff -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> Html
renderStaffPayFields fields staff awardLevels awardLevelBaseRates importedPayItems = [hsx|
    <div class="row g-3 mt-3 staff-pay-field-grid">
        <div class="col-12 col-md-6">
            <label for="employmentBasis" class="form-label">Employment Basis</label>
            <select name={surfaceFieldNameFrom @Surface.EmploymentBasisField fields} id="employmentBasis" class={selectClass staff (surfaceFieldNameFrom @Surface.EmploymentBasisField fields)}>
                <option value="permanent" selected={staff.employmentBasis == Permanent}>Permanent</option>
                <option value="casual" selected={staff.employmentBasis == Casual}>Casual</option>
            </select>
            {renderStaffFieldError staff (surfaceFieldNameFrom @Surface.EmploymentBasisField fields)}
        </div>
        <div class="col-12 col-md-6">
            <label for="payRateSelection" class="form-label">Default Pay Rate</label>
            <select name={surfaceFieldNameFrom @Surface.PayRateSelectionField fields} id="payRateSelection" class={selectClass staff "defaultAwardLevelId"}>
                <option value="" selected={isNothing staff.defaultAwardLevelId && isNothing staff.importedXeroPayItemId}>Not assigned</option>
                {renderAwardLevelOptionsGroup staff awardLevels awardLevelBaseRates}
                {renderImportedPayItemOptionsGroup staff.importedXeroPayItemId importedPayItems}
            </select>
            {renderStaffFieldError staff "defaultAwardLevelId"}
            {renderStaffFieldError staff "importedXeroPayItemId"}
        </div>
    </div>
|]

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

renderRosterGroupCheckbox :: SurfaceFields Surface.StaffProfileFields -> [Id RosterGroup] -> RosterGroup -> Html
renderRosterGroupCheckbox fields selectedRosterGroupIds rosterGroup =
    let isSelected = rosterGroup.id `elem` selectedRosterGroupIds
     in [hsx|
        <div class="col-12 col-md-6">
            {renderRosterGroupToggle fields rosterGroup isSelected}
        </div>
    |]

renderRosterGroupToggle :: SurfaceFields Surface.StaffProfileFields -> RosterGroup -> Bool -> Html
renderRosterGroupToggle fields rosterGroup isSelected =
    renderAppToggleButton $ (defaultAppToggleButtonConfig ("staff-roster-group-" <> tshow rosterGroup.id) isSelected [hsx|<span>{rosterGroup.name}</span>|])
        { appToggleInputName = Just (surfaceFieldNameFrom @Surface.RosterGroupIdsField fields)
        , appToggleInputValue = tshow rosterGroup.id
        , appToggleButtonClass = "btn-sm timesheet-approval-toggle shift-preference-availability-button w-100 d-flex align-items-center justify-content-center gap-1"
        }

