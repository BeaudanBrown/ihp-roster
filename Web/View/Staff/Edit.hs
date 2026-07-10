{-# LANGUAGE TypeApplications #-}

module Web.View.Staff.Edit where

import Application.Helper.Controller (VenueRole (VenueOwnerRole),
                                      currentUserIsSuperAdmin, currentVenueId,
                                      hasRole)
import Application.Helper.FrontendContract.AppShell (CreateTrialStaffInvitationOverlay,
                                                     CreateTrialStaffOverlay,
                                                     UpdateStaffProfileOverlay,
                                                     UpdateStaffShiftPreferencesOverlay)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             appShellActionByMarker,
                                                             applyAppShellActionAttrs)
import Application.Helper.FrontendContract.IR (AppShellActionIR)
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            FrontendSurfaceCustomHtmxAttrs (..),
                                                            renderFrontendSurfaceActionForm,
                                                            renderFrontendSurfaceMount)
import Application.Helper.StaffShiftPreferences
import Web.Profiles.FrontendSurface (ProfileScopeValue (..), staffSurfaceAction,
                                     staffSurfaceImpl)
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
    { staff                       :: Staff
    , maybeLinkedUserEmail        :: Maybe Text
    , pendingTrialStaffInvitation :: Maybe VenueInvitation
    , rosterGroups                :: [RosterGroup]
    , awardLevels                 :: [AwardLevel]
    , awardLevelBaseRates         :: [AwardLevelBaseRate]
    , importedPayItems            :: [XeroImportedPayItem]
    , selectedRosterGroupIds      :: [Id RosterGroup]
    , maybeVenueMembership        :: Maybe VenueMembership
    , preferenceWeekdays          :: [PreferenceWeekday]
    , selectedShiftPreferences    :: [ShiftPreferenceSelection]
    , staffRsaDocument            :: Maybe StaffDocument
    , leaveRequest                :: LeaveRequest
    , leaveRequests               :: [LeaveRequest]
    , today                       :: Day
    , weekOffset                  :: Int
    , maybeRosterGroupId          :: Maybe (Id RosterGroup)
    , openSection                 :: Text
    }

