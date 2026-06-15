module Web.Controller.Staff where

import Application.Helper.ProfileLeave (buildDefaultLeaveRequest,
                                        fetchStaffLeaveRequests)
import Application.Helper.RosterGroups (fetchCurrentVenueDefaultRosterGroup,
                                        fetchCurrentVenueRosterGroupIds,
                                        fetchCurrentVenueRosterGroups,
                                        fetchStaffRosterGroupIds,
                                        syncStaffRosterGroupAssignments)
import Application.Helper.StaffShiftPreferences
import Web.Controller.Admin.Support (SubmittedPayRateSelection (..),
                                     fetchActiveImportedXeroPayItems,
                                     parseSubmittedPayRateSelection)
import Application.Helper.Url (appendQueryParams)
import Application.StaffDocuments.Rsa (latestRsaDocumentForStaff)
import Data.Time.Calendar (Day)
import Data.Time.Clock (getCurrentTime, utctDay)
import Web.Controller.Prelude
import Web.RosterWeeks.Responses (respondWithRosterContentOob)
import Web.Staff.Mutations
import Web.View.Staff.Edit

instance Controller StaffController where
    beforeAction = do
        ensureIsUser
        ensureCurrentVenue
        ensureProfileCompleted
        ensureManagerRole

    action NewStaffAction = do
        let weekOffset = paramOrDefault @Int 0 "weekOffset"
        let maybeRosterGroupId = paramOrNothing @(Id RosterGroup) "rosterGroupId"
        staff <- buildNewTrialStaff
        rosterGroups <- fetchCurrentVenueRosterGroups
        awardLevels <- fetchAwardLevelsForStaffForm
        awardLevelBaseRates <- fetchAwardLevelBaseRatesForStaffForm
        importedPayItems <- fetchActiveImportedXeroPayItems
        defaultRosterGroup <- fetchCurrentVenueDefaultRosterGroup
        let selectedRosterGroupIds = [defaultRosterGroup.id]
        if isHtmxRequest
            then respondHtml (renderNewStaffModalFragment staff rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds weekOffset maybeRosterGroupId)
            else render NewView { .. }

    action CreateStaffAction = do
        ensureVenueWritable
        let weekOffset = paramOrDefault @Int 0 "weekOffset"
        let maybeRosterGroupId = paramOrNothing @(Id RosterGroup) "rosterGroupId"
        rosterGroups <- fetchCurrentVenueRosterGroups
        awardLevels <- fetchAwardLevelsForStaffForm
        awardLevelBaseRates <- fetchAwardLevelBaseRatesForStaffForm
        importedPayItems <- fetchActiveImportedXeroPayItems
        maybeSelectedRosterGroupIds <- parseStaffRosterGroupIds
        let submittedRosterGroupIds = nub (mapMaybe parseRosterGroupIdText (paramTexts "rosterGroupIds"))
        let canManageStaffPay = hasRole VenueAdminRole
        maybeSubmittedPayRateSelection <- if canManageStaffPay then parseSubmittedPayRateSelection "payRateSelection" else pure (Just emptyStaffPayRateSelection)
        let maybeSubmittedDefaultAwardLevelId = submittedAwardLevelId <$> maybeSubmittedPayRateSelection
        let maybeSubmittedImportedXeroPayItemId = submittedImportedXeroPayItemId <$> maybeSubmittedPayRateSelection
        staff <- buildNewTrialStaff
        staff
            |> buildStaff canManageStaffPay maybeSubmittedDefaultAwardLevelId maybeSubmittedImportedXeroPayItemId
            |> ifValid \case
                Left invalidStaff -> renderNewStaffResponse invalidStaff submittedRosterGroupIds rosterGroups awardLevels awardLevelBaseRates importedPayItems weekOffset maybeRosterGroupId
                Right validStaff -> do
                    case (maybeSelectedRosterGroupIds, maybeSubmittedDefaultAwardLevelId, maybeSubmittedImportedXeroPayItemId) of
                        (Just selectedRosterGroupIds@(selectedRosterGroupId : _), Just _, Just _) -> do
                            _ <- createTrialStaffMember validStaff selectedRosterGroupIds
                            if isHtmxRequest
                                then do
                                    let rosterGroupId = fromMaybe selectedRosterGroupId maybeRosterGroupId
                                    respondWithRosterContentOob rosterGroupId weekOffset
                                else do
                                    setSuccessMessage "Trial staff placeholder created"
                                    redirectToPath $
                                        maybe
                                            (pathTo ShowRosterWeekAction { weekOffset })
                                            (\rosterGroupId -> appendQueryParams (pathTo ShowRosterWeekAction { weekOffset }) [("rosterGroupId", tshow rosterGroupId)])
                                            maybeRosterGroupId
                        _ -> renderNewStaffResponse validStaff submittedRosterGroupIds rosterGroups awardLevels awardLevelBaseRates importedPayItems weekOffset maybeRosterGroupId

    action EditStaffAction { staffId } = do
        staff <- fetch staffId
        ensureRecordInCurrentVenue staff.venueId
        maybeLinkedUserEmail <- fetchStaffLinkedUserEmail staff
        let weekOffset = paramOrDefault @Int 0 "weekOffset"
        let maybeRosterGroupId = paramOrNothing "rosterGroupId"
        let openSection = normalizeStaffOpenSection (paramOrDefault @Text "" "section")
        venueConfig <- fetchVenueConfig
        rosterGroups <- fetchCurrentVenueRosterGroups
        awardLevels <- fetchAwardLevelsForStaffForm
        awardLevelBaseRates <- fetchAwardLevelBaseRatesForStaffForm
        importedPayItems <- fetchActiveImportedXeroPayItems
        selectedRosterGroupIds <- fetchStaffRosterGroupIds staff
        let preferenceWeekdays = allPreferenceWeekdays venueConfig
        selectedShiftPreferences <- fetchStaffShiftPreferenceSelections staff
        staffRsaDocument <- latestRsaDocumentForStaff staff
        leaveRequest <- buildDefaultLeaveRequest
        leaveRequests <- fetchStaffLeaveRequests staff
        today <- utctDay <$> getCurrentTime
        if isHtmxRequest
            then respondHtml (renderStaffEditModalFragment staff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds preferenceWeekdays selectedShiftPreferences staffRsaDocument leaveRequest leaveRequests today weekOffset maybeRosterGroupId openSection)
            else render EditView { .. }

    action UpdateStaffAction { staffId } = do
        ensureVenueWritable
        staff <- fetch staffId
        ensureRecordInCurrentVenue staff.venueId
        let originalStaff = staff
        maybeLinkedUserEmail <- fetchStaffLinkedUserEmail staff
        let submittedShiftPreferenceKeys = nub (paramTexts "shiftPreferenceKeys")
        let weekOffset = paramOrDefault @Int 0 "weekOffset"
        let maybeRosterGroupId = paramOrNothing "rosterGroupId"
        let openSection = normalizeStaffOpenSection (paramOrDefault @Text "" "section")
        let preferencesWereSubmitted = openSection == "preferences"
        venueConfig <- fetchVenueConfig
        rosterGroups <- fetchCurrentVenueRosterGroups
        awardLevels <- fetchAwardLevelsForStaffForm
        awardLevelBaseRates <- fetchAwardLevelBaseRatesForStaffForm
        importedPayItems <- fetchActiveImportedXeroPayItems
        currentSelectedRosterGroupIds <- fetchStaffRosterGroupIds staff
        let submittedRosterGroupIds = if preferencesWereSubmitted then currentSelectedRosterGroupIds else nub (mapMaybe parseRosterGroupIdText (paramTexts "rosterGroupIds"))
        let canManageStaffPay = hasRole VenueAdminRole
        let preferenceWeekdays = allPreferenceWeekdays venueConfig
        staffRsaDocument <- latestRsaDocumentForStaff staff
        leaveRequest <- buildDefaultLeaveRequest
        leaveRequests <- fetchStaffLeaveRequests staff
        today <- utctDay <$> getCurrentTime
        selectedShiftPreferences <-
            if preferencesWereSubmitted
                then pure $
                    case parseShiftPreferenceSelections preferenceWeekdays submittedShiftPreferenceKeys of
                        Right selections -> selections
                        Left _           -> []
                else fetchStaffShiftPreferenceSelections staff
        let renderStaffEditResponse renderedStaff renderedRosterGroupIds renderedPreferences =
                if isHtmxRequest
                    then respondHtml (renderStaffEditModalFragment renderedStaff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates importedPayItems renderedRosterGroupIds preferenceWeekdays renderedPreferences staffRsaDocument leaveRequest leaveRequests today weekOffset maybeRosterGroupId openSection)
                    else do
                        let selectedRosterGroupIds = renderedRosterGroupIds
                        let selectedShiftPreferences = renderedPreferences
                        render EditView { staff = renderedStaff, .. }
        let respondStaffUpdateSuccess successMessage =
                if isHtmxRequest
                    then do
                        rosterGroupId <- case maybeRosterGroupId of
                            Just rosterGroupId -> pure rosterGroupId
                            Nothing -> (.id) <$> fetchCurrentVenueDefaultRosterGroup
                        respondWithRosterContentOob rosterGroupId weekOffset
                    else do
                        setSuccessMessage successMessage
                        redirectToPath $
                            maybe
                                (pathTo ShowRosterWeekAction { weekOffset })
                                (\rosterGroupId -> appendQueryParams (pathTo ShowRosterWeekAction { weekOffset }) [("rosterGroupId", tshow rosterGroupId)])
                                maybeRosterGroupId
        if preferencesWereSubmitted
            then case parseShiftPreferenceSelections preferenceWeekdays submittedShiftPreferenceKeys of
                Left preferenceError -> do
                    setErrorMessage preferenceError
                    renderStaffEditResponse staff currentSelectedRosterGroupIds selectedShiftPreferences
                Right submittedSelections -> do
                    _ <- updateStaffMember originalStaff staff currentSelectedRosterGroupIds submittedSelections
                    respondStaffUpdateSuccess "Shift preferences updated"
            else do
                maybeSelectedRosterGroupIds <- parseStaffRosterGroupIds
                maybeSubmittedPayRateSelection <- if canManageStaffPay then parseSubmittedPayRateSelection "payRateSelection" else pure (Just emptyStaffPayRateSelection)
                let maybeSubmittedDefaultAwardLevelId = submittedAwardLevelId <$> maybeSubmittedPayRateSelection
                let maybeSubmittedImportedXeroPayItemId = submittedImportedXeroPayItemId <$> maybeSubmittedPayRateSelection
                staff
                    |> buildStaff canManageStaffPay maybeSubmittedDefaultAwardLevelId maybeSubmittedImportedXeroPayItemId
                    |> ifValid \case
                        Left invalidStaff -> renderStaffEditResponse invalidStaff submittedRosterGroupIds selectedShiftPreferences
                        Right validStaff -> do
                            case (maybeSelectedRosterGroupIds, maybeSubmittedDefaultAwardLevelId, maybeSubmittedImportedXeroPayItemId) of
                                (Just selectedRosterGroupIds, Just _, Just _) -> do
                                    _ <- updateStaffMember originalStaff validStaff selectedRosterGroupIds selectedShiftPreferences
                                    respondStaffUpdateSuccess "Staff member updated"
                                _ -> renderStaffEditResponse validStaff submittedRosterGroupIds selectedShiftPreferences

