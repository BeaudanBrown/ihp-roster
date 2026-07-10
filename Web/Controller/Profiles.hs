module Web.Controller.Profiles where

import Application.Helper.LiveUpdate (setActorLiveFragmentsRefresh)
import Application.Helper.ProfileLeave (buildDefaultLeaveRequest,
                                        fetchCurrentUserLeaveRequests)
import Application.Helper.Profiling (profileActionSpan)
import Application.Helper.RosterGroups (fetchCurrentVenueRosterGroups,
                                        fetchStaffRosterGroupIds)
import Application.Helper.StaffShiftPreferences
import Application.Helper.SurfaceResource (LiveMutationResult (..))
import Application.Helper.View (ToastOverlayPosition (ToastBottomCenter),
                                renderToastOob, successToast)
import Application.StaffDocuments.Rsa (latestRsaDocumentForStaff)
import Data.Time.Clock (getCurrentTime, utctDay)
import Web.Controller.Admin.Support (SubmittedPayRateSelection (..),
                                     fetchActiveImportedXeroPayItems,
                                     parseSubmittedPayRateSelection)
import Web.Controller.Prelude
import Web.Controller.Staff (buildStaff, emptyStaffPayRateSelection,
                             fetchAwardLevelBaseRatesForStaffForm,
                             fetchAwardLevelsForStaffForm,
                             parseRosterGroupIdText, parseStaffRosterGroupIds)
import Web.Controller.StaffProfileValidation (buildRequiredPersonalProfileStaff)
import Web.Profiles.FrontendSurface (ProfileScopeValue (..),
                                     profileSectionFragmentForSection,
                                     profileSurfaceScope,
                                     profileSurfaceWireFragments)
import Web.Profiles.LeaveFragments
import Web.Profiles.LiveUpdates
import Web.Profiles.Mutations
import Web.Staff.Mutations (updateStaffMember)
import Web.View.Profiles.Edit
import Web.View.StaffProfileForm (StaffManagementFieldData (..))