instance View EditView where
    html EditView { .. } =
        renderStaffEditPageModalWithButtons
            weekOffset
            []
            (renderStaffEditBody PageOverlayForm staff maybeLinkedUserEmail pendingTrialStaffInvitation rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds maybeVenueMembership preferenceWeekdays selectedShiftPreferences staffRsaDocument leaveRequest leaveRequests today weekOffset maybeRosterGroupId openSection)

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
                , managementVenueMembership = Nothing
                , managementWeekOffset = Just weekOffset
                , managementRosterGroupId = maybeRosterGroupId
                }
     in renderStaffProfileDetailsForm
            StaffProfileDetailsFormConfig
                { staffProfileDetailsFormId = "staff-new-form"
                , staffProfileDetailsFormAction = pathTo CreateStaffAction
                , staffProfileDetailsFormClass = "mt-3"
                , staffProfileDetailsFormRequestMode = staffDetailsFormRequestMode formMode (pathTo CreateStaffAction) CreateTrialStaffOverlayMarker
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

renderStaffEditModalFragment :: Staff -> Maybe Text -> Maybe VenueInvitation -> [RosterGroup] -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> [Id RosterGroup] -> Maybe VenueMembership -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Maybe StaffDocument -> LeaveRequest -> [LeaveRequest] -> Day -> Int -> Maybe (Id RosterGroup) -> Text -> Html
renderStaffEditModalFragment staff maybeLinkedUserEmail pendingTrialStaffInvitation rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds maybeVenueMembership preferenceWeekdays selectedShiftPreferences staffRsaDocument leaveRequest leaveRequests today weekOffset maybeRosterGroupId openSection =
    renderStaffEditDialogWithButtons
        []
        (renderStaffSurfaceMount staff (renderStaffEditBody HtmxOverlayForm staff maybeLinkedUserEmail pendingTrialStaffInvitation rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds maybeVenueMembership preferenceWeekdays selectedShiftPreferences staffRsaDocument leaveRequest leaveRequests today weekOffset maybeRosterGroupId openSection))

renderStaffSurfaceMount :: Staff -> Html -> Html
renderStaffSurfaceMount staff =
    renderFrontendSurfaceMount (staffSurfaceImpl (ProfileScopeValue (unpackId currentVenueId) (unpackId staff.id)))

renderStaffEditBody :: OverlayFormMode -> Staff -> Maybe Text -> Maybe VenueInvitation -> [RosterGroup] -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> [Id RosterGroup] -> Maybe VenueMembership -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Maybe StaffDocument -> LeaveRequest -> [LeaveRequest] -> Day -> Int -> Maybe (Id RosterGroup) -> Text -> Html
renderStaffEditBody formMode staff maybeLinkedUserEmail pendingTrialStaffInvitation rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds maybeVenueMembership preferenceWeekdays selectedShiftPreferences _staffRsaDocument leaveRequest leaveRequests _today weekOffset maybeRosterGroupId openSection =
    let managementFields =
            StaffManagementFieldData
                { managementStaff = staff
                , managementRosterGroups = rosterGroups
                , managementAwardLevels = awardLevels
                , managementAwardLevelBaseRates = awardLevelBaseRates
                , managementImportedPayItems = importedPayItems
                , managementSelectedRosterGroupIds = selectedRosterGroupIds
                , managementVenueMembership = maybeVenueMembership
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
                        , staffProfileSectionBody = renderStaffDetailsForm formMode staff maybeLinkedUserEmail pendingTrialStaffInvitation managementFields staffAction
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
                            , staffProfileSectionBody = renderStaffleaveRequestsContentLiveFragment staff leaveRequest leaveRequests
                            }
                       | currentUserIsManager
                       ]
                }
     in [hsx|
        {renderTrialStaffEditInviteStandaloneForm formMode staff pendingTrialStaffInvitation}
        {renderStaffProfileAccordion accordionConfig}
    |]

