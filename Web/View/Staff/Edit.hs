{-# LANGUAGE TypeApplications #-}

module Web.View.Staff.Edit where

import Application.Helper.Controller (currentVenueId)
import Application.Helper.FrontendContract.AppShell (CreateTrialStaffInvitationOverlay,
                                                     CreateTrialStaffOverlay,
                                                     OpenStaffRemovalDialog,
                                                     RemoveStaffOverlay,
                                                     UpdateStaffProfileOverlay,
                                                     UpdateStaffShiftPreferencesOverlay)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             appShellActionByMarker,
                                                             applyAppShellActionAttrs,
                                                             defaultAppShellActionRoute)
import Application.Helper.FrontendContract.IR (AppShellActionIR)
import Application.Helper.FrontendContract.Surface.Profile (StaffProfileSectionValue (..))
import qualified Application.Helper.FrontendContract.Surface.Profile as Surface
import qualified Application.Helper.FrontendContract.Surface.Profile.Action as ProfileAction
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            FrontendSurfaceCustomHtmxAttrs (..),
                                                            defaultFrontendSurfaceActionRoute,
                                                            renderFrontendSurfaceActionForm,
                                                            renderFrontendSurfaceMount)
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.StaffShiftPreferences
import Application.Helper.Url (appendQueryParams)
import Application.Helper.VenueInvitation (venueInvitationEffectiveExpiresAt)
import Web.LeaveRequests.SelfService (renderSelfServiceLeaveHistory,
                                      renderVisibleUnavailabilityBlackouts)
import Web.Profiles.FrontendSurface (ProfileScopeValue (..), staffSurfaceImpl)
import Web.View.LeaveRequests.New (LeaveRequestFieldNames (..),
                                   renderLeaveRequestFormFieldsWithNames)
import Web.View.Prelude
import Web.View.StaffDocuments.Rsa
import Web.View.StaffProfileForm
import Web.View.StaffProfileSections

staffProfileDetailsSectionId, staffProfilePreferencesSectionId, staffProfileLeaveSectionId :: Text
staffProfileDetailsSectionId = surfaceFragmentTargetId @Surface.StaffSurface @Surface.StaffDetailsSection noSurfaceFields
staffProfilePreferencesSectionId = surfaceFragmentTargetId @Surface.StaffSurface @Surface.StaffPreferencesSection noSurfaceFields
staffProfileLeaveSectionId = surfaceFragmentTargetId @Surface.StaffSurface @Surface.StaffLeaveSection noSurfaceFields

data NewView = NewView
    { staff                  :: Staff
    , rosterGroups           :: [RosterGroup]
    , awardLevels            :: [AwardLevel]
    , awardLevelBaseRates    :: [AwardLevelBaseRate]
    , importedPayItems       :: [XeroImportedPayItem]
    , selectedRosterGroupIds :: [Id RosterGroup]
    , anchorDate             :: Day
    , maybeRosterGroupId     :: Maybe (Id RosterGroup)
    }

instance View NewView where
    html NewView { .. } =
        renderStaffAddTrialPageModalWithButtons
            []
            (renderNewStaffBody PageOverlayForm staff rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds anchorDate maybeRosterGroupId)

data StaffEditRenderContext = StaffEditRenderContext
    { staff                         :: Staff
    , staffPayConfigurationRequired :: Bool
    , maybeLinkedUserEmail          :: Maybe Text
    , rosterGroups                  :: [RosterGroup]
    , awardLevels                   :: [AwardLevel]
    , awardLevelBaseRates           :: [AwardLevelBaseRate]
    , importedPayItems              :: [XeroImportedPayItem]
    , selectedRosterGroupIds        :: [Id RosterGroup]
    , maybeVenueMembership          :: Maybe VenueMembership
    , preferenceWeekdays            :: [PreferenceWeekday]
    , selectedShiftPreferences      :: [ShiftPreferenceSelection]
    , leaveRequest                  :: LeaveRequest
    , leaveRequests                 :: [LeaveRequest]
    , anchorDate                    :: Day
    , maybeRosterGroupId            :: Maybe (Id RosterGroup)
    , openSection                   :: Text
    }

