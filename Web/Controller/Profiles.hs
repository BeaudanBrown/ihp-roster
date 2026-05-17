module Web.Controller.Profiles where

import Application.Helper.LiveSurface (ensureTypedLiveSurfaceAuthorized)
import Application.Helper.ProfileLeave (buildDefaultLeaveRequest,
                                        fetchCurrentUserLeaveRequests)
import Application.Helper.StaffShiftPreferences
import Application.Helper.View (ToastOverlayPosition (ToastBottomCenter),
                                renderToastOob, successToast)
import Application.StaffDocuments.Rsa (latestRsaDocumentForStaff)
import Data.Time.Clock (getCurrentTime, utctDay)
import Web.Controller.Prelude
import Web.Profiles.LiveUpdates
import Web.Profiles.Mutations
import Web.View.Profiles.Edit

instance Controller ProfilesController where
    beforeAction = do
        ensureIsUser
        ensureCurrentVenue
        ensureStaffSelfServiceAccess

    action EditProfileAction = do
        maybeExistingStaff <- fetchCurrentUserStaff
        let staff = fromMaybe (buildNewCurrentUserStaff currentUser) maybeExistingStaff
        let currentUserEmail = currentUser.email
        let openSection = normalizeProfileOpenSection (paramOrDefault @Text "profile" "section")
        (preferenceWeekdays, selectedShiftPreferences) <- profilePreferenceViewData maybeExistingStaff
        passkeys <- fetchCurrentUserPasskeys
        leaveRequests <- fetchCurrentUserLeaveRequests
        leaveRequestForm <- buildDefaultLeaveRequest
        staffRsaDocument <- maybe (pure Nothing) latestRsaDocumentForStaff maybeExistingStaff
        today <- utctDay <$> getCurrentTime
        render EditView { .. }

    action ShowProfileLeaveRequestsContentFragmentAction = do
        ensureTypedLiveSurfaceAuthorized profileLeaveRequestsLiveSurfaceDefinition currentProfileLeaveSurfaceKey
        leaveRequests <- fetchCurrentUserLeaveRequests
        leaveRequestForm <- buildDefaultLeaveRequest
        respondHtml (renderProfileLeaveRequestsContentFragment leaveRequestForm leaveRequests)

    action ShowProfileContentFragmentAction = do
        let openSection = normalizeProfileOpenSection (paramOrDefault @Text "profile" "section")
        ensureTypedLiveSurfaceAuthorized profileContentLiveSurfaceDefinition (currentProfileContentSurfaceKey openSection)
        maybeExistingStaff <- fetchCurrentUserStaff
        let staff = fromMaybe (buildNewCurrentUserStaff currentUser) maybeExistingStaff
        let currentUserEmail = currentUser.email
        (preferenceWeekdays, selectedShiftPreferences) <- profilePreferenceViewData maybeExistingStaff
        passkeys <- fetchCurrentUserPasskeys
        leaveRequests <- fetchCurrentUserLeaveRequests
        leaveRequestForm <- buildDefaultLeaveRequest
        staffRsaDocument <- maybe (pure Nothing) latestRsaDocumentForStaff maybeExistingStaff
        today <- utctDay <$> getCurrentTime
        respondHtml (renderProfileContentFragment staff currentUserEmail preferenceWeekdays selectedShiftPreferences passkeys leaveRequests leaveRequestForm staffRsaDocument today openSection)

    action UpdateProfileAction = do
        maybeExistingStaff <- fetchCurrentUserStaff
        let submittedShiftPreferenceKeys = nub (paramTexts "shiftPreferenceKeys")
        let staff = fromMaybe (buildNewCurrentUserStaff currentUser) maybeExistingStaff
        let currentUserEmail = currentUser.email
        let openSection = normalizeProfileOpenSection (paramOrDefault @Text "profile" "section")
        passkeys <- fetchCurrentUserPasskeys
        staffRsaDocument <- maybe (pure Nothing) latestRsaDocumentForStaff maybeExistingStaff
        today <- utctDay <$> getCurrentTime
        (preferenceWeekdays, selectedShiftPreferences) <-
            profilePreferenceViewDataWithSubmitted maybeExistingStaff submittedShiftPreferenceKeys
        leaveRequests <- fetchCurrentUserLeaveRequests
        leaveRequestForm <- buildDefaultLeaveRequest
        staff
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
            |> ifValid \case
                Left staff -> do
                    if isHtmxRequest
                        then respondHtml (renderProfileContentFragment staff currentUserEmail preferenceWeekdays selectedShiftPreferences passkeys leaveRequests leaveRequestForm staffRsaDocument today openSection)
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
                                then respondHtml (renderProfileContentFragment staff currentUserEmail preferenceWeekdays selectedShiftPreferences passkeys leaveRequests leaveRequestForm staffRsaDocument today openSection)
                                else render EditView { .. }
                        Right submittedSelections -> do
                            mutationResult <- updateCurrentUserProfile openSection staff submittedSelections
                            let updatedStaff = mutationResult.profileUpdatedStaff
                            if not mutationResult.profileWasCompletedBefore && mutationResult.profileIsCompletedNow
                                then redirectTo RosterWeeksAction
                                else if isHtmxRequest
                                    then
                                        respondHtml $
                                            mconcat
                                                [ renderProfileContentFragment updatedStaff currentUserEmail preferenceWeekdays submittedSelections passkeys leaveRequests leaveRequestForm staffRsaDocument today openSection
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
    | section == "leave" = "leave"
    | section == "rsa" = "rsa"
    | section == "security" = "security"
    | otherwise = "profile"
