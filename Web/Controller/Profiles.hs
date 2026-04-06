module Web.Controller.Profiles where

import Application.Helper.StaffShiftPreferences
import Web.Controller.Prelude
import Web.View.Profiles.Edit

instance Controller ProfilesController where
    beforeAction = do
        ensureIsUser
        ensureCurrentVenue

    action EditProfileAction = do
        maybeExistingStaff <- fetchCurrentUserStaff
        staff <- pure (fromMaybe (buildNewCurrentUserStaff currentUser) maybeExistingStaff)
        let currentUserEmail = currentUser.email
        (preferenceWeekdays, preferenceSections, selectedShiftPreferenceKeys) <- profilePreferenceViewData maybeExistingStaff
        render EditView { .. }

    action UpdateProfileAction = do
        maybeExistingStaff <- fetchCurrentUserStaff
        let submittedShiftPreferenceKeys = nub (paramList @Text "shiftPreferenceKeys")
        staff <- pure (fromMaybe (buildNewCurrentUserStaff currentUser) maybeExistingStaff)
        let currentUserEmail = currentUser.email
        (preferenceWeekdays, preferenceSections, selectedShiftPreferenceKeys) <-
            profilePreferenceViewDataWithSubmitted maybeExistingStaff submittedShiftPreferenceKeys
        staff
            |> fill @'["firstName", "lastName", "preferredName", "phone", "emergencyContactName", "emergencyContactPhone", "idealShiftsPerWeek"]
            |> validateField #firstName nonEmpty
            |> validateField #lastName nonEmpty
            |> validateField #phone nonEmpty
            |> validateField #emergencyContactName nonEmpty
            |> validateField #emergencyContactPhone nonEmpty
            |> validateField #idealShiftsPerWeek (isInRange (0, 7))
            |> ifValid \case
                Left staff -> do
                    render EditView { .. }
                Right staff -> do
                    staff <- upsertCurrentUserStaff staff
                    case parseShiftPreferenceSelections preferenceSections preferenceWeekdays submittedShiftPreferenceKeys of
                        Left preferenceError -> do
                            setErrorMessage preferenceError
                            let selectedShiftPreferenceKeys = submittedShiftPreferenceKeys
                            let currentUserEmail = currentUser.email
                            let preferenceWeekdays = allPreferenceWeekdays
                            preferenceSections <- fetchStaffPreferenceGroupSections staff
                            render EditView { .. }
                        Right submittedSelections -> do
                            rosterGroupIds <- map (.rosterGroup.id) <$> fetchStaffPreferenceGroupSections staff
                            replaceStaffShiftPreferences staff rosterGroupIds submittedSelections
                            let isProfileCompleted = requiredProfileFieldsCompleted staff
                            let wasProfileCompleted = currentUser.isProfileCompleted
                            currentUser
                                |> set #isProfileCompleted isProfileCompleted
                                |> updateRecord
                            setSuccessMessage "Profile updated"
                            if not wasProfileCompleted && isProfileCompleted
                                then redirectTo RosterWeeksAction
                                else redirectTo EditProfileAction

buildNewCurrentUserStaff :: (?context :: ControllerContext) => User -> Staff
buildNewCurrentUserStaff user =
    newRecord @Staff
        |> set #venueId (unpackId currentVenueId)
        |> set #userId (Just (unpackId (get #id user)))

upsertCurrentUserStaff :: (?modelContext :: ModelContext, ?context :: ControllerContext) => Staff -> IO Staff
upsertCurrentUserStaff staff = do
    existingStaff <- fetchCurrentUserStaff

    case existingStaff of
        Just existing ->
            existing
                |> set #firstName staff.firstName
                |> set #lastName staff.lastName
                |> set #preferredName staff.preferredName
                |> set #phone staff.phone
                |> set #emergencyContactName staff.emergencyContactName
                |> set #emergencyContactPhone staff.emergencyContactPhone
                |> set #idealShiftsPerWeek staff.idealShiftsPerWeek
                |> updateRecord
        Nothing ->
            do
                createdStaff <-
                    staff
                        |> set #venueId (unpackId currentVenueId)
                        |> set #userId (Just (unpackId (get #id currentUser)))
                        |> createRecord
                _ <- fetchStaffPreferenceGroupSections createdStaff
                pure createdStaff

profilePreferenceViewData :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe Staff -> IO ([PreferenceWeekday], [StaffPreferenceGroupSection], [Text])
profilePreferenceViewData maybeStaff =
    case maybeStaff of
        Nothing -> pure ([], [], [])
        Just staff -> do
            let preferenceWeekdays = allPreferenceWeekdays
            preferenceSections <- fetchStaffPreferenceGroupSections staff
            selectedShiftPreferenceKeys <- fetchStaffShiftPreferenceKeyTexts staff (map (.rosterGroup.id) preferenceSections)
            pure (preferenceWeekdays, preferenceSections, selectedShiftPreferenceKeys)

profilePreferenceViewDataWithSubmitted :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe Staff -> [Text] -> IO ([PreferenceWeekday], [StaffPreferenceGroupSection], [Text])
profilePreferenceViewDataWithSubmitted maybeStaff submittedShiftPreferenceKeys =
    case maybeStaff of
        Nothing -> pure ([], [], submittedShiftPreferenceKeys)
        Just staff -> do
            let preferenceWeekdays = allPreferenceWeekdays
            preferenceSections <- fetchStaffPreferenceGroupSections staff
            pure (preferenceWeekdays, preferenceSections, submittedShiftPreferenceKeys)
