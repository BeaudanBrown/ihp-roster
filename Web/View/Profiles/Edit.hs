module Web.View.Profiles.Edit where

import qualified Application.Helper.FrontendSurface.Profile as Surface
import Application.Helper.FrontendSurface.Runtime (SurfaceImpl,
                                                   renderFrontendSurfaceMount)
import Application.Helper.StaffShiftPreferences
import Data.List (sortOn)
import Data.Ord (Down (..))
import Web.Profiles.FrontendSurface
import Web.Profiles.LiveUpdates
import Web.View.LeaveRequests.Index (renderStatusBadge)
import Web.View.LeaveRequests.New (renderLeaveRequestFormFields)
import Web.View.Passkeys.Management (renderPasskeyManagement)
import Web.View.Prelude
import Web.View.StaffDocuments.Rsa
import Web.View.StaffProfileForm
import Web.View.StaffProfileSections

profileContentFragmentId :: Text
profileContentFragmentId = "profile-content-fragment"

profileLiveSurfaceId :: Text
profileLiveSurfaceId = "profile-live-surface"

profileDetailsSectionId :: Text
profileDetailsSectionId = "profile-details"

profilePreferencesSectionId :: Text
profilePreferencesSectionId = "profile-preferences"

profileSecuritySectionId :: Text
profileSecuritySectionId = "profile-security"

profileLeaveSectionId :: Text
profileLeaveSectionId = "profile-leave"

profileRsaSectionId :: Text
profileRsaSectionId = "profile-rsa"

profileDetailsFormId :: Text
profileDetailsFormId = "profile-details-form"

profileShiftPreferencesFormId :: Text
profileShiftPreferencesFormId = "profile-shift-preferences-form"

profileSectionsAccordionId :: Text
profileSectionsAccordionId = "profile-sections"

profileleaveRequestsContentLiveFragmentId :: Text
profileleaveRequestsContentLiveFragmentId = "profile-leave-requests-content"

profileLeaveRequestFormFragmentId :: Text
profileLeaveRequestFormFragmentId = "profile-leave-request-form-fragment"

profileLeaveRequestsListFragmentId :: Text
profileLeaveRequestsListFragmentId = "profile-leave-requests-list-fragment"

profileLeaveQueryParams :: [(Text, Text)]
profileLeaveQueryParams =
    [ ("responseContext", "profile")
    , ("section", "leave")
    ]

profileCreateLeaveRequestPath :: Text
profileCreateLeaveRequestPath =
    appendQueryParams (pathTo CreateLeaveRequestAction) profileLeaveQueryParams

data EditView = EditView
    { staff                    :: Staff
    , currentUserEmail         :: Text
    , preferenceWeekdays       :: [PreferenceWeekday]
    , selectedShiftPreferences :: [ShiftPreferenceSelection]
    , passkeys                 :: [Passkey]
    , leaveRequests            :: [LeaveRequest]
    , leaveRequestForm         :: LeaveRequest
    , staffRsaDocument         :: Maybe StaffDocument
    , staffManagementFields    :: Maybe StaffManagementFieldData
    , today                    :: Day
    , now                      :: UTCTime
    , openSection              :: Text
    }

instance View EditView where
    html EditView { .. } =
        renderAppPage (AppPageConfig
            { appPageTitle = "Profile"
            , appPageDescription = Nothing
            , appPageActions = mempty
            , appPageWidthClass = ""
            , appPageBody =
                renderAppPanel AppPanelConfig
                    { appPanelTitle = Nothing
                    , appPanelDescription = Nothing
                    , appPanelHasActions = False
                    , appPanelActions = mempty
                    , appPanelHasCustomHeader = False
                    , appPanelCustomHeader = mempty
                    , appPanelClass = ""
                    , appPanelBodyClass = ""
                    , appPanelBody =
                        renderProfileLiveSurface
                            staff
                            openSection
                            (renderprofileContentLiveFragmentWithManagement staff currentUserEmail preferenceWeekdays selectedShiftPreferences passkeys leaveRequests leaveRequestForm staffRsaDocument staffManagementFields today now openSection)
                    }
            })

renderProfileLiveSurface :: Staff -> Text -> Html -> Html
renderProfileLiveSurface staff _openSection body =
    let mountedBody = case profileSurfaceMount staff of
            Just impl -> renderFrontendSurfaceMount impl body
            Nothing   -> body
     in [hsx|
        <div id={profileLiveSurfaceId}>
            {mountedBody}
        </div>
    |]

renderprofileContentLiveFragment :: Staff -> Text -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> [Passkey] -> [LeaveRequest] -> LeaveRequest -> Maybe StaffDocument -> Day -> UTCTime -> Text -> Html
renderprofileContentLiveFragment staff currentUserEmail preferenceWeekdays selectedShiftPreferences passkeys leaveRequests leaveRequestForm staffRsaDocument =
    renderprofileContentLiveFragmentWithManagement staff currentUserEmail preferenceWeekdays selectedShiftPreferences passkeys leaveRequests leaveRequestForm staffRsaDocument Nothing

