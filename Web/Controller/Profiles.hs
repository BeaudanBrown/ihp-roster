module Web.Controller.Profiles where

import Application.Helper.LiveResource (LiveMutationResult (..))
import Application.Helper.LiveSurface (serveTypedLiveFragment)
import Application.Helper.ProfileLeave (buildDefaultLeaveRequest,
                                        fetchCurrentUserLeaveRequests)
import Application.Helper.RosterGroups (fetchCurrentVenueRosterGroups,
                                        fetchStaffRosterGroupIds)
import Application.Helper.StaffShiftPreferences
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
import Web.Profiles.LiveUpdates
import Web.Profiles.Mutations
import Web.Staff.Mutations (updateStaffMember)
import Web.View.Profiles.Edit
import Web.View.StaffProfileForm (StaffManagementFieldData (..))

instance Controller ProfilesController where
    beforeAction = do
        ensureIsUser
        ensureCurrentVenue
        ensureStaffSelfServiceAccess

    action EditProfileAction = do
        maybeExistingStaff <- fetchCurrentUserStaff
        let staff = fromMaybe (buildNewCurrentUserStaff currentUser) maybeExistingStaff
        let currentUserEmail = currentUser.email
        let openSection = normalizeProfileOpenSection (paramOrDefault @Text "" "section")
        (preferenceWeekdays, selectedShiftPreferences) <- profilePreferenceViewData maybeExistingStaff
        passkeys <- fetchCurrentUserPasskeys
        leaveRequests <- fetchCurrentUserLeaveRequests
        leaveRequestForm <- buildDefaultLeaveRequest
        staffRsaDocument <- maybe (pure Nothing) latestRsaDocumentForStaff maybeExistingStaff
        staffManagementFields <- fetchProfileStaffManagementFields maybeExistingStaff Nothing
        now <- getCurrentTime
        let today = utctDay now
        render EditView { .. }

    action ShowProfileLeaveRequestsContentFragmentAction = do
        maybeExistingStaff <- fetchCurrentUserStaff
        case maybeExistingStaff of
            Nothing -> accessDeniedUnless False
            Just staff ->
                serveTypedLiveFragment profileLeaveRequestsLiveSurfaceDefinition (currentProfileLeaveSurfaceKey staff) profileLeaveRequestsFragment \_ -> do
                    leaveRequests <- fetchCurrentUserLeaveRequests
                    leaveRequestForm <- buildDefaultLeaveRequest
                    respondHtml (renderProfileLeaveRequestsContentFragment staff leaveRequestForm leaveRequests)

    action ShowProfileContentFragmentAction = do
        let openSection = normalizeProfileOpenSection (paramOrDefault @Text "" "section")
        fetchCurrentUserStaff >>= \case
            Nothing -> accessDeniedUnless False
            Just staff ->
                serveTypedLiveFragment profileContentLiveSurfaceDefinition (currentProfileContentSurfaceKey staff openSection) (profileContentFragment openSection) \_ -> do
                    let currentUserEmail = currentUser.email
                    (preferenceWeekdays, selectedShiftPreferences) <- profilePreferenceViewData (Just staff)
                    passkeys <- fetchCurrentUserPasskeys
                    leaveRequests <- fetchCurrentUserLeaveRequests
                    leaveRequestForm <- buildDefaultLeaveRequest
                    staffRsaDocument <- latestRsaDocumentForStaff staff
                    staffManagementFields <- fetchProfileStaffManagementFields (Just staff) Nothing
                    now <- getCurrentTime
                    let today = utctDay now
                    respondHtml (renderProfileContentFragmentWithManagement staff currentUserEmail preferenceWeekdays selectedShiftPreferences passkeys leaveRequests leaveRequestForm staffRsaDocument staffManagementFields today now openSection)

    action UpdateProfileAction = do
        maybeExistingStaff <- fetchCurrentUserStaff
        let submittedShiftPreferenceKeys = nub (paramTexts "shiftPreferenceKeys")
        let staff = fromMaybe (buildNewCurrentUserStaff currentUser) maybeExistingStaff
        let currentUserEmail = currentUser.email
        let openSection = normalizeProfileOpenSection (paramOrDefault @Text "" "section")
        passkeys <- fetchCurrentUserPasskeys
        staffRsaDocument <- maybe (pure Nothing) latestRsaDocumentForStaff maybeExistingStaff
        let submittedRosterGroupIds = nub (mapMaybe parseRosterGroupIdText (paramTexts "rosterGroupIds"))
        staffManagementFields <- fetchProfileStaffManagementFields maybeExistingStaff (Just submittedRosterGroupIds)
        now <- getCurrentTime
        let today = utctDay now
        (preferenceWeekdays, selectedShiftPreferences) <-
            profilePreferenceViewDataWithSubmitted maybeExistingStaff submittedShiftPreferenceKeys
        leaveRequests <- fetchCurrentUserLeaveRequests
        leaveRequestForm <- buildDefaultLeaveRequest
        let canManageProfileStaff = hasRole VenueAdminRole && isJust maybeExistingStaff
        maybeSelectedRosterGroupIds <- if canManageProfileStaff then parseStaffRosterGroupIds else pure Nothing
        maybeSubmittedPayRateSelection <- if canManageProfileStaff then parseSubmittedPayRateSelection "payRateSelection" else pure (Just emptyStaffPayRateSelection)
        let maybeSubmittedDefaultAwardLevelId = submittedAwardLevelId <$> maybeSubmittedPayRateSelection
        let maybeSubmittedImportedXeroPayItemId = submittedImportedXeroPayItemId <$> maybeSubmittedPayRateSelection
        let buildProfileStaff currentStaff
                | canManageProfileStaff = buildStaff True maybeSubmittedDefaultAwardLevelId maybeSubmittedImportedXeroPayItemId currentStaff
                | otherwise =
                    currentStaff
                        |> requireParam #firstName "firstName" "First name is required"
                        |> requireParam #lastName "lastName" "Last name is required"
                        |> requireParam #phone "phone" "Phone is required"
                        |> requireParam #emergencyContactName "emergencyContactName" "Emergency contact name is required"
                        |> requireParam #emergencyContactPhone "emergencyContactPhone" "Emergency contact phone is required"
                        |> requireParam #idealShiftsPerWeek "idealShiftsPerWeek" "Ideal shifts per week is required"
                        |> fill @'["firstName", "lastName", "preferredName", "phone", "emergencyContactName", "emergencyContactPhone", "idealShiftsPerWeek"]
                        |> normalizeMaybeTextField #preferredName
                        |> requiredBoundedTextField #firstName 80
                        |> requiredBoundedTextField #lastName 80
                        |> validateField #preferredName (validateMaybe (boundedText 80))
                        |> requiredBoundedTextField #phone 80
                        |> requiredBoundedTextField #emergencyContactName 120
                        |> requiredBoundedTextField #emergencyContactPhone 80
                        |> validateField #idealShiftsPerWeek (isInRange (0, 7))
        staff
            |> buildProfileStaff
            |> ifValid \case
                Left staff -> do
                    if isHtmxRequest
                        then respondHtml (renderProfileContentFragmentWithManagement staff currentUserEmail preferenceWeekdays selectedShiftPreferences passkeys leaveRequests leaveRequestForm staffRsaDocument staffManagementFields today now openSection)
                        else render EditView { .. }
                Right staff -> do
                    case parseShiftPreferenceSelections preferenceWeekdays submittedShiftPreferenceKeys of
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
                                then respondHtml (renderProfileContentFragmentWithManagement staff currentUserEmail preferenceWeekdays selectedShiftPreferences passkeys leaveRequests leaveRequestForm staffRsaDocument staffManagementFields today now openSection)
                                else render EditView { .. }
                        Right submittedSelections -> do
                            if canManageProfileStaff
                                then case (maybeExistingStaff, maybeSelectedRosterGroupIds, maybeSubmittedDefaultAwardLevelId, maybeSubmittedImportedXeroPayItemId) of
                                    (Just originalStaff, Just selectedRosterGroupIds, Just _, Just _) -> do
                                        mutationResult <- updateStaffMember originalStaff staff selectedRosterGroupIds submittedSelections
                                        let updatedStaff = mutationResult.liveMutationValue
                                        updatedManagementFields <- fetchProfileStaffManagementFields (Just updatedStaff) (Just selectedRosterGroupIds)
                                        if isHtmxRequest
                                            then
                                                respondHtml $
                                                    mconcat
                                                        [ renderProfileContentFragmentWithManagement updatedStaff currentUserEmail preferenceWeekdays submittedSelections passkeys leaveRequests leaveRequestForm staffRsaDocument updatedManagementFields today now openSection
                                                        , renderToastOob ToastBottomCenter (successToast "Profile updated")
                                                        ]
                                            else do
                                                setSuccessMessage "Profile updated"
                                                redirectTo EditProfileAction
                                    _ ->
                                        if isHtmxRequest
                                            then respondHtml (renderProfileContentFragmentWithManagement staff currentUserEmail preferenceWeekdays selectedShiftPreferences passkeys leaveRequests leaveRequestForm staffRsaDocument staffManagementFields today now openSection)
                                            else render EditView { .. }
                                else do
                                    mutationResult <- updateCurrentUserProfile openSection staff submittedSelections
                                    let profileUpdate = mutationResult.liveMutationValue
                                    let updatedStaff = profileUpdate.profileUpdatedStaff
                                    if not profileUpdate.profileWasCompletedBefore && profileUpdate.profileIsCompletedNow
                                        then redirectTo RosterWeeksAction
                                        else if isHtmxRequest
                                            then
                                                respondHtml $
                                                    mconcat
                                                        [ renderProfileContentFragmentWithManagement updatedStaff currentUserEmail preferenceWeekdays submittedSelections passkeys leaveRequests leaveRequestForm staffRsaDocument staffManagementFields today now openSection
                                                        , renderToastOob ToastBottomCenter (successToast "Profile updated")
                                                        ]
                                            else do
                                                setSuccessMessage "Profile updated"
                                                redirectTo EditProfileAction

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
    | section `elem` ["profile", "security", "leave", "rsa"] = section
    | otherwise = ""
