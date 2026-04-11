module Web.Controller.Profiles where

import Application.Helper.LiveUpdate (LiveFragmentRef)
import Application.Helper.RosterGroups (fetchStaffRosterGroupIds)
import Application.Helper.StaffShiftPreferences
import Application.Helper.View (ToastOverlayConfig (..),
                                ToastOverlayPosition (ToastBottomCenter),
                                renderToastOverlayHostOob)
import qualified Data.Map.Strict as Map
import Data.Time.Calendar (addDays)
import Data.Time.Clock (utctDay)
import qualified Data.UUID as UUID
import Web.Controller.Prelude
import Web.Controller.RosterWeeks (broadcastRosterWeekInvalidation)
import Web.RosterWeeks.Projection (buildRosterRowFragmentRefs,
                                   buildRosterStaffPanelFragmentRef)
import Web.View.Profiles.Edit

instance Controller ProfilesController where
    beforeAction = do
        ensureIsUser
        ensureCurrentVenue

    action EditProfileAction = do
        maybeExistingStaff <- fetchCurrentUserStaff
        staff <- pure (fromMaybe (buildNewCurrentUserStaff currentUser) maybeExistingStaff)
        let currentUserEmail = currentUser.email
        let openSection = normalizeProfileOpenSection (paramOrDefault @Text "section" "profile")
        (preferenceWeekdays, preferenceSections, selectedShiftPreferenceKeys) <- profilePreferenceViewData maybeExistingStaff
        leaveRequests <- fetchCurrentUserLeaveRequests
        leaveRequestForm <- buildDefaultLeaveRequest
        render EditView { .. }

    action UpdateProfileAction = do
        maybeExistingStaff <- fetchCurrentUserStaff
        let submittedShiftPreferenceKeys = nub (paramList @Text "shiftPreferenceKeys")
        staff <- pure (fromMaybe (buildNewCurrentUserStaff currentUser) maybeExistingStaff)
        let currentUserEmail = currentUser.email
        let openSection = normalizeProfileOpenSection (paramOrDefault @Text "section" "profile")
        (preferenceWeekdays, preferenceSections, selectedShiftPreferenceKeys) <-
            profilePreferenceViewDataWithSubmitted maybeExistingStaff submittedShiftPreferenceKeys
        leaveRequests <- fetchCurrentUserLeaveRequests
        leaveRequestForm <- buildDefaultLeaveRequest
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
                    if isHtmxRequest
                        then respondHtml (renderProfileContentFragment staff currentUserEmail preferenceWeekdays preferenceSections selectedShiftPreferenceKeys leaveRequests leaveRequestForm openSection)
                        else render EditView { .. }
                Right staff -> do
                    staff <- upsertCurrentUserStaff staff
                    case parseShiftPreferenceSelections preferenceSections preferenceWeekdays submittedShiftPreferenceKeys of
                        Left preferenceError -> do
                            setErrorMessage preferenceError
                            let selectedShiftPreferenceKeys = submittedShiftPreferenceKeys
                            let currentUserEmail = currentUser.email
                            let preferenceWeekdays = allPreferenceWeekdays
                            preferenceSections <- fetchStaffPreferenceGroupSections staff
                            leaveRequests <- fetchCurrentUserLeaveRequests
                            leaveRequestForm <- buildDefaultLeaveRequest
                            if isHtmxRequest
                                then respondHtml (renderProfileContentFragment staff currentUserEmail preferenceWeekdays preferenceSections selectedShiftPreferenceKeys leaveRequests leaveRequestForm openSection)
                                else render EditView { .. }
                        Right submittedSelections -> do
                            rosterGroupIds <- map (.rosterGroup.id) <$> fetchStaffPreferenceGroupSections staff
                            replaceStaffShiftPreferences staff rosterGroupIds submittedSelections
                            invalidationTargets <- fetchProfileRosterInvalidationTargets currentVenueId staff
                            let invalidations = buildProfileRosterInvalidations invalidationTargets
                            forM_ invalidations \(rosterGroupId, weekOffset, fragments) ->
                                broadcastRosterWeekInvalidation rosterGroupId weekOffset fragments
                            let isProfileCompleted = requiredProfileFieldsCompleted staff
                            let wasProfileCompleted = currentUser.isProfileCompleted
                            currentUser
                                |> set #isProfileCompleted isProfileCompleted
                                |> updateRecord
                            if not wasProfileCompleted && isProfileCompleted
                                then redirectTo RosterWeeksAction
                                else if isHtmxRequest
                                    then
                                        respondHtml $
                                            mconcat
                                                [ renderProfileContentFragment staff currentUserEmail preferenceWeekdays preferenceSections selectedShiftPreferenceKeys leaveRequests leaveRequestForm openSection
                                                , renderToastOverlayHostOob ToastBottomCenter
                                                    [ ToastOverlayConfig
                                                        { toastOverlayTitle = Just "Success"
                                                        , toastOverlayMessage = "Profile updated"
                                                        , toastOverlayClass = "app-toast-success"
                                                        , toastOverlayAutoHideMs = 3200
                                                        }
                                                    ]
                                                ]
                                    else do
                                        setSuccessMessage "Profile updated"
                                        redirectTo EditProfileAction

