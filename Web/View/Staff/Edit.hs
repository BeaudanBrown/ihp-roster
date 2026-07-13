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
import qualified Application.Helper.FrontendContract.Surface.Profile as Surface
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            FrontendSurfaceCustomHtmxAttrs (..),
                                                            renderFrontendSurfaceActionForm,
                                                            renderFrontendSurfaceMount)
import Application.Helper.FrontendContract.Surface.Values (SurfaceFields (NoSurfaceFields),
                                                           surfaceActionValue,
                                                           surfaceFragmentTargetId)
import Application.Helper.StaffShiftPreferences
import Web.Profiles.FrontendSurface (ProfileScopeValue (..), staffSurfaceImpl)
import Web.View.LeaveRequests.New (renderLeaveRequestFormFields)
import Web.View.Prelude
import Web.View.Profiles.Edit (renderProfileLeaveRequestsList)
import Web.View.StaffDocuments.Rsa
import Web.View.StaffProfileForm
import Web.View.StaffProfileSections

staffProfileDetailsSectionId, staffProfilePreferencesSectionId, staffProfileLeaveSectionId :: Text
staffProfileDetailsSectionId = surfaceFragmentTargetId @Surface.StaffSurface @Surface.StaffDetailsSection NoSurfaceFields
staffProfilePreferencesSectionId = surfaceFragmentTargetId @Surface.StaffSurface @Surface.StaffPreferencesSection NoSurfaceFields
staffProfileLeaveSectionId = surfaceFragmentTargetId @Surface.StaffSurface @Surface.StaffLeaveSection NoSurfaceFields

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
    , maybeVenueMembership     :: Maybe VenueMembership
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
            (renderStaffSurfaceMount staff (renderStaffEditBody PageOverlayForm staff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds maybeVenueMembership preferenceWeekdays selectedShiftPreferences staffRsaDocument leaveRequest leaveRequests today weekOffset maybeRosterGroupId openSection))

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

renderStaffEditModalFragment :: Staff -> Maybe Text -> [RosterGroup] -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> [Id RosterGroup] -> Maybe VenueMembership -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Maybe StaffDocument -> LeaveRequest -> [LeaveRequest] -> Day -> Int -> Maybe (Id RosterGroup) -> Text -> Html
renderStaffEditModalFragment staff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds maybeVenueMembership preferenceWeekdays selectedShiftPreferences staffRsaDocument leaveRequest leaveRequests today weekOffset maybeRosterGroupId openSection =
    renderStaffEditDialogWithButtons
        []
        (renderStaffSurfaceMount staff (renderStaffEditBody HtmxOverlayForm staff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds maybeVenueMembership preferenceWeekdays selectedShiftPreferences staffRsaDocument leaveRequest leaveRequests today weekOffset maybeRosterGroupId openSection))

renderStaffSurfaceMount :: Staff -> Html -> Html
renderStaffSurfaceMount staff =
    renderFrontendSurfaceMount (staffSurfaceImpl (ProfileScopeValue (unpackId currentVenueId) (unpackId staff.id)))

renderStaffEditBody :: OverlayFormMode -> Staff -> Maybe Text -> [RosterGroup] -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> [Id RosterGroup] -> Maybe VenueMembership -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Maybe StaffDocument -> LeaveRequest -> [LeaveRequest] -> Day -> Int -> Maybe (Id RosterGroup) -> Text -> Html
renderStaffEditBody formMode staff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds maybeVenueMembership preferenceWeekdays selectedShiftPreferences _staffRsaDocument leaveRequest leaveRequests _today weekOffset maybeRosterGroupId openSection =
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
                        , staffProfileSectionId = staffProfileDetailsSectionId
                        , staffProfileSectionTitle = "Profile Details"
                        , staffProfileSectionBody = renderStaffDetailsForm formMode staff maybeLinkedUserEmail managementFields staffAction
                        }
                    , StaffProfileAccordionSection
                        { staffProfileSectionKey = "preferences"
                        , staffProfileSectionId = staffProfilePreferencesSectionId
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
                            , staffProfileSectionId = staffProfileLeaveSectionId
                            , staffProfileSectionTitle = "Unavailability"
                            , staffProfileSectionBody = renderStaffleaveRequestsContentLiveFragment staff leaveRequest leaveRequests
                            }
                       | currentUserIsManager
                       ]
                }
     in renderStaffProfileAccordion accordionConfig

