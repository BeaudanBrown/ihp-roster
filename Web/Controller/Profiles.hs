module Web.Controller.Profiles where

import Application.Helper.LiveUpdate (LiveFragmentRef, activeRosterWeekScopes)
import Application.Helper.ProfileLeave (buildDefaultLeaveRequest,
                                        fetchCurrentUserLeaveRequests)
import Application.Helper.RosterGroups (fetchCurrentVenueDefaultRosterGroup,
                                        fetchStaffRosterGroupIds,
                                        syncStaffRosterGroupAssignments)
import Application.Helper.StaffShiftPreferences
import Application.Helper.View (ToastOverlayPosition (ToastBottomCenter),
                                renderToastOob, successToast)
import Application.StaffDocuments.Rsa (latestRsaDocumentForStaff)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Time.Clock (getCurrentTime, utctDay)
import qualified Data.UUID as UUID
import Web.Controller.Prelude
import Web.RosterWeeks.LiveUpdates (broadcastRosterWeekInvalidation)
import Web.RosterWeeks.Projection (buildDeferredRosterContentFragmentRef)
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
        leaveRequests <- fetchCurrentUserLeaveRequests
        leaveRequestForm <- buildDefaultLeaveRequest
        respondHtml (renderProfileLeaveRequestsContentFragment leaveRequestForm leaveRequests)

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
                    staff <- upsertCurrentUserStaff staff
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
                            staffRsaDocument <- latestRsaDocumentForStaff staff
                            if isHtmxRequest
                                then respondHtml (renderProfileContentFragment staff currentUserEmail preferenceWeekdays selectedShiftPreferences passkeys leaveRequests leaveRequestForm staffRsaDocument today openSection)
                                else render EditView { .. }
                        Right submittedSelections -> do
                            replaceStaffShiftPreferences staff submittedSelections
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
                                                [ renderProfileContentFragment staff currentUserEmail preferenceWeekdays submittedSelections passkeys leaveRequests leaveRequestForm staffRsaDocument today openSection
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
                defaultRosterGroup <- fetchCurrentVenueDefaultRosterGroup
                syncStaffRosterGroupAssignments createdStaff [defaultRosterGroup.id]
                pure createdStaff

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

fetchProfileRosterInvalidationTargets :: (?modelContext :: ModelContext) => Id Venue -> Staff -> IO [(Id RosterGroup, Int, [(UUID.UUID, Int)])]
fetchProfileRosterInvalidationTargets venueId staff = do
    activeScopes <- activeRosterWeekScopes
    fetchProfileRosterInvalidationTargetsForScopes venueId staff activeScopes

fetchProfileRosterInvalidationTargetsForScopes ::
    (?modelContext :: ModelContext) =>
    Id Venue ->
    Staff ->
    [(UUID.UUID, UUID.UUID, Int)] ->
    IO [(Id RosterGroup, Int, [(UUID.UUID, Int)])]
fetchProfileRosterInvalidationTargetsForScopes venueId staff activeScopes = do
    rosterGroupIds <- fetchStaffRosterGroupIds staff
    let activeWeekKeys =
            Set.fromList
                [ (rosterGroupUuid, weekOffset)
                | (venueUuid, rosterGroupUuid, weekOffset) <- activeScopes
                , venueUuid == unpackId venueId
                , rosterGroupUuid `elem` map unpackId rosterGroupIds
                ]
    if null rosterGroupIds || Set.null activeWeekKeys
        then pure []
        else do
            rosterWeeks <-
                query @RosterWeek
                    |> filterWhere (#venueId, unpackId venueId)
                    |> filterWhereIn (#rosterGroupId, map unpackId rosterGroupIds)
                    |> filterWhereIn (#weekOffset, Set.toList (Set.map snd activeWeekKeys))
                    |> fetch
            let activeRosterWeeks =
                    filter
                        (\rosterWeek -> (rosterWeek.rosterGroupId, rosterWeek.weekOffset) `Set.member` activeWeekKeys)
                        rosterWeeks
            rosterDays <-
                if null activeRosterWeeks
                    then pure []
                    else query @RosterDay
                        |> filterWhereIn (#rosterWeekId, map (unpackId . (.id)) activeRosterWeeks)
                        |> fetch
            assignedSlots <-
                if null rosterDays
                    then pure []
                    else query @RosterSlot
                        |> filterWhere (#staffId, Just (unpackId staff.id))
                        |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) rosterDays)
                        |> filterWhere (#deletedAt, Nothing)
                        |> fetch

            let rosterWeekById = Map.fromList (map (\rosterWeek -> (unpackId rosterWeek.id, rosterWeek)) activeRosterWeeks)
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
                | rosterWeek <- activeRosterWeeks
                ]

buildProfileRosterInvalidations :: (?context :: ControllerContext) => [(Id RosterGroup, Int, [(UUID.UUID, Int)])] -> [(Id RosterGroup, Int, [LiveFragmentRef])]
buildProfileRosterInvalidations =
    map \(rosterGroupId, weekOffset, _rowKeys) ->
        ( rosterGroupId
        , weekOffset
        , [buildDeferredRosterContentFragmentRef rosterGroupId weekOffset]
        )