data StaffEditBodyRenderContext = StaffEditBodyRenderContext
    { staffEditContext               :: StaffEditRenderContext
    , staffRemovalAllowed            :: Bool
    , staffLeaveSectionVisible       :: Bool
    , staffCredentialControlsAllowed :: Bool
    }

newtype EditView = EditView
    { staffEditBodyContext :: StaffEditBodyRenderContext
    }

instance View EditView where
    html EditView { staffEditBodyContext } =
        renderStaffEditPageModalWithButtons
            []
            (renderStaffSurfaceMount staffEditBodyContext.staffEditContext.staff (renderStaffEditBody PageOverlayForm staffEditBodyContext))

staffEditFormId :: Text
staffEditFormId = "staff-edit-form"

staffShiftPreferencesEditFormId :: Text
staffShiftPreferencesEditFormId = "staff-shift-preferences-form"

staffSectionsAccordionId :: Text
staffSectionsAccordionId = "staff-sections"

staffPayConfigurationWarningText :: Text
staffPayConfigurationWarningText = "Pay configuration required. A venue admin must choose a default pay rate or “No Timesheets (roster only).”"

renderNewStaffModalFragment :: Staff -> [RosterGroup] -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> [Id RosterGroup] -> Day -> Maybe (Id RosterGroup) -> Html
renderNewStaffModalFragment staff rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds anchorDate maybeRosterGroupId =
    renderStaffAddTrialDialogWithButtons
        []
        (renderNewStaffBody HtmxOverlayForm staff rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds anchorDate maybeRosterGroupId)