renderprofileContentLiveFragmentWithManagement :: Staff -> Text -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> [Passkey] -> [LeaveRequest] -> LeaveRequest -> Maybe StaffDocument -> Maybe StaffManagementFieldData -> Day -> UTCTime -> Text -> Html
renderprofileContentLiveFragmentWithManagement staff currentUserEmail preferenceWeekdays selectedShiftPreferences passkeys leaveRequests leaveRequestForm staffRsaDocument staffManagementFields today now openSection =
    let accordionConfig =
            StaffProfileAccordionConfig
                { staffProfileAccordionId = profileSectionsAccordionId
                , staffProfileAccordionOpenSection = openSection
                , staffProfileAccordionSections =
                    profileAccordionSections staff currentUserEmail preferenceWeekdays selectedShiftPreferences passkeys leaveRequests leaveRequestForm staffRsaDocument staffManagementFields today now
                }
     in [hsx|
        <div id={profileContentFragmentId}>
            {renderStaffProfileAccordion accordionConfig}
        </div>
    |]

profileAccordionSections :: Staff -> Text -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> [Passkey] -> [LeaveRequest] -> LeaveRequest -> Maybe StaffDocument -> Maybe StaffManagementFieldData -> Day -> UTCTime -> [StaffProfileAccordionSection]
profileAccordionSections staff currentUserEmail preferenceWeekdays selectedShiftPreferences passkeys leaveRequests leaveRequestForm staffRsaDocument staffManagementFields today now =
    [ profileDetailsAccordionSection staff currentUserEmail staffManagementFields
    , profilePreferencesAccordionSection preferenceWeekdays selectedShiftPreferences
    , profileSecurityAccordionSection now passkeys
    , profileLeaveAccordionSection staff leaveRequestForm leaveRequests
    , profileRsaAccordionSection staff staffRsaDocument today
    ]

profileDetailsAccordionSection :: Staff -> Text -> Maybe StaffManagementFieldData -> StaffProfileAccordionSection
profileDetailsAccordionSection staff currentUserEmail staffManagementFields =
    StaffProfileAccordionSection
        { staffProfileSectionKey = "profile"
        , staffProfileSectionId = profileDetailsSectionId
        , staffProfileSectionTitle = "Profile Details"
        , staffProfileSectionBody = renderProfileForm staff currentUserEmail staffManagementFields
        }

profilePreferencesAccordionSection :: [PreferenceWeekday] -> [ShiftPreferenceSelection] -> StaffProfileAccordionSection
profilePreferencesAccordionSection preferenceWeekdays selectedShiftPreferences =
    StaffProfileAccordionSection
        { staffProfileSectionKey = "preferences"
        , staffProfileSectionId = profilePreferencesSectionId
        , staffProfileSectionTitle = "Shift Preferences"
        , staffProfileSectionBody = renderProfileShiftPreferencesForm preferenceWeekdays selectedShiftPreferences
        }

profileSecurityAccordionSection :: UTCTime -> [Passkey] -> StaffProfileAccordionSection
profileSecurityAccordionSection now passkeys =
    StaffProfileAccordionSection
        { staffProfileSectionKey = "security"
        , staffProfileSectionId = profileSecuritySectionId
        , staffProfileSectionTitle = "Sign-In Methods"
        , staffProfileSectionBody = renderPasskeyManagement now passkeys (appendQueryParams (pathTo EditProfileAction) [("section", "security")])
        }

profileLeaveAccordionSection :: Staff -> LeaveRequest -> [LeaveRequest] -> StaffProfileAccordionSection
profileLeaveAccordionSection staff leaveRequestForm leaveRequests =
    StaffProfileAccordionSection
        { staffProfileSectionKey = "leave"
        , staffProfileSectionId = profileLeaveSectionId
        , staffProfileSectionTitle = "Unavailability"
        , staffProfileSectionBody = renderProfileleaveRequestsContentLiveFragment staff leaveRequestForm leaveRequests
        }

profileRsaAccordionSection :: Staff -> Maybe StaffDocument -> Day -> StaffProfileAccordionSection
profileRsaAccordionSection staff staffRsaDocument today =
    StaffProfileAccordionSection
        { staffProfileSectionKey = "rsa"
        , staffProfileSectionId = profileRsaSectionId
        , staffProfileSectionTitle = "RSA"
        , staffProfileSectionBody = renderProfileRsaSection staff staffRsaDocument today
        }

