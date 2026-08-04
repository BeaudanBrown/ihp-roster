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
                                           liveMutationResult)
import Application.Helper.VenueOnboardingInvitation (venueOnboardingInvitationIsActive,
                                                     venueOnboardingInvitationLifetime)
import Application.InvitationDelivery.Job (enqueueVenueOnboardingInvitationDeliveryJob)
import Application.PublicHolidays.Coverage (PublicHolidayCoverageYear,
                                            fetchPublicHolidayCoverage)
import Application.PublicHolidays.Job (enqueuePublicHolidayRefreshJob,
                                       publicHolidayRefreshJobDedupeKey,
                                       publicHolidayRefreshJobKind)
import Application.Support.LiveUpdates
import Application.VenueOnboardingInvitation.Mutations (withVenueOnboardingInvitationRenewalLock)
import Control.Monad (forM, forM_, void)
import Data.Char (isControl)
import Data.Coerce (coerce)
import qualified Data.Text as Text
import Web.Controller.Prelude
import Web.RosterWeeks.Paths (supportVenueSwitchReturnPath)
import Web.SurfaceInvalidation (invalidateTouchedResources)
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
        let onboardingInvitation = buildSupportVenueOnboardingInvitationForm |> fill @'["email"] |> normalizeTextField #email |> modify #email Text.toLower
        onboardingInvitation
            |> validateField #email nonEmpty
            |> validateField #email isEmail
            |> ifValid \case
                Left onboardingInvitation -> render IndexView { .. }
                Right onboardingInvitation -> do
                    duplicateExists <- pendingVenueOnboardingInvitationExists onboardingInvitation.email
                    if duplicateExists
                        then do
                            let onboardingInvitationWithDuplicateError = onboardingInvitation
                                    |> validateField #email (const (Failure "There is already a pending owner invite for this email."))
                            render IndexView { onboardingInvitation = onboardingInvitationWithDuplicateError, .. }
                        else do
                            invitation <- withTransaction do
                                onboardingInvitation
                                    |> set #invitedByUserId (Just (unpackId currentUser.id))
                                    |> set #status (InvitationStatusEnumPending)
                                    |> set #deliveryStatus (Queued)
                                    |> set #expiresAt (Just (addUTCTime venueOnboardingInvitationLifetime now))
                                    |> createRecord
                            void (enqueueVenueOnboardingInvitationDeliveryJob (Just currentUser.id) invitation)
                            setSuccessMessage ("Venue owner invitation queued for " <> invitation.email)
                            redirectTo SupportAction

    action currentAction@RenewSupportVenueOnboardingInvitationAction { onboardingInvitationId } = runBepis currentAction BepisMutationAction do
        now <- getCurrentTime
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
                            matchingInvitations <- fetchPendingVenueOnboardingInvitationsExcept replacementForm.email invitationToReplace.id
                            renewedAt <- getCurrentTime
                            if any (venueOnboardingInvitationIsActive renewedAt) matchingInvitations
                                then pure OnboardingRenewalEmailConflict
                                else do
                                    forM_ (invitationToReplace : matchingInvitations) \invitation ->
                                        void $
                                            invitation
                                                |> set #status (Revoked)
                                                |> set #updatedAt renewedAt
                                                |> updateRecord
                                    replacement <- replacementForm
                                        |> set #invitedByUserId (Just (unpackId currentUser.id))
                                        |> set #expiresAt (Just (addUTCTime venueOnboardingInvitationLifetime now))
                                        |> createRecord
                                    void (enqueueVenueOnboardingInvitationDeliveryJob (Just currentUser.id) replacement)
                                    pure (OnboardingRenewed replacement)
                case fromMaybe OnboardingRenewalUnavailable maybeRenewalResult of
                    OnboardingRenewed replacement ->
                        setSuccessMessage ("Venue owner invitation renewed for " <> replacement.email)
                    OnboardingRenewalUnavailable ->
                        setErrorMessage "Only pending, unaccepted owner invitations can be renewed."
                    OnboardingRenewalEmailConflict ->
                        setErrorMessage "There is already a pending owner invite for this email."
            _ ->
                setErrorMessage "Enter a valid owner email address."
        redirectTo SupportAction

    action currentAction@CreateFwcMapdRefreshJobAction = runBepis currentAction BepisMutationAction do
        enqueueResult <- enqueueFwcMapdRefreshJob (Just (unpackId currentUser.id))
        case enqueueResult of
            EnqueuedAppJob _ ->
                setSuccessMessage "Award rate refresh queued."
            ExistingActiveAppJob _ ->
                setSuccessMessage "Award rate refresh is already queued or running."
        void $
            invalidateTouchedResources "support.award_rates.enqueue" $
                liveMutationResult () [supportAwardRatesResource]
        respondToAwardRatesRefresh

    action currentAction@CreatePublicHolidayRefreshJobAction = runBepis currentAction BepisMutationAction do
        enqueueResult <- enqueuePublicHolidayRefreshJob (Just (unpackId currentUser.id))
        case enqueueResult of
            EnqueuedAppJob _ ->
                setSuccessMessage "Public holiday refresh queued."
            ExistingActiveAppJob _ ->
                setSuccessMessage "Public holiday refresh is already queued or running."
        void $
            invalidateTouchedResources "support.public_holidays.enqueue" $
                liveMutationResult () [supportPublicHolidaysResource]
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
        ensureFreshPasskeyReady
        case paramOrNothing @Text "userId" >>= parseUUIDText of
            Nothing -> renderAccessDenied
            Just userId ->
                enterCurrentVenueImpersonation (Id userId) >>= \case
                    Nothing -> renderAccessDenied
                    Just _ -> do
                        setSuccessMessage "Support impersonation started."
                        redirectTo RosterWeeksAction

    action currentAction@ExitSupportImpersonationAction = runBepis currentAction BepisMutationAction do
        void (exitCurrentImpersonation "manual_exit")
        setSuccessMessage "Returned to Super admin mode."
        redirectTo SupportAction

    action currentAction@SwitchSupportImpersonationAction = runBepis currentAction BepisMutationAction do
        let selectedUserId = Text.strip (paramOrDefault @Text "" "userId")
        let nextPath = paramOrNothing @Text "next"
        if Text.null selectedUserId
            then do
                void (exitCurrentImpersonation "selector_exit")
                setSuccessMessage "Returned to Super admin mode."
                case nextPath of
                    Just safePath | isSafeReturnPath safePath -> redirectToPath safePath
                    _ -> redirectTo SupportAction
            else do
                ensureCurrentVenue
                ensureFreshPasskeyReady
                case parseUUIDText selectedUserId of
                    Nothing -> renderAccessDenied
                    Just userId ->
                        enterCurrentVenueImpersonation (Id userId) >>= \case
                            Nothing -> renderAccessDenied
                            Just _ -> do
                                setSuccessMessage "Support impersonation started."
                                case nextPath of
                                    Just safePath | isSafeReturnPath safePath -> redirectToPath safePath
                                    _ -> redirectTo RosterWeeksAction

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
                if isSafeReturnPath nextPath
                    then redirectToPath (supportVenueSwitchReturnPath nextPath)
                    else redirectTo SupportAction

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

