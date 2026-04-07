module Application.Script.BootstrapAccount where

import Application.Helper.Controller (PlatformRole (..), platformRoleToEnum,
                                      unsafeEnumFromText)
import Application.Script.Prelude
import Application.Support (createVenueWithConfig)
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Generated.Types
import System.Environment (lookupEnv)

run :: Script
run = do
    email <- requireEnvText "BOOTSTRAP_ACCOUNT_EMAIL"
    passwordFile <- requireEnvText "BOOTSTRAP_ACCOUNT_PASSWORD_FILE"
    venueName <- requireEnvText "BOOTSTRAP_ACCOUNT_VENUE_NAME"
    password <- Text.strip <$> liftIO (TextIO.readFile (cs passwordFile))

    when (Text.null password) do
        error "BOOTSTRAP_ACCOUNT_PASSWORD_FILE is empty"

    withTransaction do
        venue <- findOrCreateBootstrapVenue venueName
        user <- findOrCreateBootstrapUser email password
        void (ensureBootstrapMembership venue user)
        void (ensureBootstrapStaff venue user)

requireEnvText :: String -> IO Text
requireEnvText name =
    lookupEnv name >>= \case
        Just value -> pure (cs value)
        Nothing -> error ("Missing required environment variable: " <> name)

findOrCreateBootstrapVenue :: (?modelContext :: ModelContext) => Text -> IO Venue
findOrCreateBootstrapVenue venueName =
    query @Venue
        |> filterWhere (#name, venueName)
        |> fetchOneOrNothing
        >>= \case
            Just venue -> pure venue
            Nothing -> createVenueWithConfig venueName

findOrCreateBootstrapUser :: (?modelContext :: ModelContext) => Text -> Text -> IO User
findOrCreateBootstrapUser email password =
    query @User
        |> filterWhere (#email, email)
        |> fetchOneOrNothing
        >>= \case
            Just user -> pure user
            Nothing -> do
                passwordHash <- hashPassword password
                newRecord @User
                    |> set #email email
                    |> set #passwordHash passwordHash
                    |> set #userRole "staff"
                    |> set #platformRole (Just (platformRoleToEnum SuperAdminRole))
                    |> set #isProfileCompleted True
                    |> set #emailVerifiedAt (Just def)
                    |> createRecord

ensureBootstrapMembership :: (?modelContext :: ModelContext) => Venue -> User -> IO VenueMembership
ensureBootstrapMembership venue user =
    query @VenueMembership
        |> filterWhere (#venueId, unpackId venue.id)
        |> filterWhere (#userId, unpackId user.id)
        |> fetchOneOrNothing
        >>= \case
            Just membership ->
                membership
                    |> set #venueRole (unsafeEnumFromText @VenueRoleEnum "venue_owner")
                    |> set #isActive True
                    |> updateRecord
            Nothing ->
                newRecord @VenueMembership
                    |> set #venueId (unpackId venue.id)
                    |> set #userId (unpackId user.id)
                    |> set #venueRole (unsafeEnumFromText @VenueRoleEnum "venue_owner")
                    |> set #isActive True
                    |> createRecord

ensureBootstrapStaff :: (?modelContext :: ModelContext) => Venue -> User -> IO Staff
ensureBootstrapStaff venue user =
    query @Staff
        |> filterWhere (#venueId, unpackId venue.id)
        |> filterWhere (#userId, Just (unpackId user.id))
        |> fetchOneOrNothing
        >>= \case
            Just staff -> pure staff
            Nothing ->
                newRecord @Staff
                    |> set #venueId (unpackId venue.id)
                    |> set #userId (Just (unpackId user.id))
                    |> set #firstName "Bootstrap"
                    |> set #lastName "Admin"
                    |> set #preferredName Nothing
                    |> set #phone ""
                    |> set #emergencyContactName ""
                    |> set #emergencyContactPhone ""
                    |> set #idealShiftsPerWeek 0
                    |> set #isActive True
                    |> createRecord