renderStaffEditSectionFragment :: OverlayFormMode -> Staff -> Maybe Text -> [RosterGroup] -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> [Id RosterGroup] -> Maybe VenueMembership -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> LeaveRequest -> [LeaveRequest] -> Int -> Maybe (Id RosterGroup) -> Text -> Html
renderStaffEditSectionFragment formMode staff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds maybeVenueMembership preferenceWeekdays selectedShiftPreferences leaveRequest leaveRequests weekOffset maybeRosterGroupId openSection =
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
                , staffProfileSectionId = staffProfilePreferencesSectionId
                , staffProfileSectionTitle = "Shift Preferences"
                , staffProfileSectionBody = renderStaffShiftPreferencesEditForm formMode preferenceWeekdays selectedShiftPreferences weekOffset maybeRosterGroupId staffAction
                }
            "leave" -> StaffProfileAccordionSection
                { staffProfileSectionKey = "leave"
                , staffProfileSectionId = staffProfileLeaveSectionId
                , staffProfileSectionTitle = "Unavailability"
                , staffProfileSectionBody = renderStaffleaveRequestsContentLiveFragment staff leaveRequest leaveRequests
                }
            _ -> StaffProfileAccordionSection
                { staffProfileSectionKey = "profile"
                , staffProfileSectionId = staffProfileDetailsSectionId
                , staffProfileSectionTitle = "Profile Details"
                , staffProfileSectionBody = renderStaffDetailsForm formMode staff maybeLinkedUserEmail managementFields staffAction
                }
     in renderStaffProfileAccordionSection staffSectionsAccordionId section.staffProfileSectionKey section

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
        (surfaceActionValue @Surface.StaffSurface @Surface.CreateStaffLeaveRequest)
        FrontendSurfaceActionRoute
            { actionRouteUrl = pathTo CreateLeaveRequestAction
            , actionRouteFields = []
            , actionRouteCustomHtmx = []
            , actionRouteStandardUrl = Just (pathTo CreateLeaveRequestAction)
            , actionRouteExtraAttrs =
                [ ("id", "staff-leave-request-form")

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

renderStaffDetailsForm :: OverlayFormMode -> Staff -> Maybe Text -> StaffManagementFieldData -> StaffController -> Html
renderStaffDetailsForm formMode staff maybeLinkedUserEmail managementFields action =
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
            , staffProfileDetailsFormEmailField = renderPersonalProfileFields
            , staffProfileDetailsFormAfterFields = mempty
            , staffProfileDetailsFormManagement = Just managementFields
            , staffProfileDetailsFormManagementBody = renderStaffManagementFields
            , staffProfileDetailsFormSubmitLabel = "Save profile details"
            }
        staff
        maybeLinkedUserEmail

renderTrialStaffInvitationModalFragment :: Staff -> [VenueInvitation] -> Maybe Text -> Maybe Text -> Int -> Maybe (Id RosterGroup) -> Html
renderTrialStaffInvitationModalFragment staff pendingInvitations maybeError submittedEmail weekOffset maybeRosterGroupId =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = "Invite trial staff"
        , dialogOverlayBody = [hsx|
            {renderTrialStaffInvitationForm staff pendingInvitations maybeError submittedEmail weekOffset maybeRosterGroupId}
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
        , dialogOverlayDialogClass = ""
        }

renderTrialStaffInvitationForm :: Staff -> [VenueInvitation] -> Maybe Text -> Maybe Text -> Int -> Maybe (Id RosterGroup) -> Html
renderTrialStaffInvitationForm staff pendingInvitations maybeError submittedEmail weekOffset maybeRosterGroupId =
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
                    <input id="trial-staff-invitation-email" name="invitationEmail" type="email" class="form-control" placeholder="name@example.com" value={fromMaybe "" submittedEmail} required="required" />
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
            Just (StaffProfileSurfaceAction (surfaceActionValue @Surface.StaffSurface @Surface.UpdateStaffProfile) (staffSectionActionRoute actionUrl ("#" <> staffProfileDetailsSectionId) "outerHTML show:none"))
        CreateTrialStaffOverlayMarker ->
            Just (StaffProfileAppShellAction (staffDetailsAppShellAction marker) (staffAppShellActionRoute actionUrl))
staffDetailsFormRequestMode PageOverlayForm _ _ = Nothing

staffDetailsAppShellAction :: StaffDetailsOverlayMarker -> AppShellActionIR
staffDetailsAppShellAction CreateTrialStaffOverlayMarker = appShellActionByMarker @CreateTrialStaffOverlay
staffDetailsAppShellAction UpdateStaffProfileOverlayMarker = appShellActionByMarker @UpdateStaffProfileOverlay

staffShiftPreferencesOverlayRequestMode :: OverlayFormMode -> Text -> Maybe StaffProfileFormRequestMode
staffShiftPreferencesOverlayRequestMode HtmxOverlayForm actionUrl =
    Just (StaffProfileSurfaceAction (surfaceActionValue @Surface.StaffSurface @Surface.UpdateStaffShiftPreferences) (staffSectionActionRoute actionUrl ("#" <> staffProfilePreferencesSectionId) "outerHTML show:none"))
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

