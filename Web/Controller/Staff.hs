module Web.Controller.Staff where

import Application.Helper.ProfileLeave (buildDefaultLeaveRequest,
                                        fetchStaffLeaveRequests)
import Application.Helper.RosterGroups (fetchCurrentVenueDefaultRosterGroup,
                                        fetchCurrentVenueRosterGroupIds,
                                        fetchCurrentVenueRosterGroups,
                                        fetchStaffRosterGroupIds)
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

    action EditStaffAction { staffId } = do
        staff <- fetch staffId
        ensureRecordInCurrentVenue staff.venueId
        maybeLinkedUserEmail <- fetchStaffLinkedUserEmail staff
        let weekOffset = paramOrDefault @Int 0 "weekOffset"
        let maybeRosterGroupId = paramOrNothing "rosterGroupId"
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
            then respondHtml (renderStaffEditModalFragment staff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds preferenceWeekdays selectedShiftPreferences staffRsaDocument leaveRequest leaveRequests today weekOffset maybeRosterGroupId)
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
        venueConfig <- fetchVenueConfig
        rosterGroups <- fetchCurrentVenueRosterGroups
        awardLevels <- fetchAwardLevelsForStaffForm
        awardLevelBaseRates <- fetchAwardLevelBaseRatesForStaffForm
        importedPayItems <- fetchActiveImportedXeroPayItems
        let submittedRosterGroupIds = nub (mapMaybe parseRosterGroupIdText (paramTexts "rosterGroupIds"))
        maybeSelectedRosterGroupIds <- parseStaffRosterGroupIds
        let canManageStaffPay = hasRole VenueAdminRole
        maybeSubmittedPayRateSelection <- if canManageStaffPay then parseSubmittedPayRateSelection "payRateSelection" else pure (Just emptyStaffPayRateSelection)
        let maybeSubmittedDefaultAwardLevelId = submittedAwardLevelId <$> maybeSubmittedPayRateSelection
        let maybeSubmittedImportedXeroPayItemId = submittedImportedXeroPayItemId <$> maybeSubmittedPayRateSelection
        let preferenceWeekdays = allPreferenceWeekdays venueConfig
        staffRsaDocument <- latestRsaDocumentForStaff staff
        leaveRequest <- buildDefaultLeaveRequest
        leaveRequests <- fetchStaffLeaveRequests staff
        today <- utctDay <$> getCurrentTime
        let selectedShiftPreferences =
                case parseShiftPreferenceSelections preferenceWeekdays submittedShiftPreferenceKeys of
                    Right selections -> selections
                    Left _           -> []
        staff
            |> buildStaff canManageStaffPay maybeSubmittedDefaultAwardLevelId maybeSubmittedImportedXeroPayItemId
            |> ifValid \case
                Left staff -> do
                    if isHtmxRequest
                        then respondHtml (renderStaffEditModalFragment staff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates importedPayItems submittedRosterGroupIds preferenceWeekdays selectedShiftPreferences staffRsaDocument leaveRequest leaveRequests today weekOffset maybeRosterGroupId)
                        else do
                            let selectedRosterGroupIds = submittedRosterGroupIds
                            render EditView { .. }
                Right staff -> do
                    case (maybeSelectedRosterGroupIds, maybeSubmittedDefaultAwardLevelId, maybeSubmittedImportedXeroPayItemId) of
                        (Nothing, _, _) -> do
                            let selectedRosterGroupIds = submittedRosterGroupIds
                            if isHtmxRequest
                                then respondHtml (renderStaffEditModalFragment staff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds preferenceWeekdays selectedShiftPreferences staffRsaDocument leaveRequest leaveRequests today weekOffset maybeRosterGroupId)
                                else render EditView { .. }
                        (_, Nothing, _) -> do
                            let selectedRosterGroupIds = submittedRosterGroupIds
                            if isHtmxRequest
                                then respondHtml (renderStaffEditModalFragment staff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds preferenceWeekdays selectedShiftPreferences staffRsaDocument leaveRequest leaveRequests today weekOffset maybeRosterGroupId)
                                else render EditView { .. }
                        (_, _, Nothing) -> do
                            let selectedRosterGroupIds = submittedRosterGroupIds
                            if isHtmxRequest
                                then respondHtml (renderStaffEditModalFragment staff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds preferenceWeekdays selectedShiftPreferences staffRsaDocument leaveRequest leaveRequests today weekOffset maybeRosterGroupId)
                                else render EditView { .. }
                        (Just selectedRosterGroupIds, Just _, Just _) -> do
                            case parseShiftPreferenceSelections preferenceWeekdays submittedShiftPreferenceKeys of
                                Left preferenceError -> do
                                    setErrorMessage preferenceError
                                    if isHtmxRequest
                                        then respondHtml (renderStaffEditModalFragment staff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds preferenceWeekdays selectedShiftPreferences staffRsaDocument leaveRequest leaveRequests today weekOffset maybeRosterGroupId)
                                        else render EditView { .. }
                                Right submittedSelections -> do
                                    _ <- updateStaffMember originalStaff staff selectedRosterGroupIds submittedSelections
                                    if isHtmxRequest
                                        then do
                                            rosterGroupId <- case maybeRosterGroupId of
                                                Just rosterGroupId -> pure rosterGroupId
                                                Nothing -> (.id) <$> fetchCurrentVenueDefaultRosterGroup
                                            respondWithRosterContentOob rosterGroupId weekOffset
                                        else do
                                            setSuccessMessage "Staff member updated"
                                            redirectToPath $
                                                maybe
                                                    (pathTo ShowRosterWeekAction { weekOffset })
                                                    (\rosterGroupId -> appendQueryParams (pathTo ShowRosterWeekAction { weekOffset }) [("rosterGroupId", tshow rosterGroupId)])
                                                    maybeRosterGroupId

emptyStaffPayRateSelection :: SubmittedPayRateSelection
emptyStaffPayRateSelection = SubmittedPayRateSelection Nothing Nothing

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
