module Web.View.Staff.Edit where

import Web.View.Prelude

data EditView = EditView
    { staff      :: Staff
    , rosterGroups :: [RosterGroup]
    , selectedRosterGroupIds :: [Id RosterGroup]
    , weekOffset :: Int
    , maybeRosterGroupId :: Maybe (Id RosterGroup)
    }

instance View EditView where
    html EditView { .. } =
        renderStaffEditPageModal
            weekOffset
            staffEditFormId
            (renderForm PageOverlayForm staff rosterGroups selectedRosterGroupIds weekOffset maybeRosterGroupId (UpdateStaffAction (get #id staff)))

staffEditFormId :: Text
staffEditFormId = "staff-edit-form"

renderStaffEditModalFragment :: Staff -> [RosterGroup] -> [Id RosterGroup] -> Int -> Maybe (Id RosterGroup) -> Html
renderStaffEditModalFragment staff rosterGroups selectedRosterGroupIds weekOffset maybeRosterGroupId =
    renderStaffEditDialog
        staffEditFormId
        (renderForm HtmxOverlayForm staff rosterGroups selectedRosterGroupIds weekOffset maybeRosterGroupId (UpdateStaffAction (get #id staff)))

renderForm :: OverlayFormMode -> Staff -> [RosterGroup] -> [Id RosterGroup] -> Int -> Maybe (Id RosterGroup) -> StaffController -> Html
renderForm formMode staff rosterGroups selectedRosterGroupIds weekOffset maybeRosterGroupId action =
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
                {renderFormFields staff rosterGroups selectedRosterGroupIds weekOffset maybeRosterGroupId}
            </form>
        |]
        PageOverlayForm -> [hsx|
            <form id={staffEditFormId}
                  method="POST"
                  action={action}
                  class="mt-3">
                {renderFormFields staff rosterGroups selectedRosterGroupIds weekOffset maybeRosterGroupId}
            </form>
        |]

renderFormFields :: Staff -> [RosterGroup] -> [Id RosterGroup] -> Int -> Maybe (Id RosterGroup) -> Html
renderFormFields staff rosterGroups selectedRosterGroupIds weekOffset maybeRosterGroupId = [hsx|
        <input type="hidden" name="weekOffset" value={tshow weekOffset} />
        {renderRosterGroupHiddenInput maybeRosterGroupId}
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
            <label for="idealShiftsPerWeek" class="form-label">Ideal Shifts Per Week</label>
            <input
                id="idealShiftsPerWeek"
                name="idealShiftsPerWeek"
                type="number"
                min="0"
                max="14"
                class={inputClass staff "idealShiftsPerWeek"}
                value={maybe "" show staff.idealShiftsPerWeek}
                placeholder="Optional"
            />
            {renderStaffFieldError staff "idealShiftsPerWeek"}
        </div>
        <div class="mb-3">
            <label for="isActive" class="form-label">Status</label>
            <select name="isActive" id="isActive" class={selectClass staff "isActive"}>
                <option value="on" selected={staff.isActive}>Active</option>
                <option value="" selected={not staff.isActive}>Inactive</option>
            </select>
            {renderStaffFieldError staff "isActive"}
        </div>
        <div class="mb-3">
            <label class="form-label d-block">Roster Groups</label>
            <div class="row g-2">
                {forEach rosterGroups (renderRosterGroupCheckbox selectedRosterGroupIds)}
            </div>
        </div>
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