instance Controller ProfilesController where
    beforeAction = bepisBeforeAction BepisAuthenticatedVenueController do
        annotateTelemetryAction
        ensureIsUser
        ensureCurrentVenue
        ensureStaffSelfServiceAccess

    action currentAction@EditProfileAction = runBepis currentAction BepisFormAction $
        profileActionSpan "profile.page.render" do
            maybeExistingStaff <- profileActionSpan "profile.page.fetch_staff" fetchCurrentUserStaff
            let staff = fromMaybe (buildNewCurrentUserStaff currentUser) maybeExistingStaff
            let currentUserEmail = currentUser.email
            let openSection = normalizeProfileOpenSection (paramOrDefault @Text "" "section")
            (preferenceWeekdays, selectedShiftPreferences) <- profileActionSpan "profile.page.fetch_preferences" (profilePreferenceViewData maybeExistingStaff)
            passkeys <- profileActionSpan "profile.page.fetch_passkeys" fetchCurrentUserPasskeys
            leaveRequests <- profileActionSpan "profile.page.fetch_leave_requests" fetchCurrentUserLeaveRequests
            leaveRequestForm <- profileActionSpan "profile.page.build_leave_form" buildDefaultLeaveRequest
            staffRsaDocument <- profileActionSpan "profile.page.fetch_rsa_document" (maybe (pure Nothing) latestRsaDocumentForStaff maybeExistingStaff)
            staffManagementFields <- profileActionSpan "profile.page.fetch_management_fields" (fetchProfileStaffManagementFields maybeExistingStaff Nothing)
            now <- getCurrentTime
            let today = utctDay now
            profileActionSpan "profile.page.render_response" (render EditView { .. })

    action currentAction@ShowProfileleaveRequestsContentLiveFragmentAction = runBepis currentAction BepisFragmentAction $
        profileActionSpan "profile.leave_fragment.respond" do
            maybeExistingStaff <- profileActionSpan "profile.leave_fragment.fetch_staff" fetchCurrentUserStaff
            case maybeExistingStaff of
                Nothing -> accessDeniedUnless False
                Just staff -> do
                    model <- profileActionSpan "profile.leave_fragment.fetch_model" (fetchProfileLeaveFragmentModel staff)
                    profileActionSpan "profile.leave_fragment.render_response" (respondHtml (renderProfileLeaveFragment FragmentPlain model profileLeaveRequestsFragment))

    action currentAction@ShowprofileContentLiveFragmentAction = runBepis currentAction BepisFragmentAction $
        profileActionSpan "profile.content_fragment.respond" do
            let openSection = normalizeProfileOpenSection (paramOrDefault @Text "" "section")
            profileActionSpan "profile.content_fragment.fetch_staff" fetchCurrentUserStaff >>= \case
                Nothing -> accessDeniedUnless False
                Just staff -> do
                    let currentUserEmail = currentUser.email
                    (preferenceWeekdays, selectedShiftPreferences) <- profileActionSpan "profile.content_fragment.fetch_preferences" (profilePreferenceViewData (Just staff))
                    passkeys <- profileActionSpan "profile.content_fragment.fetch_passkeys" fetchCurrentUserPasskeys
                    leaveRequests <- profileActionSpan "profile.content_fragment.fetch_leave_requests" fetchCurrentUserLeaveRequests
                    leaveRequestForm <- profileActionSpan "profile.content_fragment.build_leave_form" buildDefaultLeaveRequest
                    staffRsaDocument <- profileActionSpan "profile.content_fragment.fetch_rsa_document" (latestRsaDocumentForStaff staff)
                    staffManagementFields <- profileActionSpan "profile.content_fragment.fetch_management_fields" (fetchProfileStaffManagementFields (Just staff) Nothing)
                    now <- getCurrentTime
                    let today = utctDay now
                    profileActionSpan "profile.content_fragment.render_response" (respondHtml (renderProfileSectionFragmentWithManagement staff currentUserEmail preferenceWeekdays selectedShiftPreferences passkeys leaveRequests leaveRequestForm staffRsaDocument staffManagementFields today now openSection))

    action currentAction@UpdateProfileAction = runBepis currentAction BepisMutationAction do
        maybeExistingStaff <- fetchCurrentUserStaff
        let submittedShiftPreferenceKeys = nub (paramTexts "shiftPreferenceKeys")
        let staff = fromMaybe (buildNewCurrentUserStaff currentUser) maybeExistingStaff
        let currentUserEmail = currentUser.email
        let openSection = normalizeProfileOpenSection (paramOrDefault @Text "" "section")
        let preferencesWereSubmitted = openSection == "preferences"
        passkeys <- fetchCurrentUserPasskeys
        staffRsaDocument <- maybe (pure Nothing) latestRsaDocumentForStaff maybeExistingStaff
        let submittedRosterGroupIds = nub (mapMaybe parseRosterGroupIdText (paramTexts "rosterGroupIds"))
        staffManagementFields <- fetchProfileStaffManagementFields maybeExistingStaff (if preferencesWereSubmitted then Nothing else Just submittedRosterGroupIds)
        now <- getCurrentTime
        let today = utctDay now
        (preferenceWeekdays, selectedShiftPreferences) <-
            if preferencesWereSubmitted
                then profilePreferenceViewDataWithSubmitted maybeExistingStaff submittedShiftPreferenceKeys
                else profilePreferenceViewData maybeExistingStaff
        leaveRequests <- fetchCurrentUserLeaveRequests
        leaveRequestForm <- buildDefaultLeaveRequest
        let canManageProfileStaff = hasRole VenueAdminRole && isJust maybeExistingStaff && not preferencesWereSubmitted
        maybeSelectedRosterGroupIds <- if canManageProfileStaff then parseStaffRosterGroupIds else pure Nothing
        maybeSubmittedPayRateSelection <- if canManageProfileStaff then parseSubmittedPayRateSelection "payRateSelection" else pure (Just emptyStaffPayRateSelection)
        let maybeSubmittedDefaultAwardLevelId = submittedAwardLevelId <$> maybeSubmittedPayRateSelection
        let maybeSubmittedImportedXeroPayItemId = submittedImportedXeroPayItemId <$> maybeSubmittedPayRateSelection
        let buildProfileStaff currentStaff
                | preferencesWereSubmitted = currentStaff
                | canManageProfileStaff = buildStaff True maybeSubmittedDefaultAwardLevelId maybeSubmittedImportedXeroPayItemId currentStaff
                | otherwise = buildRequiredPersonalProfileStaff currentStaff
        staff
            |> buildProfileStaff
            |> ifValid \case
                Left staff -> do
                    if isHtmxRequest
                        then respondHtml (renderProfileSectionFragmentWithManagement staff currentUserEmail preferenceWeekdays selectedShiftPreferences passkeys leaveRequests leaveRequestForm staffRsaDocument staffManagementFields today now openSection)
                        else render EditView { .. }
                Right staff -> do
                    case if preferencesWereSubmitted then parseShiftPreferenceSelections preferenceWeekdays submittedShiftPreferenceKeys else Right selectedShiftPreferences of
                        Left preferenceError -> do
                            venueConfig <- fetchVenueConfig
                            setErrorMessage preferenceError
                            let currentUserEmail = currentUser.email
                            let preferenceWeekdays = allPreferenceWeekdays venueConfig
                            let selectedShiftPreferences =
                                    case parseShiftPreferenceSelections preferenceWeekdays submittedShiftPreferenceKeys of
                                        Right selections -> selections
                                        Left _           -> []
                            leaveRequests <- fetchCurrentUserLeaveRequests
                            leaveRequestForm <- buildDefaultLeaveRequest
                            staffRsaDocument <- maybe (pure Nothing) latestRsaDocumentForStaff maybeExistingStaff
                            if isHtmxRequest
                                then respondHtml (renderProfileSectionFragmentWithManagement staff currentUserEmail preferenceWeekdays selectedShiftPreferences passkeys leaveRequests leaveRequestForm staffRsaDocument staffManagementFields today now openSection)
                                else render EditView { .. }
                        Right submittedSelections -> do
                            if canManageProfileStaff
                                then case (maybeExistingStaff, maybeSelectedRosterGroupIds, maybeSubmittedDefaultAwardLevelId, maybeSubmittedImportedXeroPayItemId) of
                                    (Just originalStaff, Just selectedRosterGroupIds, Just _, Just _) -> do
                                        mutationResult <- updateStaffMember originalStaff staff selectedRosterGroupIds submittedSelections Nothing Nothing
                                        let updatedStaff = mutationResult.liveMutationValue
                                        if isHtmxRequest
                                            then respondWithProfileActorInvalidation updatedStaff openSection "Profile updated"
                                            else do
                                                setSuccessMessage "Profile updated"
                                                redirectTo EditProfileAction
                                    _ ->
                                        if isHtmxRequest
                                            then respondHtml (renderProfileSectionFragmentWithManagement staff currentUserEmail preferenceWeekdays selectedShiftPreferences passkeys leaveRequests leaveRequestForm staffRsaDocument staffManagementFields today now openSection)
                                            else render EditView { .. }
                                else if preferencesWereSubmitted && isNothing maybeExistingStaff
                                    then do
                                        setErrorMessage "Save your profile details before setting shift preferences."
                                        if isHtmxRequest
                                            then respondHtml (renderProfileSectionFragmentWithManagement staff currentUserEmail preferenceWeekdays submittedSelections passkeys leaveRequests leaveRequestForm staffRsaDocument staffManagementFields today now openSection)
                                            else render EditView { .. }
                                    else do
                                        mutationResult <- updateCurrentUserProfile openSection staff submittedSelections
                                        let profileUpdate = mutationResult.liveMutationValue
                                        let updatedStaff = profileUpdate.profileUpdatedStaff
                                        let successMessage = if preferencesWereSubmitted then "Shift preferences updated" else "Profile updated"
                                        if not preferencesWereSubmitted && not profileUpdate.profileWasCompletedBefore && profileUpdate.profileIsCompletedNow
                                            then redirectTo RosterWeeksAction
                                            else if isHtmxRequest
                                                then respondWithProfileActorInvalidation updatedStaff openSection successMessage
                                                else do
                                                    setSuccessMessage successMessage
                                                    redirectTo EditProfileAction

