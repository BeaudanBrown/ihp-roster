module Application.Script.XeroPayItemProbe where

import Application.Helper.Xero
import Application.Script.Prelude
import Application.Xero.Connection
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.ByteString.Lazy.Char8 as LByteString
import qualified Data.Char as Char
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import qualified Data.Text.IO as TextIO
import Data.Time.Format (defaultTimeLocale, formatTime)
import qualified Data.UUID as UUID
import qualified Data.Vector as Vector
import IHP.ModelSupport (inputValue)
import Network.HTTP.Simple
import System.Environment (lookupEnv)
import System.Exit (exitFailure, exitSuccess)

data ProbeOptions = ProbeOptions
    { optionConnectionId         :: !(Maybe Text)
    , optionRequirementKey       :: !(Maybe Text)
    , optionIdempotencyKey       :: !(Maybe Text)
    , optionConfirmPost          :: !Bool
    , optionConnections          :: !Bool
    , optionList                 :: !Bool
    , optionGetPayItems          :: !Bool
    , optionProbeEarningsRatesV2 :: !Bool
    }

defaultProbeOptions :: ProbeOptions
defaultProbeOptions =
    ProbeOptions
        { optionConnectionId = Nothing
        , optionRequirementKey = Nothing
        , optionIdempotencyKey = Nothing
        , optionConfirmPost = False
        , optionConnections = False
        , optionList = False
        , optionGetPayItems = False
        , optionProbeEarningsRatesV2 = False
        }

run :: Script
run = do
    args <- liftIO getArgs
    options <- liftIO (parseOptions defaultProbeOptions args)
    case validateEarningsRatesV2ProbeOptions options of
        Left message -> liftIO (liftIOError message)
        Right ()     -> pure ()
    when options.optionConnections listConnections
    when options.optionConnections do
        when (isNothing options.optionConnectionId && isNothing options.optionRequirementKey && not options.optionList && not options.optionGetPayItems) do
            liftIO exitSuccess
    connection <- resolveConnection options.optionConnectionId
    liftIO do
        TextIO.putStrLn ("Connection: " <> tshow connection.id)
        if options.optionProbeEarningsRatesV2
            then TextIO.putStrLn ("Tenant ID: " <> connection.tenantId)
            else TextIO.putStrLn ("Tenant: " <> fromMaybe connection.tenantId connection.tenantName <> " (" <> connection.tenantId <> ")")
    when options.optionList do
        listRequirements connection
    when options.optionGetPayItems do
        accessToken <- refreshConnection connection
        liftIO (rawGetPayItems connection accessToken)
    when options.optionProbeEarningsRatesV2 do
        liftIO (authorizeEarningsRatesV2Probe connection)
        accessToken <- readStoredAccessTokenForProbe connection
        liftIO (probeEarningsRatesV2 connection accessToken)
    case options.optionRequirementKey of
        Nothing ->
            when (not options.optionList && not options.optionGetPayItems && not options.optionProbeEarningsRatesV2) (liftIO usageAndExitFailure)
        Just requirementKey -> do
            requirement <- fetchRequirement connection requirementKey
            accountCode <- fetchVerifiedAccountCode connection
            accessToken <- refreshConnection connection
            existingPayItems <- liftIO (rawFetchPayItems connection accessToken)
            let body = payItemBody existingPayItems accountCode requirement
            now <- liftIO getCurrentTime
            let idempotencyKey = fromMaybe (defaultIdempotencyKey now requirement) options.optionIdempotencyKey
            liftIO do
                TextIO.putStrLn ""
                TextIO.putStrLn ("Requirement: " <> requirement.displayName)
                TextIO.putStrLn ("Requirement key: " <> requirement.requirementKey)
                TextIO.putStrLn ("Idempotency key: " <> idempotencyKey)
                TextIO.putStrLn "Request body:"
                LByteString.putStrLn (Aeson.encode body)
            if options.optionConfirmPost
                then liftIO (rawPostPayItem connection accessToken idempotencyKey body)
                else liftIO do
                    TextIO.putStrLn ""
                    TextIO.putStrLn "Not posting. Re-run with --confirm-post to hit Xero POST /PayItems."

parseOptions :: ProbeOptions -> [Text] -> IO ProbeOptions
parseOptions options [] = pure options
parseOptions options (arg : rest)
    | arg == "--help" = usageAndExitSuccess
    | arg == "--confirm-post" = parseOptions options { optionConfirmPost = True } rest
    | arg == "--connections" = parseOptions options { optionConnections = True } rest
    | arg == "--list" = parseOptions options { optionList = True } rest
    | arg == "--get-pay-items" = parseOptions options { optionGetPayItems = True } rest
    | arg == "--probe-earnings-rates-v2" = parseOptions options { optionProbeEarningsRatesV2 = True } rest
    | Just value <- stripPrefixText "--connection-id=" arg = parseOptions options { optionConnectionId = Just value } rest
    | Just value <- stripPrefixText "--requirement-key=" arg = parseOptions options { optionRequirementKey = Just value } rest
    | Just value <- stripPrefixText "--idempotency-key=" arg = parseOptions options { optionIdempotencyKey = Just value } rest
    | otherwise = do
        TextIO.putStrLn ("Unknown option: " <> arg)
        usageAndExitFailure

