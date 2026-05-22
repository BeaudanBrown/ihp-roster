module Web.Controller.Support where

import Application.Async.Queue (AppJobRequest (..), EnqueueAppJobResult (..),
                                enqueueAppJob, fetchActiveAppJobByDedupeKey,
                                fetchLatestAppJobByKind)
import Application.FwcMapd.Job (fwcMapdRefreshJobDedupeKey,
                                fwcMapdRefreshJobKind)
import Application.Helper.Controller (unsafeEnumFromText)
import Application.Helper.FwcMapd (FwcMapdAdminData, fetchFwcMapdAdminData)
import Application.Helper.LiveResource (LiveResource (..), liveMutationResult)
import Application.Helper.LiveSurface (serveTypedLiveFragment)
import Application.Helper.VenueOnboardingInvitation (venueOnboardingInvitationLifetime)
import Application.InvitationDelivery.Job (enqueueVenueOnboardingInvitationDeliveryJob)
import Application.PublicHolidays.Job (publicHolidayRefreshJobDedupeKey,
                                       publicHolidayRefreshJobKind)
import Application.Support.LiveUpdates
import Control.Monad (void)
import qualified Data.Aeson as Aeson
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
        (fwcMapdAdminData, latestFwcMapdRefreshJob, activeFwcMapdRefreshJob) <- fetchFwcMapdAwardRatesSectionData
        (publicHolidayCount, latestPublicHolidayRefreshJob, activePublicHolidayRefreshJob) <- fetchPublicHolidaySectionData
        let onboardingInvitation = buildSupportVenueOnboardingInvitationForm
        render IndexView { .. }

    action ShowFwcMapdAwardRatesSectionAction =
        serveTypedLiveFragment supportLiveSurfaceDefinition () SupportAwardRatesLiveFragment \_ -> do
            (fwcMapdAdminData, latestFwcMapdRefreshJob, activeFwcMapdRefreshJob) <- fetchFwcMapdAwardRatesSectionData
            respondHtml (renderAwardRatesSection fwcMapdAdminData latestFwcMapdRefreshJob activeFwcMapdRefreshJob)

    action ShowPublicHolidaysSectionAction =
        serveTypedLiveFragment supportLiveSurfaceDefinition () SupportPublicHolidaysLiveFragment \_ -> do
            (publicHolidayCount, latestPublicHolidayRefreshJob, activePublicHolidayRefreshJob) <- fetchPublicHolidaySectionData
            respondHtml (renderPublicHolidaysSection publicHolidayCount latestPublicHolidayRefreshJob activePublicHolidayRefreshJob)

    action CreateSupportVenueOnboardingInvitationAction = do
        onboardingInvitations <- fetchVenueOnboardingInvitations
        passkeys <- fetchCurrentUserPasskeys
        (fwcMapdAdminData, latestFwcMapdRefreshJob, activeFwcMapdRefreshJob) <- fetchFwcMapdAwardRatesSectionData
        (publicHolidayCount, latestPublicHolidayRefreshJob, activePublicHolidayRefreshJob) <- fetchPublicHolidaySectionData
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
        enqueueResult <-
            enqueueAppJob
                AppJobRequest
                    { jobKind = fwcMapdRefreshJobKind
                    , payload = Aeson.object []
                    , payloadSchemaVersion = 1
                    , requestedByUserId = Just (unpackId currentUser.id)
                    , venueId = Nothing
                    , relatedTable = Just "fwc_mapd_sync_runs"
                    , relatedId = Nothing
                    , dedupeKey = Just fwcMapdRefreshJobDedupeKey
                    , runAt = Nothing
                    }
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
        enqueueResult <-
            enqueueAppJob
                AppJobRequest
                    { jobKind = publicHolidayRefreshJobKind
                    , payload = Aeson.object ["jurisdiction" Aeson..= ("VIC" :: Text)]
                    , payloadSchemaVersion = 1
                    , requestedByUserId = Just (unpackId currentUser.id)
                    , venueId = Nothing
                    , relatedTable = Just "public_holidays"
                    , relatedId = Nothing
                    , dedupeKey = Just publicHolidayRefreshJobDedupeKey
                    , runAt = Nothing
                    }
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
    IO (Int, Maybe AppJob, Maybe AppJob)
fetchPublicHolidaySectionData = do
    publicHolidayCount <-
        query @PublicHoliday
            |> filterWhere (#jurisdiction, "VIC")
            |> filterWhere (#isRegional, False)
            |> fetchCount
    latestPublicHolidayRefreshJob <- fetchLatestAppJobByKind publicHolidayRefreshJobKind
    activePublicHolidayRefreshJob <- fetchActiveAppJobByDedupeKey publicHolidayRefreshJobDedupeKey
    pure (publicHolidayCount, latestPublicHolidayRefreshJob, activePublicHolidayRefreshJob)

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
            (publicHolidayCount, latestPublicHolidayRefreshJob, activePublicHolidayRefreshJob) <- fetchPublicHolidaySectionData
            respondHtml (renderPublicHolidaysSection publicHolidayCount latestPublicHolidayRefreshJob activePublicHolidayRefreshJob)
        else redirectTo SupportAction

isSafeReturnPath :: Text -> Bool
isSafeReturnPath candidate =
    Text.isPrefixOf "/" candidate
    && not (Text.isPrefixOf "//" candidate)
    && not (Text.isInfixOf "://" candidate)
