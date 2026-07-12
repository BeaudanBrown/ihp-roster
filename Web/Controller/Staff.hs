module Web.Controller.Staff where

import Application.Helper.Controller (VenueRole (..), parseVenueRole,
                                      venueRoleToEnum)
import Application.Helper.LiveUpdate (setActorLiveFragmentsRefresh)
import Application.Helper.Pay (rateEffectiveOn)
import Application.Helper.ProfileLeave (buildDefaultLeaveRequest,
                                        fetchStaffLeaveRequests)
import Application.Helper.RosterGroups (fetchCurrentVenueDefaultRosterGroup,
                                        fetchCurrentVenueRosterGroupIds,
                                        fetchCurrentVenueRosterGroups,
                                        fetchStaffRosterGroupIds)
import Application.Helper.StaffShiftPreferences
import Application.Helper.SurfaceResource (LiveMutationResult (..))
import Application.Helper.Url (appendQueryParams)
import Application.Helper.View (OverlayFormMode (HtmxOverlayForm),
                                ToastOverlayConfig, ToastOverlayPosition (..),
                                dialogOverlayMountId, errorToast,
                                renderToastOob, successToast)
import Application.StaffDocuments.Rsa (latestRsaDocumentForStaff)
import Data.Time.Calendar (Day)
import Data.Time.Clock (getCurrentTime, utctDay)
import Web.Controller.Admin.Support (SubmittedPayRateSelection (..),
                                     fetchActiveImportedXeroPayItems,
                                     parseRequiredEmail,
                                     parseSubmittedPayRateSelection)
import Web.Controller.Prelude
import Web.Profiles.FrontendSurface (ProfileScopeValue (..),
                                     staffSectionFragmentForSection,
                                     staffSurfaceFragmentKeys,
                                     staffSurfaceScope)
import Web.RosterWeeks.Responses (respondWithRosterContentOob)
import Web.Staff.Mutations
import Web.View.Staff.Edit

