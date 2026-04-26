module Application.Script.BootstrapAccount where

import Application.Helper.Controller (PlatformRole (..), platformRoleToEnum)
import Application.Script.Prelude
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Generated.Types
import System.Environment (lookupEnv)

data BootstrapConfig = BootstrapConfig
    { email    :: !Text
    , password :: !Text
    }

run :: Script
run = do
    bootstrapConfig <- liftIO loadBootstrapConfig
    existingSuperAdmin <- fetchExistingSuperAdmin
    case existingSuperAdmin of
        Just _ -> liftIO (putStrLn "Super-admin already exists; bootstrap skipped.")
        Nothing -> do
            _ <- createBootstrapUser bootstrapConfig.email bootstrapConfig.password
            pure ()

loadBootstrapConfig :: IO BootstrapConfig
loadBootstrapConfig = do
    lookupEnv "BOOTSTRAP_ACCOUNT_SECRET_FILE" >>= \case
        Just secretFile -> loadBootstrapConfigFromSecretFile (cs secretFile)
        Nothing -> loadBootstrapConfigFromLegacyEnv

loadBootstrapConfigFromSecretFile :: Text -> IO BootstrapConfig
loadBootstrapConfigFromSecretFile secretFile = do
    secretValues <- parseSecretFile <$> TextIO.readFile (cs secretFile)
    config <-
        BootstrapConfig
            <$> requireSecretValue secretValues "BOOTSTRAP_ACCOUNT_EMAIL"
            <*> requireSecretValue secretValues "BOOTSTRAP_ACCOUNT_PASSWORD"
    validateBootstrapConfig config
    pure config

loadBootstrapConfigFromLegacyEnv :: IO BootstrapConfig
loadBootstrapConfigFromLegacyEnv = do
    email <- requireEnvText "BOOTSTRAP_ACCOUNT_EMAIL"
    passwordFile <- requireEnvText "BOOTSTRAP_ACCOUNT_PASSWORD_FILE"
    password <- Text.strip <$> TextIO.readFile (cs passwordFile)
    let config = BootstrapConfig { email, password }
    validateBootstrapConfig config
    pure config

parseSecretFile :: Text -> [(Text, Text)]
parseSecretFile rawSecret =
    rawSecret
        |> Text.lines
        |> map Text.strip
        |> filter (not . Text.null)
        |> filter (not . Text.isPrefixOf "#")
        |> mapMaybe parseLine
    where
        parseLine line = do
            let (key, rawValue) = Text.breakOn "=" line
            guard (not (Text.null key) && Text.isPrefixOf "=" rawValue)
            Just (Text.strip key, unquote (Text.strip (Text.drop 1 rawValue)))

unquote :: Text -> Text
unquote value
    | Text.length value >= 2 && Text.head value == '"' && Text.last value == '"' = Text.init (Text.tail value)
    | Text.length value >= 2 && Text.head value == '\'' && Text.last value == '\'' = Text.init (Text.tail value)
    | otherwise = value

requireSecretValue :: [(Text, Text)] -> Text -> IO Text
requireSecretValue values key =
    case lookup key values of
        Just value -> pure value
        Nothing -> error ("Missing required bootstrap secret key: " <> cs key)

validateBootstrapConfig :: BootstrapConfig -> IO ()
validateBootstrapConfig config = do
    requireNonEmpty "BOOTSTRAP_ACCOUNT_EMAIL" config.email
    requireNonEmpty "BOOTSTRAP_ACCOUNT_PASSWORD" config.password

requireNonEmpty :: Text -> Text -> IO ()
requireNonEmpty name value =
    when (Text.null (Text.strip value)) do
        error (cs name <> " is empty")

requireEnvText :: String -> IO Text
requireEnvText name =
    lookupEnv name >>= \case
        Just value -> pure (cs value)
        Nothing -> error ("Missing required environment variable: " <> cs name)

fetchExistingSuperAdmin :: (?modelContext :: ModelContext) => IO (Maybe User)
fetchExistingSuperAdmin =
    query @User
        |> filterWhere (#platformRole, Just (platformRoleToEnum SuperAdminRole))
        |> fetchOneOrNothing

createBootstrapUser :: (?modelContext :: ModelContext) => Text -> Text -> IO User
createBootstrapUser email password =
    query @User
        |> filterWhere (#email, email)
        |> fetchOneOrNothing
        >>= \case
            Just _ -> error "Bootstrap account email already exists, but no super-admin exists; refusing to modify existing user."
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