validateEarningsRatesV2ProbeOptions :: ProbeOptions -> Either Text ()
validateEarningsRatesV2ProbeOptions options
    | not options.optionProbeEarningsRatesV2 = Right ()
    | isNothing options.optionConnectionId = Left "The live Xero Earnings Rates probe requires --connection-id=<uuid>."
    | probeHasIncompatibleOptions options = Left "The live Xero Earnings Rates probe cannot be combined with list, raw PayItems, requirement, idempotency, or mutation options."
    | otherwise = Right ()

probeHasIncompatibleOptions :: ProbeOptions -> Bool
probeHasIncompatibleOptions options =
    options.optionConnections
        || options.optionList
        || options.optionGetPayItems
        || isJust options.optionRequirementKey
        || isJust options.optionIdempotencyKey
        || options.optionConfirmPost

stripPrefixText :: Text -> Text -> Maybe Text
stripPrefixText prefix arg =
    Text.stripPrefix prefix arg

usageAndExitFailure :: IO a
usageAndExitFailure = do
    usage
    exitFailure

usageAndExitSuccess :: IO a
usageAndExitSuccess = do
    usage
    exitSuccess

usage :: IO ()
usage = do
    TextIO.putStrLn "Usage:"
    TextIO.putStrLn "  xero-pay-item-probe [app|app_test] --connections"
    TextIO.putStrLn "  xero-pay-item-probe [app|app_test] --connection-id=<uuid> --list"
    TextIO.putStrLn "  xero-pay-item-probe [app|app_test] --connection-id=<uuid> --get-pay-items"
    TextIO.putStrLn "  XERO_ALLOW_LIVE_PROBE=1 XERO_ALLOW_LIVE_PROBE_TENANT_ID=<tenant-id> xero-pay-item-probe [app|app_test] --connection-id=<uuid> --probe-earnings-rates-v2"
    TextIO.putStrLn "  xero-pay-item-probe [app|app_test] --connection-id=<uuid> --requirement-key=<key> [--idempotency-key=<key>] [--confirm-post]"
    TextIO.putStrLn ""
    TextIO.putStrLn "The v2 probe is read-only and prints only response structure; it refuses CI and requires both live-probe gates."
    TextIO.putStrLn "Without --confirm-post, the command prints the exact request body but does not create anything in Xero."

listConnections :: (?modelContext :: ModelContext) => IO ()
listConnections = do
    connections <-
        query @XeroConnection
            |> orderByDesc #connectedAt
            |> fetch
    liftIO do
        TextIO.putStrLn "Xero connections:"
        forM_ connections \connection ->
            TextIO.putStrLn $
                tshow connection.id
                    <> " | "
                    <> connection.connectionStatus
                    <> " | "
                    <> fromMaybe connection.tenantId connection.tenantName
                    <> " | tenant="
                    <> connection.tenantId

resolveConnection :: (?modelContext :: ModelContext) => Maybe Text -> IO XeroConnection
resolveConnection (Just connectionIdText) =
    case UUID.fromText connectionIdText of
        Nothing -> liftIOError ("Invalid Xero connection UUID: " <> connectionIdText)
        Just connectionUuid -> fetch (Id connectionUuid :: Id XeroConnection)
