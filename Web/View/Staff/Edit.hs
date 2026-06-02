module Web.View.Staff.Edit where

import Application.Helper.Controller (VenueRole (VenueOwnerRole), currentUserIsSuperAdmin, hasRole)
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
    , importedPayItems         :: [XeroImportedPayItem]
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
            (renderStaffEditBody PageOverlayForm staff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds preferenceWeekdays selectedShiftPreferences staffRsaDocument today weekOffset maybeRosterGroupId)

staffEditFormId :: Text
staffEditFormId = "staff-edit-form"

renderStaffEditModalFragment :: Staff -> Maybe Text -> [RosterGroup] -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> [Id RosterGroup] -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Maybe StaffDocument -> Day -> Int -> Maybe (Id RosterGroup) -> Html
renderStaffEditModalFragment staff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds preferenceWeekdays selectedShiftPreferences staffRsaDocument today weekOffset maybeRosterGroupId =
    renderStaffEditDialog
        staffEditFormId
        (renderStaffEditBody HtmxOverlayForm staff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds preferenceWeekdays selectedShiftPreferences staffRsaDocument today weekOffset maybeRosterGroupId)

renderStaffEditBody :: OverlayFormMode -> Staff -> Maybe Text -> [RosterGroup] -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> [Id RosterGroup] -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Maybe StaffDocument -> Day -> Int -> Maybe (Id RosterGroup) -> Html
renderStaffEditBody formMode staff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds preferenceWeekdays selectedShiftPreferences staffRsaDocument today weekOffset maybeRosterGroupId =
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
                    , rsaPanelShowHeader = True
                    }
     in [hsx|
        {renderForm formMode staff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds preferenceWeekdays selectedShiftPreferences weekOffset maybeRosterGroupId (UpdateStaffAction (get #id staff))}
        <div class="mt-4">
            {renderStaffLoginAccessPanel staff maybeLinkedUserEmail weekOffset maybeRosterGroupId}
        </div>
        <div class="mt-4">
            {rsaPanel}
        </div>
    |]

renderStaffLoginAccessPanel :: Staff -> Maybe Text -> Int -> Maybe (Id RosterGroup) -> Html
renderStaffLoginAccessPanel staff maybeLinkedUserEmail weekOffset maybeRosterGroupId = [hsx|
    <div class="app-panel">
        <div class="app-panel-header">
            <div>
                <h3 class="app-panel-title mb-1">Sign-in access</h3>
                <p class="app-panel-description mb-0">Manage passkey setup and recovery for the linked login.</p>
            </div>
        </div>
        <div class="app-panel-body">
            {renderLinkedLoginSummary maybeLinkedUserEmail}
            {renderStaffPasskeySetupControls staff maybeLinkedUserEmail weekOffset maybeRosterGroupId}
        </div>
    </div>
|]

renderLinkedLoginSummary :: Maybe Text -> Html
renderLinkedLoginSummary Nothing = [hsx|<p class="app-muted mb-0">No linked login for this staff member.</p>|]
renderLinkedLoginSummary (Just email) = [hsx|
    <p class="mb-2"><span class="app-muted">Linked login:</span> {email}</p>
|]

renderStaffPasskeySetupControls :: Staff -> Maybe Text -> Int -> Maybe (Id RosterGroup) -> Html
renderStaffPasskeySetupControls _ Nothing _ _ = mempty
renderStaffPasskeySetupControls staff (Just _) weekOffset maybeRosterGroupId
    | currentUserIsSuperAdmin || hasRole VenueOwnerRole = [hsx|
        <div class="d-flex flex-wrap gap-2">
            <form method="POST" action={SendStaffPasskeySetupEmailAction staff.id} class="d-inline">
                {renderStaffPasskeyReturnInputs weekOffset maybeRosterGroupId}
                <button type="submit" class="btn btn-sm btn-outline-secondary">Email passkey setup</button>
            </form>
            <form method="POST" action={SendStaffPasskeyRecoveryEmailAction staff.id} class="d-inline">
                {renderStaffPasskeyReturnInputs weekOffset maybeRosterGroupId}
                <button type="submit" class="btn btn-sm btn-outline-warning">Email recovery link</button>
            </form>
        </div>
    |]
    | otherwise = mempty

renderStaffPasskeyReturnInputs :: Int -> Maybe (Id RosterGroup) -> Html
renderStaffPasskeyReturnInputs weekOffset maybeRosterGroupId = [hsx|
    <input type="hidden" name="returnTo" value="staff"/>
    <input type="hidden" name="weekOffset" value={tshow weekOffset}/>
    {forEach maybeRosterGroupId renderStaffPasskeyRosterGroupInput}
|]

renderStaffPasskeyRosterGroupInput :: Id RosterGroup -> Html
renderStaffPasskeyRosterGroupInput rosterGroupId = [hsx|<input type="hidden" name="rosterGroupId" value={tshow rosterGroupId}/>|]

renderForm :: OverlayFormMode -> Staff -> Maybe Text -> [RosterGroup] -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> [Id RosterGroup] -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Int -> Maybe (Id RosterGroup) -> StaffController -> Html
renderForm formMode staff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds preferenceWeekdays selectedShiftPreferences weekOffset maybeRosterGroupId action =
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
                {renderFormFields staff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds preferenceWeekdays selectedShiftPreferences weekOffset maybeRosterGroupId}
            </form>
        |]
        PageOverlayForm -> [hsx|
            <form id={staffEditFormId}
                  method="POST"
                  action={action}
                  class="mt-3">
                {renderFormFields staff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds preferenceWeekdays selectedShiftPreferences weekOffset maybeRosterGroupId}
            </form>
        |]

renderFormFields :: Staff -> Maybe Text -> [RosterGroup] -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> [Id RosterGroup] -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Int -> Maybe (Id RosterGroup) -> Html
renderFormFields staff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds preferenceWeekdays selectedShiftPreferences weekOffset maybeRosterGroupId = [hsx|
        <input type="hidden" name="weekOffset" value={tshow weekOffset} />
        {renderRosterGroupHiddenInput maybeRosterGroupId}
        {renderPersonalProfileFields staff maybeLinkedUserEmail}
        {when currentUserIsAdmin (renderStaffPayFields staff awardLevels awardLevelBaseRates importedPayItems)}
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

renderStaffPayFields :: Staff -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> Html
renderStaffPayFields staff awardLevels awardLevelBaseRates importedPayItems = [hsx|
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

