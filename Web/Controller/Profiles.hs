module Web.Controller.Profiles where

import Application.Helper.FrontendContract.Surface.Request (attachSurfaceRequestFieldErrors,
                                                            surfaceRequestFieldErrorsMessage)
import Application.Helper.LiveUpdate (setActorLiveResourcesRefresh)
import Application.Helper.ProfileLeave (buildDefaultLeaveRequest,
                                        fetchCurrentUserLeaveRequests)
import Application.Helper.Profiling (profileActionSpan)
import Application.Helper.RosterGroups (fetchCurrentVenueRosterGroups,
                                        fetchStaffRosterGroupIds)
import Application.Helper.StaffShiftPreferences
import Application.Helper.SurfaceResource (LiveMutationResult (..))
import Application.Helper.View (ToastOverlayPosition (ToastBottomCenter),
                                renderToastOob, successToast)
import Data.Time.Clock (getCurrentTime)
import Web.Controller.Admin.Support (SubmittedPayRateSelection (..),
                                     fetchActiveImportedXeroPayItems,
                                     parseSubmittedPayRateSelectionValue)
import Web.Controller.Prelude
import Web.Controller.Staff (buildStaffFromSurfaceSubmission,
                             emptyStaffPayRateSelection,
                             fetchAwardLevelBaseRatesForStaffForm,
                             fetchAwardLevelsForStaffForm,
                             validateSubmittedRosterGroupIds)
import Web.Profiles.FrontendSurface (ProfileScopeValue (..),
                                     profileCandidateMountedFragments,
                                     profileSurfaceScope)