pendingVenueOnboardingInvitationExists :: (?modelContext :: ModelContext) => Text -> IO Bool
pendingVenueOnboardingInvitationExists email = do
    pendingInvitations <- fetchPendingVenueOnboardingInvitations
    pure (any (hasNormalizedOnboardingEmail email) pendingInvitations)

fetchPendingVenueOnboardingInvitationsExcept :: (?modelContext :: ModelContext) => Text -> Id VenueOnboardingInvitation -> IO [VenueOnboardingInvitation]
fetchPendingVenueOnboardingInvitationsExcept email excludedInvitationId = do
    pendingInvitations <- fetchPendingVenueOnboardingInvitations
    pure (filter (\invitation -> invitation.id /= excludedInvitationId && hasNormalizedOnboardingEmail email invitation) pendingInvitations)

fetchPendingVenueOnboardingInvitations :: (?modelContext :: ModelContext) => IO [VenueOnboardingInvitation]
fetchPendingVenueOnboardingInvitations =
    query @VenueOnboardingInvitation
        |> filterWhere (#status, InvitationStatusEnumPending)
        |> filterWhere (#acceptedAt, Nothing)
        |> fetch

hasNormalizedOnboardingEmail :: Text -> VenueOnboardingInvitation -> Bool
hasNormalizedOnboardingEmail email invitation =
    Text.toLower (Text.strip email) == Text.toLower (Text.strip invitation.email)

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

isSafeReturnPath :: Text -> Bool
isSafeReturnPath candidate =
    Text.isPrefixOf "/" candidate
    && not (Text.isPrefixOf "//" candidate)
    && not (Text.isInfixOf "://" candidate)
    && Text.all (\character -> not (isControl character) && character /= '\\') candidate
