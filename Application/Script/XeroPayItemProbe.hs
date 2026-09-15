module Application.Script.XeroPayItemProbe where

import Application.Helper.Xero
import Application.Operator.Error
import Application.Script.Prelude
import Application.Xero.Connection
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.ByteString.Lazy.Char8 as LByteString
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import qualified Data.Text.IO as TextIO
import qualified Data.UUID as UUID
import qualified Data.Vector as Vector
import Network.HTTP.Simple
import System.Environment (lookupEnv)
import System.Exit (exitSuccess)

data ProbeOptions = ProbeOptions
    { optionConnectionId         :: !(Maybe Text)
    , optionProbeEarningsRatesV2 :: !Bool
    }
    deriving (Eq, Show)

defaultProbeOptions :: ProbeOptions
defaultProbeOptions =
    ProbeOptions
        { optionConnectionId = Nothing
        , optionProbeEarningsRatesV2 = False
        }

run :: Script
run = do
    args <- liftIO getArgs
    when ("--help" `elem` args) (liftIO usageAndExitSuccess)
    options <- liftIO (requireScriptResult (parseOptions defaultProbeOptions args))
    liftIO (requireScriptResult (either (Left . InvalidScriptArgument) Right (validateProbeOptions options)))
    connection <- resolveConnection options.optionConnectionId
    liftIO (authorizeEarningsRatesV2Probe connection)
    accessToken <- readStoredAccessTokenForProbe connection
    liftIO (probeEarningsRatesV2 connection accessToken)

parseOptions :: ProbeOptions -> [Text] -> Either ScriptError ProbeOptions
parseOptions options [] = Right options
parseOptions options (arg : rest)
    | arg == "--probe-earnings-rates-v2" = parseOptions options { optionProbeEarningsRatesV2 = True } rest
    | Just value <- Text.stripPrefix "--connection-id=" arg
    , not (Text.null value) = parseOptions options { optionConnectionId = Just value } rest
    | arg == "--connection-id=" = Left (InvalidScriptArgument "--connection-id requires a value")
    | otherwise = Left (InvalidScriptArgument ("unknown Xero pay-item probe option: " <> arg))

validateProbeOptions :: ProbeOptions -> Either Text ()
validateProbeOptions options
    | not options.optionProbeEarningsRatesV2 = Left "No probe action selected; use --help for usage."
    | otherwise = validateEarningsRatesV2ProbeOptions options

validateEarningsRatesV2ProbeOptions :: ProbeOptions -> Either Text ()
validateEarningsRatesV2ProbeOptions options
    | not options.optionProbeEarningsRatesV2 = Right ()
    | isNothing options.optionConnectionId = Left "The live Xero Earnings Rates probe requires --connection-id=<uuid>."
    | otherwise = Right ()

usageAndExitSuccess :: IO a
usageAndExitSuccess = usage >> exitSuccess

usage :: IO ()
usage = do
    TextIO.putStrLn "Usage:"
    TextIO.putStrLn "  XERO_ALLOW_LIVE_PROBE=1 XERO_ALLOW_LIVE_PROBE_TENANT_ID=<tenant-id> xero-pay-item-probe [app|app_test] --connection-id=<uuid> --probe-earnings-rates-v2"
    TextIO.putStrLn ""
    TextIO.putStrLn "This diagnostic is read-only, prints only response structure, refuses CI, and requires both live-probe gates."

