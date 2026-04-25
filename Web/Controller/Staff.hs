module Web.Controller.Staff where

import Application.Helper.RosterGroups (fetchCurrentVenueDefaultRosterGroup,
                                        fetchCurrentVenueRosterGroupIds,
                                        fetchCurrentVenueRosterGroups,
                                        fetchStaffRosterGroupIds,
                                        syncStaffRosterGroupAssignments)
import Application.Helper.StaffShiftPreferences
import Application.Helper.View (appendQueryParams)
import Web.Controller.Prelude
import Web.RosterWeeks.LiveUpdates (broadcastRosterWeekInvalidation)
import Web.RosterWeeks.Projection (buildRosterContentFragmentRef)
import Web.RosterWeeks.Responses (respondWithRosterContentOob)
import Web.View.Staff.Edit

instance Controller StaffController where
    beforeAction = do
        ensureIsUser
        ensureCurrentVenue
        ensureProfileCompleted
        ensureManagerRole

    action EditStaffAction { staffId } = do
        staff <- fetch staffId
        ensureRecordInCurrentVenue staff.venueId
        maybeLinkedUserEmail <- fetchStaffLinkedUserEmail staff
        let weekOffset = paramOrDefault @Int 0 "weekOffset"
        let maybeRosterGroupId = paramOrNothing "rosterGroupId"
        venueConfig <- fetchVenueConfig
        rosterGroups <- fetchCurrentVenueRosterGroups
        awardLevels <- fetchAwardLevelsForStaffForm
        selectedRosterGroupIds <- fetchStaffRosterGroupIds staff
        let preferenceWeekdays = allPreferenceWeekdays venueConfig
        preferenceSections <- fetchPreferenceSectionsForRosterGroups selectedRosterGroupIds
        selectedShiftPreferenceKeys <- fetchStaffShiftPreferenceKeyTexts staff selectedRosterGroupIds
        if isHtmxRequest
            then respondHtml (renderStaffEditModalFragment staff maybeLinkedUserEmail rosterGroups awardLevels selectedRosterGroupIds preferenceWeekdays preferenceSections selectedShiftPreferenceKeys weekOffset maybeRosterGroupId)
            else render EditView { .. }

    action UpdateStaffAction { staffId } = do
        staff <- fetch staffId
        ensureRecordInCurrentVenue staff.venueId
        maybeLinkedUserEmail <- fetchStaffLinkedUserEmail staff
        let submittedShiftPreferenceKeys = nub (paramList @Text "shiftPreferenceKeys")
        let weekOffset = paramOrDefault @Int 0 "weekOffset"
        let maybeRosterGroupId = paramOrNothing "rosterGroupId"
        venueConfig <- fetchVenueConfig
        rosterGroups <- fetchCurrentVenueRosterGroups
        awardLevels <- fetchAwardLevelsForStaffForm
        let submittedRosterGroupIds = nub (paramList @(Id RosterGroup) "rosterGroupIds")
        maybeSelectedRosterGroupIds <- parseStaffRosterGroupIds
        let canManageStaffPay = hasRole VenueAdminRole
        maybeSubmittedDefaultAwardLevelId <- parseSubmittedDefaultAwardLevelId canManageStaffPay
        previousRosterGroupIds <- fetchStaffRosterGroupIds staff
        let preferenceWeekdays = allPreferenceWeekdays venueConfig
        preferenceSections <- fetchPreferenceSectionsForRosterGroups submittedRosterGroupIds
        let selectedShiftPreferenceKeys = submittedShiftPreferenceKeys
        staff
            |> buildStaff canManageStaffPay maybeSubmittedDefaultAwardLevelId
            |> ifValid \case
                Left staff -> do
                    if isHtmxRequest
                        then respondHtml (renderStaffEditModalFragment staff maybeLinkedUserEmail rosterGroups awardLevels submittedRosterGroupIds preferenceWeekdays preferenceSections selectedShiftPreferenceKeys weekOffset maybeRosterGroupId)
                        else do
                            let selectedRosterGroupIds = submittedRosterGroupIds
                            render EditView { .. }
                Right staff -> do
                    case (maybeSelectedRosterGroupIds, maybeSubmittedDefaultAwardLevelId) of
                        (Nothing, _) -> do
                            let selectedRosterGroupIds = submittedRosterGroupIds
                            if isHtmxRequest
                                then respondHtml (renderStaffEditModalFragment staff maybeLinkedUserEmail rosterGroups awardLevels selectedRosterGroupIds preferenceWeekdays preferenceSections selectedShiftPreferenceKeys weekOffset maybeRosterGroupId)
                                else render EditView { .. }
                        (_, Nothing) -> do
                            let selectedRosterGroupIds = submittedRosterGroupIds
                            if isHtmxRequest
                                then respondHtml (renderStaffEditModalFragment staff maybeLinkedUserEmail rosterGroups awardLevels selectedRosterGroupIds preferenceWeekdays preferenceSections selectedShiftPreferenceKeys weekOffset maybeRosterGroupId)
                                else render EditView { .. }
                        (Just selectedRosterGroupIds, Just _) -> do
                            case parseShiftPreferenceSelections preferenceSections preferenceWeekdays submittedShiftPreferenceKeys of
                                Left preferenceError -> do
                                    setErrorMessage preferenceError
                                    if isHtmxRequest
                                        then respondHtml (renderStaffEditModalFragment staff maybeLinkedUserEmail rosterGroups awardLevels selectedRosterGroupIds preferenceWeekdays preferenceSections selectedShiftPreferenceKeys weekOffset maybeRosterGroupId)
                                        else render EditView { .. }
                                Right submittedSelections -> do
                                    staff <- withTransaction do
                                        updatedStaff <- staff |> updateRecord
                                        syncStaffRosterGroupAssignments updatedStaff selectedRosterGroupIds
                                        replaceStaffShiftPreferences updatedStaff (nub (previousRosterGroupIds <> selectedRosterGroupIds)) submittedSelections
                                        pure updatedStaff
                                    let invalidatedRosterGroupIds = nub (previousRosterGroupIds <> selectedRosterGroupIds)
                                    if isHtmxRequest
                                        then do
                                            rosterGroupId <- case maybeRosterGroupId of
                                                Just rosterGroupId -> pure rosterGroupId
                                                Nothing -> (.id) <$> fetchCurrentVenueDefaultRosterGroup
                                            forM_ invalidatedRosterGroupIds \invalidatedRosterGroupId ->
                                                broadcastRosterWeekInvalidation
                                                    invalidatedRosterGroupId
                                                    weekOffset
                                                    [buildRosterContentFragmentRef invalidatedRosterGroupId weekOffset]
                                            respondWithRosterContentOob rosterGroupId weekOffset
                                        else do
                                            setSuccessMessage "Staff member updated"
                                            redirectToPath $
                                                maybe
                                                    (pathTo ShowRosterWeekAction { weekOffset })
                                                    (\rosterGroupId -> appendQueryParams (pathTo ShowRosterWeekAction { weekOffset }) [("rosterGroupId", tshow rosterGroupId)])
                                                    maybeRosterGroupId

