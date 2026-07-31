{-# LANGUAGE TypeApplications #-}

module Web.View.Profiles.Edit where

import qualified Application.Helper.FrontendContract.Surface.Profile as Surface
import qualified Application.Helper.FrontendContract.Surface.Profile.Action as ProfileAction
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            FrontendSurfaceCustomHtmxAttrs (..),
                                                            SurfaceImpl,
                                                            renderFrontendSurfaceActionForm,
                                                            renderFrontendSurfaceMount)
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.StaffShiftPreferences
import Web.LeaveRequests.SelfService (renderSelfServiceLeaveFormMount)
import Web.Profiles.FrontendSurface
import Web.View.Passkeys.Management (renderPasskeyManagement)
import Web.View.Prelude
import Web.View.StaffDocuments.Rsa
import Web.View.StaffProfileForm
import Web.View.StaffProfileSections

profileContentFragmentId :: Text
profileContentFragmentId = "profile-content-fragment"

profileSurfaceId :: Text
profileSurfaceId = "profile-live-surface"

profileDetailsSectionId :: Text
profileDetailsSectionId = surfaceFragmentTargetId @Surface.ProfileSurface @Surface.ProfileDetailsSection noSurfaceFields

profilePreferencesSectionId :: Text
profilePreferencesSectionId = surfaceFragmentTargetId @Surface.ProfileSurface @Surface.ProfilePreferencesSection noSurfaceFields

profileSecuritySectionId :: Text
profileSecuritySectionId = surfaceFragmentTargetId @Surface.ProfileSurface @Surface.ProfileSecuritySection noSurfaceFields

profileLeaveSectionId :: Text
profileLeaveSectionId = surfaceFragmentTargetId @Surface.ProfileSurface @Surface.ProfileLeaveSection noSurfaceFields

profileRsaSectionId :: Text
profileRsaSectionId = surfaceFragmentTargetId @Surface.ProfileSurface @Surface.ProfileRsaSection noSurfaceFields

profileDetailsFormId :: Text
profileDetailsFormId = "profile-details-form"

profileShiftPreferencesFormId :: Text
profileShiftPreferencesFormId = "profile-shift-preferences-form"

profileSectionsAccordionId :: Text
profileSectionsAccordionId = "profile-sections"

profileLeaveQueryParams :: [(Text, Text)]
profileLeaveQueryParams =
    [ ("responseContext", "profile")
    , ("section", "leave")
    ]

profileCreateLeaveRequestPath :: Text
profileCreateLeaveRequestPath =
    appendQueryParams (pathTo CreateLeaveRequestAction) profileLeaveQueryParams

profileActionRoute :: Text -> FrontendSurfaceActionRoute
profileActionRoute actionUrl =
    FrontendSurfaceActionRoute
        { actionRouteUrl = actionUrl
        , actionRouteCustomHtmx = []
        , actionRouteStandardUrl = Just actionUrl
        , actionRouteExtraAttrs = []
        }

profileSectionActionRoute :: Text -> Text -> Text -> FrontendSurfaceActionRoute
profileSectionActionRoute actionUrl target swap =
    (profileActionRoute actionUrl)
        { actionRouteCustomHtmx =
            [ FrontendSurfaceCustomHtmxAttrs
                { customHtmxAttrMarker = "staff-profile-section-htmx-attrs"
                , customHtmxAttrValues =
                    [ ("hx-target", "#" <> target)
                    , ("hx-swap", swap)
                    ]
                }
            ]
        }

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
            , appPageHelpTopic = Just (PageHelpTopicId "profile")
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
                        renderProfileSurface
                            staff
                            openSection
                            (renderprofileContentLiveFragmentWithManagement staff currentUserEmail preferenceWeekdays selectedShiftPreferences passkeys leaveRequests leaveRequestForm staffRsaDocument staffManagementFields today now openSection)
                    }
            })

renderProfileSurface :: Staff -> Text -> Html -> Html
renderProfileSurface staff _openSection body =
    let mountedBody = case profileSurfaceMount staff of
            Just impl -> renderFrontendSurfaceMount impl body
            Nothing   -> body
     in [hsx|
        <div id={profileSurfaceId}>
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
profileAccordionSections staff currentUserEmail preferenceWeekdays selectedShiftPreferences passkeys leaveRequests leaveRequestForm _staffRsaDocument staffManagementFields _today now =
    [ profileDetailsAccordionSection staff currentUserEmail staffManagementFields
    , profilePreferencesAccordionSection preferenceWeekdays selectedShiftPreferences
    , profileSecurityAccordionSection now passkeys
    , profileLeaveAccordionSection staff leaveRequestForm leaveRequests
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
        , staffProfileSectionBody = renderSelfServiceLeaveFormMount "profile" True staff leaveRequestForm leaveRequests
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
            _             -> profileDetailsAccordionSection staff currentUserEmail staffManagementFields
     in renderStaffProfileAccordionSection profileSectionsAccordionId openSection section

normalizeProfileSectionForRender :: Text -> Text
normalizeProfileSectionForRender section
    | section `elem` ["preferences", "security", "leave"] = section
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
            , staffProfileDetailsFormRequestMode =
                Just (StaffProfileDetailsSurfaceAction ProfileAction.updateProfileDetailsAction (profileSectionActionRoute (pathTo UpdateProfileAction) profileDetailsSectionId "outerHTML show:none"))
            , staffProfileDetailsSurfaceFields = fields
            , staffProfileDetailsFormAttributes = []
            , staffProfileDetailsFormHiddenInputs = [hsx|<input type="hidden" name={surfaceFieldNameFrom @Surface.SectionField fields} value="profile"/>|]
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
  where
    values = staffProfileDetailsSurfaceValues "profile" staff staffManagementFields
    fields =
        ProfileAction.updateProfileDetailsActionFields
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

renderProfileShiftPreferencesForm :: [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Html
renderProfileShiftPreferencesForm preferenceWeekdays selectedShiftPreferences =
    renderStaffShiftPreferencesForm
        StaffShiftPreferencesFormConfig
            { staffShiftPreferencesFormId = profileShiftPreferencesFormId
            , staffShiftPreferencesFormAction = pathTo UpdateProfileAction
            , staffShiftPreferencesFormClass = ""
            , staffShiftPreferencesFormRequestMode =
                Just (StaffShiftPreferencesSurfaceAction ProfileAction.updateProfileShiftPreferencesAction (profileSectionActionRoute (pathTo UpdateProfileAction) profilePreferencesSectionId "outerHTML show:none"))
            , staffShiftPreferencesSurfaceFields = fields
            , staffShiftPreferencesFormHiddenInputs = [hsx|<input type="hidden" name={surfaceFieldNameFrom @Surface.SectionField fields} value="preferences"/>|]
            , staffShiftPreferencesFormSubmitLabel = "Save shift preferences"
            }
        preferenceWeekdays
        selectedShiftPreferences
  where
    values = staffShiftPreferencesSurfaceValues "preferences" selectedShiftPreferences
    fields =
        ProfileAction.updateProfileShiftPreferencesActionFields
            values.shiftPreferencesSection
            values.shiftPreferenceKeys

renderProfileStaffManagementSection :: SurfaceActionFields Surface.ProfileSurface Surface.UpdateProfileDetails -> StaffManagementFieldData -> Html
renderProfileStaffManagementSection fields managementFields = [hsx|
    <div class="mt-4">
        <h5 class="mb-3">Staff Admin</h5>
        {renderStaffManagementFields fields managementFields}
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

