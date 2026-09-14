module Application.Script.BootstrapAccount where

import Application.Operator.Error
import Application.Script.Prelude
import qualified Control.Exception as Exception
import Control.Monad (guard, void)
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import System.Environment (lookupEnv)

data BootstrapConfig = BootstrapConfig
    { email    :: !Text
    , password :: !Text
    }

run :: Script
run = do
    bootstrapConfig <- liftIO (loadBootstrapConfig >>= requireScriptResult)
    existingSuperAdmin <- fetchExistingSuperAdmin
    case existingSuperAdmin of
        Just _ -> liftIO (putStrLn "Super-admin already exists; bootstrap skipped.")
        Nothing -> do
            void (createBootstrapUser bootstrapConfig.email bootstrapConfig.password >>= liftIO . requireScriptResult)

loadBootstrapConfig :: IO (Either ScriptError BootstrapConfig)
loadBootstrapConfig = do
    lookupEnv "BOOTSTRAP_ACCOUNT_SECRET_FILE" >>= \case
        Just secretFile -> loadBootstrapConfigFromSecretFile (cs secretFile)
        Nothing         -> loadBootstrapConfigFromLegacyEnv

loadBootstrapConfigFromSecretFile :: Text -> IO (Either ScriptError BootstrapConfig)
loadBootstrapConfigFromSecretFile secretFile = do
    readResult <- readConfigurationFile "bootstrap secret file" (cs secretFile)
    pure do
        rawSecret <- readResult
        let secretValues = parseSecretFile rawSecret
        config <-
            BootstrapConfig
                <$> requireSecretValue secretValues "BOOTSTRAP_ACCOUNT_EMAIL"
                <*> requireSecretValue secretValues "BOOTSTRAP_ACCOUNT_PASSWORD"
        validateBootstrapConfig config
        Right config

loadBootstrapConfigFromLegacyEnv :: IO (Either ScriptError BootstrapConfig)
loadBootstrapConfigFromLegacyEnv = do
    maybeEmail <- lookupEnv "BOOTSTRAP_ACCOUNT_EMAIL"
    maybePasswordFile <- lookupEnv "BOOTSTRAP_ACCOUNT_PASSWORD_FILE"
    case (maybeEmail, maybePasswordFile) of
        (Nothing, _) -> pure (Left (InvalidScriptConfiguration "missing required environment variable BOOTSTRAP_ACCOUNT_EMAIL"))
        (_, Nothing) -> pure (Left (InvalidScriptConfiguration "missing required environment variable BOOTSTRAP_ACCOUNT_PASSWORD_FILE"))
        (Just emailValue, Just passwordFile) -> do
            passwordResult <- readConfigurationFile "bootstrap password file" passwordFile
            pure do
                password <- Text.strip <$> passwordResult
                let config = BootstrapConfig { email = cs emailValue, password }
                validateBootstrapConfig config
                Right config

readConfigurationFile :: Text -> FilePath -> IO (Either ScriptError Text)
readConfigurationFile label path = do
    readResult <- Exception.try (TextIO.readFile path)
    pure case readResult of
        Left (_ :: Exception.IOException) -> Left (InvalidScriptConfiguration (label <> " could not be read"))
        Right contents -> Right contents

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
    | Text.length value < 2 = value
    | otherwise =
        case (Text.uncons value, Text.unsnoc value) of
            (Just ('"', _), Just (_, '"'))   -> Text.dropEnd 1 (Text.drop 1 value)
            (Just ('\'', _), Just (_, '\'')) -> Text.dropEnd 1 (Text.drop 1 value)
            _                                -> value

requireSecretValue :: [(Text, Text)] -> Text -> Either ScriptError Text
requireSecretValue values key =
    maybe
        (Left (InvalidScriptConfiguration ("missing required bootstrap secret key " <> key)))
        Right
        (lookup key values)

validateBootstrapConfig :: BootstrapConfig -> Either ScriptError ()
validateBootstrapConfig config = do
    requireNonEmpty "BOOTSTRAP_ACCOUNT_EMAIL" config.email
    requireNonEmpty "BOOTSTRAP_ACCOUNT_PASSWORD" config.password

requireNonEmpty :: Text -> Text -> Either ScriptError ()
requireNonEmpty name value =
    if Text.null (Text.strip value)
        then Left (InvalidScriptConfiguration (name <> " is empty"))
        else Right ()

fetchExistingSuperAdmin :: (?modelContext :: ModelContext) => IO (Maybe User)
fetchExistingSuperAdmin =
    query @User
        |> filterWhere (#platformRole, Just (SuperAdmin))
        |> fetchOneOrNothing

createBootstrapUser :: (?modelContext :: ModelContext) => Text -> Text -> IO (Either ScriptError User)
createBootstrapUser email password =
    query @User
        |> filterWhere (#email, email)
        |> fetchOneOrNothing
        >>= \case
            Just _ -> pure (Left (ScriptOperationFailed "bootstrap account email already exists but no super-admin exists; refusing to modify the existing user"))
            Nothing -> do
                passwordHash <- hashPassword password
                user <-
                    newRecord @User
                        |> set #email email
                        |> set #passwordHash passwordHash
                        |> set #userRole "staff"
                        |> set #platformRole (Just (SuperAdmin))
                        |> set #isProfileCompleted True
                        |> set #emailVerifiedAt (Just def)
                        |> createRecord
                pure (Right user)
