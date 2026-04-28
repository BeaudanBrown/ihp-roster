module Web.Controller.Support where

import Application.Async.Queue (AppJobRequest (..), EnqueueAppJobResult (..),
                                enqueueAppJob, fetchActiveAppJobByDedupeKey,
                                fetchLatestAppJobByKind)
import Application.FwcMapd.Job (fwcMapdRefreshJobDedupeKey,
                                fwcMapdRefreshJobKind)
import Application.Helper.Controller (currentSupportVenueOptions,
                                      defaultRosterWeekStartsOn,
                                      unsafeEnumFromText)
import Application.Helper.FwcMapd (FwcMapdAdminData, fetchFwcMapdAdminData)
import Application.Helper.LiveUpdate (broadcastLiveInvalidation,
                                      liveUpdateSourceClientId)
import Application.Helper.VenueOnboardingInvitation (venueOnboardingInvitationLifetime)
import Application.Helper.View (appendQueryParams)
import Application.Helper.WeekBoundaries (validRosterWeekStartDays)
import Application.InvitationDelivery.Job (enqueueVenueOnboardingInvitationDeliveryJob)
import Application.PublicHolidays.Job (publicHolidayRefreshJobDedupeKey,
                                       publicHolidayRefreshJobKind)
import Application.Support (createVenueWithBootstrapConfigInCurrentTransaction,
                            defaultVenueBootstrapTimezone)
import Application.Support.LiveUpdates
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Data.Coerce (coerce)
import qualified Data.Text as Text
import Web.Controller.Prelude
import Web.View.Support.Index