renderProfileSectionFragmentWithManagement :: Staff -> Text -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> [Passkey] -> [LeaveRequest] -> LeaveRequest -> Maybe StaffDocument -> Maybe StaffManagementFieldData -> Day -> UTCTime -> Text -> Html
renderProfileSectionFragmentWithManagement staff currentUserEmail preferenceWeekdays selectedShiftPreferences passkeys leaveRequests leaveRequestForm staffRsaDocument staffManagementFields today now openSection =
    let section = case normalizeProfileSectionForRender openSection of
            "preferences" -> profilePreferencesAccordionSection preferenceWeekdays selectedShiftPreferences
            "security"    -> profileSecurityAccordionSection now passkeys
            "leave"       -> profileLeaveAccordionSection staff leaveRequestForm leaveRequests
            "rsa"         -> profileRsaAccordionSection staff staffRsaDocument today
            _             -> profileDetailsAccordionSection staff currentUserEmail staffManagementFields
     in renderStaffProfileAccordionSection profileSectionsAccordionId openSection section

normalizeProfileSectionForRender :: Text -> Text
normalizeProfileSectionForRender section
    | section `elem` ["preferences", "security", "leave", "rsa"] = section
    | otherwise = "profile"

profileSurfaceMount :: (?context :: ControllerContext) => Staff -> Maybe (SurfaceImpl Surface.ProfileSurface)
profileSurfaceMount staff =
    if currentUser.isProfileCompleted && not (isNew staff)
        then Just (profileSurfaceImpl ProfileScopeValue { profileVenueId = staff.venueId, profileStaffId = unpackId staff.id })
        else Nothing

renderAccordionSection :: Text -> Text -> Bool -> Html -> Html
renderAccordionSection sectionId title isOpen body =
    renderStaffProfileAccordionSection
        profileSectionsAccordionId
        (if isOpen then sectionId else "")
        StaffProfileAccordionSection
            { staffProfileSectionKey = sectionId
            , staffProfileSectionId = sectionId
            , staffProfileSectionTitle = title
            , staffProfileSectionBody = body
            }

renderProfileForm :: Staff -> Text -> Maybe StaffManagementFieldData -> Html
renderProfileForm staff currentUserEmail staffManagementFields =
    renderStaffProfileDetailsForm
        StaffProfileDetailsFormConfig
            { staffProfileDetailsFormId = profileDetailsFormId
            , staffProfileDetailsFormAction = pathTo UpdateProfileAction
            , staffProfileDetailsFormClass = ""
            , staffProfileDetailsFormHtmx =
                Just StaffProfileFormHtmxConfig
                    { staffProfileFormHtmxTarget = "#" <> profileDetailsSectionId
                    , staffProfileFormHtmxSwap = "outerHTML show:none"
                    , staffProfileFormHtmxPushUrl = "false"
                    }
            , staffProfileDetailsFormAttributes = []
            , staffProfileDetailsFormHiddenInputs = [hsx|<input type="hidden" name="section" value="profile"/>|]
            , staffProfileDetailsFormBeforeFields = mempty
            , staffProfileDetailsFormFieldsHeading = Nothing
            , staffProfileDetailsFormEmailField = renderPersonalProfileFields
            , staffProfileDetailsFormAfterFields = mempty
            , staffProfileDetailsFormManagement = staffManagementFields
            , staffProfileDetailsFormManagementBody = renderProfileStaffManagementSection
            , staffProfileDetailsFormSubmitLabel = "Save profile details"
            }
        staff
        (Just currentUserEmail)

