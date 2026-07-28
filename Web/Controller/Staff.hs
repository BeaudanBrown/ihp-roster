module Web.Controller.Staff where

import Application.Helper.Controller (VenueRole (..), parseVenueRole,
                                      venueRoleToEnum)
import Application.Helper.FrontendContract.Surface.Request (attachSurfaceRequestFieldErrors,
                                                            surfaceRequestFieldErrorsMessage)
import Application.Helper.FrontendContract.Surface.Roster.Resource (rosterSlotsContentResource,
                                                                    rosterWeekResource)
import Application.Helper.Pay (rateEffectiveOn)
import Application.Helper.ProfileLeave (buildDefaultLeaveRequest,
                                        fetchStaffLeaveRequests)
import Application.Helper.RosterGroups (fetchCurrentVenueDefaultRosterGroup,
                                        fetchCurrentVenueRosterGroupIds,
                                        fetchCurrentVenueRosterGroupOrDefault,
                                        fetchCurrentVenueRosterGroups,
                                        fetchStaffRosterGroupIds)
import Application.Helper.Staff (isAdoptableTrialStaff)
import Application.Helper.StaffShiftPreferences
import Application.Helper.SurfaceResource (LiveMutationResult (..))
import Application.Helper.Url (appendQueryParams)
import Application.Helper.View (OverlayFormMode (HtmxOverlayForm),
                                ToastOverlayPosition (..), dialogOverlayMountId,
                                errorToast, renderToastOob, successToast)
import Application.PayAssignment (selectableStaffAssignmentMode)
import Application.StaffDocuments.Rsa (latestRsaDocumentForStaff)
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import Data.Time.Clock (getCurrentTime, utctDay)
import qualified Data.UUID as UUID
import Web.Controller.Admin.Support (SubmittedPayRateSelection (..),
                                     fetchActiveImportedXeroPayItems,
                                     parseSubmittedPayRateSelectionValue)
import Web.Controller.Prelude
import Web.RosterWeeks.Projection (rosterGridInnerAndStaffPanelFragments)
import Web.RosterWeeks.Responses (respondWithRosterContentOob,
                                  respondWithRosterResourceInvalidation)