respondWithProfileActorInvalidation :: (?context :: ControllerContext, ?request :: Request) => Staff -> Text -> Text -> IO ()
respondWithProfileActorInvalidation staff openSection successMessage = do
    let scope = ProfileScopeValue (unpackId currentVenueId) (unpackId staff.id)
    setHeader ("HX-Reswap", "none")
    setActorLiveFragmentsRefresh (profileSurfaceScope scope) (profileSurfaceWireFragments [profileSectionFragmentForSection openSection])
    respondHtml (renderToastOob ToastBottomCenter (successToast successMessage))

buildNewCurrentUserStaff :: (?context :: ControllerContext) => User -> Staff
buildNewCurrentUserStaff user =
    newRecord @Staff
        |> set #venueId (unpackId currentVenueId)
        |> set #userId (Just (unpackId (get #id user)))

fetchProfileStaffManagementFields :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe Staff -> Maybe [Id RosterGroup] -> IO (Maybe StaffManagementFieldData)
fetchProfileStaffManagementFields Nothing _ = pure Nothing
fetchProfileStaffManagementFields (Just staff) maybeSubmittedRosterGroupIds
    | not (hasRole VenueAdminRole) = pure Nothing
    | otherwise = do
        rosterGroups <- fetchCurrentVenueRosterGroups
        awardLevels <- fetchAwardLevelsForStaffForm
        awardLevelBaseRates <- fetchAwardLevelBaseRatesForStaffForm
        importedPayItems <- fetchActiveImportedXeroPayItems
        selectedRosterGroupIds <- maybe (fetchStaffRosterGroupIds staff) pure maybeSubmittedRosterGroupIds
        pure $
            Just
                StaffManagementFieldData
                    { managementStaff = staff
                    , managementRosterGroups = rosterGroups
                    , managementAwardLevels = awardLevels
                    , managementAwardLevelBaseRates = awardLevelBaseRates
                    , managementImportedPayItems = importedPayItems
                    , managementSelectedRosterGroupIds = selectedRosterGroupIds
                    , managementVenueMembership = Nothing
                    , managementWeekOffset = Nothing
                    , managementRosterGroupId = Nothing
                    }

