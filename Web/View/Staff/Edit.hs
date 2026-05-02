module Web.View.Staff.Edit where

import Application.Helper.StaffShiftPreferences
import Web.View.Prelude
import Web.View.StaffDocuments.Rsa
import Web.View.StaffProfileForm

data EditView = EditView
    { staff                    :: Staff
    , maybeLinkedUserEmail     :: Maybe Text
    , rosterGroups             :: [RosterGroup]
    , awardLevels              :: [AwardLevel]
    , awardLevelBaseRates      :: [AwardLevelBaseRate]
    , selectedRosterGroupIds   :: [Id RosterGroup]
    , preferenceWeekdays       :: [PreferenceWeekday]
    , selectedShiftPreferences :: [ShiftPreferenceSelection]
    , staffRsaDocument         :: Maybe StaffDocument
    , today                    :: Day
    , weekOffset               :: Int
    , maybeRosterGroupId       :: Maybe (Id RosterGroup)
    }

instance View EditView where
    html EditView { .. } =
        renderStaffEditPageModal
            weekOffset
            staffEditFormId
            (renderStaffEditBody PageOverlayForm staff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates selectedRosterGroupIds preferenceWeekdays selectedShiftPreferences staffRsaDocument today weekOffset maybeRosterGroupId)

staffEditFormId :: Text
staffEditFormId = "staff-edit-form"

renderStaffEditModalFragment :: Staff -> Maybe Text -> [RosterGroup] -> [AwardLevel] -> [AwardLevelBaseRate] -> [Id RosterGroup] -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Maybe StaffDocument -> Day -> Int -> Maybe (Id RosterGroup) -> Html
renderStaffEditModalFragment staff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates selectedRosterGroupIds preferenceWeekdays selectedShiftPreferences staffRsaDocument today weekOffset maybeRosterGroupId =
    renderStaffEditDialog
        staffEditFormId
        (renderStaffEditBody HtmxOverlayForm staff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates selectedRosterGroupIds preferenceWeekdays selectedShiftPreferences staffRsaDocument today weekOffset maybeRosterGroupId)

renderStaffEditBody :: OverlayFormMode -> Staff -> Maybe Text -> [RosterGroup] -> [AwardLevel] -> [AwardLevelBaseRate] -> [Id RosterGroup] -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Maybe StaffDocument -> Day -> Int -> Maybe (Id RosterGroup) -> Html
renderStaffEditBody formMode staff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates selectedRosterGroupIds preferenceWeekdays selectedShiftPreferences staffRsaDocument today weekOffset maybeRosterGroupId =
    let rsaPanel =
            renderRsaDocumentPanel
                RsaPanelConfig
                    { rsaPanelStaff = staff
                    , rsaPanelDocument = staffRsaDocument
                    , rsaPanelToday = today
                    , rsaPanelReturnContext =
                        RsaReturnContext
                            { rsaReturnTo = "staff"
                            , rsaReturnWeekOffset = Just weekOffset
                            , rsaReturnRosterGroupId = maybeRosterGroupId
                            }
                    , rsaPanelCanReview = currentUserIsManager
                    }
     in [hsx|
        {renderForm formMode staff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates selectedRosterGroupIds preferenceWeekdays selectedShiftPreferences weekOffset maybeRosterGroupId (UpdateStaffAction (get #id staff))}
        <div class="mt-4">
            {rsaPanel}
        </div>
    |]

renderForm :: OverlayFormMode -> Staff -> Maybe Text -> [RosterGroup] -> [AwardLevel] -> [AwardLevelBaseRate] -> [Id RosterGroup] -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Int -> Maybe (Id RosterGroup) -> StaffController -> Html
renderForm formMode staff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates selectedRosterGroupIds preferenceWeekdays selectedShiftPreferences weekOffset maybeRosterGroupId action =
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
                {renderFormFields staff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates selectedRosterGroupIds preferenceWeekdays selectedShiftPreferences weekOffset maybeRosterGroupId}
            </form>
        |]
        PageOverlayForm -> [hsx|
            <form id={staffEditFormId}
                  method="POST"
                  action={action}
                  class="mt-3">
                {renderFormFields staff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates selectedRosterGroupIds preferenceWeekdays selectedShiftPreferences weekOffset maybeRosterGroupId}
            </form>
        |]

renderFormFields :: Staff -> Maybe Text -> [RosterGroup] -> [AwardLevel] -> [AwardLevelBaseRate] -> [Id RosterGroup] -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Int -> Maybe (Id RosterGroup) -> Html
renderFormFields staff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates selectedRosterGroupIds preferenceWeekdays selectedShiftPreferences weekOffset maybeRosterGroupId = [hsx|
        <input type="hidden" name="weekOffset" value={tshow weekOffset} />
        {renderRosterGroupHiddenInput maybeRosterGroupId}
        {renderPersonalProfileFields staff maybeLinkedUserEmail}
        {when currentUserIsAdmin (renderStaffPayFields staff awardLevels awardLevelBaseRates)}
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
        <div class="mb-3">
            <label class="form-label d-block">Shift Preferences</label>
            {renderShiftPreferenceSections preferenceWeekdays selectedShiftPreferences}
        </div>
|]

renderStaffPayFields :: Staff -> [AwardLevel] -> [AwardLevelBaseRate] -> Html
renderStaffPayFields staff awardLevels awardLevelBaseRates = [hsx|
    <div class="row g-3">
        <div class="col-12 col-md-6">
            <label for="employmentBasis" class="form-label">Employment Basis</label>
            <select name="employmentBasis" id="employmentBasis" class={selectClass staff "employmentBasis"}>
                <option value="permanent" selected={staff.employmentBasis == Permanent}>Permanent</option>
                <option value="casual" selected={staff.employmentBasis == Casual}>Casual</option>
            </select>
            {renderStaffFieldError staff "employmentBasis"}
        </div>
        <div class="col-12 col-md-6">
            <label for="defaultAwardLevelId" class="form-label">Default Award Level</label>
            <select name="defaultAwardLevelId" id="defaultAwardLevelId" class={selectClass staff "defaultAwardLevelId"}>
                <option value="" selected={isNothing staff.defaultAwardLevelId}>Not assigned</option>
                {forEach awardLevels (renderAwardLevelOption staff awardLevelBaseRates)}
            </select>
            {renderStaffFieldError staff "defaultAwardLevelId"}
        </div>
    </div>
|]

renderAwardLevelOption :: Staff -> [AwardLevelBaseRate] -> AwardLevel -> Html
renderAwardLevelOption staff awardLevelBaseRates awardLevel = [hsx|
    <option value={inputValue awardLevel.id} selected={staff.defaultAwardLevelId == Just awardLevel.id}>
        {awardLevelOptionLabel awardLevelBaseRates awardLevel}
    </option>
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