buildNewCurrentUserStaff :: (?context :: ControllerContext) => User -> Staff
buildNewCurrentUserStaff user =
    newRecord @Staff
        |> set #venueId (unpackId currentVenueId)
        |> set #userId (Just (unpackId (get #id user)))

upsertCurrentUserStaff :: (?modelContext :: ModelContext, ?context :: ControllerContext, ?request :: Request) => Staff -> IO Staff
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

fetchCurrentUserLeaveRequests :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [LeaveRequest]
fetchCurrentUserLeaveRequests = do
    maybeStaff <- fetchCurrentUserStaff
    case maybeStaff of
        Nothing -> pure []
        Just staff ->
            query @LeaveRequest
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhere (#staffId, unpackId staff.id)
                |> orderByDesc #startDate
                |> fetch

buildDefaultLeaveRequest :: (?context :: ControllerContext) => IO LeaveRequest
buildDefaultLeaveRequest = do
    today <- utctDay <$> getCurrentTime
    pure $
        newRecord @LeaveRequest
            |> set #startDate today
            |> set #endDate (addDays 1 today)

normalizeProfileOpenSection :: Text -> Text
normalizeProfileOpenSection section
    | section == "leave" = "leave"
    | otherwise = "profile"

fetchProfileRosterInvalidationTargets :: (?modelContext :: ModelContext) => Id Venue -> Staff -> IO [(Id RosterGroup, Int, [(UUID.UUID, Int)])]
fetchProfileRosterInvalidationTargets venueId staff = do
    rosterGroupIds <- fetchStaffRosterGroupIds staff
    if null rosterGroupIds
        then pure []
        else do
            rosterWeeks <-
                query @RosterWeek
                    |> filterWhere (#venueId, unpackId venueId)
                    |> filterWhereIn (#rosterGroupId, map unpackId rosterGroupIds)
                    |> fetch
            rosterDays <-
                if null rosterWeeks
                    then pure []
                    else query @RosterDay
                        |> filterWhereIn (#rosterWeekId, map (unpackId . (.id)) rosterWeeks)
                        |> fetch
            assignedSlots <-
                if null rosterDays
                    then pure []
                    else query @RosterSlot
                        |> filterWhere (#staffId, Just (unpackId staff.id))
                        |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) rosterDays)
                        |> fetch

            let rosterWeekById = Map.fromList (map (\rosterWeek -> (unpackId rosterWeek.id, rosterWeek)) rosterWeeks)
            let rosterDayById = Map.fromList (map (\rosterDay -> (unpackId rosterDay.id, rosterDay)) rosterDays)
            let assignedRowKeysByWeek =
                    Map.fromListWith (<>)
                        [ ((Id rosterWeek.rosterGroupId :: Id RosterGroup, rosterWeek.weekOffset), [(rosterSlot.rosterDayId, rosterSlot.rowIndex)])
                        | rosterSlot <- assignedSlots
                        , Just rosterDay <- [Map.lookup rosterSlot.rosterDayId rosterDayById]
                        , Just rosterWeek <- [Map.lookup rosterDay.rosterWeekId rosterWeekById]
                        ]

            pure
                [ let rosterGroupId = Id rosterWeek.rosterGroupId :: Id RosterGroup
                   in ( rosterGroupId
                      , rosterWeek.weekOffset
                      , Map.findWithDefault [] (rosterGroupId, rosterWeek.weekOffset) assignedRowKeysByWeek
                      )
                | rosterWeek <- rosterWeeks
                ]

buildProfileRosterInvalidations :: (?context :: ControllerContext) => [(Id RosterGroup, Int, [(UUID.UUID, Int)])] -> [(Id RosterGroup, Int, [LiveFragmentRef])]
buildProfileRosterInvalidations =
    map \(rosterGroupId, weekOffset, rowKeys) ->
        ( rosterGroupId
        , weekOffset
        , buildRosterRowFragmentRefs rosterGroupId weekOffset rowKeys
            <> [buildRosterStaffPanelFragmentRef rosterGroupId weekOffset]
        )
