module Web.Controller.Support where

import Application.Async.Queue (EnqueueAppJobResult (..),
                                fetchActiveAppJobByDedupeKey,
                                fetchLatestAppJobByKind)
import Application.FwcMapd.Job (enqueueFwcMapdRefreshJob,
                                fwcMapdRefreshJobDedupeKey,
                                fwcMapdRefreshJobKind)
import Application.Helper.Controller (unsafeEnumFromText)
import Application.Helper.Feedback (SupportUnreadFeedbackCount (..),
                                    allowedFeedbackPriorities,
                                    allowedFeedbackStatuses,
                                    fetchSupportUnreadFeedbackCount)
import Application.Helper.FwcMapd (FwcMapdAdminData, fetchFwcMapdAdminData)
import Application.Helper.LiveResource (LiveResource (..), liveMutationResult)
import Application.Helper.VenueOnboardingInvitation (venueOnboardingInvitationLifetime)
import Application.InvitationDelivery.Job (enqueueVenueOnboardingInvitationDeliveryJob)
import Application.PublicHolidays.Coverage (PublicHolidayCoverageYear,
                                            fetchPublicHolidayCoverage)
import Application.PublicHolidays.Job (enqueuePublicHolidayRefreshJob,
                                       publicHolidayRefreshJobDedupeKey,
                                       publicHolidayRefreshJobKind)
import Application.Support.LiveUpdates
import Control.Monad (forM, forM_, void)
import Data.Coerce (coerce)
import qualified Data.Text as Text
import Web.Controller.Prelude
import Web.LiveResourceInvalidation (invalidateTouchedResources)
import Web.Support.FrontendSurfaceLab (renderSurfaceLabPanelFragment)
import Web.View.Support.FrontendSurfaceLab
import Web.View.Support.Index

instance Controller SupportController where
    beforeAction = bepisBeforeAction BepisSupportController do
        annotateTelemetryAction
        ensureIsUser
        ensureSupportAccess
        ensureProfileCompleted

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

    action currentAction@FrontendSurfaceLabAction = runBepis currentAction BepisPageAction do
        render FrontendSurfaceLabView

    action currentAction@ShowFrontendSurfaceLabPanelFragmentAction { panelId } = runBepis currentAction BepisPageAction do
        respondHtml (renderSurfaceLabPanelFragment panelId "Loaded through the lab fragment GET endpoint.")

    action currentAction@RefreshFrontendSurfaceLabPanelAction = runBepis currentAction BepisPageAction do
        let panelId = paramOrDefault @Text "11111111-1111-1111-1111-111111111111" "panelId"
        respondHtml (renderSurfaceLabPanelFragment panelId "Refreshed through minimal SurfaceImpl HTMX action metadata.")

    action currentAction@MoveFrontendSurfaceLabCardAction = runBepis currentAction BepisPageAction do
        let sourceItemKey = paramOrDefault @Text "unknown-source" "sourceItemKey"
        let targetDropzoneKey = paramOrDefault @Text "unknown-target" "targetDropzoneKey"
        respondHtml (renderSurfaceLabPanelFragment "11111111-1111-1111-1111-111111111111" ("Intent accepted: " <> sourceItemKey <> " -> " <> targetDropzoneKey))

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
                                    |> set #status (unsafeEnumFromText @InvitationStatusEnum "pending")
                                    |> set #deliveryStatus (unsafeEnumFromText @InvitationDeliveryStatusEnum "queued")
                                    |> set #expiresAt (Just (addUTCTime venueOnboardingInvitationLifetime now))
                                    |> createRecord
                            void (enqueueVenueOnboardingInvitationDeliveryJob (Just currentUser.id) invitation)
                            setSuccessMessage ("Venue owner invitation queued for " <> invitation.email)
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
                liveMutationResult () [SupportAwardRatesResource]
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
                liveMutationResult () [SupportPublicHolidaysResource]
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

    action currentAction@SwitchSupportVenueAction = runBepis currentAction BepisPageAction do
        let venueId = (coerce (param @UUID "venueId") :: Id Venue)
        let nextPath = fromMaybe (pathTo SupportAction) (paramOrNothing @Text "next")
        venue <- query @Venue
            |> filterWhere (#id, venueId)
            |> filterWhere (#status, unsafeEnumFromText @VenueStatusEnum "active")
            |> fetchOneOrNothing

        case venue of
            Nothing -> do
                setErrorMessage "Choose an active venue."
                redirectTo SupportAction
            Just currentVenue -> do
                setSession currentVenueSessionKey currentVenue.id
                setSuccessMessage ("Support venue switched to " <> currentVenue.name)
                if isSafeReturnPath nextPath
                    then redirectToPath nextPath
                    else redirectTo SupportAction

buildSupportVenueOnboardingInvitationForm :: VenueOnboardingInvitation
buildSupportVenueOnboardingInvitationForm =
    newRecord @VenueOnboardingInvitation
        |> set #status (unsafeEnumFromText @InvitationStatusEnum "pending")
        |> set #deliveryStatus (unsafeEnumFromText @InvitationDeliveryStatusEnum "queued")

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
    pendingInvitations <- query @VenueOnboardingInvitation
        |> filterWhere (#status, unsafeEnumFromText @InvitationStatusEnum "pending")
        |> filterWhere (#acceptedAt, Nothing)
        |> fetch
    pure (any ((== Text.toLower (Text.strip email)) . Text.toLower . Text.strip . (.email)) pendingInvitations)

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
supportCanAddPasskey passkeys = do
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
