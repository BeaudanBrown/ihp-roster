module Web.View.Staff.Edit where

import Application.Helper.StaffShiftPreferences
import Web.View.Prelude
import Web.View.StaffProfileForm

data EditView = EditView
    { staff                       :: Staff
    , maybeLinkedUserEmail        :: Maybe Text
    , rosterGroups                :: [RosterGroup]
    , selectedRosterGroupIds      :: [Id RosterGroup]
    , preferenceWeekdays          :: [PreferenceWeekday]
    , preferenceSections          :: [StaffPreferenceGroupSection]
    , selectedShiftPreferenceKeys :: [Text]
    , weekOffset                  :: Int
    , maybeRosterGroupId          :: Maybe (Id RosterGroup)
    }

instance View EditView where
    html EditView { .. } =
        renderStaffEditPageModal
            weekOffset
            staffEditFormId
            (renderForm PageOverlayForm staff maybeLinkedUserEmail rosterGroups selectedRosterGroupIds preferenceWeekdays preferenceSections selectedShiftPreferenceKeys weekOffset maybeRosterGroupId (UpdateStaffAction (get #id staff)))

staffEditFormId :: Text
staffEditFormId = "staff-edit-form"

renderStaffEditModalFragment :: Staff -> Maybe Text -> [RosterGroup] -> [Id RosterGroup] -> [PreferenceWeekday] -> [StaffPreferenceGroupSection] -> [Text] -> Int -> Maybe (Id RosterGroup) -> Html
renderStaffEditModalFragment staff maybeLinkedUserEmail rosterGroups selectedRosterGroupIds preferenceWeekdays preferenceSections selectedShiftPreferenceKeys weekOffset maybeRosterGroupId =
    renderStaffEditDialog
        staffEditFormId
        (renderForm HtmxOverlayForm staff maybeLinkedUserEmail rosterGroups selectedRosterGroupIds preferenceWeekdays preferenceSections selectedShiftPreferenceKeys weekOffset maybeRosterGroupId (UpdateStaffAction (get #id staff)))

renderForm :: OverlayFormMode -> Staff -> Maybe Text -> [RosterGroup] -> [Id RosterGroup] -> [PreferenceWeekday] -> [StaffPreferenceGroupSection] -> [Text] -> Int -> Maybe (Id RosterGroup) -> StaffController -> Html
renderForm formMode staff maybeLinkedUserEmail rosterGroups selectedRosterGroupIds preferenceWeekdays preferenceSections selectedShiftPreferenceKeys weekOffset maybeRosterGroupId action =
    case formMode of
        HtmxOverlayForm -> [hsx|
            <form id={staffEditFormId}
                  method="POST"
                  action={action}
                  class="mt-3"
                  data-disable-javascript-submission="true"
                  hx-post={action}
                  hx-target={"#" <> dialogOverlayMountId}
                  hx-swap="innerHTML"
                  hx-push-url="false">
                {renderFormFields staff maybeLinkedUserEmail rosterGroups selectedRosterGroupIds preferenceWeekdays preferenceSections selectedShiftPreferenceKeys weekOffset maybeRosterGroupId}
            </form>
        |]
        PageOverlayForm -> [hsx|
            <form id={staffEditFormId}
                  method="POST"
                  action={action}
                  class="mt-3">
                {renderFormFields staff maybeLinkedUserEmail rosterGroups selectedRosterGroupIds preferenceWeekdays preferenceSections selectedShiftPreferenceKeys weekOffset maybeRosterGroupId}
            </form>
        |]

renderFormFields :: Staff -> Maybe Text -> [RosterGroup] -> [Id RosterGroup] -> [PreferenceWeekday] -> [StaffPreferenceGroupSection] -> [Text] -> Int -> Maybe (Id RosterGroup) -> Html
renderFormFields staff maybeLinkedUserEmail rosterGroups selectedRosterGroupIds preferenceWeekdays preferenceSections selectedShiftPreferenceKeys weekOffset maybeRosterGroupId = [hsx|
        <input type="hidden" name="weekOffset" value={tshow weekOffset} />
        {renderRosterGroupHiddenInput maybeRosterGroupId}
        {renderPersonalProfileFields staff maybeLinkedUserEmail}
        <div class="mb-3">
            <label for="isActive" class="form-label">Status</label>
            <select name="isActive" id="isActive" class={selectClass staff "isActive"}>
                <option value="on" selected={staff.isActive}>Active</option>
                <option value="" selected={not staff.isActive}>Inactive</option>
            </select>
            {renderStaffFieldError staff "isActive"}
        </div>
        <div class="mb-3">
            <label class="form-label d-block">Schedule Groups</label>
            <div class="row g-2">
                {forEach rosterGroups (renderRosterGroupCheckbox selectedRosterGroupIds)}
            </div>
        </div>
        <div class="mb-3">
            <label class="form-label d-block">Shift Preferences</label>
            {renderShiftPreferenceSections preferenceWeekdays preferenceSections selectedShiftPreferenceKeys}
        </div>
|]

renderRosterGroupHiddenInput :: Maybe (Id RosterGroup) -> Html
renderRosterGroupHiddenInput maybeRosterGroupId =
    case maybeRosterGroupId of
        Just rosterGroupId -> [hsx|<input type="hidden" name="rosterGroupId" value={tshow rosterGroupId} />|]
        Nothing -> mempty

renderRosterGroupCheckbox :: [Id RosterGroup] -> RosterGroup -> Html
renderRosterGroupCheckbox selectedRosterGroupIds rosterGroup = [hsx|
    <div class="col-12 col-md-6">
        <label class="form-check border rounded p-2 d-flex align-items-center gap-2">
            <input
                class="form-check-input mt-0"
                type="checkbox"
                name="rosterGroupIds"
                value={tshow rosterGroup.id}
                checked={rosterGroup.id `elem` selectedRosterGroupIds}
            />
            <span class="form-check-label">
                {rosterGroup.name}
                {renderRosterGroupDefaultLabel rosterGroup}
            </span>
        </label>
    </div>
|]

renderRosterGroupDefaultLabel :: RosterGroup -> Html
renderRosterGroupDefaultLabel rosterGroup
    | rosterGroup.isDefault = [hsx|<span class="small app-muted ms-1">(default)</span>|]
    | otherwise = mempty
