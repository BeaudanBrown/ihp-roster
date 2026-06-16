module Web.View.Staff.Edit where

import Application.Helper.Controller (VenueRole (VenueOwnerRole), currentUserIsSuperAdmin, hasRole)
import Application.Helper.StaffShiftPreferences
import Web.View.LeaveRequests.New (renderLeaveRequestFormFields)
import Web.View.Prelude
import Web.View.Profiles.Edit (renderProfileLeaveRequestsList)
import Web.View.StaffDocuments.Rsa
import Web.View.StaffProfileForm
import Web.View.StaffProfileSections

data NewView = NewView
    { staff                  :: Staff
    , rosterGroups           :: [RosterGroup]
    , awardLevels            :: [AwardLevel]
    , awardLevelBaseRates    :: [AwardLevelBaseRate]
    , importedPayItems       :: [XeroImportedPayItem]
    , selectedRosterGroupIds :: [Id RosterGroup]
    , weekOffset             :: Int
    , maybeRosterGroupId     :: Maybe (Id RosterGroup)
    }

instance View NewView where
    html NewView { .. } =
        renderStaffAddTrialPageModalWithButtons
            weekOffset
            []
            (renderNewStaffBody PageOverlayForm staff rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds weekOffset maybeRosterGroupId)

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
    , leaveRequest             :: LeaveRequest
    , leaveRequests            :: [LeaveRequest]
    , today                    :: Day
    , weekOffset               :: Int
    , maybeRosterGroupId       :: Maybe (Id RosterGroup)
    , openSection              :: Text
    }

instance View EditView where
    html EditView { .. } =
        renderStaffEditPageModalWithButtons
            weekOffset
            []
            (renderStaffEditBody PageOverlayForm staff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds preferenceWeekdays selectedShiftPreferences staffRsaDocument leaveRequest leaveRequests today weekOffset maybeRosterGroupId openSection)

staffEditFormId :: Text
staffEditFormId = "staff-edit-form"

staffShiftPreferencesEditFormId :: Text
staffShiftPreferencesEditFormId = "staff-shift-preferences-form"

staffSectionsAccordionId :: Text
staffSectionsAccordionId = "staff-sections"

renderNewStaffModalFragment :: Staff -> [RosterGroup] -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> [Id RosterGroup] -> Int -> Maybe (Id RosterGroup) -> Html
renderNewStaffModalFragment staff rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds weekOffset maybeRosterGroupId =
    renderStaffAddTrialDialogWithButtons
        []
        (renderNewStaffBody HtmxOverlayForm staff rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds weekOffset maybeRosterGroupId)

renderNewStaffBody :: OverlayFormMode -> Staff -> [RosterGroup] -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> [Id RosterGroup] -> Int -> Maybe (Id RosterGroup) -> Html
renderNewStaffBody formMode staff rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds weekOffset maybeRosterGroupId =
    let managementFields =
            StaffManagementFieldData
                { managementStaff = staff
                , managementRosterGroups = rosterGroups
                , managementAwardLevels = awardLevels
                , managementAwardLevelBaseRates = awardLevelBaseRates
                , managementImportedPayItems = importedPayItems
                , managementSelectedRosterGroupIds = selectedRosterGroupIds
                , managementWeekOffset = Just weekOffset
                , managementRosterGroupId = maybeRosterGroupId
                }
     in renderStaffProfileDetailsForm
            StaffProfileDetailsFormConfig
                { staffProfileDetailsFormId = "staff-new-form"
                , staffProfileDetailsFormAction = pathTo CreateStaffAction
                , staffProfileDetailsFormClass = "mt-3"
                , staffProfileDetailsFormHtmx = staffEditFormHtmxConfig formMode
                , staffProfileDetailsFormAttributes = []
                , staffProfileDetailsFormHiddenInputs = mempty
                , staffProfileDetailsFormBeforeFields = [hsx|
                    <div class="alert alert-info" role="alert">
                        Create a trial staff placeholder for roster planning. Trial staff have no sign-in access.
                    </div>
                |]
                , staffProfileDetailsFormFieldsHeading = Just "Trial staff details"
                , staffProfileDetailsFormEmailField = renderPersonalProfileFields
                , staffProfileDetailsFormAfterFields = mempty
                , staffProfileDetailsFormManagement = Just managementFields
                , staffProfileDetailsFormManagementBody = renderStaffManagementFields
                , staffProfileDetailsFormSubmitLabel = "Create trial staff"
                }
            staff
            Nothing