renderNewStaffBody :: OverlayFormMode -> Staff -> [RosterGroup] -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> [Id RosterGroup] -> Day -> Maybe (Id RosterGroup) -> Html
renderNewStaffBody formMode staff rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds anchorDate maybeRosterGroupId =
    renderStaffProfileDetailsForm
            StaffProfileDetailsFormConfig
                { staffProfileDetailsFormId = "staff-new-form"
                , staffProfileDetailsFormAction = pathTo CreateStaffAction
                , staffProfileDetailsFormClass = "mt-3"
                , staffProfileDetailsFormRequestMode = staffDetailsFormRequestMode formMode (pathTo CreateStaffAction) CreateTrialStaffOverlayMarker
                , staffProfileDetailsSurfaceFields = fields
                , staffProfileDetailsFormAttributes = []
                , staffProfileDetailsFormHiddenInputs = mempty
                , staffProfileDetailsFormBeforeFields = [hsx|
                    <div class="alert alert-info" role="alert">
                        Create a trial staff placeholder for roster planning. Trial staff have no sign-in access.
                    </div>
                    {renderNewStaffPayDefaultError staff}
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
  where
    renderNewStaffPayDefaultError currentStaff =
        case getValidationFailure #defaultAwardLevelId currentStaff of
            Just message -> [hsx|<div class="alert alert-danger" role="alert">{message}</div>|]
            Nothing -> mempty
    managementFields =
        StaffManagementFieldData
            { managementStaff = staff
            , managementRosterGroups = rosterGroups
            , managementAwardLevels = awardLevels
            , managementAwardLevelBaseRates = awardLevelBaseRates
            , managementImportedPayItems = importedPayItems
            , managementSelectedRosterGroupIds = selectedRosterGroupIds
            , managementVenueMembership = Nothing
            , managementAnchorDate = Just anchorDate
            , managementRosterGroupId = maybeRosterGroupId
            }
    values = staffProfileDetailsSurfaceValues StaffProfileDetailsSection staff (Just managementFields)
    fields =
        ProfileAction.updateStaffProfileActionFields
            values.profileDetailsFirstName
            values.profileDetailsLastName
            values.profileDetailsPreferredName
            values.profileDetailsPhone
            values.profileDetailsIdealShiftsPerWeek
            values.profileDetailsEmergencyContactName
            values.profileDetailsEmergencyContactPhone
            values.profileDetailsSection
            values.profileDetailsVenueRole
            values.profileDetailsEmploymentBasis
            values.profileDetailsPayRateSelection
            values.profileDetailsRosterGroupIds

renderStaffEditModalFragment :: StaffEditBodyRenderContext -> Html
renderStaffEditModalFragment staffEditBodyContext =
    renderStaffEditDialogWithButtons
        []
        (renderStaffSurfaceMount staffEditBodyContext.staffEditContext.staff (renderStaffEditBody HtmxOverlayForm staffEditBodyContext))

renderStaffSurfaceMount :: Staff -> Html -> Html
renderStaffSurfaceMount staff =
    renderFrontendSurfaceMount (staffSurfaceImpl (ProfileScopeValue (unpackId currentVenueId) (unpackId staff.id)))

renderStaffEditBody :: OverlayFormMode -> StaffEditBodyRenderContext -> Html
renderStaffEditBody formMode staffEditBodyContext@StaffEditBodyRenderContext { staffEditContext, staffRemovalAllowed, staffLeaveSectionVisible } =
    let StaffEditRenderContext { .. } = staffEditContext
        managementFields = staffEditManagementFields staffEditContext
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
                        , staffProfileSectionWarning = if staffPayConfigurationRequired then Just staffPayConfigurationWarningText else Nothing
                        , staffProfileSectionBody = renderStaffDetailsForm formMode staff maybeLinkedUserEmail managementFields staffAction
                        }
                    , StaffProfileAccordionSection
                        { staffProfileSectionKey = "preferences"
                        , staffProfileSectionId = staffProfilePreferencesSectionId
                        , staffProfileSectionTitle = "Shift Preferences"
                        , staffProfileSectionWarning = Nothing
                        , staffProfileSectionBody = renderStaffShiftPreferencesEditForm formMode preferenceWeekdays selectedShiftPreferences anchorDate maybeRosterGroupId staffAction
                        }
                    , StaffProfileAccordionSection
                        { staffProfileSectionKey = "security"
                        , staffProfileSectionId = "staff-profile-security"
                        , staffProfileSectionTitle = "Sign-In Methods"
                        , staffProfileSectionWarning = Nothing
                        , staffProfileSectionBody = renderStaffLoginAccessPanel staffEditBodyContext
                        }
                    ]
                    <> [ StaffProfileAccordionSection
                            { staffProfileSectionKey = "leave"
                            , staffProfileSectionId = staffProfileLeaveSectionId
                            , staffProfileSectionTitle = "Unavailability"
                            , staffProfileSectionWarning = Nothing
                            , staffProfileSectionBody = renderStaffleaveRequestsContentLiveFragment staff leaveRequest leaveRequests
                            }
                       | staffLeaveSectionVisible
                       ]
                }
     in renderStaffProfileAccordion accordionConfig <> renderStaffRemovalPanel staff staffRemovalAllowed anchorDate maybeRosterGroupId

renderStaffRemovalPanel :: Staff -> Bool -> Day -> Maybe (Id RosterGroup) -> Html
renderStaffRemovalPanel staff staffRemovalAllowed anchorDate maybeRosterGroupId
    | not staffRemovalAllowed = mempty
    | otherwise = [hsx|
        <div class="d-grid mt-4">
            {removalButton}
        </div>
    |]
  where
    removalReturnParams =
        [("anchorDate", tshow anchorDate)]
            <> maybe [] (\rosterGroupId -> [("rosterGroupId", tshow rosterGroupId)]) maybeRosterGroupId
    removalUrl = appendQueryParams (pathTo (NewRemoveStaffAction staff.id)) removalReturnParams
    removalButton =
        applyAppShellActionAttrs
            (appShellActionByMarker @OpenStaffRemovalDialog)
            removalDialogRoute
            [hsx|<a href={removalUrl} class="btn btn-outline-danger">Remove staff member</a>|]
    removalDialogRoute = ((defaultAppShellActionRoute (removalUrl))
        { appShellActionRouteStandardUrl = Just removalUrl
        })

