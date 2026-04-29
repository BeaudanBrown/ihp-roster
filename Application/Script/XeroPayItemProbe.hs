module Application.Script.XeroPayItemProbe where

import Application.Helper.Xero
import Application.Script.Prelude
import Application.Xero.Connection
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.ByteString.Lazy.Char8 as LByteString
import qualified Data.Char as Char
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import qualified Data.Text.IO as TextIO
import qualified Data.UUID as UUID
import Data.Time.Format (defaultTimeLocale, formatTime)
import Network.HTTP.Simple
import System.Exit (exitFailure, exitSuccess)

data ProbeOptions = ProbeOptions
    { optionConnectionId   :: !(Maybe Text)
    , optionRequirementKey :: !(Maybe Text)
    , optionIdempotencyKey :: !(Maybe Text)
    , optionConfirmPost    :: !Bool
    , optionConnections    :: !Bool
    , optionList           :: !Bool
    , optionGetPayItems    :: !Bool
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
        }

run :: Script
run = do
    args <- liftIO getArgs
    options <- liftIO (parseOptions defaultProbeOptions args)
    when options.optionConnections listConnections
    when options.optionConnections do
        when (isNothing options.optionConnectionId && isNothing options.optionRequirementKey && not options.optionList && not options.optionGetPayItems) do
            liftIO exitSuccess
    connection <- resolveConnection options.optionConnectionId
    liftIO do
        TextIO.putStrLn ("Connection: " <> tshow connection.id)
        TextIO.putStrLn ("Tenant: " <> fromMaybe connection.tenantId connection.tenantName <> " (" <> connection.tenantId <> ")")
    when options.optionList do
        listRequirements connection
    when options.optionGetPayItems do
        accessToken <- refreshConnection connection
        liftIO (rawGetPayItems connection accessToken)
    case options.optionRequirementKey of
        Nothing ->
            when (not options.optionList && not options.optionGetPayItems) (liftIO usageAndExitFailure)
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
    | Just value <- stripPrefixText "--connection-id=" arg = parseOptions options { optionConnectionId = Just value } rest
    | Just value <- stripPrefixText "--requirement-key=" arg = parseOptions options { optionRequirementKey = Just value } rest
    | Just value <- stripPrefixText "--idempotency-key=" arg = parseOptions options { optionIdempotencyKey = Just value } rest
    | otherwise = do
        TextIO.putStrLn ("Unknown option: " <> arg)
        usageAndExitFailure

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
    TextIO.putStrLn "  xero-pay-item-probe [app|app_test] --connection-id=<uuid> --requirement-key=<key> [--idempotency-key=<key>] [--confirm-post]"
    TextIO.putStrLn ""
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
                requirement.requirementStatus
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
            |> filterWhere (#selectionStatus, "verified" :: Text)
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