renderProfileShiftPreferencesForm :: [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Html
renderProfileShiftPreferencesForm preferenceWeekdays selectedShiftPreferences =
    renderStaffShiftPreferencesForm
        StaffShiftPreferencesFormConfig
            { staffShiftPreferencesFormId = profileShiftPreferencesFormId
            , staffShiftPreferencesFormAction = pathTo UpdateProfileAction
            , staffShiftPreferencesFormClass = ""
            , staffShiftPreferencesFormHtmx =
                Just StaffProfileFormHtmxConfig
                    { staffProfileFormHtmxTarget = "#" <> profilePreferencesSectionId
                    , staffProfileFormHtmxSwap = "outerHTML show:none"
                    , staffProfileFormHtmxPushUrl = "false"
                    }
            , staffShiftPreferencesFormHiddenInputs = [hsx|<input type="hidden" name="section" value="preferences"/>|]
            , staffShiftPreferencesFormSubmitLabel = "Save shift preferences"
            }
        preferenceWeekdays
        selectedShiftPreferences

renderProfileStaffManagementSection :: StaffManagementFieldData -> Html
renderProfileStaffManagementSection managementFields = [hsx|
    <div class="mt-4">
        <h5 class="mb-3">Staff Admin</h5>
        {renderStaffManagementFields managementFields}
    </div>
|]

renderProfileRsaSection :: Staff -> Maybe StaffDocument -> Day -> Html
renderProfileRsaSection staff staffRsaDocument today =
    if isNew staff
        then renderAppPanel AppPanelConfig
            { appPanelTitle = Nothing
            , appPanelDescription = Nothing
            , appPanelHasActions = False
            , appPanelActions = mempty
            , appPanelHasCustomHeader = False
            , appPanelCustomHeader = mempty
            , appPanelClass = ""
            , appPanelBodyClass = ""
            , appPanelBody = [hsx|<p class="app-muted mb-0">Save your profile details before uploading RSA.</p>|]
            }
        else renderRsaDocumentPanel
            RsaPanelConfig
                { rsaPanelStaff = staff
                , rsaPanelDocument = staffRsaDocument
                , rsaPanelToday = today
                , rsaPanelReturnContext =
                    RsaReturnContext
                        { rsaReturnTo = "profile"
                        , rsaReturnWeekOffset = Nothing
                        , rsaReturnRosterGroupId = Nothing
                        }
                , rsaPanelCanReview = currentUserIsManager
                , rsaPanelShowHeader = False
                }

renderProfileleaveRequestsContentLiveFragment :: Staff -> LeaveRequest -> [LeaveRequest] -> Html
renderProfileleaveRequestsContentLiveFragment =
    renderProfileleaveRequestsContentLiveFragmentWithSwap Nothing

renderProfileleaveRequestsContentLiveFragmentWithSwap :: Maybe Text -> Staff -> LeaveRequest -> [LeaveRequest] -> Html
renderProfileleaveRequestsContentLiveFragmentWithSwap maybeSwapOob staff leaveRequest leaveRequests = [hsx|
    <div id={profileleaveRequestsContentLiveFragmentId}
         hx-swap-oob={maybeSwapOob}>
        <div class="row g-4 align-items-start">
            <div class="col-12 col-xl-5">
                {renderProfileLeaveRequestFormFragment leaveRequest}
            </div>
            <div class="col-12 col-xl-7">
                {renderProfileLeaveRequestsListFragment leaveRequests}
            </div>
        </div>
    </div>
|]

renderProfileLeaveRequestFormFragment :: LeaveRequest -> Html
renderProfileLeaveRequestFormFragment leaveRequest = [hsx|
    <div id={profileLeaveRequestFormFragmentId}>
        <form id="profile-leave-request-form"
              method="POST"
              action={profileCreateLeaveRequestPath}
              data-disable-javascript-submission="true"
              hx-post={profileCreateLeaveRequestPath}
              hx-target={"#" <> profileLeaveRequestFormFragmentId}
              hx-swap="outerHTML"
              hx-push-url="false">
            <input type="hidden" name="responseContext" value="profile"/>
            <input type="hidden" name="section" value="leave"/>
            {renderLeaveRequestFormFields leaveRequest}
            <div class="d-grid mt-4 app-form-width">
                <button type="submit" class="btn btn-primary">Add unavailable time</button>
            </div>
        </form>
    </div>
|]

renderProfileLeaveRequestsListFragment :: [LeaveRequest] -> Html
renderProfileLeaveRequestsListFragment leaveRequests = [hsx|
    <div id={profileLeaveRequestsListFragmentId}>
        <h5 class="mb-3">Unavailable periods</h5>
        {renderProfileLeaveRequestsList leaveRequests}
    </div>
|]

renderProfileLeaveRequestsList :: [LeaveRequest] -> Html
renderProfileLeaveRequestsList leaveRequests
    | null leaveRequests =
        renderAppPanel AppPanelConfig
            { appPanelTitle = Nothing
            , appPanelDescription = Nothing
            , appPanelHasActions = False
            , appPanelActions = mempty
            , appPanelHasCustomHeader = False
            , appPanelCustomHeader = mempty
            , appPanelClass = "app-form-width"
            , appPanelBodyClass = ""
            , appPanelBody = [hsx|<p class="app-muted mb-0">No unavailable periods submitted yet.</p>|]
            }
    | otherwise = [hsx|
        <div class="leave-request-list">
            <div class="leave-request-list-head">
                <div>Dates</div>
                <div>Status</div>
                <div>Notes</div>
            </div>
            <div class="leave-request-list-body">
                {forEach sortedLeaveRequests renderProfileLeaveRequestRow}
            </div>
        </div>
    |]
    where
        sortedLeaveRequests = sortOn (Down . (.startDate)) leaveRequests

renderProfileLeaveRequestRow :: LeaveRequest -> Html
renderProfileLeaveRequestRow leaveRequest = [hsx|
    <article class="leave-request-row">
        <div class="leave-request-row-dates">{renderDateRangeText leaveRequest}</div>
        <div class="leave-request-row-status">{renderStatusBadge leaveRequest.status}</div>
        <div class="leave-request-row-notes">{fromMaybe "No notes" (leaveRequest.notes >>= nonEmptyText)}</div>
    </article>
|]