staffEditManagementFields :: StaffEditRenderContext -> StaffManagementFieldData
staffEditManagementFields StaffEditRenderContext { .. } =
    StaffManagementFieldData
        { managementStaff = staff
        , managementRosterGroups = rosterGroups
        , managementAwardLevels = awardLevels
        , managementAwardLevelBaseRates = awardLevelBaseRates
        , managementImportedPayItems = importedPayItems
        , managementSelectedRosterGroupIds = selectedRosterGroupIds
        , managementVenueMembership = maybeVenueMembership
        , managementAnchorDate = Just anchorDate
        , managementRosterGroupId = maybeRosterGroupId
        }

renderStaffEditSectionFragment :: OverlayFormMode -> StaffEditRenderContext -> Html
renderStaffEditSectionFragment formMode staffEditContext =
    let StaffEditRenderContext { .. } = staffEditContext
        managementFields = staffEditManagementFields staffEditContext
        staffAction = UpdateStaffAction (get #id staff)
        section = case openSection of
            "preferences" -> StaffProfileAccordionSection
                { staffProfileSectionKey = "preferences"
                , staffProfileSectionId = staffProfilePreferencesSectionId
                , staffProfileSectionTitle = "Shift Preferences"
                , staffProfileSectionWarning = Nothing
                , staffProfileSectionBody = renderStaffShiftPreferencesEditForm formMode preferenceWeekdays selectedShiftPreferences anchorDate maybeRosterGroupId staffAction
                }
            "leave" -> StaffProfileAccordionSection
                { staffProfileSectionKey = "leave"
                , staffProfileSectionId = staffProfileLeaveSectionId
                , staffProfileSectionTitle = "Unavailability"
                , staffProfileSectionWarning = Nothing
                , staffProfileSectionBody = renderStaffleaveRequestsContentLiveFragment staff leaveRequest leaveRequests
                }
            _ -> StaffProfileAccordionSection
                { staffProfileSectionKey = "profile"
                , staffProfileSectionId = staffProfileDetailsSectionId
                , staffProfileSectionTitle = "Profile Details"
                , staffProfileSectionWarning = if staffPayConfigurationRequired then Just staffPayConfigurationWarningText else Nothing
                , staffProfileSectionBody = renderStaffDetailsForm formMode staff maybeLinkedUserEmail managementFields staffAction
                }
     in renderStaffProfileAccordionSection staffSectionsAccordionId section.staffProfileSectionKey section

staffLeaveRequestFormFragmentId :: Text
staffLeaveRequestFormFragmentId = "staff-leave-request-form-fragment"

staffLeaveRequestsListFragmentId :: Text
staffLeaveRequestsListFragmentId = "staff-leave-requests-list-fragment"

renderStaffleaveRequestsContentLiveFragment :: Staff -> LeaveRequest -> [LeaveRequest] -> Html
renderStaffleaveRequestsContentLiveFragment staff leaveRequest leaveRequests = [hsx|
    {renderStaffVisibleUnavailabilityBlackoutsMount}
    <div class="row g-4 align-items-start">
        <div class="col-12 col-xl-5">
            {renderStaffLeaveRequestFormFragment staff.id leaveRequest}
        </div>
        <div class="col-12 col-xl-7">
            {renderStaffLeaveRequestsListFragment leaveRequests}
        </div>
    </div>
|]

renderStaffVisibleUnavailabilityBlackoutsMount :: Html
renderStaffVisibleUnavailabilityBlackoutsMount = [hsx|
    <div id={surfaceFragmentTargetId @Surface.StaffSurface @Surface.StaffVisibleUnavailabilityBlackouts noSurfaceFields}
         class="mb-3"
         hx-get={appendQueryParams (pathTo ShowVisibleUnavailabilityBlackoutsFragmentAction) [("surface", "staff")]}
         hx-trigger="load"
         hx-swap="outerHTML">
        <p class="small app-muted mb-0">Loading submission blackout periods…</p>
    </div>
|]

renderStaffVisibleUnavailabilityBlackoutsFragment :: [UnavailabilityBlackout] -> Html
renderStaffVisibleUnavailabilityBlackoutsFragment blackouts = [hsx|
    <div id={surfaceFragmentTargetId @Surface.StaffSurface @Surface.StaffVisibleUnavailabilityBlackouts noSurfaceFields} class="mb-3">
        {if null blackouts then mempty else renderVisibleUnavailabilityBlackouts blackouts}
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
        (ProfileAction.createStaffLeaveRequestAction fields)
        ((defaultFrontendSurfaceActionRoute (pathTo CreateLeaveRequestAction))
            { actionRouteStandardUrl = Just (pathTo CreateLeaveRequestAction)
            , actionRouteExtraAttrs = [ ("id", "staff-leave-request-form")

                ]
            })
        [hsx|
            <input type="hidden" name="responseContext" value="staff"/>
            <input type="hidden" name="staffId" value={tshow staffId}/>
            {renderLeaveRequestFormFieldsWithNames fieldNames leaveRequest}
            <div class="d-grid mt-4 app-form-width app-modal-sticky-actions">
                <button type="submit" class="btn btn-primary">Add unavailable time</button>
            </div>
        |]
  where
    fields = ProfileAction.createStaffLeaveRequestActionFields leaveRequest.startDate leaveRequest.endDate (fromMaybe "" leaveRequest.notes)
    fieldNames =
        LeaveRequestFieldNames
            { leaveRequestStartDateFieldName = surfaceFieldNameFrom @Surface.StartDate fields
            , leaveRequestEndDateFieldName = surfaceFieldNameFrom @Surface.EndDate fields
            , leaveRequestNotesFieldName = surfaceFieldNameFrom @Surface.Notes fields
            }

renderStaffLeaveRequestsListFragment :: [LeaveRequest] -> Html
renderStaffLeaveRequestsListFragment leaveRequests = [hsx|
    <div id={staffLeaveRequestsListFragmentId}>
        <h5 class="mb-3">Unavailable periods</h5>
        {renderSelfServiceLeaveHistory leaveRequests}
    </div>
|]


renderStaffLoginAccessPanel :: StaffEditBodyRenderContext -> Html
renderStaffLoginAccessPanel staffEditBodyContext@StaffEditBodyRenderContext { staffEditContext = StaffEditRenderContext { maybeLinkedUserEmail, .. } } = [hsx|
    <div class="app-panel">
        <div class="app-panel-header">
            <div>
                <h3 class="app-panel-title mb-1">Sign-in access</h3>
                <p class="app-panel-description mb-0">Manage passkey setup, recovery, and password reset for the linked login.</p>
            </div>
        </div>
        <div class="app-panel-body">
            {renderLinkedLoginSummary maybeLinkedUserEmail}
            {renderStaffPasskeySetupControls staffEditBodyContext}
        </div>
    </div>
|]

renderLinkedLoginSummary :: Maybe Text -> Html
renderLinkedLoginSummary Nothing = [hsx|<p class="app-muted mb-0">No linked login for this staff member.</p>|]
renderLinkedLoginSummary (Just email) = [hsx|
    <p class="mb-2"><span class="app-muted">Linked login:</span> {email}</p>
|]

renderStaffPasskeySetupControls :: StaffEditBodyRenderContext -> Html
renderStaffPasskeySetupControls StaffEditBodyRenderContext
        { staffEditContext = StaffEditRenderContext { staff, maybeLinkedUserEmail = Just _, anchorDate, maybeRosterGroupId, .. }
        , staffCredentialControlsAllowed = True
        } = [hsx|
        <div class="d-flex flex-wrap gap-2">
            <form method="POST" action={SendStaffPasskeySetupEmailAction staff.id} class="d-inline">
                {renderStaffPasskeyReturnInputs anchorDate maybeRosterGroupId}
                <button type="submit" class="btn btn-sm btn-outline-secondary">Email passkey setup</button>
            </form>
            <form method="POST" action={SendStaffPasskeyRecoveryEmailAction staff.id} class="d-inline">
                {renderStaffPasskeyReturnInputs anchorDate maybeRosterGroupId}
                <button type="submit" class="btn btn-sm btn-outline-warning">Email recovery link</button>
            </form>
            <form method="POST" action={SendStaffPasswordResetEmailAction staff.id} class="d-inline">
                {renderStaffPasskeyReturnInputs anchorDate maybeRosterGroupId}
                <button type="submit" class="btn btn-sm btn-outline-warning">Email password reset</button>
            </form>
        </div>
    |]
renderStaffPasskeySetupControls _ = mempty

renderStaffPasskeyReturnInputs :: Day -> Maybe (Id RosterGroup) -> Html
renderStaffPasskeyReturnInputs anchorDate maybeRosterGroupId = [hsx|
    <input type="hidden" name="returnTo" value="staff"/>
    <input type="hidden" name="anchorDate" value={tshow anchorDate}/>
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
            , staffProfileDetailsSurfaceFields = fields
            , staffProfileDetailsFormAttributes = []
            , staffProfileDetailsFormHiddenInputs = [hsx|<input type="hidden" name={surfaceFieldNameFrom @Surface.SectionField fields} value={inputValue StaffProfileDetailsSection}/>|]
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
  where
    values = staffProfileDetailsSurfaceValues StaffProfileDetailsSection staff (Just managementFields)
    fields =
        ProfileAction.updateStaffProfileActionFields
            values.profileDetailsFirstName
            values.profileDetailsLastName
            values.profileDetailsPreferredName
            values.profileDetailsPhone
            values.profileDetailsIdealShiftsPerWeek
            values.profileDetailsEmergencyContactName
            values.profileDetailsEmergencyContactPhone
            values.profileDetailsSection
            values.profileDetailsVenueRole
            values.profileDetailsEmploymentBasis
            values.profileDetailsPayRateSelection
            values.profileDetailsRosterGroupIds

renderTrialStaffInvitationModalFragment :: UTCTime -> Staff -> [VenueInvitation] -> Maybe Text -> Maybe Text -> Day -> Maybe (Id RosterGroup) -> Html
renderTrialStaffInvitationModalFragment now staff pendingInvitations maybeError submittedEmail anchorDate maybeRosterGroupId =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = "Invite trial staff"
        , dialogOverlayBody = [hsx|
            {renderTrialStaffInvitationForm now staff pendingInvitations maybeError submittedEmail anchorDate maybeRosterGroupId}
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

renderTrialStaffInvitationForm :: UTCTime -> Staff -> [VenueInvitation] -> Maybe Text -> Maybe Text -> Day -> Maybe (Id RosterGroup) -> Html
renderTrialStaffInvitationForm now staff pendingInvitations maybeError submittedEmail anchorDate maybeRosterGroupId = [hsx|
    {renderCreateTrialStaffInvitationForm staff maybeError submittedEmail anchorDate maybeRosterGroupId}
    {renderPendingTrialInvitationList now pendingInvitations}
|]

renderCreateTrialStaffInvitationForm :: Staff -> Maybe Text -> Maybe Text -> Day -> Maybe (Id RosterGroup) -> Html
renderCreateTrialStaffInvitationForm staff maybeError submittedEmail anchorDate maybeRosterGroupId =
    applyAppShellActionAttrs
        (appShellActionByMarker @CreateTrialStaffInvitationOverlay)
        (trialInvitationSubmitRoute (pathTo (CreateTrialStaffInvitationAction staff.id)) [("id", "trial-staff-invite-form")])
        [hsx|
            <form method="POST" action={pathTo (CreateTrialStaffInvitationAction staff.id)}>
                {renderAnchorDateHiddenInput anchorDate}
                {renderRosterGroupHiddenInput maybeRosterGroupId}
                <p class="app-muted mb-3">Send an invite link so {staff.firstName} {staff.lastName} can claim this trial staff profile.</p>
                {forEach maybeError renderTrialInviteError}
                <div class="mb-3">
                    <label for="trial-staff-invitation-email" class="form-label">Email</label>
                    <input id="trial-staff-invitation-email" name="invitationEmail" type="email" class="form-control" placeholder="name@example.com" value={fromMaybe "" submittedEmail} required="required" />
                </div>
            </form>
        |]

trialInvitationSubmitRoute :: Text -> [(Text, Text)] -> AppShellActionRoute
trialInvitationSubmitRoute actionUrl extraAttrs =
    ((defaultAppShellActionRoute (actionUrl))
        { appShellActionRouteExtraAttrs = extraAttrs
        })

renderTrialInviteError :: Text -> Html
renderTrialInviteError message = [hsx|<div class="alert alert-danger" role="alert">{message}</div>|]

renderPendingTrialInvitationList :: UTCTime -> [VenueInvitation] -> Html
renderPendingTrialInvitationList _ [] = mempty
renderPendingTrialInvitationList now invitations = [hsx|
    <div class="border-top pt-3 mt-3">
        <h3 class="h6 mb-2">Pending invites</h3>
        <div class="list-group list-group-flush">
            {forEach invitations (renderPendingTrialInvitationRow now)}
        </div>
    </div>
|]

renderPendingTrialInvitationRow :: UTCTime -> VenueInvitation -> Html
renderPendingTrialInvitationRow now invitation = [hsx|
    <div class="list-group-item px-0 d-flex flex-wrap align-items-center justify-content-between gap-2">
        <div class="min-w-0">
            <div class="fw-semibold text-truncate">{invitation.email}</div>
            <div class="small app-muted">{if venueInvitationEffectiveExpiresAt invitation <= now then "Expired" else "Expires " <> formatUtcTimestamp (venueInvitationEffectiveExpiresAt invitation)}</div>
        </div>
        <div class="d-flex align-items-center gap-2">
            {renderInvitationStatusOrDeliveryBadge invitation.status invitation.deliveryStatus}
            {renderRenewTrialInvitationForm invitation}
        </div>
    </div>
|]

renderRenewTrialInvitationForm :: VenueInvitation -> Html
renderRenewTrialInvitationForm invitation =
    applyAppShellActionAttrs
        (appShellActionByMarker @CreateTrialStaffInvitationOverlay)
        (trialInvitationSubmitRoute (pathTo (RenewTrialStaffInvitationAction invitation.id)) [("class", "mb-0")])
        [hsx|
            <form method="POST" action={pathTo (RenewTrialStaffInvitationAction invitation.id)}>
                <div class="input-group input-group-sm">
                    <input type="email" class="form-control" name="invitationEmail" value={invitation.email} required="required" aria-label="Renewal email" />
                    <button type="submit" class="btn btn-outline-primary">Renew</button>
                </div>
            </form>
        |]

renderStaffShiftPreferencesEditForm :: OverlayFormMode -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Day -> Maybe (Id RosterGroup) -> StaffController -> Html
renderStaffShiftPreferencesEditForm formMode preferenceWeekdays selectedShiftPreferences anchorDate maybeRosterGroupId action =
    renderStaffShiftPreferencesForm
        StaffShiftPreferencesFormConfig
            { staffShiftPreferencesFormId = staffShiftPreferencesEditFormId
            , staffShiftPreferencesFormAction = pathTo action
            , staffShiftPreferencesFormClass = "mt-3"
            , staffShiftPreferencesFormRequestMode = staffShiftPreferencesOverlayRequestMode formMode (pathTo action)
            , staffShiftPreferencesSurfaceFields = fields
            , staffShiftPreferencesFormHiddenInputs = [hsx|
                <input type="hidden" name={surfaceFieldNameFrom @Surface.SectionField fields} value={inputValue StaffProfilePreferencesSection}/>
                {renderAnchorDateHiddenInput anchorDate}
                {renderRosterGroupHiddenInput maybeRosterGroupId}
            |]
            }
        preferenceWeekdays
        selectedShiftPreferences
  where
    values = staffShiftPreferencesSurfaceValues StaffProfilePreferencesSection selectedShiftPreferences
    fields =
        ProfileAction.updateStaffShiftPreferencesActionFields
            values.shiftPreferencesSection
            values.shiftPreferenceKeys

data StaffDetailsOverlayMarker
    = CreateTrialStaffOverlayMarker
    | UpdateStaffProfileOverlayMarker

staffDetailsFormRequestMode :: OverlayFormMode -> Text -> StaffDetailsOverlayMarker -> Maybe (StaffProfileDetailsFormRequestMode (ActionFields ProfileAction.UpdateStaffProfileActionOperation))
staffDetailsFormRequestMode HtmxOverlayForm actionUrl marker =
    case marker of
        UpdateStaffProfileOverlayMarker ->
            Just (StaffProfileDetailsSurfaceAction ProfileAction.updateStaffProfileAction (staffSectionActionRoute actionUrl ("#" <> staffProfileDetailsSectionId) "outerHTML show:none"))
        CreateTrialStaffOverlayMarker ->
            Just (StaffProfileDetailsAppShellAction (staffDetailsAppShellAction marker) (staffAppShellActionRoute actionUrl))
staffDetailsFormRequestMode PageOverlayForm _ _ = Nothing

staffDetailsAppShellAction :: StaffDetailsOverlayMarker -> AppShellActionIR
staffDetailsAppShellAction CreateTrialStaffOverlayMarker = appShellActionByMarker @CreateTrialStaffOverlay
staffDetailsAppShellAction UpdateStaffProfileOverlayMarker = appShellActionByMarker @UpdateStaffProfileOverlay

staffShiftPreferencesOverlayRequestMode :: OverlayFormMode -> Text -> Maybe (StaffShiftPreferencesFormRequestMode (ActionFields ProfileAction.UpdateStaffShiftPreferencesActionOperation))
staffShiftPreferencesOverlayRequestMode HtmxOverlayForm actionUrl =
    Just (StaffShiftPreferencesSurfaceAction ProfileAction.updateStaffShiftPreferencesAction (staffSectionActionRoute actionUrl ("#" <> staffProfilePreferencesSectionId) "outerHTML show:none"))
staffShiftPreferencesOverlayRequestMode PageOverlayForm _ = Nothing

staffAppShellActionRoute :: Text -> AppShellActionRoute
staffAppShellActionRoute actionUrl =
    (defaultAppShellActionRoute (actionUrl))

staffSectionActionRoute :: Text -> Text -> Text -> FrontendSurfaceActionRoute
staffSectionActionRoute actionUrl target swap =
    ((defaultFrontendSurfaceActionRoute (actionUrl))
        { actionRouteCustomHtmx = [ FrontendSurfaceCustomHtmxAttrs
                { customHtmxAttrMarker = "staff-profile-section-htmx-attrs"
                , customHtmxAttrValues =
                    [ ("hx-target", target)
                    , ("hx-swap", swap)
                    ]
                }
            ]
        })