instance Controller SupportController where
    beforeAction = do
        ensureIsUser
        accessDeniedUnless currentUserIsSuperAdmin
        ensureProfileCompleted

    action SupportAction = do
        let venues = currentSupportVenueOptions
        onboardingInvitations <- fetchVenueOnboardingInvitations
        passkeys <- fetchCurrentUserPasskeys
        (fwcMapdAdminData, latestFwcMapdRefreshJob, activeFwcMapdRefreshJob) <- fetchFwcMapdAwardRatesSectionData
        (publicHolidayCount, latestPublicHolidayRefreshJob, activePublicHolidayRefreshJob) <- fetchPublicHolidaySectionData
        createdVenue <- case paramOrNothing @(Id Venue) "createdVenueId" of
            Nothing      -> pure Nothing
            Just venueId -> Just <$> fetchCreatedVenue venueId
        let venue = buildSupportVenueForm
        let venueTimezone = defaultVenueBootstrapTimezone
        let venueRosterWeekStartsOn = defaultRosterWeekStartsOn
        let onboardingInvitation = buildSupportVenueOnboardingInvitationForm
        render IndexView { .. }

    action ShowFwcMapdAwardRatesSectionAction = do
        (fwcMapdAdminData, latestFwcMapdRefreshJob, activeFwcMapdRefreshJob) <- fetchFwcMapdAwardRatesSectionData
        respondHtml (renderAwardRatesSection fwcMapdAdminData latestFwcMapdRefreshJob activeFwcMapdRefreshJob)

    action ShowPublicHolidaysSectionAction = do
        (publicHolidayCount, latestPublicHolidayRefreshJob, activePublicHolidayRefreshJob) <- fetchPublicHolidaySectionData
        respondHtml (renderPublicHolidaysSection publicHolidayCount latestPublicHolidayRefreshJob activePublicHolidayRefreshJob)

    action CreateSupportVenueAction = do
        let venues = currentSupportVenueOptions
        onboardingInvitations <- fetchVenueOnboardingInvitations
        passkeys <- fetchCurrentUserPasskeys
        (fwcMapdAdminData, latestFwcMapdRefreshJob, activeFwcMapdRefreshJob) <- fetchFwcMapdAwardRatesSectionData
        (publicHolidayCount, latestPublicHolidayRefreshJob, activePublicHolidayRefreshJob) <- fetchPublicHolidaySectionData
        let createdVenue = Nothing
        let venueTimezone = paramOrDefault defaultVenueBootstrapTimezone "timezone"
        let venueRosterWeekStartsOn = fromMaybe defaultRosterWeekStartsOn (paramOrNothing @Int "rosterWeekStartsOn")
        let venue = buildSupportVenueForm |> fill @'["name"]
        let onboardingInvitation = buildSupportVenueOnboardingInvitationForm
        venue
            |> validateField #name nonEmpty
            |> ifValid \case
                Left venue -> do
                    render IndexView { .. }
                Right venue -> do
                    if venueRosterWeekStartsOn `elem` validRosterWeekStartDays && not (isEmpty venueTimezone)
                        then do
                            createdVenue <- withTransaction do
                                (createdVenue, venueConfig) <- createVenueWithBootstrapConfigInCurrentTransaction venue.name venueTimezone venueRosterWeekStartsOn
                                _ <- recordAuditEvent
                                    (unpackId createdVenue.id)
                                    (unpackId currentUser.id)
                                    "venue_bootstrapped"
                                    "venues"
                                    (unpackId createdVenue.id)
                                    (Aeson.object
                                        [ "venueName" Aeson..= createdVenue.name
                                        , "timezone" Aeson..= venueConfig.timezone
                                        , "rosterWeekStartsOn" Aeson..= venueConfig.rosterWeekStartsOn
                                        ]
                                    )
                                    requestAuditSourceChannel
                                pure createdVenue
                            setSuccessMessage ("Venue created: " <> createdVenue.name)
                            redirectToPath (appendQueryParams (pathTo SupportAction) [("createdVenueId", tshow createdVenue.id)])
                        else do
                            setErrorMessage "Provide a venue name, timezone, and valid roster week start."
                            render IndexView { .. }

    action CreateSupportVenueOnboardingInvitationAction = do
        let venues = currentSupportVenueOptions
        onboardingInvitations <- fetchVenueOnboardingInvitations
        passkeys <- fetchCurrentUserPasskeys
        (fwcMapdAdminData, latestFwcMapdRefreshJob, activeFwcMapdRefreshJob) <- fetchFwcMapdAwardRatesSectionData
        (publicHolidayCount, latestPublicHolidayRefreshJob, activePublicHolidayRefreshJob) <- fetchPublicHolidaySectionData
        let createdVenue = Nothing
        let venue = buildSupportVenueForm
        let venueTimezone = defaultVenueBootstrapTimezone
        let venueRosterWeekStartsOn = defaultRosterWeekStartsOn
        now <- getCurrentTime
        let onboardingInvitation = buildSupportVenueOnboardingInvitationForm |> fill @'["email"]
        onboardingInvitation
            |> validateField #email nonEmpty
            |> validateField #email isEmail
            |> ifValid \case
                Left onboardingInvitation -> render IndexView { .. }
                Right onboardingInvitation -> do
                    invitation <- withTransaction do
                        invitation <-
                            onboardingInvitation
                                |> set #invitedByUserId (Just (unpackId currentUser.id))
                                |> set #status (unsafeEnumFromText @InvitationStatusEnum "pending")
                                |> set #deliveryStatus (unsafeEnumFromText @InvitationDeliveryStatusEnum "queued")
                                |> set #expiresAt (Just (addUTCTime venueOnboardingInvitationLifetime now))
                                |> createRecord
                        pure invitation
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
        broadcastLiveInvalidation
            supportLiveUpdateScope
            liveUpdateSourceClientId
            [supportAwardRatesSectionFragmentRef]
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
        broadcastLiveInvalidation
            supportLiveUpdateScope
            liveUpdateSourceClientId
            [supportPublicHolidaysSectionFragmentRef]
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

buildSupportVenueForm :: Venue
buildSupportVenueForm =
    newRecord @Venue
        |> set #status (unsafeEnumFromText @VenueStatusEnum "active")

buildSupportVenueOnboardingInvitationForm :: VenueOnboardingInvitation
buildSupportVenueOnboardingInvitationForm =
    newRecord @VenueOnboardingInvitation
        |> set #status (unsafeEnumFromText @InvitationStatusEnum "pending")
        |> set #deliveryStatus (unsafeEnumFromText @InvitationDeliveryStatusEnum "queued")

fetchCreatedVenue :: (?modelContext :: ModelContext) => Id Venue -> IO Venue
fetchCreatedVenue venueId =
    query @Venue
        |> filterWhere (#id, venueId)
        |> filterWhere (#status, unsafeEnumFromText @VenueStatusEnum "active")
        |> fetchOne

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