profilePreferenceViewData :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe Staff -> IO ([PreferenceWeekday], [ShiftPreferenceSelection])
profilePreferenceViewData maybeStaff = do
    venueConfig <- fetchVenueConfig
    let preferenceWeekdays = allPreferenceWeekdays venueConfig
    selectedShiftPreferences <-
        case maybeStaff of
            Nothing    -> pure []
            Just staff -> fetchStaffShiftPreferenceSelections staff
    pure (preferenceWeekdays, selectedShiftPreferences)

profilePreferenceViewDataWithSubmitted :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Maybe Staff -> [Text] -> IO ([PreferenceWeekday], [ShiftPreferenceSelection])
profilePreferenceViewDataWithSubmitted _maybeStaff submittedShiftPreferenceKeys = do
    venueConfig <- fetchVenueConfig
    let preferenceWeekdays = allPreferenceWeekdays venueConfig
    let selectedShiftPreferences =
            case parseShiftPreferenceSelections preferenceWeekdays submittedShiftPreferenceKeys of
                Right selections -> selections
                Left _           -> []
    pure (preferenceWeekdays, selectedShiftPreferences)

normalizeProfileOpenSection :: Text -> Text
normalizeProfileOpenSection section
    | section `elem` ["profile", "preferences", "security", "leave"] = section
    | otherwise = ""
