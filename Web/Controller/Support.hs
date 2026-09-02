module Web.Controller.Support where

import Application.Async.Queue (EnqueueAppJobResult (..),
                                fetchActiveAppJobByDedupeKey,
                                fetchLatestAppJobByKind)
import Application.FwcMapd.Job (enqueueFwcMapdRefreshJob,
                                fwcMapdRefreshJobDedupeKey,
                                fwcMapdRefreshJobKind)
import Application.Helper.Feedback (SupportUnreadFeedbackCount (..),
                                    allowedFeedbackPriorities,
                                    allowedFeedbackStatuses,
                                    fetchSupportUnreadFeedbackCount)
import Application.Helper.FrontendContract.Surface.Support.Resource
import Application.Helper.FwcMapd (FwcMapdAdminData, fetchFwcMapdAdminData)
import Application.Helper.SurfaceResource (SurfaceResourceValue,
                                           liveMutationResult,
                                           liveMutationValue)
import Application.Helper.VenueInvitation (accountInvitationConflictMessage,
                                           activeVenueInvitationsForEmail,
                                           registeredInvitationAccountExists)
import Application.Helper.VenueOnboardingInvitation (venueOnboardingInvitationIsActive,
                                                     venueOnboardingInvitationLifetime)
import Application.Helper.View (PageHelpTopicId (..), lookupPageHelpTopic)
import Application.InvitationDelivery.Enqueue (enqueueVenueOnboardingInvitationEmail)
import Application.PublicHolidays.Coverage (PublicHolidayCoverageYear,
                                            fetchPublicHolidayCoverage)
import Application.PublicHolidays.Job (enqueuePublicHolidayRefreshJob,
                                       publicHolidayRefreshJobDedupeKey,
                                       publicHolidayRefreshJobKind)
import Application.Support.LiveUpdates
import Application.VenueInvitation.Mutations (withVenueInvitationEmailLockInCurrentTransaction)
import Application.VenueOnboardingInvitation.Mutations (withVenueOnboardingInvitationRenewalLock)
import Application.Xero.Timesheets.Diagnostic (XeroTimesheetDiagnosticError (..),
                                               fetchXeroTimesheetDiagnostic)
import Control.Monad (forM, forM_, guard, void)
import Data.Char (isControl)
import Data.Coerce (coerce)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import Data.Time.Calendar (Day)
import Data.Time.Format (defaultTimeLocale, parseTimeM)
import qualified Data.UUID as UUID
import qualified Network.HTTP.Types.URI as URI
import Text.Read (readMaybe)
import Web.Controller.Prelude
import Web.RosterWeeks.Paths (supportVenueSwitchReturnPath)
import Web.SurfaceInvalidation (withDurableLiveMutation)
import Web.View.Support.Index

data OnboardingRenewalResult
    = OnboardingRenewed VenueOnboardingInvitation
    | OnboardingRenewalUnavailable
    | OnboardingRenewalEmailConflict

