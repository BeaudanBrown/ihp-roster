{-# LANGUAGE PackageImports #-}

-- | Read-only, redacted support evidence for one persisted Xero timesheet write.
module Application.Xero.Timesheets.Diagnostic
    ( XeroTimesheetDiagnostic (..)
    , XeroTimesheetDiagnosticError (..)
    , XeroTimesheetDiagnosticLine (..)
    , XeroTimesheetDiagnosticSnapshot (..)
    , fetchXeroTimesheetDiagnostic
    ) where

import Application.Helper.OpaqueToken (hashOpaqueToken)
import Application.Helper.Xero
import Application.Xero.Connection (refreshXeroConnectionAccess)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.KeyMap as AesonKeyMap
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Data.Scientific (Scientific)
import qualified Data.Text as Text
import qualified Data.Vector as Vector
import Generated.Types
import IHP.ControllerPrelude

data XeroTimesheetDiagnosticError
    = DiagnosticMissingTimesheetReference
    | DiagnosticXeroConfigurationUnavailable
    | DiagnosticXeroConnectionUnavailable
    | DiagnosticXeroTimesheetUnavailable
    | DiagnosticXeroTimesheetScopeMismatch
    deriving (Eq, Show)

data XeroTimesheetDiagnostic = XeroTimesheetDiagnostic
    { diagnosticSubmissionRef :: !Text
    , diagnosticTimesheetRef  :: !Text
    , diagnosticEmployeeRef   :: !Text
    , diagnosticPeriodStart   :: !Day
    , diagnosticPeriodEnd     :: !Day
    , diagnosticSnapshots     :: ![XeroTimesheetDiagnosticSnapshot]
    }
    deriving (Eq, Show)

data XeroTimesheetDiagnosticSnapshot = XeroTimesheetDiagnosticSnapshot
    { diagnosticSnapshotLabel               :: !Text
    , diagnosticSnapshotStatus              :: !(Maybe Text)
    , diagnosticSnapshotProviderUpdatedAt   :: !(Maybe Text)
    , diagnosticSnapshotHasValidationErrors :: !Bool
    , diagnosticSnapshotLines               :: ![XeroTimesheetDiagnosticLine]
    }
    deriving (Eq, Show)

data XeroTimesheetDiagnosticLine = XeroTimesheetDiagnosticLine
    { diagnosticLineOrdinal           :: !Int
    , diagnosticLineEarningsRateRef   :: !(Maybe Text)
    , diagnosticLineUnits             :: ![Scientific]
    , diagnosticLinePayItemFound      :: !Bool
    , diagnosticLineRateType          :: !(Maybe Text)
    , diagnosticLineTypeOfUnits       :: !(Maybe Text)
    , diagnosticLineRatePerUnit       :: !(Maybe Scientific)
    , diagnosticLineActive            :: !(Maybe Bool)
    , diagnosticLineProviderAvailable :: !(Maybe Bool)
    , diagnosticLineReferenceSyncedAt :: !(Maybe UTCTime)
    }
    deriving (Eq, Show)

fetchXeroTimesheetDiagnostic ::
    (?modelContext :: ModelContext) =>
    XeroTimesheetSubmission ->
    XeroConnection ->
    IO (Either XeroTimesheetDiagnosticError XeroTimesheetDiagnostic)
fetchXeroTimesheetDiagnostic submission connection =
    case submission.xeroTimesheetId of
        Nothing -> pure (Left DiagnosticMissingTimesheetReference)
        Just timesheetId -> do
            readXeroConfig >>= \case
                Left _ -> pure (Left DiagnosticXeroConfigurationUnavailable)
                Right xeroConfig ->
                    refreshXeroConnectionAccess xeroConfig connection >>= \case
                        Left _ -> pure (Left DiagnosticXeroConnectionUnavailable)
                        Right (refreshedConnection, accessToken) -> do
                            client <- currentXeroClient
                            client.fetchTimesheet accessToken refreshedConnection.tenantId timesheetId >>= \case
                                Left _ -> pure (Left DiagnosticXeroTimesheetUnavailable)
                                Right remote
                                    | not (remoteMatchesSubmission submission remote) ->
                                        pure (Left DiagnosticXeroTimesheetScopeMismatch)
                                    | otherwise -> do
                                        let rateIds =
                                                List.nub
                                                    ( mapMaybe (.xeroTimesheetLineEarningsRateId) remote.xeroTimesheetLines
                                                        <> snapshotRateIds (firstRequestObject submission.requestPayloadJson)
                                                        <> snapshotRateIds (storedResponseObject submission.responsePayloadJson)
                                                    )
                                        rates <-
                                            query @XeroEarningsRate
                                                |> filterWhere (#xeroConnectionId, unpackId refreshedConnection.id)
                                                |> filterWhereIn (#xeroEarningsRateId, rateIds)
                                                |> fetch
                                        pure (Right (buildDiagnostic submission timesheetId rates remote))

remoteMatchesSubmission :: XeroTimesheetSubmission -> XeroTimesheetRef -> Bool
remoteMatchesSubmission submission remote =
    remote.xeroTimesheetEmployeeId == submission.xeroEmployeeId
        && remote.xeroTimesheetStartDate == submission.payPeriodStart
        && remote.xeroTimesheetEndDate == submission.payPeriodEnd

buildDiagnostic :: XeroTimesheetSubmission -> Text -> [XeroEarningsRate] -> XeroTimesheetRef -> XeroTimesheetDiagnostic
buildDiagnostic submission timesheetId rates remote =
    let rateMap = Map.fromList [(rate.xeroEarningsRateId, rate) | rate <- rates]
     in XeroTimesheetDiagnostic
            { diagnosticSubmissionRef = redactedRef (tshow (unpackId submission.id))
            , diagnosticTimesheetRef = redactedRef timesheetId
            , diagnosticEmployeeRef = redactedRef submission.xeroEmployeeId
            , diagnosticPeriodStart = submission.payPeriodStart
            , diagnosticPeriodEnd = submission.payPeriodEnd
            , diagnosticSnapshots =
                [ snapshotFromRequest rateMap submission.requestPayloadJson
                , snapshotFromStoredResponse rateMap submission.responsePayloadJson
                , snapshotFromRemote rateMap remote
                ]
            }

snapshotFromRequest :: Map.Map Text XeroEarningsRate -> Aeson.Value -> XeroTimesheetDiagnosticSnapshot
snapshotFromRequest rateMap payload =
    snapshotFromValue rateMap "Submitted request" (firstRequestObject payload)

snapshotFromStoredResponse :: Map.Map Text XeroEarningsRate -> Aeson.Value -> XeroTimesheetDiagnosticSnapshot
snapshotFromStoredResponse rateMap payload =
    snapshotFromValue rateMap "Stored Xero response" (storedResponseObject payload)

snapshotFromRemote :: Map.Map Text XeroEarningsRate -> XeroTimesheetRef -> XeroTimesheetDiagnosticSnapshot
snapshotFromRemote rateMap remote =
    XeroTimesheetDiagnosticSnapshot
        { diagnosticSnapshotLabel = "Current Xero draft"
        , diagnosticSnapshotStatus = remote.xeroTimesheetStatus
        , diagnosticSnapshotProviderUpdatedAt = providerUpdatedAt remote.xeroTimesheetRaw
        , diagnosticSnapshotHasValidationErrors = hasValidationErrors remote.xeroTimesheetRaw
        , diagnosticSnapshotLines = zipWith (diagnosticLine rateMap) [1 ..] remote.xeroTimesheetLines
        }

snapshotFromValue :: Map.Map Text XeroEarningsRate -> Text -> Maybe Aeson.Value -> XeroTimesheetDiagnosticSnapshot
snapshotFromValue rateMap label maybeValue =
    let value = fromMaybe (Aeson.object []) maybeValue
        linesForSnapshot = timesheetLines value
     in XeroTimesheetDiagnosticSnapshot
            { diagnosticSnapshotLabel = label
            , diagnosticSnapshotStatus = objectText ["Status", "status"] value
            , diagnosticSnapshotProviderUpdatedAt = providerUpdatedAt value
            , diagnosticSnapshotHasValidationErrors = hasValidationErrors value
            , diagnosticSnapshotLines = zipWith (diagnosticLine rateMap) [1 ..] linesForSnapshot
            }

firstRequestObject :: Aeson.Value -> Maybe Aeson.Value
firstRequestObject (Aeson.Array values)   = Vector.toList values |> listToMaybe
firstRequestObject value@(Aeson.Object _) = Just value
firstRequestObject _                      = Nothing

storedResponseObject :: Aeson.Value -> Maybe Aeson.Value
storedResponseObject (Aeson.Object object) = do
    Aeson.Array timesheets <- lookupAny ["Timesheets", "timesheets"] object
    value <- listToMaybe (Vector.toList timesheets)
    case value of
        Aeson.Object timesheetObject ->
            case lookupAny ["Raw", "raw"] timesheetObject of
                Just raw@(Aeson.Object _) -> Just raw
                _                         -> Just value
        _ -> Nothing
storedResponseObject _ = Nothing

timesheetLines :: Aeson.Value -> [XeroTimesheetLineRef]
timesheetLines (Aeson.Object object) =
    case lookupAny ["TimesheetLines", "timesheetLines"] object of
        Just (Aeson.Array values) -> mapMaybe decodeLine (Vector.toList values)
        _                         -> []
  where
    decodeLine value =
        case Aeson.fromJSON value of
            Aeson.Success line -> Just line
            Aeson.Error _      -> Nothing
timesheetLines _ = []

snapshotRateIds :: Maybe Aeson.Value -> [Text]
snapshotRateIds = maybe [] (mapMaybe (.xeroTimesheetLineEarningsRateId) . timesheetLines)

diagnosticLine :: Map.Map Text XeroEarningsRate -> Int -> XeroTimesheetLineRef -> XeroTimesheetDiagnosticLine
diagnosticLine rateMap ordinal line =
    let maybeRate = line.xeroTimesheetLineEarningsRateId >>= (`Map.lookup` rateMap)
     in XeroTimesheetDiagnosticLine
            { diagnosticLineOrdinal = ordinal
            , diagnosticLineEarningsRateRef = redactedRef <$> line.xeroTimesheetLineEarningsRateId
            , diagnosticLineUnits = line.xeroTimesheetLineUnits
            , diagnosticLinePayItemFound = isJust maybeRate
            , diagnosticLineRateType = (.rateType) =<< maybeRate
            , diagnosticLineTypeOfUnits = maybeRate >>= rawPayloadText ["TypeOfUnits", "typeOfUnits"] . (.rawPayload)
            , diagnosticLineRatePerUnit = maybeRate >>= rawPayloadScientific ["RatePerUnit", "ratePerUnit"] . (.rawPayload)
            , diagnosticLineActive = (.isActive) <$> maybeRate
            , diagnosticLineProviderAvailable = (.providerAvailable) <$> maybeRate
            , diagnosticLineReferenceSyncedAt = (.syncedAt) <$> maybeRate
            }

redactedRef :: Text -> Text
redactedRef = Text.take 16 . hashOpaqueToken

providerUpdatedAt :: Aeson.Value -> Maybe Text
providerUpdatedAt = objectText ["UpdatedDateUTC", "updatedDateUTC", "UpdatedDateUtc", "updatedDateUtc"]

objectText :: [Text] -> Aeson.Value -> Maybe Text
objectText keys (Aeson.Object object) =
    case lookupAny keys object of
        Just (Aeson.String value) -> Just value
        _                         -> Nothing
objectText _ _ = Nothing

rawPayloadText :: [Text] -> Aeson.Value -> Maybe Text
rawPayloadText = objectText

rawPayloadScientific :: [Text] -> Aeson.Value -> Maybe Scientific
rawPayloadScientific keys (Aeson.Object object) =
    case lookupAny keys object of
        Just (Aeson.Number value) -> Just value
        _                         -> Nothing
rawPayloadScientific _ _ = Nothing

lookupAny :: [Text] -> AesonKeyMap.KeyMap Aeson.Value -> Maybe Aeson.Value
lookupAny keys object =
    listToMaybe (mapMaybe (\key -> AesonKeyMap.lookup (AesonKey.fromText key) object) keys)

hasValidationErrors :: Aeson.Value -> Bool
hasValidationErrors (Aeson.Object object) =
    any keyContainsValidationErrors (AesonKeyMap.toList object)
  where
    keyContainsValidationErrors (key, value)
        | Text.toCaseFold (AesonKey.toText key) `elem` ["validationerrors", "validation_errors"] = nonEmptyValue value
        | otherwise = hasValidationErrors value
hasValidationErrors (Aeson.Array values) = any hasValidationErrors values
hasValidationErrors _ = False

nonEmptyValue :: Aeson.Value -> Bool
nonEmptyValue (Aeson.Array values)  = not (Vector.null values)
nonEmptyValue (Aeson.Object object) = not (AesonKeyMap.null object)
nonEmptyValue Aeson.Null            = False
nonEmptyValue (Aeson.String value)  = not (Text.null (Text.strip value))
nonEmptyValue _                     = True
