module Application.Script.BootstrapAccount where

import Application.Helper.Controller (PlatformRole (..), platformRoleToEnum)
import Application.Script.Prelude
import Application.Support (createVenueWithConfig, provisionVenueUser)
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

    venue <- findOrCreateBootstrapVenue venueName
    user <- findOrCreateBootstrapUser email password
    _ <- provisionVenueUser venue user "venue_owner" "Bootstrap" "Admin"
    pure ()

requireEnvText :: String -> IO Text
requireEnvText name =
    lookupEnv name >>= \case
        Just value -> pure (cs value)
        Nothing -> error ("Missing required environment variable: " <> cs name)

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