import Web.Staff.Mutations
import Web.Staff.ProfileSurfaceRequest (StaffProfileDetailsSubmission (..),
                                        StaffProfileSurfaceSubmission (..),
                                        StaffShiftPreferencesSubmission (..),
                                        parseStaffSurfaceSubmission)
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
        maybeSubmittedPayRateSelection <- if canManageStaffPay then requireSubmittedPayRateSelection "payRateSelection" else pure (Just emptyStaffPayRateSelection)
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
            then respondHtml (renderStaffEditModalFragment staff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds maybeVenueMembership preferenceWeekdays selectedShiftPreferences staffRsaDocument leaveRequest leaveRequests today weekOffset maybeRosterGroupId openSection)
            else render EditView { .. }

    action currentAction@ShowStaffContentLiveFragmentAction { staffId } = runBepis currentAction BepisFragmentAction do
        staff <- fetch staffId
        ensureRecordInCurrentVenue staff.venueId
        maybeLinkedUserEmail <- fetchStaffLinkedUserEmail staff
        maybeVenueMembership <- fetchStaffVenueMembership staff
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
        respondHtml (renderStaffEditSectionFragment HtmxOverlayForm staff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds maybeVenueMembership preferenceWeekdays selectedShiftPreferences leaveRequest leaveRequests weekOffset maybeRosterGroupId openSection)

    action currentAction@UpdateStaffAction { staffId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        staff <- fetch staffId
        ensureRecordInCurrentVenue staff.venueId
        let originalStaff = staff
        let submissionResult = parseStaffSurfaceSubmission
        maybeLinkedUserEmail <- fetchStaffLinkedUserEmail staff
        maybeVenueMembership <- fetchStaffVenueMembership staff
        let weekOffset = paramOrDefault @Int 0 "weekOffset"
        let maybeRosterGroupId = paramOrNothing "rosterGroupId"
        let openSection =
                case submissionResult of
                    Right (SubmittedStaffShiftPreferences _) -> "preferences"
                    Right (SubmittedStaffProfileDetails submitted) -> normalizeStaffOpenSection submitted.submittedProfileSection
                    Left _ -> "profile"
        venueConfig <- fetchVenueConfig
        rosterGroups <- fetchCurrentVenueRosterGroups
        awardLevels <- fetchAwardLevelsForStaffForm
        awardLevelBaseRates <- fetchAwardLevelBaseRatesForStaffForm
        importedPayItems <- fetchActiveImportedXeroPayItems
        currentSelectedRosterGroupIds <- fetchStaffRosterGroupIds staff
        let submittedRosterGroupIds =
                case submissionResult of
                    Right (SubmittedStaffProfileDetails submitted) -> map Id (fromMaybe [] submitted.submittedRosterGroupIds)
                    _ -> currentSelectedRosterGroupIds
        let canManageStaffPay = hasRole VenueAdminRole
        let preferenceWeekdays = allPreferenceWeekdays venueConfig
        staffRsaDocument <- latestRsaDocumentForStaff staff
        leaveRequest <- buildDefaultLeaveRequest
        leaveRequests <- fetchStaffLeaveRequests staff
        today <- utctDay <$> getCurrentTime
        selectedShiftPreferences <-
            case submissionResult of
                Right (SubmittedStaffShiftPreferences submitted) ->
                    pure $
                        case parseShiftPreferenceSelections preferenceWeekdays submitted.submittedShiftPreferenceKeys of
                            Right selections -> selections
                            Left _           -> []
                _ -> fetchStaffShiftPreferenceSelections staff
        let renderStaffEditResponse renderedStaff renderedRosterGroupIds renderedPreferences =
                if isHtmxRequest
                    then respondHtml (renderStaffEditModalFragment renderedStaff maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates importedPayItems renderedRosterGroupIds maybeVenueMembership preferenceWeekdays renderedPreferences staffRsaDocument leaveRequest leaveRequests today weekOffset maybeRosterGroupId openSection)
                    else do
                        let selectedRosterGroupIds = renderedRosterGroupIds
                        let selectedShiftPreferences = renderedPreferences
                        render EditView { staff = renderedStaff, .. }
        let respondStaffUpdateSuccess mutationResult successMessage =
                if isHtmxRequest
                    then do
                        rosterGroup <- fetchCurrentVenueRosterGroupOrDefault maybeRosterGroupId
                        let actorTouchedResources =
                                mutationResult.liveMutationTouchedResources
                                    <> Set.fromList
                                        [ rosterWeekResource (unpackId rosterGroup.id) weekOffset
                                        , rosterSlotsContentResource (unpackId rosterGroup.id) weekOffset
                                        ]
                        respondWithRosterResourceInvalidation
                            rosterGroup.id
                            weekOffset
                            actorTouchedResources
                            rosterGridInnerAndStaffPanelFragments
                            (renderToastOob ToastBottomCenter (successToast successMessage))
                    else do
                        setSuccessMessage successMessage
                        redirectToPath $
                            maybe
                                (pathTo ShowRosterWeekAction { weekOffset })
                                (\rosterGroupId -> appendQueryParams (pathTo ShowRosterWeekAction { weekOffset }) [("rosterGroupId", tshow rosterGroupId)])
                                maybeRosterGroupId
        case submissionResult of
            Left errors -> do
                setErrorMessage (surfaceRequestFieldErrorsMessage errors)
                renderStaffEditResponse (attachSurfaceRequestFieldErrors errors staff) currentSelectedRosterGroupIds selectedShiftPreferences
            Right (SubmittedStaffShiftPreferences submitted) ->
                case parseShiftPreferenceSelections preferenceWeekdays submitted.submittedShiftPreferenceKeys of
                    Left preferenceError -> do
                        setErrorMessage preferenceError
                        renderStaffEditResponse staff currentSelectedRosterGroupIds selectedShiftPreferences
                    Right submittedSelections -> do
                        mutationResult <- updateStaffMember originalStaff staff currentSelectedRosterGroupIds submittedSelections Nothing Nothing
                        respondStaffUpdateSuccess mutationResult "Shift preferences updated"
            Right (SubmittedStaffProfileDetails submitted)
                | submitted.submittedProfileSection /= "profile" -> do
                    setErrorMessage "Choose a valid staff profile section."
                    renderStaffEditResponse staff submittedRosterGroupIds selectedShiftPreferences
                | otherwise -> do
                    maybeSelectedRosterGroupIds <- validateSubmittedRosterGroupIds submitted.submittedRosterGroupIds
                    maybeSubmittedVenueRole <- if canManageStaffPay then validateSubmittedStaffVenueRole staff maybeVenueMembership submitted.submittedVenueRole else pure (Just Nothing)
                    maybeSubmittedPayRateSelection <- if canManageStaffPay then parseSubmittedPayRateSelectionValue (fromMaybe "" submitted.submittedPayRateSelection) else pure (Just emptyStaffPayRateSelection)
                    let maybeSubmittedDefaultAwardLevelId = submittedAwardLevelId <$> maybeSubmittedPayRateSelection
                    let maybeSubmittedImportedXeroPayItemId = submittedImportedXeroPayItemId <$> maybeSubmittedPayRateSelection
                    staff
                        |> buildStaffFromSurfaceSubmission True canManageStaffPay maybeSubmittedDefaultAwardLevelId maybeSubmittedImportedXeroPayItemId submitted
                        |> ifValid \case
                            Left invalidStaff -> renderStaffEditResponse invalidStaff submittedRosterGroupIds selectedShiftPreferences
                            Right validStaff ->
                                case (maybeSelectedRosterGroupIds, maybeSubmittedVenueRole, maybeSubmittedDefaultAwardLevelId, maybeSubmittedImportedXeroPayItemId) of
                                    (Just selectedRosterGroupIds, Just submittedVenueRole, Just _, Just _) -> do
                                        mutationResult <- updateStaffMember originalStaff validStaff selectedRosterGroupIds selectedShiftPreferences maybeVenueMembership submittedVenueRole
                                        respondStaffUpdateSuccess mutationResult "Staff member updated"
                                    _ -> renderStaffEditResponse validStaff submittedRosterGroupIds selectedShiftPreferences

    action currentAction@NewTrialStaffInvitationAction { staffId } = runBepis currentAction BepisDialogAction do
        ensureVenueWritable
        staff <- fetch staffId
        ensureRecordInCurrentVenue staff.venueId
        if isAdoptableTrialStaff staff
            then do
                pendingInvitations <- fetchPendingTrialStaffInvitations staff
                let weekOffset = paramOrDefault @Int 0 "weekOffset"
                let maybeRosterGroupId = paramOrNothing "rosterGroupId"
                respondHtml (renderTrialStaffInvitationModalFragment staff pendingInvitations Nothing Nothing weekOffset maybeRosterGroupId)
            else respondWithTrialStaffInvitationFailure ineligibleTrialStaffInvitationMessage

    action currentAction@CreateTrialStaffInvitationAction { staffId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        staff <- fetch staffId
        ensureRecordInCurrentVenue staff.venueId
        if not (isAdoptableTrialStaff staff)
            then respondWithTrialStaffInvitationFailure ineligibleTrialStaffInvitationMessage
            else case parseTrialStaffInvitationEmail of
                Left message -> renderTrialStaffInvitationError staff message (Just submittedTrialStaffInvitationEmail)
                Right email ->
                    createTrialStaffInvitationMutation staff email >>= \case
                        Right _ -> respondWithTrialStaffInvitationSuccess ("Invitation sent to " <> email)
                        Left message -> renderTrialStaffInvitationError staff message (Just email)

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
                    Left message -> renderTrialStaffInvitationError staff message Nothing

emptyStaffPayRateSelection :: SubmittedPayRateSelection
emptyStaffPayRateSelection = SubmittedPayRateSelection Nothing Nothing True

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
            |> set #payAssignmentMode RosterOnly
            |> set #isActive True

renderNewStaffResponse :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => Staff -> [Id RosterGroup] -> [RosterGroup] -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> Int -> Maybe (Id RosterGroup) -> IO ()
renderNewStaffResponse staff selectedRosterGroupIds rosterGroups awardLevels awardLevelBaseRates importedPayItems weekOffset maybeRosterGroupId =
    if isHtmxRequest
        then respondHtml (renderNewStaffModalFragment staff rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds weekOffset maybeRosterGroupId)
        else render NewView { .. }

ineligibleTrialStaffInvitationMessage :: Text
ineligibleTrialStaffInvitationMessage = "Only active trial staff without a linked login can be invited."

submittedTrialStaffInvitationEmail :: (?request :: Request) => Text
submittedTrialStaffInvitationEmail = Text.strip (paramOrDefault "" "invitationEmail")

parseTrialStaffInvitationEmail :: (?request :: Request) => Either Text Text
parseTrialStaffInvitationEmail =
    case submittedTrialStaffInvitationEmail of
        "" -> Left "Invite email is required."
        email
            | Text.length email > 254 -> Left "Email must be 254 characters or fewer."
            | otherwise ->
                case isEmail email of
                    Success       -> Right email
                    Failure _     -> Left "Enter a valid email address."
                    FailureHtml _ -> Left "Enter a valid email address."

respondWithTrialStaffInvitationSuccess :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => Text -> IO ()
respondWithTrialStaffInvitationSuccess message =
    respondHtml [hsx|
        <div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>
        {renderToastOob ToastBottomCenter (successToast message)}
    |]

respondWithTrialStaffInvitationFailure :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => Text -> IO ()
respondWithTrialStaffInvitationFailure message =
    respondHtml [hsx|
        <div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>
        {renderToastOob ToastBottomCenter (errorToast message)}
    |]

renderTrialStaffInvitationError :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => Staff -> Text -> Maybe Text -> IO ()
renderTrialStaffInvitationError staff message submittedEmail
    | not (isAdoptableTrialStaff staff) = respondWithTrialStaffInvitationFailure ineligibleTrialStaffInvitationMessage
    | otherwise = do
        pendingInvitations <- fetchPendingTrialStaffInvitations staff
        let weekOffset = paramOrDefault @Int 0 "weekOffset"
        let maybeRosterGroupId = paramOrNothing "rosterGroupId"
        respondHtml (renderTrialStaffInvitationModalFragment staff pendingInvitations (Just message) submittedEmail weekOffset maybeRosterGroupId)

renderTrialStaffInvitationErrorForInvitation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => VenueInvitation -> Text -> IO ()
renderTrialStaffInvitationErrorForInvitation invitation message =
    case invitation.staffId of
        Nothing -> respondWithTrialStaffInvitationFailure message
        Just staffId -> fetch staffId >>= \staff -> renderTrialStaffInvitationError staff message Nothing

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

buildStaffFromSurfaceSubmission :: Bool -> Bool -> Maybe (Maybe (Id AwardLevel)) -> Maybe (Maybe (Id XeroImportedPayItem)) -> StaffProfileDetailsSubmission -> Staff -> Staff
buildStaffFromSurfaceSubmission canManageStaffStatus canManageStaffPay maybeSubmittedDefaultAwardLevelId maybeSubmittedImportedXeroPayItemId submitted staff =
    staff
        |> set #firstName submitted.submittedFirstName
        |> set #lastName submitted.submittedLastName
        |> set #preferredName (Just submitted.submittedPreferredName)
        |> set #phone submitted.submittedPhone
        |> set #emergencyContactName submitted.submittedEmergencyContactName
        |> set #emergencyContactPhone submitted.submittedEmergencyContactPhone
        |> set #idealShiftsPerWeek submitted.submittedIdealShiftsPerWeek
        |> normalizeMaybeTextField #preferredName
        |> applyStaffManagementFields
        |> requiredBoundedTextField #firstName 80
        |> requiredBoundedTextField #lastName 80
        |> validateField #preferredName (validateMaybe (boundedText 80))
        |> requiredBoundedTextField #phone 80
        |> requiredBoundedTextField #emergencyContactName 120
        |> requiredBoundedTextField #emergencyContactPhone 80
        |> validateField #idealShiftsPerWeek (isInRange (0, 7))
  where
    applyStaffManagementFields currentStaff =
        let withActive
                | canManageStaffStatus = maybe currentStaff (\value -> set #isActive value currentStaff) submitted.submittedIsActive
                | otherwise = currentStaff
         in if not canManageStaffPay
                then withActive
                else
                    let withEmploymentBasis = applyEmploymentBasis withActive
                        withAwardLevel = maybe withEmploymentBasis (\value -> set #defaultAwardLevelId value withEmploymentBasis) maybeSubmittedDefaultAwardLevelId
                        withImportedPayItem = maybe withAwardLevel (\value -> set #importedXeroPayItemId value withAwardLevel) maybeSubmittedImportedXeroPayItemId
                     in applySelectableStaffPayMode withImportedPayItem

    applyEmploymentBasis currentStaff =
        case Text.toLower <$> submitted.submittedEmploymentBasis of
            Just "permanent" -> currentStaff |> set #employmentBasis Permanent
            Just "casual" -> currentStaff |> set #employmentBasis Casual
            Just _ -> currentStaff |> attachFailure #employmentBasis "Choose a valid employment basis."
            Nothing -> currentStaff

validateSubmittedRosterGroupIds ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Maybe [UUID.UUID] ->
    IO (Maybe [Id RosterGroup])
validateSubmittedRosterGroupIds maybeSubmittedIds = do
    let submittedRosterGroupIds = nub (maybe [] (map Id) maybeSubmittedIds)
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

validateSubmittedStaffVenueRole :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Staff -> Maybe VenueMembership -> Maybe Text -> IO (Maybe (Maybe VenueRoleEnum))
validateSubmittedStaffVenueRole _ Nothing _ = pure (Just Nothing)
validateSubmittedStaffVenueRole staff (Just membership) maybeSubmittedRoleText =
    case maybeSubmittedRoleText >>= parseVenueRole of
        Nothing -> do
            setErrorMessage "Choose a valid staff role."
            pure Nothing
        Just submittedRole -> validateRole submittedRole
  where
    validateRole submittedRole = do
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

    currentUserCanAssignVenueRole existingRole submittedRole =
        currentUserIsSuperAdmin
            || hasRole VenueOwnerRole
            || (submittedRole /= VenueOwnerRole && existingRole /= Just VenueOwnerRole)

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
                    withPayReferences = case maybeSubmittedDefaultAwardLevelId of
                        Just defaultAwardLevelId -> withEmploymentBasis |> set #defaultAwardLevelId defaultAwardLevelId |> applyImportedPayItem
                        Nothing -> withEmploymentBasis |> applyImportedPayItem
                 in applySelectableStaffPayMode withPayReferences

        applyImportedPayItem currentStaff =
            case maybeSubmittedImportedXeroPayItemId of
                Just importedXeroPayItemId -> currentStaff |> set #importedXeroPayItemId importedXeroPayItemId
                Nothing -> currentStaff

applySelectableStaffPayMode :: Staff -> Staff
applySelectableStaffPayMode staff =
    case selectableStaffAssignmentMode staff.defaultAwardLevelId staff.importedXeroPayItemId of
        Just mode -> staff |> set #payAssignmentMode mode
        Nothing -> staff |> attachFailure #defaultAwardLevelId "Choose one pay-rate source."

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

requireSubmittedPayRateSelection ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    ByteString ->
    IO (Maybe SubmittedPayRateSelection)
requireSubmittedPayRateSelection paramName =
    case paramOrNothing @Text paramName of
        Nothing -> do
            setErrorMessage "Choose a default pay rate or No Timesheets (roster only)."
            pure Nothing
        Just value -> parseSubmittedPayRateSelectionValue value

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
