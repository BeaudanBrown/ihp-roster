module Web.Controller.Support where

import Application.Helper.Controller (currentSupportVenueOptions,
                                      defaultRosterWeekStartsOn,
                                      defaultWeekOffsetEpochForStartDay,
                                      unsafeEnumFromText)
import Application.Helper.RosterGroups (ensureVenueRosterDefaults)
import Application.Helper.VenueOnboardingInvitation (deliverVenueOnboardingInvitationEmail,
                                                     venueOnboardingInvitationLifetime)
import Application.Helper.View (appendQueryParams)
import Application.Support (createVenueWithBootstrapConfigInCurrentTransaction)
import Control.Concurrent (forkIO)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Data.Coerce (coerce)
import qualified Data.Text as Text
import Web.Controller.Prelude
import Web.View.Support.Index

instance Controller SupportController where
    beforeAction = do
        ensureIsUser
        ensureProfileCompleted
        accessDeniedUnless currentUserIsSuperAdmin

    action SupportAction = do
        let venues = currentSupportVenueOptions
        onboardingInvitations <- fetchVenueOnboardingInvitations
        createdVenue <- case paramOrNothing @(Id Venue) "createdVenueId" of
            Nothing      -> pure Nothing
            Just venueId -> Just <$> fetchCreatedVenue venueId
        let venue = buildSupportVenueForm
        let onboardingInvitation = buildSupportVenueOnboardingInvitationForm
        render IndexView { .. }

    action CreateSupportVenueAction = do
        let venues = currentSupportVenueOptions
        onboardingInvitations <- fetchVenueOnboardingInvitations
        let createdVenue = Nothing
        let venue = buildSupportVenueForm |> fill @'["name"]
        let onboardingInvitation = buildSupportVenueOnboardingInvitationForm
        venue
            |> validateField #name nonEmpty
            |> ifValid \case
                Left venue -> do
                    render IndexView { .. }
                Right venue -> do
                    createdVenue <- withTransaction do
                        (createdVenue, venueConfig) <- createVenueWithBootstrapConfigInCurrentTransaction venue.name defaultSupportVenueTimezone defaultRosterWeekStartsOn
                        _ <- recordAuditEvent
                            (unpackId createdVenue.id)
                            (unpackId currentUser.id)
                            "venue_bootstrapped"
                            "venues"
                            (unpackId createdVenue.id)
                            (Aeson.object
                                [ "venueName" Aeson..= createdVenue.name
                                , "timezone" Aeson..= venueConfig.timezone
                                ]
                            )
                            requestAuditSourceChannel
                        pure createdVenue
                    setSuccessMessage ("Venue created: " <> createdVenue.name)
                    redirectToPath (appendQueryParams (pathTo SupportAction) [("createdVenueId", tshow createdVenue.id)])

    action CreateSupportVenueOnboardingInvitationAction = do
        let venues = currentSupportVenueOptions
        onboardingInvitations <- fetchVenueOnboardingInvitations
        let createdVenue = Nothing
        let venue = buildSupportVenueForm
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
                    queueVenueOnboardingInvitationDelivery invitation
                    setSuccessMessage ("Venue owner invitation queued for " <> invitation.email)
                    redirectTo SupportAction

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

defaultSupportVenueTimezone :: Text
defaultSupportVenueTimezone = "Australia/Melbourne"

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

queueVenueOnboardingInvitationDelivery ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    VenueOnboardingInvitation ->
    IO ()
queueVenueOnboardingInvitationDelivery invitation = do
    let currentContext = ?context
    let currentModelContext = ?modelContext
    let currentRequest = ?request
    void $
        forkIO do
            let ?context = currentContext
            let ?modelContext = currentModelContext
            let ?request = currentRequest
            _ <- deliverVenueOnboardingInvitationEmail invitation
            pure ()

isSafeReturnPath :: Text -> Bool
isSafeReturnPath candidate =
    Text.isPrefixOf "/" candidate
    && not (Text.isPrefixOf "//" candidate)
    && not (Text.isInfixOf "://" candidate)
