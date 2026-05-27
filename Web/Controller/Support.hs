module Web.Controller.Support where

import Application.Async.Queue (EnqueueAppJobResult (..),
                                fetchActiveAppJobByDedupeKey,
                                fetchLatestAppJobByKind)
import Application.FwcMapd.Job (enqueueFwcMapdRefreshJob,
                                fwcMapdRefreshJobDedupeKey,
                                fwcMapdRefreshJobKind)
import Application.Helper.Controller (unsafeEnumFromText)
import Application.Helper.FwcMapd (FwcMapdAdminData, fetchFwcMapdAdminData)
import Application.Helper.LiveResource (LiveResource (..), liveMutationResult)
import Application.Helper.LiveSurface (serveTypedLiveFragment)
import Application.Helper.VenueOnboardingInvitation (venueOnboardingInvitationLifetime)
import Application.InvitationDelivery.Job (enqueueVenueOnboardingInvitationDeliveryJob)
import Application.PublicHolidays.Coverage (PublicHolidayCoverageYear,
                                            fetchPublicHolidayCoverage)
import Application.PublicHolidays.Job (enqueuePublicHolidayRefreshJob,
                                       publicHolidayRefreshJobDedupeKey,
                                       publicHolidayRefreshJobKind)
import Application.Support.LiveUpdates
import Control.Monad (void)
import Data.Coerce (coerce)
import qualified Data.Text as Text
import Web.Controller.Prelude
import Web.LiveResourceInvalidation (invalidateTouchedResources)
import Web.View.Support.Index

instance Controller SupportController where
    beforeAction = do
        ensureIsUser
        redirectPermissionDeniedUnless currentUserIsSuperAdmin "You need super admin access to view that page."
        ensureProfileCompleted

    action SupportAction = do
        onboardingInvitations <- fetchVenueOnboardingInvitations
        passkeys <- fetchCurrentUserPasskeys
        canAddPasskey <- supportCanAddPasskey passkeys
        (fwcMapdAdminData, latestFwcMapdRefreshJob, activeFwcMapdRefreshJob) <- fetchFwcMapdAwardRatesSectionData
        (publicHolidayCoverage, latestPublicHolidayRefreshJob, activePublicHolidayRefreshJob) <- fetchPublicHolidaySectionData
        let onboardingInvitation = buildSupportVenueOnboardingInvitationForm
        render IndexView { .. }

    action ShowFwcMapdAwardRatesSectionAction =
        serveTypedLiveFragment supportLiveSurfaceDefinition () SupportAwardRatesLiveFragment \_ -> do
            (fwcMapdAdminData, latestFwcMapdRefreshJob, activeFwcMapdRefreshJob) <- fetchFwcMapdAwardRatesSectionData
            respondHtml (renderAwardRatesSection fwcMapdAdminData latestFwcMapdRefreshJob activeFwcMapdRefreshJob)

    action ShowPublicHolidaysSectionAction =
        serveTypedLiveFragment supportLiveSurfaceDefinition () SupportPublicHolidaysLiveFragment \_ -> do
            (publicHolidayCoverage, latestPublicHolidayRefreshJob, activePublicHolidayRefreshJob) <- fetchPublicHolidaySectionData
            respondHtml (renderPublicHolidaysSection publicHolidayCoverage latestPublicHolidayRefreshJob activePublicHolidayRefreshJob)

    action CreateSupportVenueOnboardingInvitationAction = do
        onboardingInvitations <- fetchVenueOnboardingInvitations
        passkeys <- fetchCurrentUserPasskeys
        canAddPasskey <- supportCanAddPasskey passkeys
        (fwcMapdAdminData, latestFwcMapdRefreshJob, activeFwcMapdRefreshJob) <- fetchFwcMapdAwardRatesSectionData
        (publicHolidayCoverage, latestPublicHolidayRefreshJob, activePublicHolidayRefreshJob) <- fetchPublicHolidaySectionData
        now <- getCurrentTime
        let onboardingInvitation = buildSupportVenueOnboardingInvitationForm |> fill @'["email"]
        onboardingInvitation
            |> validateField #email nonEmpty
            |> validateField #email isEmail
            |> ifValid \case
                Left onboardingInvitation -> render IndexView { .. }
                Right onboardingInvitation -> do
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

    action CreateFwcMapdRefreshJobAction = do
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

    action CreatePublicHolidayRefreshJobAction = do
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

    action SwitchSupportVenueAction = do
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

fetchVenueOnboardingInvitations :: (?modelContext :: ModelContext) => IO [VenueOnboardingInvitation]
fetchVenueOnboardingInvitations =
    query @VenueOnboardingInvitation
        |> orderByDesc #createdAt
        |> fetch

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
