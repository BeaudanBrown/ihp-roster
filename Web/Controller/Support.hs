module Web.Controller.Support where

import Application.Helper.Controller (currentSupportVenueOptions,
                                      unsafeEnumFromText)
import Application.Helper.RosterGroups (ensureVenueRosterDefaults)
import Application.Helper.View (appendQueryParams)
import qualified Data.Aeson as Aeson
import Data.Coerce (coerce)
import qualified Data.Text as Text
import Data.Time.Calendar (fromGregorian)
import Web.Controller.Prelude
import Web.View.Support.Index

instance Controller SupportController where
    beforeAction = do
        ensureIsUser
        ensureProfileCompleted
        accessDeniedUnless currentUserIsSuperAdmin

    action SupportAction = do
        let venues = currentSupportVenueOptions
        createdVenue <- case paramOrNothing @(Id Venue) "createdVenueId" of
            Nothing      -> pure Nothing
            Just venueId -> Just <$> fetchCreatedVenue venueId
        let venue = buildSupportVenueForm
        render IndexView { .. }

    action CreateSupportVenueAction = do
        let venues = currentSupportVenueOptions
        let createdVenue = Nothing
        let venue = buildSupportVenueForm |> fill @'["name"]
        venue
            |> validateField #name nonEmpty
            |> ifValid \case
                Left venue -> do
                    render IndexView { .. }
                Right venue -> do
                    createdVenue <- withTransaction do
                        createdVenue <-
                            venue
                                |> set #status (unsafeEnumFromText @VenueStatusEnum "active")
                                |> createRecord
                        venueConfig <- ensureVenueConfigRecord createdVenue
                        _ <- ensureVenueRosterDefaults createdVenue
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

defaultSupportVenueTimezone :: Text
defaultSupportVenueTimezone = "Australia/Melbourne"

ensureVenueConfigRecord :: (?modelContext :: ModelContext) => Venue -> IO VenueConfig
ensureVenueConfigRecord venue =
    query @VenueConfig
        |> filterWhere (#venueId, unpackId venue.id)
        |> fetchOneOrNothing
        >>= \case
            Just venueConfig -> pure venueConfig
            Nothing ->
                newRecord @VenueConfig
                    |> set #venueId (unpackId venue.id)
                    |> set #timezone defaultSupportVenueTimezone
                    |> set #weekOffsetEpoch (fromGregorian 2025 1 6)
                    |> set #lateToEarlyMinStartGapMinutes 600
                    |> set #staffTimesheetEditWindowDays 7
                    |> createRecord

fetchCreatedVenue :: (?modelContext :: ModelContext) => Id Venue -> IO Venue
fetchCreatedVenue venueId =
    query @Venue
        |> filterWhere (#id, venueId)
        |> filterWhere (#status, unsafeEnumFromText @VenueStatusEnum "active")
        |> fetchOne

isSafeReturnPath :: Text -> Bool
isSafeReturnPath candidate =
    Text.isPrefixOf "/" candidate
    && not (Text.isPrefixOf "//" candidate)
    && not (Text.isInfixOf "://" candidate)
