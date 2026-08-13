module Web.Controller.Staff where

import Application.Helper.Controller (parseVenueRole)
import Application.Helper.FrontendContract.AppShell (RemoveStaffOverlay)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             appShellActionByMarker)
import Application.Helper.FrontendContract.Surface.Profile (StaffProfileSectionValue (..))
import Application.Helper.FrontendContract.Surface.Request (attachSurfaceRequestFieldErrors,
                                                            surfaceRequestFieldErrorsMessage)
import Application.Helper.FrontendContract.Surface.Roster.Resource (rosterSlotsContentResource,
                                                                    rosterWeekResource)
import Application.Helper.Pay (rateEffectiveOn)
import Application.Helper.ProfileLeave (buildDefaultLeaveRequest,
                                        fetchStaffLeaveRequests)
import Application.Helper.RosterGroups (fetchCurrentVenueDefaultRosterGroup,
                                        fetchCurrentVenueRosterGroupOrDefault,
                                        fetchCurrentVenueRosterGroups,
                                        fetchStaffRosterGroupIds)
import Application.Helper.Staff (isAdoptableTrialStaff)
import Application.Helper.StaffShiftPreferences
import Application.Helper.SurfaceResource (LiveMutationResult (..))
import Application.Helper.Url (appendQueryParams)
import Application.Helper.View (DialogOverlayConfig (..), OverlayButton (..),
                                OverlayButtonAction (..),
                                OverlayFormMode (HtmxOverlayForm),
                                ToastOverlayPosition (..), dialogOverlayMountId,
                                errorToast, renderDialogOverlay, renderToastOob,
                                successToast)
import Application.Helper.TimeRules (currentOperationalDayForVenue)
import Application.Helper.WeekBoundaries (startOfWeekFor, venueWeekOffsetForDay)
import Application.PayAssignment (selectableStaffAssignmentMode)
import Application.StaffDefaults (applyVenueDefaultStaffPayAssignment,
                                  validateStaffAwardRateAvailability)
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Time.Calendar (Day, addDays)
import Data.Time.Clock (getCurrentTime, utctDay)
import qualified Data.UUID as UUID
import Text.Blaze.Html (Html)
import Web.Controller.Admin.Support (SubmittedPayRateSelection (..),
                                     fetchActiveImportedXeroPayItems,
                                     parseSubmittedPayRateSelectionValue)
import Web.Controller.Prelude
import Web.RosterWeeks.Projection (rosterGridInnerAndStaffPanelFragments)
import Web.RosterWeeks.Responses (respondWithRosterContentOob,
                                  respondWithRosterResourceInvalidation)