emptyStaffPayRateSelection :: SubmittedPayRateSelection
emptyStaffPayRateSelection = SubmittedPayRateSelection Nothing Nothing

buildNewTrialStaff :: (?context :: ControllerContext) => IO Staff
buildNewTrialStaff =
    pure $
        newRecord @Staff
            |> set #venueId (unpackId currentVenueId)
            |> set #userId Nothing
            |> set #firstName ""
            |> set #lastName ""
            |> set #phone "Trial placeholder"
            |> set #emergencyContactName "Trial placeholder"
            |> set #emergencyContactPhone "Trial placeholder"
            |> set #idealShiftsPerWeek 0
            |> set #isActive True

createTrialStaffMember :: (?modelContext :: ModelContext) => Staff -> [Id RosterGroup] -> IO Staff
createTrialStaffMember staff selectedRosterGroupIds =
    withTransaction do
        createdStaff <- staff |> createRecord
        syncStaffRosterGroupAssignments createdStaff selectedRosterGroupIds
        pure createdStaff

renderNewStaffResponse :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => Staff -> [Id RosterGroup] -> [RosterGroup] -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> Int -> Maybe (Id RosterGroup) -> IO ()
renderNewStaffResponse staff selectedRosterGroupIds rosterGroups awardLevels awardLevelBaseRates importedPayItems weekOffset maybeRosterGroupId =
    if isHtmxRequest
        then respondHtml (renderNewStaffModalFragment staff rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds weekOffset maybeRosterGroupId)
        else render NewView { .. }