resolveConnection Nothing = do
    connections <-
        query @XeroConnection
            |> filterWhere (#connectionStatus, "active" :: Text)
            |> fetch
    case connections of
        [connection] -> pure connection
        []           -> liftIOError "No active Xero connection found. Pass --connection-id=<uuid>."
        _            -> liftIOError "Multiple active Xero connections found. Pass --connection-id=<uuid>."

listRequirements :: (?modelContext :: ModelContext) => XeroConnection -> IO ()
listRequirements connection = do
    requirements <-
        query @XeroPayItemRequirementRecord
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> orderByAsc #displayName
            |> fetch
    liftIO do
        TextIO.putStrLn ""
        TextIO.putStrLn "Local Xero pay item requirements:"
        forM_ requirements \requirement ->
            TextIO.putStrLn $
                inputValue requirement.requirementStatus
                    <> " | "
                    <> requirement.requirementKey
                    <> " | "
                    <> requirement.displayName

fetchRequirement :: (?modelContext :: ModelContext) => XeroConnection -> Text -> IO XeroPayItemRequirementRecord
fetchRequirement connection requirementKey =
    query @XeroPayItemRequirementRecord
        |> filterWhere (#xeroConnectionId, unpackId connection.id)
        |> filterWhere (#requirementKey, requirementKey)
        |> fetchOne

fetchVerifiedAccountCode :: (?modelContext :: ModelContext) => XeroConnection -> IO Text
fetchVerifiedAccountCode connection = do
    selection <-
        query @XeroPayItemAccountCodeSelection
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#selectionStatus, XeroPayItemAccountCodeSelectionStatusEnumVerified)
            |> fetchOne
    case Text.strip <$> selection.accountCode of
        Just accountCode | not (Text.null accountCode) -> pure accountCode
        _ -> liftIOError "The selected Xero pay item account code is blank."

refreshConnection :: (?modelContext :: ModelContext) => XeroConnection -> IO Text
refreshConnection connection =
    readXeroConfig >>= \case
        Left message -> liftIOError message
        Right xeroConfig ->
            refreshXeroConnectionAccess xeroConfig connection >>= \case
                Left message -> liftIOError message
                Right (_, accessToken) -> pure accessToken

rawGetPayItems :: XeroConnection -> Text -> IO ()
rawGetPayItems connection accessToken = do
    response <- rawFetchPayItemsResponse connection accessToken
    printRawResponse response

rawFetchPayItems :: XeroConnection -> Text -> IO Aeson.Value
rawFetchPayItems connection accessToken = do
    response <- rawFetchPayItemsResponse connection accessToken
    let body = getResponseBody response
    case Aeson.eitherDecode body of
        Left err -> liftIOError ("Could not decode Xero GET /PayItems response: " <> cs err)
        Right value -> pure value

rawFetchPayItemsResponse :: XeroConnection -> Text -> IO (Response LByteString.ByteString)
rawFetchPayItemsResponse connection accessToken = do
    request <- parseRequest "https://api.xero.com/payroll.xro/1.0/PayItems"
    let requestWithHeaders =
            request
                |> setRequestMethod "GET"
                |> setRequestHeader "Authorization" ["Bearer " <> TextEncoding.encodeUtf8 accessToken]
                |> setRequestHeader "Xero-Tenant-Id" [TextEncoding.encodeUtf8 connection.tenantId]
                |> setRequestHeader "Accept" ["application/json"]
    httpLBS requestWithHeaders

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

rawPostPayItem :: XeroConnection -> Text -> Text -> Aeson.Value -> IO ()
rawPostPayItem connection accessToken idempotencyKey body = do
    request <- parseRequest "https://api.xero.com/payroll.xro/1.0/PayItems"
    let requestWithHeaders =
            request
                |> setRequestMethod "POST"
                |> setRequestHeader "Authorization" ["Bearer " <> TextEncoding.encodeUtf8 accessToken]
                |> setRequestHeader "Xero-Tenant-Id" [TextEncoding.encodeUtf8 connection.tenantId]
                |> setRequestHeader "Idempotency-Key" [TextEncoding.encodeUtf8 idempotencyKey]
                |> setRequestHeader "Accept" ["application/json"]
                |> setRequestHeader "Content-Type" ["application/json"]
                |> setRequestBodyJSON body
    response <- httpLBS requestWithHeaders
    printRawResponse response

printRawResponse :: Response LByteString.ByteString -> IO ()
printRawResponse response = do
    TextIO.putStrLn ""
    TextIO.putStrLn ("Xero status: " <> tshow (getResponseStatusCode response))
    TextIO.putStrLn "Xero response body:"
    LByteString.putStrLn (getResponseBody response)

payItemBody :: Aeson.Value -> Text -> XeroPayItemRequirementRecord -> Aeson.Value
payItemBody existingPayItems accountCode requirement =
    Aeson.object
        [ "EarningsRates" Aeson..= (existingEarningsRates existingPayItems <> [earningsRateBody accountCode requirement])
        ]

existingEarningsRates :: Aeson.Value -> [Aeson.Value]
existingEarningsRates =
    fromMaybe [] . AesonTypes.parseMaybe parser
    where
        parser =
            Aeson.withObject "Xero pay items response" \object -> do
                payItems <- object Aeson..: "PayItems"
                Aeson.withObject "Xero pay items" (\payItemsObject -> payItemsObject Aeson..: "EarningsRates") payItems

earningsRateBody :: Text -> XeroPayItemRequirementRecord -> Aeson.Value
earningsRateBody accountCode requirement =
    Aeson.object
        [ "Name" Aeson..= requirement.displayName
        , "TypeOfUnits" Aeson..= ("Hours" :: Text)
        , "EarningsType" Aeson..= requirement.earningsType
        , "RateType" Aeson..= requirement.rateType
        , "RatePerUnit" Aeson..= requirement.ratePerUnit
        , "IsExemptFromTax" Aeson..= False
        , "IsExemptFromSuper" Aeson..= False
        , "IsReportableAsW1" Aeson..= True
        , "IsQualifyingEarnings" Aeson..= True
        , "AccountCode" Aeson..= accountCode
        ]

defaultIdempotencyKey :: UTCTime -> XeroPayItemRequirementRecord -> Text
defaultIdempotencyKey now requirement =
    "bepis-pay-item-"
        <> cs (formatTime defaultTimeLocale "%Y%m%d%H%M%S%q" now)
        <> "-"
        <> Text.take 80 (idempotencySlug requirement.requirementKey)

idempotencySlug :: Text -> Text
idempotencySlug =
    Text.map \char ->
        if Char.isAlphaNum char
            then Char.toLower char
            else '-'

liftIOError :: Text -> IO a
liftIOError message =
    error (cs message)