import Web.RosterWeeks.StaffOptions (fetchStaffPayConfigurationRequiredIds)
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
        anchorDate <- staffAnchorDateFromParamOrCurrent
        let maybeRosterGroupId = paramOrNothing @(Id RosterGroup) "rosterGroupId"
        staff <- buildNewTrialStaff
        rosterGroups <- fetchCurrentVenueRosterGroups
        awardLevels <- fetchAwardLevelsForStaffForm
        awardLevelBaseRates <- fetchAwardLevelBaseRatesForStaffForm
        importedPayItems <- fetchActiveImportedXeroPayItems
        defaultRosterGroup <- fetchCurrentVenueDefaultRosterGroup
        let selectedRosterGroupIds = [defaultRosterGroup.id]
        if isHtmxRequest
            then respondHtml (renderNewStaffModalFragment staff rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds anchorDate maybeRosterGroupId)
            else render NewView { .. }

    action currentAction@CreateStaffAction = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        anchorDate <- staffAnchorDateFromParamOrCurrent
        let maybeRosterGroupId = paramOrNothing @(Id RosterGroup) "rosterGroupId"
        rosterGroups <- fetchCurrentVenueRosterGroups
        awardLevels <- fetchAwardLevelsForStaffForm
        awardLevelBaseRates <- fetchAwardLevelBaseRatesForStaffForm
        importedPayItems <- fetchActiveImportedXeroPayItems
        maybeSelectedRosterGroupIds <- parseStaffRosterGroupIds
        let submittedRosterGroupIds = nub (mapMaybe parseRosterGroupIdText (paramTexts "rosterGroupIds"))
        let canManageStaffPay = hasRole VenueAdmin
        maybeSubmittedPayRateSelection <- if canManageStaffPay then requireSubmittedPayRateSelection "payRateSelection" else pure (Just emptyStaffPayRateSelection)
        let maybeSubmittedDefaultAwardLevelId = submittedAwardLevelId <$> maybeSubmittedPayRateSelection
        let maybeSubmittedImportedXeroPayItemId = submittedImportedXeroPayItemId <$> maybeSubmittedPayRateSelection
        staff <- buildNewTrialStaff
        staff
            |> buildStaff canManageStaffPay maybeSubmittedDefaultAwardLevelId maybeSubmittedImportedXeroPayItemId
            |> validateStaffAwardRateAvailability
                awardLevels
                awardLevelBaseRates
                (if canManageStaffPay
                    then "Choose an active award rate with a current rate for this employment basis."
                    else "The venue default staff rate is unavailable. Ask a venue admin to update Venue Settings.")
            |> ifValid \case
                Left invalidStaff -> renderNewStaffResponse invalidStaff submittedRosterGroupIds rosterGroups awardLevels awardLevelBaseRates importedPayItems anchorDate maybeRosterGroupId
                Right validStaff -> do
                    case (maybeSelectedRosterGroupIds, maybeSubmittedDefaultAwardLevelId, maybeSubmittedImportedXeroPayItemId) of
                        (Just selectedRosterGroupIds@(selectedRosterGroupId : _), Just _, Just _) -> do
                            _ <- createTrialStaffMember validStaff selectedRosterGroupIds
                            if isHtmxRequest
                                then do
                                    let rosterGroupId = fromMaybe selectedRosterGroupId maybeRosterGroupId
                                    compatibilityWeekOffset <- staffCompatibilityWeekOffset anchorDate
                                    respondWithRosterContentOob rosterGroupId compatibilityWeekOffset
                                else do
                                    setSuccessMessage "Trial staff placeholder created"
                                    redirectToPath $
                                        maybe
                                            (pathTo RosterWeeksAction)
                                            (\rosterGroupId -> appendQueryParams (pathTo RosterWeeksAction) [("rosterGroupId", tshow rosterGroupId)])
                                            maybeRosterGroupId
                        _ -> renderNewStaffResponse validStaff submittedRosterGroupIds rosterGroups awardLevels awardLevelBaseRates importedPayItems anchorDate maybeRosterGroupId

    action currentAction@EditStaffAction { staffId } = runBepis currentAction BepisFormAction do
        staff <- fetch staffId
        ensureRecordInCurrentVenue staff.venueId
        maybeLinkedUserEmail <- fetchStaffLinkedUserEmail staff
        maybeVenueMembership <- fetchStaffVenueMembership staff
        staffRemovalAllowed <- canRenderStaffRemoval staff
        staffPayConfigurationRequired <- staffRequiresPayConfigurationRemediation staff
        anchorDate <- staffAnchorDateFromParamOrCurrent
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
        if isHtmxRequest
            then respondHtml (renderStaffEditModalFragment staff staffPayConfigurationRequired maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds maybeVenueMembership staffRemovalAllowed preferenceWeekdays selectedShiftPreferences leaveRequest leaveRequests anchorDate maybeRosterGroupId openSection)
            else render EditView { .. }

    action currentAction@ShowStaffContentLiveFragmentAction { staffId } = runBepis currentAction BepisFragmentAction do
        staff <- fetch staffId
        ensureRecordInCurrentVenue staff.venueId
        maybeLinkedUserEmail <- fetchStaffLinkedUserEmail staff
        maybeVenueMembership <- fetchStaffVenueMembership staff
        anchorDate <- staffAnchorDateFromParamOrCurrent
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
        staffPayConfigurationRequired <- staffRequiresPayConfigurationRemediation staff
        leaveRequest <- buildDefaultLeaveRequest
        leaveRequests <- fetchStaffLeaveRequests staff
        respondHtml (renderStaffEditSectionFragment HtmxOverlayForm staff staffPayConfigurationRequired maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds maybeVenueMembership preferenceWeekdays selectedShiftPreferences leaveRequest leaveRequests anchorDate maybeRosterGroupId openSection)

    action currentAction@UpdateStaffAction { staffId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        staff <- fetch staffId
        ensureRecordInCurrentVenue staff.venueId
        let originalStaff = staff
        let submissionResult = parseStaffSurfaceSubmission
        maybeLinkedUserEmail <- fetchStaffLinkedUserEmail staff
        maybeVenueMembership <- fetchStaffVenueMembership staff
        staffRemovalAllowed <- canRenderStaffRemoval staff
        staffPayConfigurationRequired <- staffRequiresPayConfigurationRemediation staff
        anchorDate <- staffAnchorDateFromParamOrCurrent
        let maybeRosterGroupId = paramOrNothing "rosterGroupId"
        let openSection =
                case submissionResult of
                    Right (SubmittedStaffShiftPreferences _) -> "preferences"
                    Right (SubmittedStaffProfileDetails submitted) -> normalizeStaffOpenSection (inputValue submitted.submittedProfileSection)
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
        let canManageStaffPay = hasRole VenueAdmin
        let preferenceWeekdays = allPreferenceWeekdays venueConfig
        leaveRequest <- buildDefaultLeaveRequest
        leaveRequests <- fetchStaffLeaveRequests staff
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
                    then respondHtml (renderStaffEditModalFragment renderedStaff staffPayConfigurationRequired maybeLinkedUserEmail rosterGroups awardLevels awardLevelBaseRates importedPayItems renderedRosterGroupIds maybeVenueMembership staffRemovalAllowed preferenceWeekdays renderedPreferences leaveRequest leaveRequests anchorDate maybeRosterGroupId openSection)
                    else do
                        let selectedRosterGroupIds = renderedRosterGroupIds
                        let selectedShiftPreferences = renderedPreferences
                        render EditView { staff = renderedStaff, .. }
        let respondStaffUpdateSuccess mutationResult successMessage =
                if isHtmxRequest
                    then do
                        rosterGroup <- fetchCurrentVenueRosterGroupOrDefault maybeRosterGroupId
                        let windowStart = anchorDate
                        let windowEnd = addDays 7 windowStart
                        let compatibilityWeekOffset = venueWeekOffsetForDay venueConfig anchorDate
                        let actorTouchedResources =
                                mutationResult.liveMutationTouchedResources
                                    <> Set.fromList
                                        [ rosterWeekResource (unpackId rosterGroup.id) windowStart windowEnd
                                        , rosterSlotsContentResource (unpackId rosterGroup.id) windowStart windowEnd
                                        ]
                        respondWithRosterResourceInvalidation
                            rosterGroup.id
                            compatibilityWeekOffset
                            actorTouchedResources
                            rosterGridInnerAndStaffPanelFragments
                            (renderToastOob ToastBottomCenter (successToast successMessage))
                    else do
                        setSuccessMessage successMessage
                        redirectToPath $
                            maybe
                                (pathTo RosterWeeksAction)
                                (\rosterGroupId -> appendQueryParams (pathTo RosterWeeksAction) [("rosterGroupId", tshow rosterGroupId)])
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
                        updateStaffMember originalStaff staff currentSelectedRosterGroupIds submittedSelections Nothing Nothing >>= \case
                            Nothing -> do
                                setErrorMessage "This staff member is no longer active."
                                renderStaffEditResponse originalStaff currentSelectedRosterGroupIds selectedShiftPreferences
                            Just mutationResult -> respondStaffUpdateSuccess mutationResult "Shift preferences updated"
            Right (SubmittedStaffProfileDetails submitted)
                | submitted.submittedProfileSection /= StaffProfileDetailsSection -> do
                    setErrorMessage "Choose a valid staff profile section."
                    renderStaffEditResponse staff submittedRosterGroupIds selectedShiftPreferences
                | otherwise -> do
                    maybeSelectedRosterGroupIds <- validateSubmittedRosterGroupIds staff submitted.submittedRosterGroupIds
                    maybeSubmittedVenueRole <- if canManageStaffPay then validateSubmittedStaffVenueRole staff maybeVenueMembership submitted.submittedVenueRole else pure (Just Nothing)
                    maybeSubmittedPayRateSelection <- if canManageStaffPay then parseSubmittedPayRateSelectionValue (fromMaybe "" submitted.submittedPayRateSelection) else pure (Just emptyStaffPayRateSelection)
                    let maybeSubmittedDefaultAwardLevelId = submittedAwardLevelId <$> maybeSubmittedPayRateSelection
                    let maybeSubmittedImportedXeroPayItemId = submittedImportedXeroPayItemId <$> maybeSubmittedPayRateSelection
                    staff
                        |> buildStaffFromSurfaceSubmission canManageStaffPay maybeSubmittedDefaultAwardLevelId maybeSubmittedImportedXeroPayItemId submitted
                        |> ifValid \case
                            Left invalidStaff -> renderStaffEditResponse invalidStaff submittedRosterGroupIds selectedShiftPreferences
                            Right validStaff ->
                                case (maybeSelectedRosterGroupIds, maybeSubmittedVenueRole, maybeSubmittedDefaultAwardLevelId, maybeSubmittedImportedXeroPayItemId) of
                                    (Just selectedRosterGroupIds, Just submittedVenueRole, Just _, Just _) -> do
                                        updateStaffMember originalStaff validStaff selectedRosterGroupIds selectedShiftPreferences maybeVenueMembership submittedVenueRole >>= \case
                                            Nothing -> do
                                                setErrorMessage "This staff member is no longer active."
                                                renderStaffEditResponse originalStaff currentSelectedRosterGroupIds selectedShiftPreferences
                                            Just mutationResult -> respondStaffUpdateSuccess mutationResult "Staff member updated"
                                    _ -> renderStaffEditResponse validStaff submittedRosterGroupIds selectedShiftPreferences

    action currentAction@NewRemoveStaffAction { staffId } = runBepis currentAction BepisDialogAction do
        ensureCanRemoveStaff
        staff <- fetch staffId
        ensureRecordInCurrentVenue staff.venueId
        staffRemovalBlockReason staff >>= \case
            Just message -> do
                setErrorMessage message
                redirectTo EditStaffAction { staffId = staff.id }
            Nothing -> do
                anchorDate <- staffAnchorDateFromParamOrCurrent
                let maybeRosterGroupId = paramOrNothing @(Id RosterGroup) "rosterGroupId"
                respondHtml (renderStaffRemovalConfirmation staff anchorDate maybeRosterGroupId)

    action currentAction@RemoveStaffAction { staffId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        ensureCanRemoveStaff
        staff <- fetch staffId
        ensureRecordInCurrentVenue staff.venueId
        removeStaffMember staff >>= \case
            Left message -> do
                setErrorMessage message
                redirectTo EditStaffAction { staffId = staff.id }
            Right mutationResult ->
                if isHtmxRequest
                    then do
                        anchorDate <- staffAnchorDateFromParamOrCurrent
                        let maybeRosterGroupId = paramOrNothing @(Id RosterGroup) "rosterGroupId"
                        rosterGroup <- fetchCurrentVenueRosterGroupOrDefault maybeRosterGroupId
                        venueConfig <- fetchVenueConfig
                        let windowStart = anchorDate
                        let windowEnd = addDays 7 windowStart
                        let compatibilityWeekOffset = venueWeekOffsetForDay venueConfig anchorDate
                        let actorTouchedResources =
                                mutationResult.liveMutationTouchedResources
                                    <> Set.fromList
                                        [ rosterWeekResource (unpackId rosterGroup.id) windowStart windowEnd
                                        , rosterSlotsContentResource (unpackId rosterGroup.id) windowStart windowEnd
                                        ]
                        respondWithRosterResourceInvalidation
                            rosterGroup.id
                            compatibilityWeekOffset
                            actorTouchedResources
                            rosterGridInnerAndStaffPanelFragments
                            [hsx|
                                <div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>
                                {renderToastOob ToastBottomCenter (successToast "Staff member removed")}
                            |]
                    else do
                        setSuccessMessage "Staff member removed"
                        redirectTo RosterWeeksAction

    action currentAction@NewTrialStaffInvitationAction { staffId } = runBepis currentAction BepisDialogAction do
        ensureVenueWritable
        staff <- fetch staffId
        ensureRecordInCurrentVenue staff.venueId
        if isAdoptableTrialStaff staff
            then do
                pendingInvitations <- fetchPendingTrialStaffInvitations staff
                anchorDate <- staffAnchorDateFromParamOrCurrent
                let maybeRosterGroupId = paramOrNothing "rosterGroupId"
                now <- getCurrentTime
                respondHtml (renderTrialStaffInvitationModalFragment now staff pendingInvitations Nothing Nothing anchorDate maybeRosterGroupId)
            else respondWithTrialStaffInvitationFailure ineligibleTrialStaffInvitationMessage

    action currentAction@CreateTrialStaffInvitationAction { staffId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        staff <- fetch staffId
        ensureRecordInCurrentVenue staff.venueId
        if not (isAdoptableTrialStaff staff)
            then respondWithTrialStaffInvitationFailure ineligibleTrialStaffInvitationMessage
            else case validateTrialStaffInvitationEmail submittedTrialStaffInvitationEmail of
                Left message -> renderTrialStaffInvitationError staff message (Just submittedTrialStaffInvitationEmail)
                Right email ->
                    createTrialStaffInvitationMutation staff email >>= \case
                        Right _ -> respondWithTrialStaffInvitationSuccess ("Invitation queued for " <> email <> " and should arrive shortly")
                        Left message -> renderTrialStaffInvitationError staff message (Just email)

    action currentAction@RenewTrialStaffInvitationAction { venueInvitationId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        invitation <- fetch venueInvitationId
        ensureRecordInCurrentVenue invitation.venueId
        case invitation.staffId of
            Nothing -> renderTrialStaffInvitationErrorForInvitation invitation "Choose a staff-linked invitation to resend."
            Just staffId -> do
                staff <- fetch staffId
                ensureRecordInCurrentVenue staff.venueId
                let correctedEmail = Text.strip (fromMaybe invitation.email (paramOrNothing @Text "invitationEmail"))
                case validateTrialStaffInvitationEmail correctedEmail of
                    Left message -> renderTrialStaffInvitationError staff message (Just correctedEmail)
                    Right email ->
                        renewTrialStaffInvitationMutation staff invitation email >>= \case
                            Right _ -> respondWithTrialStaffInvitationSuccess ("Renewed invitation queued for " <> email <> " and should arrive shortly")
                            Left message -> renderTrialStaffInvitationError staff message (Just email)

staffAnchorDateFromParamOrCurrent :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO Day
staffAnchorDateFromParamOrCurrent = do
    venueConfig <- fetchVenueConfig
    requestedDay <- case paramOrNothing @Text "anchorDate" of
        Just rawAnchorDate -> parseIsoDayRouteParam rawAnchorDate
        Nothing -> currentOperationalDayForVenue venueConfig
    pure (startOfWeekFor venueConfig.rosterWeekStartsOn requestedDay)

staffCompatibilityWeekOffset :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Day -> IO Int
staffCompatibilityWeekOffset anchorDate = do
    venueConfig <- fetchVenueConfig
    pure (venueWeekOffsetForDay venueConfig anchorDate)

staffRequiresPayConfigurationRemediation :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Staff -> IO Bool
staffRequiresPayConfigurationRemediation staff =
    Set.member (unpackId staff.id) <$> fetchStaffPayConfigurationRequiredIds [staff]

renderStaffRemovalConfirmation :: (?context :: ControllerContext, ?request :: Request) => Staff -> Day -> Maybe (Id RosterGroup) -> Html
renderStaffRemovalConfirmation staff anchorDate maybeRosterGroupId =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = "Remove staff member"
        , dialogOverlayBody = [hsx|
            <p class="mb-0">Are you sure you want to remove this staff member? This cannot be undone.</p>
        |]
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons =
            [ OverlayButton
                { overlayButtonLabel = "Cancel"
                , overlayButtonClass = "btn btn-outline-secondary"
                , overlayButtonAction = OverlayCloseAction
                }
            , OverlayButton
                { overlayButtonLabel = "Remove staff member"
                , overlayButtonClass = "btn btn-danger"
                , overlayButtonAction = GeneratedDialogFormAction
                    (appShellActionByMarker @RemoveStaffOverlay)
                    AppShellActionRoute
                        { appShellActionRouteUrl = pathTo (RemoveStaffAction staff.id)
                        , appShellActionRouteFields = []
                        , appShellActionRouteCustomHtmx = []
                        , appShellActionRouteStandardUrl = Just (pathTo (RemoveStaffAction staff.id))
                        , appShellActionRouteExtraAttrs = []
                        }
                    returnFields
                    Nothing
                }
            ]
        , dialogOverlayDialogClass = ""
        }
  where
    returnFields =
        [("anchorDate", tshow anchorDate)]
            <> maybe [] (\rosterGroupId -> [("rosterGroupId", tshow rosterGroupId)]) maybeRosterGroupId

canRenderStaffRemoval :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Staff -> IO Bool
canRenderStaffRemoval staff
    | not (currentUserIsUnimpersonatedSuperAdmin || hasRole VenueAdmin) = pure False
    | otherwise = isNothing <$> staffRemovalBlockReason staff

ensureCanRemoveStaff :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
ensureCanRemoveStaff =
    redirectPermissionDeniedUnless (currentUserIsUnimpersonatedSuperAdmin || hasRole VenueAdmin) "Only venue admins and owners can remove staff members."

emptyStaffPayRateSelection :: SubmittedPayRateSelection
emptyStaffPayRateSelection = SubmittedPayRateSelection Nothing Nothing True

buildNewTrialStaff :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO Staff
buildNewTrialStaff = do
    venueConfig <- fetchVenueConfig
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
            |> applyVenueDefaultStaffPayAssignment venueConfig

renderNewStaffResponse :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => Staff -> [Id RosterGroup] -> [RosterGroup] -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> Day -> Maybe (Id RosterGroup) -> IO ()
renderNewStaffResponse staff selectedRosterGroupIds rosterGroups awardLevels awardLevelBaseRates importedPayItems anchorDate maybeRosterGroupId =
    if isHtmxRequest
        then respondHtml (renderNewStaffModalFragment staff rosterGroups awardLevels awardLevelBaseRates importedPayItems selectedRosterGroupIds anchorDate maybeRosterGroupId)
        else render NewView { .. }

ineligibleTrialStaffInvitationMessage :: Text
ineligibleTrialStaffInvitationMessage = "Only active trial staff without a linked login can be invited."

submittedTrialStaffInvitationEmail :: (?request :: Request) => Text
submittedTrialStaffInvitationEmail = Text.strip (paramOrDefault "" "invitationEmail")

validateTrialStaffInvitationEmail :: Text -> Either Text Text
validateTrialStaffInvitationEmail submittedEmail =
    case submittedEmail of
        "" -> Left "Invite email is required."
        email
            | Text.length email > 254 -> Left "Email must be 254 characters or fewer."
            | Text.any (`elem` ("<>\r\n" :: String)) email -> Left "Enter a valid email address."
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
        anchorDate <- staffAnchorDateFromParamOrCurrent
        let maybeRosterGroupId = paramOrNothing "rosterGroupId"
        now <- getCurrentTime
        respondHtml (renderTrialStaffInvitationModalFragment now staff pendingInvitations (Just message) submittedEmail anchorDate maybeRosterGroupId)

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
                |> filterWhere (#status, InvitationStatusEnumPending)
                |> orderByDesc #createdAt
                |> fetch

buildStaffFromSurfaceSubmission :: Bool -> Maybe (Maybe (Id AwardLevel)) -> Maybe (Maybe (Id XeroImportedPayItem)) -> StaffProfileDetailsSubmission -> Staff -> Staff
buildStaffFromSurfaceSubmission canManageStaffPay maybeSubmittedDefaultAwardLevelId maybeSubmittedImportedXeroPayItemId submitted staff =
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
    applyStaffManagementFields currentStaff
        | not canManageStaffPay = currentStaff
        | otherwise =
            let withEmploymentBasis = applyEmploymentBasis currentStaff
                withAwardLevel = maybe withEmploymentBasis (\value -> set #defaultAwardLevelId value withEmploymentBasis) maybeSubmittedDefaultAwardLevelId
                withImportedPayItem = maybe withAwardLevel (\value -> set #importedXeroPayItemId value withAwardLevel) maybeSubmittedImportedXeroPayItemId
             in applySelectableStaffPayMode withImportedPayItem

    applyEmploymentBasis currentStaff =
        maybe currentStaff (\employmentBasis -> currentStaff |> set #employmentBasis employmentBasis) submitted.submittedEmploymentBasis

validateSubmittedRosterGroupIds ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Staff ->
    Maybe [UUID.UUID] ->
    IO (Maybe [Id RosterGroup])
validateSubmittedRosterGroupIds staff maybeSubmittedIds = do
    existingRosterGroupIds <- fetchStaffRosterGroupIds staff
    resolveSubmittedRosterGroupIds existingRosterGroupIds (nub (maybe [] (map Id) maybeSubmittedIds))

resolveSubmittedRosterGroupIds ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    [Id RosterGroup] ->
    [Id RosterGroup] ->
    IO (Maybe [Id RosterGroup])
resolveSubmittedRosterGroupIds retainableRosterGroupIds submittedRosterGroupIds = do
    rosterGroups <- fetchCurrentVenueRosterGroups
    let currentVenueRosterGroupIds = map (.id) rosterGroups
    let activeRosterGroupIds = map (.id) (filter (.isActive) rosterGroups)
    let submittedInactiveRosterGroupIds = filter (`notElem` activeRosterGroupIds) submittedRosterGroupIds
    let resolvedRosterGroupIds =
            case activeRosterGroupIds of
                [soleActiveRosterGroupId] -> nub (soleActiveRosterGroupId : submittedRosterGroupIds)
                _                         -> submittedRosterGroupIds
    if not (all (`elem` currentVenueRosterGroupIds) submittedRosterGroupIds)
        then do
            setErrorMessage "Choose roster groups from the current venue."
            pure Nothing
        else if not (all (`elem` retainableRosterGroupIds) submittedInactiveRosterGroupIds)
            then do
                setErrorMessage "Inactive roster groups can only be retained from this staff member's existing assignments."
                pure Nothing
        else if null activeRosterGroupIds
            then do
                setErrorMessage "Configure an active roster group before assigning staff."
                pure Nothing
        else if not (any (`elem` activeRosterGroupIds) resolvedRosterGroupIds)
            then do
                setErrorMessage "Choose at least one active roster group for this staff member."
                pure Nothing
        else pure (Just resolvedRosterGroupIds)

validateSubmittedStaffVenueRole :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Staff -> Maybe VenueMembership -> Maybe VenueRoleEnum -> IO (Maybe (Maybe VenueRoleEnum))
validateSubmittedStaffVenueRole _ Nothing _ = pure (Just Nothing)
validateSubmittedStaffVenueRole staff (Just membership) maybeSubmittedRole =
    case maybeSubmittedRole of
        Nothing -> do
            setErrorMessage "Choose a valid staff role."
            pure Nothing
        Just submittedRole -> validateRole submittedRole
  where
    validateRole submittedRole = do
        let existingRole = membership.venueRole
        if not (canAssignVenueRole currentUserIsUnimpersonatedSuperAdmin effectiveVenueRoleOrNothing existingRole submittedRole)
            then do
                setErrorMessage "Only the venue owner or a super admin can assign venue owner access."
                pure Nothing
            else if membership.userId == unpackId effectiveCurrentUser.id && not (hasVenueRole submittedRole VenueAdmin)
                then do
                    setErrorMessage "You cannot remove your own admin access."
                    pure Nothing
                else if existingRole == VenueOwner && submittedRole /= VenueOwner
                    then do
                        ownerCount <- activeVenueOwnerCount
                        if ownerCount <= 1
                            then do
                                setErrorMessage "Each venue needs at least one owner."
                                pure Nothing
                            else pure (Just (Just submittedRole))
                    else pure (Just (Just submittedRole))

buildStaff :: (?request :: Request) => Bool -> Maybe (Maybe (Id AwardLevel)) -> Maybe (Maybe (Id XeroImportedPayItem)) -> Staff -> Staff
buildStaff canManageStaffPay maybeSubmittedDefaultAwardLevelId maybeSubmittedImportedXeroPayItemId staff =
    staff
        |> requireParam #firstName "firstName" "First name is required"
        |> requireParam #lastName "lastName" "Last name is required"
        |> requireParam #phone "phone" "Phone is required"
        |> requireParam #emergencyContactName "emergencyContactName" "Emergency contact name is required"
        |> requireParam #emergencyContactPhone "emergencyContactPhone" "Emergency contact phone is required"
        |> requireParam #idealShiftsPerWeek "idealShiftsPerWeek" "Ideal shifts per week is required"
        |> fill @'["firstName", "lastName", "preferredName", "phone", "emergencyContactName", "emergencyContactPhone", "idealShiftsPerWeek"]
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
        |> filterWhere (#venueRole, VenueOwner)
        |> filterWhere (#isActive, True)
        |> fetchCount

parseStaffRosterGroupIds :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO (Maybe [Id RosterGroup])
parseStaffRosterGroupIds = do
    let submittedRosterGroupTexts = nub (paramTexts "rosterGroupIds")
    let submittedRosterGroupIds = mapMaybe parseRosterGroupIdText submittedRosterGroupTexts
    if length submittedRosterGroupIds /= length submittedRosterGroupTexts
        then do
            setErrorMessage "Choose roster groups from the current venue."
            pure Nothing
        else resolveSubmittedRosterGroupIds [] submittedRosterGroupIds

parseRosterGroupIdText :: Text -> Maybe (Id RosterGroup)
parseRosterGroupIdText value =
    Id <$> parseUUIDText value

normalizeStaffOpenSection :: Text -> Text
normalizeStaffOpenSection section
    | section `elem` ["profile", "preferences", "security", "leave"] = section
    | otherwise = ""