buildStaff :: (?request :: Request) => Bool -> Maybe (Maybe (Id AwardLevel)) -> Maybe (Maybe (Id XeroImportedPayItem)) -> Staff -> Staff
buildStaff canManageStaffPay maybeSubmittedDefaultAwardLevelId maybeSubmittedImportedXeroPayItemId staff =
    staff
        |> requireParam #firstName "firstName" "First name is required"
        |> requireParam #lastName "lastName" "Last name is required"
        |> requireParam #phone "phone" "Phone is required"
        |> requireParam #emergencyContactName "emergencyContactName" "Emergency contact name is required"
        |> requireParam #emergencyContactPhone "emergencyContactPhone" "Emergency contact phone is required"
        |> requireParam #idealShiftsPerWeek "idealShiftsPerWeek" "Ideal shifts per week is required"
        |> fill @'["firstName", "lastName", "preferredName", "phone", "emergencyContactName", "emergencyContactPhone", "idealShiftsPerWeek", "isActive"]
        |> normalizeStaffTextFields
        |> applyStaffPayFields
        |> requiredBoundedTextField #firstName 80
        |> requiredBoundedTextField #lastName 80
        |> validateField #preferredName (validateMaybe (boundedText 80))
        |> requiredBoundedTextField #phone 80
        |> requiredBoundedTextField #emergencyContactName 120
        |> requiredBoundedTextField #emergencyContactPhone 80
        |> validateField #idealShiftsPerWeek (isInRange (0, 7))
    where
        normalizeStaffTextFields =
            normalizeMaybeTextField #preferredName

        applyStaffPayFields currentStaff
            | not canManageStaffPay = currentStaff
            | otherwise =
                let withEmploymentBasis = currentStaff |> fill @'["employmentBasis"]
                 in case maybeSubmittedDefaultAwardLevelId of
                        Just defaultAwardLevelId -> withEmploymentBasis |> set #defaultAwardLevelId defaultAwardLevelId |> applyImportedPayItem
                        Nothing -> withEmploymentBasis |> applyImportedPayItem

        applyImportedPayItem currentStaff =
            case maybeSubmittedImportedXeroPayItemId of
                Just importedXeroPayItemId -> currentStaff |> set #importedXeroPayItemId importedXeroPayItemId
                Nothing -> currentStaff