instance Controller StaffController where
    beforeAction = bepisBeforeAction BepisAuthenticatedVenueController do
        annotateTelemetryAction
        ensureIsUser
        ensureCurrentVenue
        ensureProfileCompleted
        ensureManagerRole

    action currentAction@NewStaffAction = runBepis currentAction BepisFormAction do
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

    action currentAction@CreateStaffAction = runBepis currentAction BepisMutationAction do
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

    action currentAction@EditStaffAction { staffId } = runBepis currentAction BepisFormAction do
        staff <- fetch staffId
        ensureRecordInCurrentVenue staff.venueId
        maybeLinkedUserEmail <- fetchStaffLinkedUserEmail staff
        maybeVenueMembership <- fetchStaffVenueMembership staff
        pendingTrialStaffInvitation <- fetchPendingTrialStaffInvitation staff
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
            then respondHtml (renderStaffEditModalFragment staff maybeLinkedUserEmail pendingTrialStaffInvitation rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds maybeVenueMembership preferenceWeekdays selectedShiftPreferences staffRsaDocument leaveRequest leaveRequests today weekOffset maybeRosterGroupId openSection)
            else render EditView { .. }

    action currentAction@ShowStaffContentLiveFragmentAction { staffId } = runBepis currentAction BepisFragmentAction do
        staff <- fetch staffId
        ensureRecordInCurrentVenue staff.venueId
        maybeLinkedUserEmail <- fetchStaffLinkedUserEmail staff
        maybeVenueMembership <- fetchStaffVenueMembership staff
        pendingTrialStaffInvitation <- fetchPendingTrialStaffInvitation staff
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
        leaveRequest <- buildDefaultLeaveRequest
        leaveRequests <- fetchStaffLeaveRequests staff
        respondHtml (renderStaffEditSectionFragment HtmxOverlayForm staff maybeLinkedUserEmail pendingTrialStaffInvitation rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds maybeVenueMembership preferenceWeekdays selectedShiftPreferences leaveRequest leaveRequests weekOffset maybeRosterGroupId openSection)

    action currentAction@UpdateStaffAction { staffId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        staff <- fetch staffId
        ensureRecordInCurrentVenue staff.venueId
        let originalStaff = staff
        maybeLinkedUserEmail <- fetchStaffLinkedUserEmail staff
        maybeVenueMembership <- fetchStaffVenueMembership staff
        pendingTrialStaffInvitation <- fetchPendingTrialStaffInvitation staff
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
                    then respondHtml (renderStaffEditModalFragment renderedStaff maybeLinkedUserEmail pendingTrialStaffInvitation rosterGroups awardLevels awardLevelBaseRates importedPayItems renderedRosterGroupIds maybeVenueMembership preferenceWeekdays renderedPreferences staffRsaDocument leaveRequest leaveRequests today weekOffset maybeRosterGroupId openSection)
                    else do
                        let selectedRosterGroupIds = renderedRosterGroupIds
                        let selectedShiftPreferences = renderedPreferences
                        render EditView { staff = renderedStaff, .. }
        let respondStaffUpdateSuccess updatedStaff successMessage =
                if isHtmxRequest
                    then respondWithStaffActorInvalidation updatedStaff openSection successMessage
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
                    mutationResult <- updateStaffMember originalStaff staff currentSelectedRosterGroupIds submittedSelections Nothing Nothing
                    respondStaffUpdateSuccess mutationResult.liveMutationValue "Shift preferences updated"
            else do
                maybeSelectedRosterGroupIds <- parseStaffRosterGroupIds
                maybeSubmittedVenueRole <- if canManageStaffPay then parseSubmittedStaffVenueRole staff maybeVenueMembership else pure (Just Nothing)
                maybeSubmittedPayRateSelection <- if canManageStaffPay then parseSubmittedPayRateSelection "payRateSelection" else pure (Just emptyStaffPayRateSelection)
                let maybeSubmittedDefaultAwardLevelId = submittedAwardLevelId <$> maybeSubmittedPayRateSelection
                let maybeSubmittedImportedXeroPayItemId = submittedImportedXeroPayItemId <$> maybeSubmittedPayRateSelection
                staff
                    |> buildStaff canManageStaffPay maybeSubmittedDefaultAwardLevelId maybeSubmittedImportedXeroPayItemId
                    |> ifValid \case
                        Left invalidStaff -> renderStaffEditResponse invalidStaff submittedRosterGroupIds selectedShiftPreferences
                        Right validStaff -> do
                            case (maybeSelectedRosterGroupIds, maybeSubmittedVenueRole, maybeSubmittedDefaultAwardLevelId, maybeSubmittedImportedXeroPayItemId) of
                                (Just selectedRosterGroupIds, Just submittedVenueRole, Just _, Just _) -> do
                                    mutationResult <- updateStaffMember originalStaff validStaff selectedRosterGroupIds selectedShiftPreferences maybeVenueMembership submittedVenueRole
                                    respondStaffUpdateSuccess mutationResult.liveMutationValue "Staff member updated"
                                _ -> renderStaffEditResponse validStaff submittedRosterGroupIds selectedShiftPreferences

    action currentAction@NewTrialStaffInvitationAction { staffId } = runBepis currentAction BepisDialogAction do
        ensureVenueWritable
        staff <- fetch staffId
        ensureRecordInCurrentVenue staff.venueId
        pendingInvitations <- fetchPendingTrialStaffInvitations staff
        let weekOffset = paramOrDefault @Int 0 "weekOffset"
        let maybeRosterGroupId = paramOrNothing "rosterGroupId"
        respondHtml (renderTrialStaffInvitationModalFragment staff pendingInvitations Nothing weekOffset maybeRosterGroupId)

    action currentAction@CreateTrialStaffInvitationAction { staffId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        staff <- fetch staffId
        ensureRecordInCurrentVenue staff.venueId
        maybeEmail <- parseRequiredEmail "invitationEmail" "Invite email is required."
        case maybeEmail of
            Just email -> do
                createTrialStaffInvitationMutation staff email >>= \case
                    Right _ -> renderStaffEditResponseFor staff "profile" (Just (successToast ("Invitation sent to " <> email)))
                    Left message -> do
                        setErrorMessage message
                        renderStaffEditResponseFor staff "profile" Nothing
            Nothing -> do
                setErrorMessage "Invite email is required."
                renderStaffEditResponseFor staff "profile" Nothing

    action currentAction@ResendTrialStaffInvitationAction { venueInvitationId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        invitation <- fetch venueInvitationId
        ensureRecordInCurrentVenue invitation.venueId
        case invitation.staffId of
            Nothing -> renderTrialStaffInvitationErrorForInvitation invitation "Choose a staff-linked invitation to resend."
            Just staffId -> do
                staff <- fetch staffId
                ensureRecordInCurrentVenue staff.venueId
                resendTrialStaffInvitationMutation staff invitation >>= \case
                    Right _ -> respondWithTrialStaffInvitationSuccess ("Invitation resent to " <> invitation.email)
                    Left message -> renderTrialStaffInvitationError staff message

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
            |> set #employmentBasis Casual
            |> set #isActive True

respondWithStaffActorInvalidation :: (?context :: ControllerContext, ?request :: Request) => Staff -> Text -> Text -> IO ()
respondWithStaffActorInvalidation staff openSection successMessage = do
    let scope = ProfileScopeValue (unpackId currentVenueId) (unpackId staff.id)
    setHeader ("HX-Reswap", "none")
    setActorLiveFragmentsRefresh (staffSurfaceScope scope) (staffSurfaceFragmentKeys [staffSectionFragmentForSection scope openSection])
    respondHtml (renderToastOob ToastBottomCenter (successToast successMessage))

renderNewStaffResponse :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => Staff -> [Id RosterGroup] -> [RosterGroup] -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> Int -> Maybe (Id RosterGroup) -> IO ()
renderNewStaffResponse staff selectedRosterGroupIds rosterGroups awardLevels awardLevelBaseRates importedPayItems weekOffset maybeRosterGroupId =
    if isHtmxRequest
        then respondHtml (renderNewStaffModalFragment staff rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds weekOffset maybeRosterGroupId)
        else render NewView { .. }

respondWithTrialStaffInvitationSuccess :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => Text -> IO ()
respondWithTrialStaffInvitationSuccess message =
    respondHtml [hsx|
        <div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>
        {renderToastOob ToastBottomCenter (successToast message)}
    |]

renderTrialStaffInvitationError :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => Staff -> Text -> IO ()
renderTrialStaffInvitationError staff message = do
    pendingInvitations <- fetchPendingTrialStaffInvitations staff
    let weekOffset = paramOrDefault @Int 0 "weekOffset"
    let maybeRosterGroupId = paramOrNothing "rosterGroupId"
    respondHtml (renderTrialStaffInvitationModalFragment staff pendingInvitations (Just message) weekOffset maybeRosterGroupId)

renderTrialStaffInvitationErrorForInvitation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => VenueInvitation -> Text -> IO ()
renderTrialStaffInvitationErrorForInvitation invitation message =
    case invitation.staffId of
        Nothing -> respondHtml [hsx|{renderToastOob ToastBottomCenter (errorToast message)}|]
        Just staffId -> fetch staffId >>= \staff -> renderTrialStaffInvitationError staff message

renderStaffEditResponseFor :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => Staff -> Text -> Maybe ToastOverlayConfig -> IO ()
renderStaffEditResponseFor staff openSection maybeToast = do
    maybeLinkedUserEmail <- fetchStaffLinkedUserEmail staff
    maybeVenueMembership <- fetchStaffVenueMembership staff
    pendingTrialStaffInvitation <- fetchPendingTrialStaffInvitation staff
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
        then respondHtml [hsx|
            {renderStaffEditModalFragment staff maybeLinkedUserEmail pendingTrialStaffInvitation rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds maybeVenueMembership preferenceWeekdays selectedShiftPreferences staffRsaDocument leaveRequest leaveRequests today weekOffset maybeRosterGroupId openSection}
            {maybe mempty (renderToastOob ToastBottomCenter) maybeToast}
        |]
        else render EditView { .. }

fetchPendingTrialStaffInvitation :: (?modelContext :: ModelContext) => Staff -> IO (Maybe VenueInvitation)
fetchPendingTrialStaffInvitation staff = listToMaybe <$> fetchPendingTrialStaffInvitations staff

fetchPendingTrialStaffInvitations :: (?modelContext :: ModelContext) => Staff -> IO [VenueInvitation]
fetchPendingTrialStaffInvitations staff =
    case staff.userId of
        Just _ -> pure []
        Nothing ->
            query @VenueInvitation
                |> filterWhere (#staffId, Just staff.id)
                |> filterWhere (#status, unsafeEnumFromText @InvitationStatusEnum "pending")
                |> orderByDesc #createdAt
                |> fetch

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

fetchAwardLevelBaseRatesForStaffForm :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [AwardLevelBaseRate]
fetchAwardLevelBaseRatesForStaffForm = do
    venueConfig <- fetchVenueConfig
    today <- utctDay <$> getCurrentTime
    rates <-
        query @AwardLevelBaseRate
            |> orderByAsc #createdAt
            |> fetch
    pure (filter (rateEffectiveOn venueConfig.rosterWeekStartsOn today) rates)

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

fetchStaffVenueMembership :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Staff -> IO (Maybe VenueMembership)
fetchStaffVenueMembership staff =
    case staff.userId of
        Nothing -> pure Nothing
        Just userId ->
            query @VenueMembership
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhere (#userId, userId)
                |> filterWhere (#isActive, True)
                |> fetchOneOrNothing

parseSubmittedStaffVenueRole :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Staff -> Maybe VenueMembership -> IO (Maybe (Maybe VenueRoleEnum))
parseSubmittedStaffVenueRole _ Nothing = pure (Just Nothing)
parseSubmittedStaffVenueRole staff (Just membership) = do
    let submittedRoleText = paramOrDefault @Text "" "venueRole"
    case parseVenueRole submittedRoleText of
        Nothing -> do
            setErrorMessage "Choose a valid staff role."
            pure Nothing
        Just submittedRole -> do
            let existingRole = parseVenueRole membership.venueRole
            if not (currentUserCanAssignVenueRole existingRole submittedRole)
                then do
                    setErrorMessage "Only the venue owner or a super admin can assign venue owner access."
                    pure Nothing
                else if membership.userId == unpackId currentUser.id && submittedRole < VenueAdminRole
                    then do
                        setErrorMessage "You cannot remove your own admin access."
                        pure Nothing
                else if existingRole == Just VenueOwnerRole && submittedRole /= VenueOwnerRole
                    then do
                        ownerCount <- activeVenueOwnerCount
                        if ownerCount <= 1
                            then do
                                setErrorMessage "Each venue needs at least one owner."
                                pure Nothing
                            else pure (Just (Just (venueRoleToEnum submittedRole)))
                    else pure (Just (Just (venueRoleToEnum submittedRole)))
    where
        currentUserCanAssignVenueRole existingRole submittedRole =
            currentUserIsSuperAdmin
                || hasRole VenueOwnerRole
                || (submittedRole /= VenueOwnerRole && existingRole /= Just VenueOwnerRole)

activeVenueOwnerCount :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO Int
activeVenueOwnerCount =
    query @VenueMembership
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#venueRole, venueRoleToEnum VenueOwnerRole)
        |> filterWhere (#isActive, True)
        |> fetchCount

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
    | section `elem` ["profile", "preferences", "security", "leave"] = section
    | otherwise = ""