buildStaff :: (?request :: Request) => Bool -> Maybe (Maybe (Id AwardLevel)) -> Staff -> Staff
buildStaff canManageStaffPay maybeSubmittedDefaultAwardLevelId staff =
    staff
        |> fill @'["firstName", "lastName", "preferredName", "phone", "emergencyContactName", "emergencyContactPhone", "idealShiftsPerWeek", "isActive"]
        |> applyStaffPayFields
        |> validateField #firstName nonEmpty
        |> validateField #lastName nonEmpty
        |> validateField #phone nonEmpty
        |> validateField #emergencyContactName nonEmpty
        |> validateField #emergencyContactPhone nonEmpty
        |> validateField #idealShiftsPerWeek (isInRange (0, 7))
    where
        applyStaffPayFields currentStaff
            | not canManageStaffPay = currentStaff
            | otherwise =
                let withEmploymentBasis = currentStaff |> fill @'["employmentBasis"]
                 in case maybeSubmittedDefaultAwardLevelId of
                        Just defaultAwardLevelId -> withEmploymentBasis |> set #defaultAwardLevelId defaultAwardLevelId
                        Nothing -> withEmploymentBasis

fetchAwardLevelsForStaffForm :: (?modelContext :: ModelContext) => IO [AwardLevel]
fetchAwardLevelsForStaffForm =
    query @AwardLevel
        |> filterWhere (#isActive, True)
        |> orderByAsc #classification
        |> fetch

parseSubmittedDefaultAwardLevelId ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Bool ->
    IO (Maybe (Maybe (Id AwardLevel)))
parseSubmittedDefaultAwardLevelId canManageStaffPay
    | not canManageStaffPay = pure (Just Nothing)
    | otherwise = do
        let maybeAwardLevelId = paramOrNothing @(Id AwardLevel) "defaultAwardLevelId"
        case maybeAwardLevelId of
            Nothing -> pure (Just Nothing)
            Just awardLevelId -> do
                maybeAwardLevel <-
                    query @AwardLevel
                        |> filterWhere (#id, awardLevelId)
                        |> filterWhere (#isActive, True)
                        |> fetchOneOrNothing
                case maybeAwardLevel of
                    Just _ -> pure (Just (Just awardLevelId))
                    Nothing -> do
                        setErrorMessage "Choose a synced award level."
                        pure Nothing

fetchStaffLinkedUserEmail :: (?modelContext :: ModelContext) => Staff -> IO (Maybe Text)
fetchStaffLinkedUserEmail staff =
    case staff.userId of
        Nothing     -> pure Nothing
        Just userId -> Just . (.email) <$> fetch (Id userId :: Id User)

parseStaffRosterGroupIds :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO (Maybe [Id RosterGroup])
parseStaffRosterGroupIds = do
    let submittedRosterGroupIds = nub (paramList @(Id RosterGroup) "rosterGroupIds")
    currentVenueRosterGroupIds <- fetchCurrentVenueRosterGroupIds
    if null submittedRosterGroupIds
        then do
            setErrorMessage "Choose at least one roster group for this staff member."
            pure Nothing
        else if all (`elem` currentVenueRosterGroupIds) submittedRosterGroupIds
            then pure (Just submittedRosterGroupIds)
            else do
                setErrorMessage "Choose roster groups from the current venue."
                pure Nothing