fetchAwardLevelsForStaffForm :: (?modelContext :: ModelContext) => IO [AwardLevel]
fetchAwardLevelsForStaffForm =
    query @AwardLevel
        |> filterWhere (#isActive, True)
        |> orderByAsc #classification
        |> fetch

fetchAwardLevelBaseRatesForStaffForm :: (?modelContext :: ModelContext) => IO [AwardLevelBaseRate]
fetchAwardLevelBaseRatesForStaffForm =
    query @AwardLevelBaseRate
        |> filterWhere (#operativeTo, Nothing :: Maybe Day)
        |> orderByAsc #createdAt
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
    let submittedRosterGroupTexts = nub (paramTexts "rosterGroupIds")
    let submittedRosterGroupIds = mapMaybe parseRosterGroupIdText submittedRosterGroupTexts
    currentVenueRosterGroupIds <- fetchCurrentVenueRosterGroupIds
    if null submittedRosterGroupIds
        then do
            setErrorMessage "Choose at least one roster group for this staff member."
            pure Nothing
        else if length submittedRosterGroupIds /= length submittedRosterGroupTexts
            then do
                setErrorMessage "Choose roster groups from the current venue."
                pure Nothing
        else if all (`elem` currentVenueRosterGroupIds) submittedRosterGroupIds
            then pure (Just submittedRosterGroupIds)
            else do
                setErrorMessage "Choose roster groups from the current venue."
                pure Nothing

parseRosterGroupIdText :: Text -> Maybe (Id RosterGroup)
parseRosterGroupIdText value =
    Id <$> parseUUIDText value

normalizeStaffOpenSection :: Text -> Text
normalizeStaffOpenSection section
    | section `elem` ["profile", "preferences", "security", "leave", "rsa"] = section
    | otherwise = ""