import Web.Profiles.Mutations
import Web.Staff.Mutations (updateStaffMember)
import Web.Staff.ProfileSurfaceRequest (StaffProfileDetailsSubmission (..),
                                        StaffProfileSurfaceSubmission (..),
                                        StaffShiftPreferencesSubmission (..),
                                        parseProfileSurfaceSubmission)
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
            staffManagementFields <- profileActionSpan "profile.page.fetch_management_fields" (fetchProfileStaffManagementFields maybeExistingStaff Nothing)
            now <- getCurrentTime
            profileActionSpan "profile.page.render_response" (render EditView { .. })

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
                    staffManagementFields <- profileActionSpan "profile.content_fragment.fetch_management_fields" (fetchProfileStaffManagementFields (Just staff) Nothing)
                    now <- getCurrentTime
                    profileActionSpan "profile.content_fragment.render_response" (respondHtml (renderProfileSectionFragmentWithManagement staff currentUserEmail preferenceWeekdays selectedShiftPreferences passkeys leaveRequests leaveRequestForm staffManagementFields now openSection))

    action currentAction@UpdateProfileAction = runBepis currentAction BepisMutationAction do
        maybeExistingStaff <- fetchCurrentUserStaff
        let submissionResult = parseProfileSurfaceSubmission
        let staff = fromMaybe (buildNewCurrentUserStaff currentUser) maybeExistingStaff
        let currentUserEmail = currentUser.email
        let openSection =
                case submissionResult of
                    Right (SubmittedStaffShiftPreferences _) -> "preferences"
                    Right (SubmittedStaffProfileDetails submitted) -> normalizeProfileOpenSection submitted.submittedProfileSection
                    Left _ -> "profile"
        passkeys <- fetchCurrentUserPasskeys
        let submittedRosterGroupIds =
                case submissionResult of
                    Right (SubmittedStaffProfileDetails submitted) -> map Id (fromMaybe [] submitted.submittedRosterGroupIds)
                    _ -> []
        staffManagementFields <- fetchProfileStaffManagementFields maybeExistingStaff (case submissionResult of Right SubmittedStaffProfileDetails {} -> Just submittedRosterGroupIds; _ -> Nothing)
        now <- getCurrentTime
        (preferenceWeekdays, selectedShiftPreferences) <-
            case submissionResult of
                Right (SubmittedStaffShiftPreferences submitted) -> profilePreferenceViewDataWithSubmitted maybeExistingStaff submitted.submittedShiftPreferenceKeys
                _ -> profilePreferenceViewData maybeExistingStaff
        leaveRequests <- fetchCurrentUserLeaveRequests
        leaveRequestForm <- buildDefaultLeaveRequest
        let renderProfileResponse renderedStaff renderedPreferences =
                if isHtmxRequest
                    then respondHtml (renderProfileSectionFragmentWithManagement renderedStaff currentUserEmail preferenceWeekdays renderedPreferences passkeys leaveRequests leaveRequestForm staffManagementFields now openSection)
                    else do
                        let staff = renderedStaff
                        let selectedShiftPreferences = renderedPreferences
                        render EditView { .. }
        let finishCurrentUserUpdate section validStaff submittedSelections successMessage =
                updateCurrentUserProfile section validStaff submittedSelections >>= \case
                    Nothing -> do
                        setErrorMessage "Your staff access for this venue is no longer active."
                        renderProfileResponse validStaff selectedShiftPreferences
                    Just mutationResult -> do
                        let profileUpdate = mutationResult.liveMutationValue
                        let updatedStaff = profileUpdate.profileUpdatedStaff
                        if section /= "preferences" && not profileUpdate.profileWasCompletedBefore && profileUpdate.profileIsCompletedNow
                            then redirectTo RosterWeeksAction
                            else if isHtmxRequest
                                then respondWithProfileActorInvalidation updatedStaff mutationResult successMessage
                                else do
                                    setSuccessMessage successMessage
                                    redirectTo EditProfileAction
        case submissionResult of
            Left errors -> do
                setErrorMessage (surfaceRequestFieldErrorsMessage errors)
                renderProfileResponse (attachSurfaceRequestFieldErrors errors staff) selectedShiftPreferences
            Right (SubmittedStaffShiftPreferences submitted) ->
                if isNothing maybeExistingStaff
                    then do
                        setErrorMessage "Save your profile details before setting shift preferences."
                        renderProfileResponse staff selectedShiftPreferences
                    else case parseShiftPreferenceSelections preferenceWeekdays submitted.submittedShiftPreferenceKeys of
                        Left preferenceError -> do
                            setErrorMessage preferenceError
                            renderProfileResponse staff selectedShiftPreferences
                        Right submittedSelections ->
                            finishCurrentUserUpdate "preferences" staff submittedSelections "Shift preferences updated"
            Right (SubmittedStaffProfileDetails submitted)
                | submitted.submittedProfileSection /= "profile" -> do
                    setErrorMessage "Choose a valid profile section."
                    renderProfileResponse staff selectedShiftPreferences
                | otherwise -> do
                    let canManageProfileStaff = hasRole VenueAdmin && isJust maybeExistingStaff
                    maybeSelectedRosterGroupIds <- if canManageProfileStaff then validateSubmittedRosterGroupIds submitted.submittedRosterGroupIds else pure Nothing
                    maybeSubmittedPayRateSelection <- if canManageProfileStaff then parseSubmittedPayRateSelectionValue (fromMaybe "" submitted.submittedPayRateSelection) else pure (Just emptyStaffPayRateSelection)
                    let maybeSubmittedDefaultAwardLevelId = submittedAwardLevelId <$> maybeSubmittedPayRateSelection
                    let maybeSubmittedImportedXeroPayItemId = submittedImportedXeroPayItemId <$> maybeSubmittedPayRateSelection
                    staff
                        |> buildStaffFromSurfaceSubmission canManageProfileStaff maybeSubmittedDefaultAwardLevelId maybeSubmittedImportedXeroPayItemId submitted
                        |> ifValid \case
                            Left invalidStaff -> renderProfileResponse invalidStaff selectedShiftPreferences
                            Right validStaff ->
                                if canManageProfileStaff
                                    then case (maybeExistingStaff, maybeSelectedRosterGroupIds, maybeSubmittedDefaultAwardLevelId, maybeSubmittedImportedXeroPayItemId) of
                                        (Just originalStaff, Just selectedRosterGroupIds, Just _, Just _) -> do
                                            updateStaffMember originalStaff validStaff selectedRosterGroupIds selectedShiftPreferences Nothing Nothing >>= \case
                                                Nothing -> do
                                                    setErrorMessage "This staff member is no longer active."
                                                    renderProfileResponse originalStaff selectedShiftPreferences
                                                Just mutationResult -> do
                                                    let updatedStaff = mutationResult.liveMutationValue
                                                    if isHtmxRequest
                                                        then respondWithProfileActorInvalidation updatedStaff mutationResult "Profile updated"
                                                        else do
                                                            setSuccessMessage "Profile updated"
                                                            redirectTo EditProfileAction
                                        _ -> renderProfileResponse validStaff selectedShiftPreferences
                                    else finishCurrentUserUpdate "profile" validStaff selectedShiftPreferences "Profile updated"

respondWithProfileActorInvalidation :: (?context :: ControllerContext, ?request :: Request) => Staff -> LiveMutationResult value -> Text -> IO ()
respondWithProfileActorInvalidation staff mutationResult successMessage = do
    let scope = ProfileScopeValue (unpackId currentVenueId) (unpackId staff.id)
    setHeader ("HX-Reswap", "none")
    setActorLiveResourcesRefresh (profileSurfaceScope scope) mutationResult.liveMutationTouchedResources (profileCandidateMountedFragments scope)
    respondHtml (renderToastOob ToastBottomCenter (successToast successMessage))

buildNewCurrentUserStaff :: (?context :: ControllerContext) => User -> Staff
buildNewCurrentUserStaff user =
    newRecord @Staff
        |> set #venueId (unpackId currentVenueId)
        |> set #userId (Just (unpackId (get #id user)))

fetchProfileStaffManagementFields :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe Staff -> Maybe [Id RosterGroup] -> IO (Maybe StaffManagementFieldData)
fetchProfileStaffManagementFields Nothing _ = pure Nothing
fetchProfileStaffManagementFields (Just staff) maybeSubmittedRosterGroupIds
    | not (hasRole VenueAdmin) = pure Nothing
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