resolveConnection :: (?modelContext :: ModelContext) => Maybe Text -> IO XeroConnection
resolveConnection (Just connectionIdText) =
    case UUID.fromText connectionIdText of
        Nothing -> liftIOError "Invalid Xero connection UUID."
        Just connectionUuid ->
            query @XeroConnection
                |> filterWhere (#id, (Id connectionUuid :: Id XeroConnection))
                |> fetchOneOrNothing
                >>= maybe (liftIOError "The selected Xero connection does not exist.") pure
resolveConnection Nothing = liftIOError "Pass --connection-id=<uuid>."

readStoredAccessTokenForProbe :: (?modelContext :: ModelContext) => XeroConnection -> IO Text
readStoredAccessTokenForProbe connection =
    readXeroConfig >>= \case
        Left message -> liftIOError message
        Right xeroConfig -> do
            now <- getCurrentTime
            case (connection.encryptedAccessToken, connection.accessTokenExpiresAt) of
                (Just encryptedAccessToken, Just expiresAt)
                    | expiresAt > addUTCTime 60 now ->
                        case decryptXeroToken xeroConfig.tokenEncryptionKey encryptedAccessToken of
                            Left _ -> liftIOError "Could not decrypt the stored Xero access token. Use the normal Xero workflow before probing."
                            Right accessToken -> pure accessToken
                _ -> liftIOError "The stored Xero access token is missing or near expiry. Use the normal Xero workflow to refresh it before probing; this read-only probe never rotates tokens."

authorizeEarningsRatesV2Probe :: XeroConnection -> IO ()
authorizeEarningsRatesV2Probe connection = do
    ci <- lookupEnv "CI"
    allowLiveProbe <- lookupEnv "XERO_ALLOW_LIVE_PROBE"
    allowedTenantId <- lookupEnv "XERO_ALLOW_LIVE_PROBE_TENANT_ID"
    when (isJust ci) (liftIOError "The live Xero Earnings Rates probe refuses to run in CI.")
    when (allowLiveProbe /= Just "1") (liftIOError "Set XERO_ALLOW_LIVE_PROBE=1 to acknowledge the real Xero network call.")
    when (allowedTenantId /= Just (cs connection.tenantId)) (liftIOError "XERO_ALLOW_LIVE_PROBE_TENANT_ID must exactly match the selected connection tenant id.")

probeEarningsRatesV2 :: XeroConnection -> Text -> IO ()
probeEarningsRatesV2 connection accessToken = do
    request <- parseRequest "https://api.xero.com/payroll.xro/2.0/earningsRates"
    let requestWithHeaders =
            request
                |> setRequestMethod "GET"
                |> setRequestHeader "Authorization" ["Bearer " <> TextEncoding.encodeUtf8 accessToken]
                |> setRequestHeader "Xero-Tenant-Id" [TextEncoding.encodeUtf8 connection.tenantId]
                |> setRequestHeader "Accept" ["application/json"]
    response <- httpLBS requestWithHeaders
    let statusCode = getResponseStatusCode response
    TextIO.putStrLn "Operation: GET /payroll.xro/2.0/earningsRates"
    TextIO.putStrLn ("Xero status: " <> tshow statusCode)
    if statusCode >= 200 && statusCode < 300
        then TextIO.putStrLn ("Sanitized response shape: " <> earningsRatesResponseShape (getResponseBody response))
        else TextIO.putStrLn ("Response body redacted; bytes=" <> tshow (LByteString.length (getResponseBody response)))

-- Keep live diagnostics structural: names, rates, account codes, and provider
-- error bodies can contain customer data and must not be emitted by this probe.
earningsRatesResponseShape :: LByteString.ByteString -> Text
earningsRatesResponseShape body =
    case Aeson.decode body of
        Nothing -> "non-JSON body; bytes=" <> tshow (LByteString.length body)
        Just (Aeson.Array values) -> "direct array; count=" <> tshow (Vector.length values)
        Just (Aeson.Object object) ->
            case KeyMap.lookup (Key.fromText "EarningsRates") object <|> KeyMap.lookup (Key.fromText "earningsRates") object of
                Just (Aeson.Array values) -> "EarningsRates envelope; count=" <> tshow (Vector.length values)
                Just _ -> "EarningsRates envelope; collection is not an array"
                Nothing -> "object; EarningsRates collection absent"
        Just _ -> "JSON scalar"

liftIOError :: Text -> IO a
liftIOError = exitWithScriptError . ScriptOperationFailed