renderStaffEditSectionFragment :: OverlayFormMode -> Staff -> Maybe Text -> Maybe VenueInvitation -> [RosterGroup] -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> [Id RosterGroup] -> Maybe VenueMembership -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> LeaveRequest -> [LeaveRequest] -> Int -> Maybe (Id RosterGroup) -> Text -> Html
renderStaffEditSectionFragment formMode staff maybeLinkedUserEmail pendingTrialStaffInvitation rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds maybeVenueMembership preferenceWeekdays selectedShiftPreferences leaveRequest leaveRequests weekOffset maybeRosterGroupId openSection =
    let managementFields =
            StaffManagementFieldData
                { managementStaff = staff
                , managementRosterGroups = rosterGroups
                , managementAwardLevels = awardLevels
                , managementAwardLevelBaseRates = awardLevelBaseRates
                , managementImportedPayItems = importedPayItems
                , managementSelectedRosterGroupIds = selectedRosterGroupIds
                , managementVenueMembership = maybeVenueMembership
                , managementWeekOffset = Just weekOffset
                , managementRosterGroupId = maybeRosterGroupId
                }
        staffAction = UpdateStaffAction (get #id staff)
        section = case openSection of
            "preferences" -> StaffProfileAccordionSection
                { staffProfileSectionKey = "preferences"
                , staffProfileSectionId = "staff-profile-preferences"
                , staffProfileSectionTitle = "Shift Preferences"
                , staffProfileSectionBody = renderStaffShiftPreferencesEditForm formMode preferenceWeekdays selectedShiftPreferences weekOffset maybeRosterGroupId staffAction
                }
            "leave" -> StaffProfileAccordionSection
                { staffProfileSectionKey = "leave"
                , staffProfileSectionId = "staff-profile-leave"
                , staffProfileSectionTitle = "Unavailability"
                , staffProfileSectionBody = renderStaffleaveRequestsContentLiveFragment staff leaveRequest leaveRequests
                }
            _ -> StaffProfileAccordionSection
                { staffProfileSectionKey = "profile"
                , staffProfileSectionId = "staff-profile-details"
                , staffProfileSectionTitle = "Profile Details"
                , staffProfileSectionBody = renderStaffDetailsForm formMode staff maybeLinkedUserEmail pendingTrialStaffInvitation managementFields staffAction
                }
     in renderStaffProfileAccordionSection staffSectionsAccordionId section.staffProfileSectionKey section

trialStaffEditInviteFormId :: Text
trialStaffEditInviteFormId = "trial-staff-edit-invite-form"

staffLeaveRequestFormFragmentId :: Text
staffLeaveRequestFormFragmentId = "staff-leave-request-form-fragment"

staffLeaveRequestsListFragmentId :: Text
staffLeaveRequestsListFragmentId = "staff-leave-requests-list-fragment"

renderStaffleaveRequestsContentLiveFragment :: Staff -> LeaveRequest -> [LeaveRequest] -> Html
renderStaffleaveRequestsContentLiveFragment staff leaveRequest leaveRequests = [hsx|
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
        {renderStaffLeaveRequestForm staffId leaveRequest}
    </div>
|]

renderStaffLeaveRequestForm :: Id Staff -> LeaveRequest -> Html
renderStaffLeaveRequestForm staffId leaveRequest =
    renderFrontendSurfaceActionForm
        (staffSurfaceAction "create-staff-leave-request")
        FrontendSurfaceActionRoute
            { actionRouteUrl = pathTo CreateLeaveRequestAction
            , actionRouteFields = []
            , actionRouteCustomHtmx = []
            , actionRouteStandardUrl = Just (pathTo CreateLeaveRequestAction)
            , actionRouteExtraAttrs =
                [ ("id", "staff-leave-request-form")
                , ("data-disable-javascript-submission", "true")
                ]
            }
        [hsx|
            <input type="hidden" name="responseContext" value="staff"/>
            <input type="hidden" name="staffId" value={tshow staffId}/>
            {renderLeaveRequestFormFields leaveRequest}
            <div class="d-grid mt-4 app-form-width app-modal-sticky-actions">
                <button type="submit" class="btn btn-primary">Add unavailable time</button>
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

renderStaffDetailsForm :: OverlayFormMode -> Staff -> Maybe Text -> Maybe VenueInvitation -> StaffManagementFieldData -> StaffController -> Html
renderStaffDetailsForm formMode staff maybeLinkedUserEmail pendingTrialStaffInvitation managementFields action =
    renderStaffProfileDetailsForm
        StaffProfileDetailsFormConfig
            { staffProfileDetailsFormId = staffEditFormId
            , staffProfileDetailsFormAction = pathTo action
            , staffProfileDetailsFormClass = "mt-3"
            , staffProfileDetailsFormRequestMode = staffDetailsFormRequestMode formMode (pathTo action) UpdateStaffProfileOverlayMarker
            , staffProfileDetailsFormAttributes = []
            , staffProfileDetailsFormHiddenInputs = [hsx|<input type="hidden" name="section" value="profile"/>|]
            , staffProfileDetailsFormBeforeFields = mempty
            , staffProfileDetailsFormFieldsHeading = Nothing
            , staffProfileDetailsFormEmailField = renderStaffEditPersonalProfileFields formMode pendingTrialStaffInvitation
            , staffProfileDetailsFormAfterFields = mempty
            , staffProfileDetailsFormManagement = Just managementFields
            , staffProfileDetailsFormManagementBody = renderStaffManagementFields
            , staffProfileDetailsFormSubmitLabel = "Save profile details"
            }
        staff
        maybeLinkedUserEmail

renderStaffEditPersonalProfileFields :: OverlayFormMode -> Maybe VenueInvitation -> Staff -> Maybe Text -> Html
renderStaffEditPersonalProfileFields _formMode _pendingTrialStaffInvitation staff maybeLinkedUserEmail =
    renderPersonalProfileFields staff maybeLinkedUserEmail

renderTrialStaffEmailField :: OverlayFormMode -> Staff -> Maybe VenueInvitation -> Html
renderTrialStaffEmailField _ _ (Just invitation) = [hsx|
    <div class="col-12 col-lg-6">
        <label for="pendingInvitationEmail" class="form-label">Email</label>
        <div class="form-control d-flex align-items-center justify-content-between gap-2" id="pendingInvitationEmail">
            <span>{invitation.email}</span>
            <span class="badge text-bg-warning">Pending invite</span>
        </div>
        <div class="form-text">An invitation has been sent and is waiting to be accepted.</div>
    </div>
|]
renderTrialStaffEmailField HtmxOverlayForm staff Nothing = [hsx|
    <div class="col-12 col-lg-6">
        <label for="invitationEmail" class="form-label">Email</label>
        <div class="input-group">
            <input
                id="invitationEmail"
                name="invitationEmail"
                type="email"
                class="form-control"
                placeholder="name@example.com"
                form={trialStaffEditInviteFormId}
            />
            {renderTrialStaffInviteOverlayButton staff}
        </div>
        <div class="form-text">Send an invite link to claim this trial staff profile.</div>
    </div>
|]
renderTrialStaffEmailField PageOverlayForm staff Nothing = [hsx|
    <div class="col-12 col-lg-6">
        <label for="invitationEmail" class="form-label">Email</label>
        <div class="input-group">
            <input
                id="invitationEmail"
                name="invitationEmail"
                type="email"
                class="form-control"
                placeholder="name@example.com"
                form={trialStaffEditInviteFormId}
            />
            <button
                type="submit"
                class="btn btn-outline-primary"
                form={trialStaffEditInviteFormId}
            >Invite</button>
        </div>
        <div class="form-text">Send an invite link to claim this trial staff profile.</div>
    </div>
|]

renderTrialStaffInviteOverlayButton :: Staff -> Html
renderTrialStaffInviteOverlayButton _ = [hsx|
    <button
        type="submit"
        class="btn btn-outline-primary"
        form={trialStaffEditInviteFormId}
    >Invite</button>
|]

renderTrialStaffEditInviteStandaloneForm :: OverlayFormMode -> Staff -> Maybe VenueInvitation -> Html
renderTrialStaffEditInviteStandaloneForm _ staff pendingTrialStaffInvitation
    | isJust staff.userId || isJust pendingTrialStaffInvitation = mempty
renderTrialStaffEditInviteStandaloneForm HtmxOverlayForm staff _ =
    applyAppShellActionAttrs
        (appShellActionByMarker @CreateTrialStaffInvitationOverlay)
        AppShellActionRoute
            { appShellActionRouteUrl = pathTo (CreateTrialStaffInvitationAction staff.id)
            , appShellActionRouteFields = []
            , appShellActionRouteCustomHtmx = []
            , appShellActionRouteStandardUrl = Nothing
            , appShellActionRouteExtraAttrs =
                [ ("id", trialStaffEditInviteFormId)
                , ("class", "d-none")
                ]
            }
        [hsx|<form method="POST" action={pathTo (CreateTrialStaffInvitationAction staff.id)}></form>|]
renderTrialStaffEditInviteStandaloneForm PageOverlayForm staff _ = [hsx|
    <form
        id={trialStaffEditInviteFormId}
        method="POST"
        action={pathTo (CreateTrialStaffInvitationAction staff.id)}
        class="d-none"
    ></form>
|]

renderTrialStaffInvitationModalFragment :: Staff -> [VenueInvitation] -> Maybe Text -> Int -> Maybe (Id RosterGroup) -> Html
renderTrialStaffInvitationModalFragment staff pendingInvitations maybeError weekOffset maybeRosterGroupId =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = "Invite trial staff"
        , dialogOverlayBody = [hsx|
            {renderTrialStaffInvitationForm staff pendingInvitations maybeError weekOffset maybeRosterGroupId}
        |]
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons =
            [ OverlayButton
                { overlayButtonLabel = "Cancel"
                , overlayButtonClass = "btn btn-outline-secondary"
                , overlayButtonAction = OverlayCloseAction
                }
            , OverlayButton
                { overlayButtonLabel = "Send invite"
                , overlayButtonClass = "btn btn-primary"
                , overlayButtonAction = OverlaySubmitFormAction "trial-staff-invite-form"
                }
            ]
        , dialogOverlayDialogClass = "app-staff-edit-dialog"
        }

renderTrialStaffInvitationForm :: Staff -> [VenueInvitation] -> Maybe Text -> Int -> Maybe (Id RosterGroup) -> Html
renderTrialStaffInvitationForm staff pendingInvitations maybeError weekOffset maybeRosterGroupId =
    applyAppShellActionAttrs
        (appShellActionByMarker @CreateTrialStaffInvitationOverlay)
        (trialInvitationSubmitRoute (pathTo (CreateTrialStaffInvitationAction staff.id)) [("id", "trial-staff-invite-form")])
        [hsx|
            <form method="POST" action={pathTo (CreateTrialStaffInvitationAction staff.id)}>
                {renderWeekOffsetHiddenInput weekOffset}
                {renderRosterGroupHiddenInput maybeRosterGroupId}
                <p class="app-muted mb-3">Send an invite link so {staff.firstName} {staff.lastName} can claim this trial staff profile.</p>
                {forEach maybeError renderTrialInviteError}
                <div class="mb-3">
                    <label for="trial-staff-invitation-email" class="form-label">Email</label>
                    <input id="trial-staff-invitation-email" name="invitationEmail" type="email" class="form-control" placeholder="name@example.com" required="required" />
                </div>
                {renderPendingTrialInvitationList pendingInvitations}
            </form>
        |]

trialInvitationSubmitRoute :: Text -> [(Text, Text)] -> AppShellActionRoute
trialInvitationSubmitRoute actionUrl extraAttrs =
    AppShellActionRoute
        { appShellActionRouteUrl = actionUrl
        , appShellActionRouteFields = []
        , appShellActionRouteCustomHtmx = []
        , appShellActionRouteStandardUrl = Nothing
        , appShellActionRouteExtraAttrs = extraAttrs
        }

renderTrialInviteError :: Text -> Html
renderTrialInviteError message = [hsx|<div class="alert alert-danger" role="alert">{message}</div>|]

renderPendingTrialInvitationList :: [VenueInvitation] -> Html
renderPendingTrialInvitationList [] = mempty
renderPendingTrialInvitationList invitations = [hsx|
    <div class="border-top pt-3 mt-3">
        <h3 class="h6 mb-2">Pending invites</h3>
        <div class="list-group list-group-flush">
            {forEach invitations renderPendingTrialInvitationRow}
        </div>
    </div>
|]

renderPendingTrialInvitationRow :: VenueInvitation -> Html
renderPendingTrialInvitationRow invitation = [hsx|
    <div class="list-group-item px-0 d-flex flex-wrap align-items-center justify-content-between gap-2">
        <div class="min-w-0">
            <div class="fw-semibold text-truncate">{invitation.email}</div>
            <div class="small app-muted">Expires {formatUtcTimestamp (fromMaybe invitation.createdAt invitation.expiresAt)}</div>
        </div>
        <div class="d-flex align-items-center gap-2">
            {renderInvitationStatusOrDeliveryBadge (inputValue invitation.status) (inputValue invitation.deliveryStatus)}
            {renderResendTrialInvitationForm invitation}
        </div>
    </div>
|]

renderResendTrialInvitationForm :: VenueInvitation -> Html
renderResendTrialInvitationForm invitation =
    applyAppShellActionAttrs
        (appShellActionByMarker @CreateTrialStaffInvitationOverlay)
        (trialInvitationSubmitRoute (pathTo (ResendTrialStaffInvitationAction invitation.id)) [("class", "mb-0")])
        [hsx|
            <form method="POST" action={pathTo (ResendTrialStaffInvitationAction invitation.id)}>
                <button type="submit" class="btn btn-sm btn-outline-primary">Resend</button>
            </form>
        |]

renderStaffShiftPreferencesEditForm :: OverlayFormMode -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Int -> Maybe (Id RosterGroup) -> StaffController -> Html
renderStaffShiftPreferencesEditForm formMode preferenceWeekdays selectedShiftPreferences weekOffset maybeRosterGroupId action =
    renderStaffShiftPreferencesForm
        StaffShiftPreferencesFormConfig
            { staffShiftPreferencesFormId = staffShiftPreferencesEditFormId
            , staffShiftPreferencesFormAction = pathTo action
            , staffShiftPreferencesFormClass = "mt-3"
            , staffShiftPreferencesFormRequestMode = staffShiftPreferencesOverlayRequestMode formMode (pathTo action)
            , staffShiftPreferencesFormHiddenInputs = [hsx|
                <input type="hidden" name="section" value="preferences"/>
                {renderWeekOffsetHiddenInput weekOffset}
                {renderRosterGroupHiddenInput maybeRosterGroupId}
            |]
            , staffShiftPreferencesFormSubmitLabel = "Save shift preferences"
            }
        preferenceWeekdays
        selectedShiftPreferences

data StaffDetailsOverlayMarker
    = CreateTrialStaffOverlayMarker
    | UpdateStaffProfileOverlayMarker

staffDetailsFormRequestMode :: OverlayFormMode -> Text -> StaffDetailsOverlayMarker -> Maybe StaffProfileFormRequestMode
staffDetailsFormRequestMode HtmxOverlayForm actionUrl marker =
    case marker of
        UpdateStaffProfileOverlayMarker ->
            Just (StaffProfileSurfaceAction (staffSurfaceAction "update-staff-profile") (staffSectionActionRoute actionUrl "#staff-profile-details" "outerHTML show:none"))
        CreateTrialStaffOverlayMarker ->
            Just (StaffProfileAppShellAction (staffDetailsAppShellAction marker) (staffAppShellActionRoute actionUrl))
staffDetailsFormRequestMode PageOverlayForm _ _ = Nothing

staffDetailsAppShellAction :: StaffDetailsOverlayMarker -> AppShellActionIR
staffDetailsAppShellAction CreateTrialStaffOverlayMarker = appShellActionByMarker @CreateTrialStaffOverlay
staffDetailsAppShellAction UpdateStaffProfileOverlayMarker = appShellActionByMarker @UpdateStaffProfileOverlay

staffShiftPreferencesOverlayRequestMode :: OverlayFormMode -> Text -> Maybe StaffProfileFormRequestMode
staffShiftPreferencesOverlayRequestMode HtmxOverlayForm actionUrl =
    Just (StaffProfileSurfaceAction (staffSurfaceAction "update-staff-shift-preferences") (staffSectionActionRoute actionUrl "#staff-profile-preferences" "outerHTML show:none"))
staffShiftPreferencesOverlayRequestMode PageOverlayForm _ = Nothing

staffAppShellActionRoute :: Text -> AppShellActionRoute
staffAppShellActionRoute actionUrl =
    AppShellActionRoute
        { appShellActionRouteUrl = actionUrl
        , appShellActionRouteFields = []
        , appShellActionRouteCustomHtmx = []
        , appShellActionRouteStandardUrl = Nothing
        , appShellActionRouteExtraAttrs = []
        }

staffSectionActionRoute :: Text -> Text -> Text -> FrontendSurfaceActionRoute
staffSectionActionRoute actionUrl target swap =
    FrontendSurfaceActionRoute
        { actionRouteUrl = actionUrl
        , actionRouteFields = []
        , actionRouteCustomHtmx =
            [ FrontendSurfaceCustomHtmxAttrs
                { customHtmxAttrMarker = "staff-profile-section-htmx-attrs"
                , customHtmxAttrValues =
                    [ ("hx-target", target)
                    , ("hx-swap", swap)
                    ]
                }
            ]
        , actionRouteStandardUrl = Nothing
        , actionRouteExtraAttrs = []
        }