instance Controller SupportController where
    beforeAction = bepisBeforeAction BepisSupportController do
        annotateTelemetryAction
        ensureIsUser
        ensureSupportAccess

    action currentAction@SupportAction = runBepis currentAction BepisPageAction do
        onboardingInvitations <- fetchVenueOnboardingInvitations
        passkeys <- fetchCurrentUserPasskeys
        canAddPasskey <- supportCanAddPasskey passkeys
        now <- getCurrentTime
        (fwcMapdAdminData, latestFwcMapdRefreshJob, activeFwcMapdRefreshJob) <- fetchFwcMapdAwardRatesSectionData
        (publicHolidayCoverage, latestPublicHolidayRefreshJob, activePublicHolidayRefreshJob) <- fetchPublicHolidaySectionData
        feedbackRows <- fetchSupportFeedbackRows
        SupportUnreadFeedbackCount unreadFeedbackCount <- fetchSupportUnreadFeedbackCount
        let onboardingInvitation = buildSupportVenueOnboardingInvitationForm
        let xeroDiagnosticSubmissionId = ""
        let xeroTimesheetDiagnostic = Nothing
        let xeroTimesheetDiagnosticError = Nothing
        render IndexView { .. }

    action currentAction@RunXeroTimesheetDiagnosticAction = runBepis currentAction BepisMutationAction do
        ensureCurrentVenue
        ensureFreshPasskeyReady
        onboardingInvitations <- fetchVenueOnboardingInvitations
        passkeys <- fetchCurrentUserPasskeys
        canAddPasskey <- supportCanAddPasskey passkeys
        now <- getCurrentTime
        (fwcMapdAdminData, latestFwcMapdRefreshJob, activeFwcMapdRefreshJob) <- fetchFwcMapdAwardRatesSectionData
        (publicHolidayCoverage, latestPublicHolidayRefreshJob, activePublicHolidayRefreshJob) <- fetchPublicHolidaySectionData
        feedbackRows <- fetchSupportFeedbackRows
        SupportUnreadFeedbackCount unreadFeedbackCount <- fetchSupportUnreadFeedbackCount
        let onboardingInvitation = buildSupportVenueOnboardingInvitationForm
        let xeroDiagnosticSubmissionId = Text.strip (paramOrDefault @Text "" "submissionId")
        let maybeSubmissionUuid
                | Text.null xeroDiagnosticSubmissionId || Text.length xeroDiagnosticSubmissionId > 64 = Nothing
                | otherwise = parseUUIDText xeroDiagnosticSubmissionId
        (xeroTimesheetDiagnostic, xeroTimesheetDiagnosticError) <-
            case maybeSubmissionUuid of
                Nothing -> pure (Nothing, Just "Enter a valid Bepis Xero submission ID.")
                Just submissionUuid -> do
                    maybeSubmission <-
                        query @XeroTimesheetSubmission
                            |> filterWhere (#id, Id submissionUuid)
                            |> filterWhere (#venueId, unpackId currentVenue.id)
                            |> fetchOneOrNothing
                    case maybeSubmission of
                        Nothing -> pure (Nothing, Just "No Xero submission was found for the current support venue.")
                        Just submission -> do
                            maybeConnection <-
                                query @XeroConnection
                                    |> filterWhere (#id, Id submission.xeroConnectionId)
                                    |> filterWhere (#venueId, unpackId currentVenue.id)
                                    |> fetchOneOrNothing
                            case maybeConnection of
                                Nothing -> pure (Nothing, Just "The submission's Xero connection is unavailable for this venue.")
                                Just connection ->
                                    fetchXeroTimesheetDiagnostic submission connection >>= \case
                                        Left diagnosticError -> pure (Nothing, Just (xeroTimesheetDiagnosticErrorMessage diagnosticError))
                                        Right diagnostic -> pure (Just diagnostic, Nothing)
        render IndexView { .. }

    action currentAction@ShowFwcMapdAwardRatesSectionAction = runBepis currentAction BepisPageAction do
        (fwcMapdAdminData, latestFwcMapdRefreshJob, activeFwcMapdRefreshJob) <- fetchFwcMapdAwardRatesSectionData
        respondHtml (renderAwardRatesSection fwcMapdAdminData latestFwcMapdRefreshJob activeFwcMapdRefreshJob)

    action currentAction@ShowPublicHolidaysSectionAction = runBepis currentAction BepisPageAction do
        (publicHolidayCoverage, latestPublicHolidayRefreshJob, activePublicHolidayRefreshJob) <- fetchPublicHolidaySectionData
        respondHtml (renderPublicHolidaysSection publicHolidayCoverage latestPublicHolidayRefreshJob activePublicHolidayRefreshJob)

    action currentAction@CreateSupportVenueOnboardingInvitationAction = runBepis currentAction BepisMutationAction do
        onboardingInvitations <- fetchVenueOnboardingInvitations
        passkeys <- fetchCurrentUserPasskeys
        canAddPasskey <- supportCanAddPasskey passkeys
        (fwcMapdAdminData, latestFwcMapdRefreshJob, activeFwcMapdRefreshJob) <- fetchFwcMapdAwardRatesSectionData
        (publicHolidayCoverage, latestPublicHolidayRefreshJob, activePublicHolidayRefreshJob) <- fetchPublicHolidaySectionData
        feedbackRows <- fetchSupportFeedbackRows
        SupportUnreadFeedbackCount unreadFeedbackCount <- fetchSupportUnreadFeedbackCount
        now <- getCurrentTime
        let xeroDiagnosticSubmissionId = ""
        let xeroTimesheetDiagnostic = Nothing
        let xeroTimesheetDiagnosticError = Nothing
        let onboardingInvitation = buildSupportVenueOnboardingInvitationForm |> fill @'["email"] |> normalizeTextField #email |> modify #email Text.toLower
        onboardingInvitation
            |> validateField #email nonEmpty
            |> validateField #email isEmail
            |> ifValid \case
                Left onboardingInvitation -> render IndexView { .. }
                Right onboardingInvitation -> do
                    creation <- withTransaction $
                        withVenueInvitationEmailLockInCurrentTransaction onboardingInvitation.email do
                            createdAt <- getCurrentTime
                            accountExists <- registeredInvitationAccountExists onboardingInvitation.email
                            activeVenueInvitations <- activeVenueInvitationsForEmail createdAt onboardingInvitation.email
                            if accountExists || not (null activeVenueInvitations)
                                then pure (Left accountInvitationConflictMessage)
                                else do
                                    revokePendingVenueOnboardingInvitations onboardingInvitation.email Nothing createdAt
                                    createdInvitation <- onboardingInvitation
                                        |> set #invitedByUserId (Just (unpackId currentUser.id))
                                        |> set #status (InvitationStatusEnumPending)
                                        |> set #deliveryStatus (Queued)
                                        |> set #expiresAt (Just (addUTCTime venueOnboardingInvitationLifetime createdAt))
                                        |> createRecord
                                    void (enqueueVenueOnboardingInvitationEmail (Just currentUser.id) createdInvitation)
                                    pure (Right createdInvitation)
                    case creation of
                        Left conflictMessage -> do
                            let onboardingInvitationWithConflict = onboardingInvitation
                                    |> validateField #email (const (Failure conflictMessage))
                            render IndexView { onboardingInvitation = onboardingInvitationWithConflict, .. }
                        Right invitation -> do
                            setSuccessMessage ("Venue owner invitation queued for " <> invitation.email <> " and should arrive shortly")
                            redirectTo SupportAction

    action currentAction@RenewSupportVenueOnboardingInvitationAction { onboardingInvitationId } = runBepis currentAction BepisMutationAction do
        invitationForDefaultEmail <- query @VenueOnboardingInvitation
            |> filterWhere (#id, onboardingInvitationId)
            |> fetchOneOrNothing
        let submittedEmail = paramOrNothing @Text "email"
        let replacementForm =
                buildSupportVenueOnboardingInvitationForm
                    |> set #email (fromMaybe (maybe "" (.email) invitationForDefaultEmail) submittedEmail)
                    |> normalizeTextField #email
                    |> modify #email Text.toLower
                    |> validateField #email nonEmpty
                    |> validateField #email (boundedText 254)
                    |> validateField #email isEmail
        case replacementForm.meta.annotations of
            [] -> do
                maybeRenewalResult <- withVenueOnboardingInvitationRenewalLock (unpackId onboardingInvitationId) replacementForm.email do
                    invitationOrNothing <- query @VenueOnboardingInvitation
                        |> filterWhere (#id, onboardingInvitationId)
                        |> filterWhere (#status, InvitationStatusEnumPending)
                        |> filterWhere (#acceptedAt, Nothing)
                        |> fetchOneOrNothing
                    case invitationOrNothing of
                        Nothing -> pure OnboardingRenewalUnavailable
                        Just invitationToReplace -> do
                            renewedAt <- getCurrentTime
                            accountExists <- registeredInvitationAccountExists replacementForm.email
                            activeVenueInvitations <- activeVenueInvitationsForEmail renewedAt replacementForm.email
                            if accountExists || not (null activeVenueInvitations)
                                then pure OnboardingRenewalEmailConflict
                                else do
                                    revokePendingVenueOnboardingInvitations replacementForm.email (Just invitationToReplace.id) renewedAt
                                    void $
                                        invitationToReplace
                                            |> set #status (Revoked)
                                            |> set #updatedAt renewedAt
                                            |> updateRecord
                                    replacement <- replacementForm
                                        |> set #invitedByUserId (Just (unpackId currentUser.id))
                                        |> set #expiresAt (Just (addUTCTime venueOnboardingInvitationLifetime renewedAt))
                                        |> createRecord
                                    void (enqueueVenueOnboardingInvitationEmail (Just currentUser.id) replacement)
                                    pure (OnboardingRenewed replacement)
                case fromMaybe OnboardingRenewalUnavailable maybeRenewalResult of
                    OnboardingRenewed replacement ->
                        setSuccessMessage ("Renewed venue owner invitation queued for " <> replacement.email <> " and should arrive shortly")
                    OnboardingRenewalUnavailable ->
                        setErrorMessage "Only pending, unaccepted owner invitations can be renewed."
                    OnboardingRenewalEmailConflict ->
                        setErrorMessage accountInvitationConflictMessage
            _ ->
                setErrorMessage "Enter a valid owner email address."
        redirectTo SupportAction

    action currentAction@CreateFwcMapdRefreshJobAction = runBepis currentAction BepisMutationAction do
        enqueueResult <- liveMutationValue <$> withDurableLiveMutation "support.award_rates.enqueue" do
            result <- enqueueFwcMapdRefreshJob (Just (unpackId currentUser.id))
            pure (liveMutationResult result [supportAwardRatesResource])
        case enqueueResult of
            EnqueuedAppJob _ ->
                setSuccessMessage "Award rate refresh queued."
            ExistingActiveAppJob _ ->
                setSuccessMessage "Award rate refresh is already queued or running."
        respondToAwardRatesRefresh

    action currentAction@CreatePublicHolidayRefreshJobAction = runBepis currentAction BepisMutationAction do
        enqueueResult <- liveMutationValue <$> withDurableLiveMutation "support.public_holidays.enqueue" do
            result <- enqueuePublicHolidayRefreshJob (Just (unpackId currentUser.id))
            pure (liveMutationResult result [supportPublicHolidaysResource])
        case enqueueResult of
            EnqueuedAppJob _ ->
                setSuccessMessage "Public holiday refresh queued."
            ExistingActiveAppJob _ ->
                setSuccessMessage "Public holiday refresh is already queued or running."
        respondToPublicHolidayRefresh

    action currentAction@MarkFeedbackReadAction { feedbackItemId } = runBepis currentAction BepisMutationAction do
        feedbackItem <- fetch feedbackItemId
        _ <- markFeedbackRead feedbackItem
        setSuccessMessage "Feedback marked read."
        redirectTo SupportAction

    action currentAction@MarkAllFeedbackReadAction = runBepis currentAction BepisMutationAction do
        unreadFeedbackItems <- query @UserFeedbackItem
            |> filterWhere (#readAt, Nothing)
            |> fetch
        forM_ unreadFeedbackItems markFeedbackRead
        setSuccessMessage "All feedback marked read."
        redirectTo SupportAction

    action currentAction@UpdateFeedbackStatusAction { feedbackItemId } = runBepis currentAction BepisMutationAction do
        let status = param @Text "status"
        if status `elem` allowedFeedbackStatuses
            then do
                feedbackItem <- fetch feedbackItemId
                now <- getCurrentTime
                _ <- feedbackItem
                    |> set #status status
                    |> setResolvedFieldsForStatus status now
                    |> markFeedbackReadFields now
                    |> updateRecord
                setSuccessMessage "Feedback status updated."
            else setErrorMessage "Choose a valid feedback status."
        redirectTo SupportAction

    action currentAction@UpdateFeedbackPriorityAction { feedbackItemId } = runBepis currentAction BepisMutationAction do
        let priority = param @Text "priority"
        if priority `elem` allowedFeedbackPriorities
            then do
                feedbackItem <- fetch feedbackItemId
                now <- getCurrentTime
                _ <- feedbackItem
                    |> set #priority priority
                    |> markFeedbackReadFields now
                    |> updateRecord
                setSuccessMessage "Feedback priority updated."
            else setErrorMessage "Choose a valid feedback priority."
        redirectTo SupportAction

    action currentAction@UpdateFeedbackSupportNoteAction { feedbackItemId } = runBepis currentAction BepisMutationAction do
        feedbackItem <- fetch feedbackItemId
        now <- getCurrentTime
        let supportNote = Text.take 3000 (Text.strip (paramOrDefault @Text "" "supportNote"))
        _ <- feedbackItem
            |> set #supportNote (if Text.null supportNote then Nothing else Just supportNote)
            |> markFeedbackReadFields now
            |> updateRecord
        setSuccessMessage "Feedback note updated."
        redirectTo SupportAction

    action currentAction@StartSupportImpersonationAction = runBepis currentAction BepisMutationAction do
        ensureCurrentVenue
        let nextPath = paramOrNothing @Text "next"
        ensureFreshPasskeyReadyFor (safeSupportReturnPathOrRoster nextPath)
        case paramOrNothing @Text "userId" >>= parseUUIDText of
            Nothing -> renderAccessDenied
            Just userId ->
                enterCurrentVenueImpersonation (Id userId) >>= \case
                    Nothing -> renderAccessDenied
                    Just impersonationContext -> do
                        setSuccessMessage "Support impersonation started."
                        destination <- authorizedSupportReturnPath impersonationContext nextPath
                        redirectAfterImpersonationTransition destination

    action currentAction@ExitSupportImpersonationAction = runBepis currentAction BepisMutationAction do
        let nextPath = paramOrNothing @Text "next"
        void (exitCurrentImpersonation "manual_exit")
        setSuccessMessage "Returned to Super admin mode."
        destination <- founderSupportReturnPath nextPath
        redirectAfterImpersonationTransition destination

    action currentAction@SwitchSupportImpersonationAction = runBepis currentAction BepisMutationAction do
        let selectedUserId = Text.strip (paramOrDefault @Text "" "userId")
        let nextPath = paramOrNothing @Text "next"
        if Text.null selectedUserId
            then do
                void (exitCurrentImpersonation "selector_exit")
                setSuccessMessage "Returned to Super admin mode."
                destination <- founderSupportReturnPath nextPath
                redirectAfterImpersonationTransition destination
            else do
                ensureCurrentVenue
                ensureFreshPasskeyReadyFor (safeSupportReturnPathOrRoster nextPath)
                case parseUUIDText selectedUserId of
                    Nothing -> renderAccessDenied
                    Just userId ->
                        enterCurrentVenueImpersonation (Id userId) >>= \case
                            Nothing -> renderAccessDenied
                            Just impersonationContext -> do
                                setSuccessMessage "Support impersonation started."
                                destination <- authorizedSupportReturnPath impersonationContext nextPath
                                redirectAfterImpersonationTransition destination

    action currentAction@SwitchSupportVenueAction = runBepis currentAction BepisPageAction do
        void (exitCurrentImpersonation "venue_switch")
        let venueId = (coerce (param @UUID "venueId") :: Id Venue)
        let nextPath = fromMaybe (pathTo SupportAction) (paramOrNothing @Text "next")
        venue <- query @Venue
            |> filterWhere (#id, venueId)
            |> filterWhere (#status, Active)
            |> fetchOneOrNothing

        case venue of
            Nothing -> do
                setErrorMessage "Choose an active venue."
                redirectTo SupportAction
            Just currentVenue -> do
                setSession currentVenueSessionKey currentVenue.id
                setSuccessMessage ("Support venue switched to " <> currentVenue.name)
                if isSafeSupportVenueReturnPath nextPath
                    then redirectToPath (supportVenueSwitchReturnPath nextPath)
                    else redirectTo SupportAction

xeroTimesheetDiagnosticErrorMessage :: XeroTimesheetDiagnosticError -> Text
xeroTimesheetDiagnosticErrorMessage = \case
    DiagnosticMissingTimesheetReference -> "The selected submission has no stored Xero timesheet reference."
    DiagnosticXeroConfigurationUnavailable -> "Xero configuration is unavailable."
    DiagnosticXeroConnectionUnavailable -> "The Xero connection could not be refreshed. Reconnect Xero and try again."
    DiagnosticXeroTimesheetUnavailable -> "Xero could not return the selected timesheet."
    DiagnosticXeroTimesheetScopeMismatch -> "Xero returned a timesheet outside the selected submission scope."

buildSupportVenueOnboardingInvitationForm :: VenueOnboardingInvitation
buildSupportVenueOnboardingInvitationForm =
    newRecord @VenueOnboardingInvitation
        |> set #status (InvitationStatusEnumPending)
        |> set #deliveryStatus (Queued)

fetchSupportFeedbackRows :: (?modelContext :: ModelContext) => IO [SupportFeedbackRow]
fetchSupportFeedbackRows = do
    feedbackItems <- query @UserFeedbackItem
        |> orderByDesc #createdAt
        |> limit 50
        |> fetch
    forM feedbackItems \supportFeedbackItem -> do
        venue <- fetch (coerce supportFeedbackItem.venueId :: Id Venue)
        submitter <- fetch (coerce supportFeedbackItem.submittedByUserId :: Id User)
        pure SupportFeedbackRow
            { supportFeedbackItem
            , supportFeedbackVenueName = venue.name
            , supportFeedbackSubmitter = submitter.email
            }

markFeedbackRead :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => UserFeedbackItem -> IO UserFeedbackItem
markFeedbackRead feedbackItem
    | isJust feedbackItem.readAt = pure feedbackItem
    | otherwise = do
        now <- getCurrentTime
        feedbackItem
            |> markFeedbackReadFields now
            |> updateRecord

markFeedbackReadFields :: (?context :: ControllerContext, ?request :: Request) => UTCTime -> UserFeedbackItem -> UserFeedbackItem
markFeedbackReadFields now feedbackItem =
    feedbackItem
        |> set #readAt (Just now)
        |> set #readByUserId (Just (unpackId currentUser.id))

setResolvedFieldsForStatus :: (?context :: ControllerContext, ?request :: Request) => Text -> UTCTime -> UserFeedbackItem -> UserFeedbackItem
setResolvedFieldsForStatus status now feedbackItem
    | status == "done" || status == "closed" =
        feedbackItem
            |> set #resolvedAt (Just now)
            |> set #resolvedByUserId (Just (unpackId currentUser.id))
    | otherwise =
        feedbackItem
            |> set #resolvedAt Nothing
            |> set #resolvedByUserId Nothing

fetchVenueOnboardingInvitations :: (?modelContext :: ModelContext) => IO [VenueOnboardingInvitation]
fetchVenueOnboardingInvitations =
    query @VenueOnboardingInvitation
        |> orderByDesc #createdAt
        |> fetch

revokePendingVenueOnboardingInvitations ::
    (?modelContext :: ModelContext) =>
    Text ->
    Maybe (Id VenueOnboardingInvitation) ->
    UTCTime ->
    IO ()
revokePendingVenueOnboardingInvitations email excludedInvitationId revokedAt = do
    pendingInvitations <- query @VenueOnboardingInvitation
        |> filterWhereCaseInsensitive (#email, email)
        |> filterWhere (#status, InvitationStatusEnumPending)
        |> filterWhere (#acceptedAt, Nothing)
        |> fetch
    forM_ pendingInvitations \invitation ->
        when (Just invitation.id /= excludedInvitationId) do
            invitation
                |> set #status (Revoked)
                |> set #updatedAt revokedAt
                |> updateRecordDiscardResult

fetchFwcMapdAwardRatesSectionData ::
    (?modelContext :: ModelContext) =>
    IO (FwcMapdAdminData, Maybe AppJob, Maybe AppJob)
fetchFwcMapdAwardRatesSectionData = do
    fwcMapdAdminData <- fetchFwcMapdAdminData
    latestFwcMapdRefreshJob <- fetchLatestAppJobByKind fwcMapdRefreshJobKind
    activeFwcMapdRefreshJob <- fetchActiveAppJobByDedupeKey fwcMapdRefreshJobDedupeKey
    pure (fwcMapdAdminData, latestFwcMapdRefreshJob, activeFwcMapdRefreshJob)

fetchPublicHolidaySectionData ::
    (?modelContext :: ModelContext) =>
    IO ([PublicHolidayCoverageYear], Maybe AppJob, Maybe AppJob)
fetchPublicHolidaySectionData = do
    publicHolidayCoverage <- fetchPublicHolidayCoverage
    latestPublicHolidayRefreshJob <- fetchLatestAppJobByKind publicHolidayRefreshJobKind
    activePublicHolidayRefreshJob <- fetchActiveAppJobByDedupeKey publicHolidayRefreshJobDedupeKey
    pure (publicHolidayCoverage, latestPublicHolidayRefreshJob, activePublicHolidayRefreshJob)

supportCanAddPasskey :: (?context :: ControllerContext) => [Passkey] -> IO Bool
supportCanAddPasskey passkeys
    | currentUserIsImpersonating = pure False
    | otherwise = do
        recoveryVerified <- isCurrentUserPasskeyRecoveryVerified
        pure (null passkeys || recoveryVerified)

respondToAwardRatesRefresh :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
respondToAwardRatesRefresh =
    if isHtmxRequest
        then do
            (fwcMapdAdminData, latestFwcMapdRefreshJob, activeFwcMapdRefreshJob) <- fetchFwcMapdAwardRatesSectionData
            respondHtml (renderAwardRatesSection fwcMapdAdminData latestFwcMapdRefreshJob activeFwcMapdRefreshJob)
        else redirectTo SupportAction

respondToPublicHolidayRefresh :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
respondToPublicHolidayRefresh =
    if isHtmxRequest
        then do
            (publicHolidayCoverage, latestPublicHolidayRefreshJob, activePublicHolidayRefreshJob) <- fetchPublicHolidaySectionData
            respondHtml (renderPublicHolidaysSection publicHolidayCoverage latestPublicHolidayRefreshJob activePublicHolidayRefreshJob)
        else redirectTo SupportAction

isSafeSupportVenueReturnPath :: Text -> Bool
isSafeSupportVenueReturnPath candidate =
    Text.isPrefixOf "/" candidate
    && not (Text.isPrefixOf "//" candidate)
    && not (Text.isInfixOf "://" candidate)
    && Text.all (\character -> not (isControl character) && character /= '\\') candidate

safeSupportReturnPathOrRoster :: Maybe Text -> Text
safeSupportReturnPathOrRoster candidate =
    fromMaybe (pathTo RosterWeeksAction) do
        safePath <- candidate >>= safePasskeyReturnPath
        guard (isJust (supportReturnAuthority safePath))
        pure safePath

founderSupportReturnPath :: (?context :: ControllerContext, ?request :: Request) => Maybe Text -> IO Text
founderSupportReturnPath candidate =
    case candidate >>= safePasskeyReturnPath of
        Just safePath | isJust (supportReturnAuthority safePath) -> do
            clearImpersonationReturnFallback
            pure safePath
        _ -> do
            when (isJust candidate) markImpersonationReturnFallback
            pure (pathTo RosterWeeksAction)

authorizedSupportReturnPath :: (?context :: ControllerContext, ?request :: Request) => ImpersonationRequestContext -> Maybe Text -> IO Text
authorizedSupportReturnPath impersonationContext candidate =
    case candidate >>= safePasskeyReturnPath of
        Just safePath | effectiveUserCanReturnTo impersonationContext safePath -> do
            clearImpersonationReturnFallback
            pure safePath
        _ -> do
            when (isJust candidate) markImpersonationReturnFallback
            pure (pathTo RosterWeeksAction)

data SupportReturnAuthority
    = SupportReturnProfile
    | SupportReturnVenueUser
    | SupportReturnStaff
    | SupportReturnManager
    | SupportReturnAdmin
    | SupportReturnOwner
    | SupportReturnFounder

effectiveUserCanReturnTo :: ImpersonationRequestContext -> Text -> Bool
effectiveUserCanReturnTo impersonationContext candidate =
    case supportReturnAuthority candidate of
        Just SupportReturnProfile -> True
        Just SupportReturnVenueUser -> profileCompleted
        Just SupportReturnStaff -> profileCompleted
        Just SupportReturnManager -> profileCompleted && hasRequiredRole Manager
        Just SupportReturnAdmin -> profileCompleted && hasRequiredRole VenueAdmin
        Just SupportReturnOwner -> profileCompleted && hasRequiredRole VenueOwner
        Just SupportReturnFounder -> False
        Nothing -> False
  where
    profileCompleted = maybe False requiredProfileFieldsCompleted impersonationContext.impersonationStaff
    hasRequiredRole = hasVenueRole impersonationContext.impersonationVenueRole

supportReturnAuthority :: Text -> Maybe SupportReturnAuthority
supportReturnAuthority candidate
    | returnPathIs "/Support" && queryAllows ["section"] = Just SupportReturnFounder
    | returnPathIs "/Billing"
        && queryAllows ["checkout", "attempt_id", "session_id"]
        && returnQueryOptionalValueIsValid candidate "checkout" (== "success")
        && returnQueryOptionalValueIsValid candidate "attempt_id" (isJust . UUID.fromText)
        && returnQueryOptionalValueIsValid candidate "session_id" (not . Text.null) = Just SupportReturnOwner
    | returnPathIs "/BillingSuccess"
        && queryAllows ["attempt_id", "session_id"]
        && returnQueryHasUUID "attempt_id"
        && returnQueryHasNonEmpty "session_id" = Just SupportReturnOwner
    | returnPathIs "/BillingCancel"
        && queryAllows ["attempt_id"]
        && returnQueryHasUUID "attempt_id" = Just SupportReturnOwner
    | returnPathIs "/Xero" && queryAllows [] = Just SupportReturnOwner
    | returnPathIs "/Admin"
        && queryAllows ["anchorDate", "rosterGroupId", "showExports"]
        && returnQueryOptionalDayIsValid candidate "anchorDate"
        && returnQueryOptionalUUIDIsValid candidate "rosterGroupId" = Just SupportReturnAdmin
    | returnPathIs "/ExportJobs" && queryAllows [] = Just SupportReturnAdmin
    | returnPathIs "/NewStaff"
        && queryAllows ["anchorDate", "rosterGroupId"]
        && returnQueryOptionalDayIsValid candidate "anchorDate"
        && returnQueryOptionalUUIDIsValid candidate "rosterGroupId" = Just SupportReturnManager
    | returnPathIs "/EditStaff"
        && queryAllows ["staffId", "anchorDate", "rosterGroupId", "section"]
        && returnQueryHasUUID "staffId"
        && returnQueryOptionalDayIsValid candidate "anchorDate"
        && returnQueryOptionalUUIDIsValid candidate "rosterGroupId" = Just SupportReturnManager
    | returnPathIs "/EditProfile" && queryAllows ["section"] && returnQueryHas "section" "security" = Just SupportReturnFounder
    | returnPathIs "/EditProfile" && queryAllows ["section"] = Just SupportReturnProfile
    | returnPathIs "/NewFeedback" && queryAllows [] = Just SupportReturnProfile
    | returnPathIs "/ShowPageHelp"
        && queryAllows ["topic"]
        && maybe False (isJust . lookupPageHelpTopic . PageHelpTopicId) (returnQueryValue candidate "topic") = Just SupportReturnProfile
    | returnPathIs "/Timesheets" && queryAllows [] = Just SupportReturnStaff
    | returnPathIs "/ShowTimesheetWindow"
        && queryAllows ["anchorDate", "staffFilterId", "rosterGroupFilterId"]
        && returnQueryHasDay "anchorDate"
        && returnQueryOptionalUUIDIsValid candidate "staffFilterId"
        && returnQueryOptionalUUIDIsValid candidate "rosterGroupFilterId" = Just SupportReturnStaff
    | returnPathIs "/LeaveRequests"
        && queryAllows ["archivePage", "openSection", "section", "weekOffset"]
        && returnQueryOptionalValueIsValid candidate "archivePage" validPositiveInt
        && returnQueryOptionalValueIsValid candidate "weekOffset" validInt
        && returnQueryOptionalValueIsValid candidate "openSection" (== "archive")
        && returnQueryOptionalValueIsValid candidate "section" (`elem` ["pending", "approved", "denied", "archive"]) = Just SupportReturnManager
    | returnPathIs "/NewLeaveRequest" && queryAllows [] = Just SupportReturnStaff
    | returnPathIs "/RosterWeeks"
        && queryAllows ["rosterGroupId", "rosterView", "dayDate"]
        && returnQueryOptionalUUIDIsValid candidate "rosterGroupId"
        && validRosterViewQuery candidate = Just SupportReturnVenueUser
    | returnPathIs "/ShowRosterWindow"
        && queryAllows ["anchorDate", "rosterGroupId", "rosterView", "dayDate"]
        && returnQueryHasDay "anchorDate"
        && returnQueryOptionalUUIDIsValid candidate "rosterGroupId"
        && returnQueryOptionalDayIsValid candidate "dayDate"
        && validRosterViewQuery candidate = Just SupportReturnVenueUser
    | otherwise = Nothing
  where
    candidatePath = Text.takeWhile (/= '?') candidate
    returnPathIs expected = candidatePath == expected
    queryAllows = returnQueryAllows candidate
    returnQueryHas name value = returnQueryValue candidate name == Just value
    returnQueryHasUUID name = maybe False (isJust . UUID.fromText) (returnQueryValue candidate name)
    returnQueryHasNonEmpty name = maybe False (not . Text.null) (returnQueryValue candidate name)
    returnQueryHasDay name = maybe False validIsoDay (returnQueryValue candidate name)

returnQueryValue :: Text -> Text -> Maybe Text
returnQueryValue candidate name =
    join (lookup name (returnQuery candidate))

returnQueryAllows :: Text -> [Text] -> Bool
returnQueryAllows candidate allowedNames =
    all (`elem` allowedNames) names
        && all (isJust . snd) parsedQuery
        && length names == length (nub names)
  where
    parsedQuery = returnQuery candidate
    names = map fst parsedQuery

returnQueryOptionalUUIDIsValid :: Text -> Text -> Bool
returnQueryOptionalUUIDIsValid candidate name =
    returnQueryOptionalValueIsValid candidate name (isJust . UUID.fromText)

returnQueryOptionalDayIsValid :: Text -> Text -> Bool
returnQueryOptionalDayIsValid candidate name =
    returnQueryOptionalValueIsValid candidate name validIsoDay

returnQueryOptionalValueIsValid :: Text -> Text -> (Text -> Bool) -> Bool
returnQueryOptionalValueIsValid candidate name validValue =
    case lookup name (returnQuery candidate) of
        Nothing           -> True
        Just (Just value) -> validValue value
        Just Nothing      -> False

returnQuery :: Text -> URI.QueryText
returnQuery candidate =
    URI.parseQueryText (TextEncoding.encodeUtf8 queryText)
  where
    queryText = Text.takeWhile (/= '#') (Text.drop 1 (snd (Text.breakOn "?" candidate)))

validIsoDay :: Text -> Bool
validIsoDay value =
    isJust (parseTimeM True defaultTimeLocale "%F" (Text.unpack value) :: Maybe Day)

validRosterViewQuery :: Text -> Bool
validRosterViewQuery candidate =
    case returnQueryValue candidate "rosterView" of
        Nothing -> isNothing (returnQueryValue candidate "dayDate")
        Just "timeline" -> maybe False validIsoDay (returnQueryValue candidate "dayDate")
        Just _ -> False

validPositiveInt :: Text -> Bool
validPositiveInt value =
    maybe False (> (0 :: Int)) (readMaybe (Text.unpack value))

validInt :: Text -> Bool
validInt value =
    isJust (readMaybe (Text.unpack value) :: Maybe Int)

redirectAfterImpersonationTransition :: (?context :: ControllerContext, ?request :: Request) => Text -> IO ()
redirectAfterImpersonationTransition destination
    | isHtmxRequest = do
        setHeader ("HX-Redirect", cs destination)
        renderPlain ""
    | otherwise = redirectToPath destination