renderStaffEditModalFragment :: Staff -> Maybe Text -> [RosterGroup] -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> [Id RosterGroup] -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Maybe StaffDocument -> LeaveRequest -> [LeaveRequest] -> Day -> Int -> Maybe (Id RosterGroup) -> Text -> Html
renderStaffEditModalFragment staff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds preferenceWeekdays selectedShiftPreferences staffRsaDocument leaveRequest leaveRequests today weekOffset maybeRosterGroupId openSection =
    renderStaffEditDialogWithButtons
        []
        (renderStaffEditBody HtmxOverlayForm staff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds preferenceWeekdays selectedShiftPreferences staffRsaDocument leaveRequest leaveRequests today weekOffset maybeRosterGroupId openSection)

renderStaffEditBody :: OverlayFormMode -> Staff -> Maybe Text -> [RosterGroup] -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> [Id RosterGroup] -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Maybe StaffDocument -> LeaveRequest -> [LeaveRequest] -> Day -> Int -> Maybe (Id RosterGroup) -> Text -> Html
renderStaffEditBody formMode staff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds preferenceWeekdays selectedShiftPreferences staffRsaDocument leaveRequest leaveRequests today weekOffset maybeRosterGroupId openSection =
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
        managementFields =
            StaffManagementFieldData
                { managementStaff = staff
                , managementRosterGroups = rosterGroups
                , managementAwardLevels = awardLevels
                , managementAwardLevelBaseRates = awardLevelBaseRates
                , managementImportedPayItems = importedPayItems
                , managementSelectedRosterGroupIds = selectedRosterGroupIds
                , managementWeekOffset = Just weekOffset
                , managementRosterGroupId = maybeRosterGroupId
                }
        staffAction = UpdateStaffAction (get #id staff)
        accordionConfig =
            StaffProfileAccordionConfig
                { staffProfileAccordionId = staffSectionsAccordionId
                , staffProfileAccordionOpenSection = openSection
                , staffProfileAccordionSections =
                    [ StaffProfileAccordionSection
                        { staffProfileSectionKey = "profile"
                        , staffProfileSectionId = "staff-profile-details"
                        , staffProfileSectionTitle = "Profile Details"
                        , staffProfileSectionBody = renderStaffDetailsForm formMode staff maybeLinkedUserEmail managementFields staffAction
                        }
                    , StaffProfileAccordionSection
                        { staffProfileSectionKey = "preferences"
                        , staffProfileSectionId = "staff-profile-preferences"
                        , staffProfileSectionTitle = "Shift Preferences"
                        , staffProfileSectionBody = renderStaffShiftPreferencesEditForm formMode preferenceWeekdays selectedShiftPreferences weekOffset maybeRosterGroupId staffAction
                        }
                    , StaffProfileAccordionSection
                        { staffProfileSectionKey = "security"
                        , staffProfileSectionId = "staff-profile-security"
                        , staffProfileSectionTitle = "Sign-In Methods"
                        , staffProfileSectionBody = renderStaffLoginAccessPanel staff maybeLinkedUserEmail weekOffset maybeRosterGroupId
                        }
                    ]
                    <> [ StaffProfileAccordionSection
                            { staffProfileSectionKey = "leave"
                            , staffProfileSectionId = "staff-profile-leave"
                            , staffProfileSectionTitle = "Unavailability"
                            , staffProfileSectionBody = renderStaffLeaveRequestsContentFragment staff leaveRequest leaveRequests
                            }
                       | currentUserIsManager
                       ]
                    <> [ StaffProfileAccordionSection
                            { staffProfileSectionKey = "rsa"
                            , staffProfileSectionId = "staff-profile-rsa"
                            , staffProfileSectionTitle = "RSA"
                            , staffProfileSectionBody = rsaPanel
                            }
                       ]
                }
     in [hsx|
        {renderStaffProfileAccordion accordionConfig}
    |]

staffLeaveRequestFormFragmentId :: Text
staffLeaveRequestFormFragmentId = "staff-leave-request-form-fragment"

staffLeaveRequestsListFragmentId :: Text
staffLeaveRequestsListFragmentId = "staff-leave-requests-list-fragment"

renderStaffLeaveRequestsContentFragment :: Staff -> LeaveRequest -> [LeaveRequest] -> Html
renderStaffLeaveRequestsContentFragment staff leaveRequest leaveRequests = [hsx|
    <div class="row g-4 align-items-start">
        <div class="col-12 col-xl-5">
            {renderStaffLeaveRequestFormFragment staff.id leaveRequest}
        </div>
        <div class="col-12 col-xl-7">
            {renderStaffLeaveRequestsListFragment leaveRequests}
        </div>
    </div>
|]

renderStaffLeaveRequestFormFragment :: Id Staff -> LeaveRequest -> Html
renderStaffLeaveRequestFormFragment staffId leaveRequest = [hsx|
    <div id={staffLeaveRequestFormFragmentId}>
        <form id="staff-leave-request-form"
              method="POST"
              action={CreateLeaveRequestAction}
              data-disable-javascript-submission="true"
              hx-post={CreateLeaveRequestAction}
              hx-target={"#" <> staffLeaveRequestFormFragmentId}
              hx-swap="outerHTML"
              hx-push-url="false">
            <input type="hidden" name="responseContext" value="staff"/>
            <input type="hidden" name="staffId" value={tshow staffId}/>
            {renderLeaveRequestFormFields leaveRequest}
            <div class="d-grid mt-4 app-form-width app-modal-sticky-actions">
                <button type="submit" class="btn btn-primary">Add unavailable time</button>
            </div>
        </form>
    </div>
|]

renderStaffLeaveRequestsListFragment :: [LeaveRequest] -> Html
renderStaffLeaveRequestsListFragment leaveRequests = [hsx|
    <div id={staffLeaveRequestsListFragmentId}>
        <h5 class="mb-3">Unavailable periods</h5>
        {renderProfileLeaveRequestsList leaveRequests}
    </div>
|]

renderStaffLeaveRequestsListFragmentOob :: [LeaveRequest] -> Html
renderStaffLeaveRequestsListFragmentOob leaveRequests = [hsx|
    <div id={staffLeaveRequestsListFragmentId} hx-swap-oob="outerHTML">
        <h5 class="mb-3">Unavailable periods</h5>
        {renderProfileLeaveRequestsList leaveRequests}
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

renderStaffDetailsForm :: OverlayFormMode -> Staff -> Maybe Text -> StaffManagementFieldData -> StaffController -> Html
renderStaffDetailsForm formMode staff maybeLinkedUserEmail managementFields action =
    renderStaffProfileDetailsForm
        StaffProfileDetailsFormConfig
            { staffProfileDetailsFormId = staffEditFormId
            , staffProfileDetailsFormAction = pathTo action
            , staffProfileDetailsFormClass = "mt-3"
            , staffProfileDetailsFormHtmx = staffEditFormHtmxConfig formMode
            , staffProfileDetailsFormAttributes = []
            , staffProfileDetailsFormHiddenInputs = [hsx|<input type="hidden" name="section" value="profile"/>|]
            , staffProfileDetailsFormBeforeFields = mempty
            , staffProfileDetailsFormFieldsHeading = Nothing
            , staffProfileDetailsFormEmailField = renderStaffEditPersonalProfileFields formMode
            , staffProfileDetailsFormAfterFields = mempty
            , staffProfileDetailsFormManagement = Just managementFields
            , staffProfileDetailsFormManagementBody = renderStaffManagementFields
            , staffProfileDetailsFormSubmitLabel = "Save profile details"
            }
        staff
        maybeLinkedUserEmail

renderStaffEditPersonalProfileFields :: OverlayFormMode -> Staff -> Maybe Text -> Html
renderStaffEditPersonalProfileFields formMode staff maybeLinkedUserEmail
    | isNothing staff.userId = renderPersonalProfileFieldsWithEmailSlot (renderTrialStaffInviteEmailField formMode staff) staff
    | otherwise = renderPersonalProfileFields staff maybeLinkedUserEmail

renderTrialStaffInviteEmailField :: OverlayFormMode -> Staff -> Html
renderTrialStaffInviteEmailField HtmxOverlayForm staff = [hsx|
    <div class="col-12 col-lg-6">
        <label for="invitationEmail" class="form-label">Email</label>
        <div class="input-group">
            <input
                id="invitationEmail"
                name="invitationEmail"
                type="email"
                class="form-control"
                placeholder="name@example.com"
            />
            <button
                type="submit"
                class="btn btn-outline-primary"
                formaction={CreateTrialStaffInvitationAction staff.id}
                formmethod="POST"
                hx-post={CreateTrialStaffInvitationAction staff.id}
                hx-target={"#" <> dialogOverlayMountId}
                hx-swap="innerHTML"
                hx-push-url="false"
            >Invite</button>
        </div>
        <div class="form-text">Send an invite link to claim this trial staff profile.</div>
    </div>
|]
renderTrialStaffInviteEmailField PageOverlayForm staff = [hsx|
    <div class="col-12 col-lg-6">
        <label for="invitationEmail" class="form-label">Email</label>
        <div class="input-group">
            <input
                id="invitationEmail"
                name="invitationEmail"
                type="email"
                class="form-control"
                placeholder="name@example.com"
            />
            <button
                type="submit"
                class="btn btn-outline-primary"
                formaction={CreateTrialStaffInvitationAction staff.id}
                formmethod="POST"
            >Invite</button>
        </div>
        <div class="form-text">Send an invite link to claim this trial staff profile.</div>
    </div>
|]

renderStaffShiftPreferencesEditForm :: OverlayFormMode -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Int -> Maybe (Id RosterGroup) -> StaffController -> Html
renderStaffShiftPreferencesEditForm formMode preferenceWeekdays selectedShiftPreferences weekOffset maybeRosterGroupId action =
    renderStaffShiftPreferencesForm
        StaffShiftPreferencesFormConfig
            { staffShiftPreferencesFormId = staffShiftPreferencesEditFormId
            , staffShiftPreferencesFormAction = pathTo action
            , staffShiftPreferencesFormClass = "mt-3"
            , staffShiftPreferencesFormHtmx = staffEditFormHtmxConfig formMode
            , staffShiftPreferencesFormHiddenInputs = [hsx|
                <input type="hidden" name="section" value="preferences"/>
                {renderWeekOffsetHiddenInput weekOffset}
                {renderRosterGroupHiddenInput maybeRosterGroupId}
            |]
            , staffShiftPreferencesFormSubmitLabel = "Save shift preferences"
            }
        preferenceWeekdays
        selectedShiftPreferences

staffEditFormHtmxConfig :: OverlayFormMode -> Maybe StaffProfileFormHtmxConfig
staffEditFormHtmxConfig HtmxOverlayForm =
    Just StaffProfileFormHtmxConfig
        { staffProfileFormHtmxTarget = "#" <> dialogOverlayMountId
        , staffProfileFormHtmxSwap = "innerHTML"
        , staffProfileFormHtmxPushUrl = "false"
        }
staffEditFormHtmxConfig PageOverlayForm = Nothing

