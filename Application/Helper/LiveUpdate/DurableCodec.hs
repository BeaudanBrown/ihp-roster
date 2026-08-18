{-# LANGUAGE LambdaCase #-}

-- | Stable persistence representation for typed Surface resources.
--
-- The database never needs a column per resource: the checked Surface registry
-- is the schema for resource names and field shapes.  The payload envelope is
-- explicitly versioned so later codecs can be introduced without rewriting
-- event history.
module Application.Helper.LiveUpdate.DurableCodec
    ( DurableResource (..)
    , canonicalDurableResourceKey
    , decodeDurableResource
    , encodeDurableResource
    ) where

import qualified Application.Helper.FrontendContract.Core as Contract
import qualified Application.Helper.FrontendContract.Surface.ContractIR as Surface
import Application.Helper.FrontendContract.Surface.Contracts (registeredFrontendSurfaceContractIR)
import Application.Helper.FrontendContract.Surface.Resource (SurfaceResourceValue)
import qualified Application.Helper.FrontendContract.Surface.Resource.Internal as Resource
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.KeyMap as AesonKeyMap
import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Lazy as LazyByteString
import Data.Scientific (Scientific)
import qualified Data.Text.Encoding as TextEncoding
import Data.Time.Format (defaultTimeLocale, parseTimeM)
import qualified Data.UUID as UUID
import IHP.Prelude

data DurableResource = DurableResource
    { durableResourceKey     :: !Text
    , durableResourcePayload :: !Aeson.Value
    , durableResourceValue   :: !SurfaceResourceValue
    }
    deriving (Eq, Show)

codecVersion :: Int
codecVersion = 1

maximumPayloadBytes :: Int
maximumPayloadBytes = 8192

maximumResourceKeyBytes :: Int
maximumResourceKeyBytes = 2048

-- | Encode only resources declared by the checked production registry.  This
-- rejects invalid opaque values before they can enter the durable handoff.
encodeDurableResource :: SurfaceResourceValue -> Either Text DurableResource
encodeDurableResource resource = do
    let (name, fields) = Resource.surfaceResourceIdentity resource
    declaration <- maybeToRight "unknown live resource" (findResource name)
    validateFields declaration.resourceFields fields
    let payload = Aeson.object
            [ "version" Aeson..= codecVersion
            , "resource" Aeson..= name
            , "fields" Aeson..= fields
            ]
    let encodedPayload = LazyByteString.toStrict (Aeson.encode payload)
    unless (ByteString.length encodedPayload <= maximumPayloadBytes) do
        Left "live resource payload exceeds 8192 bytes"
    let key = canonicalDurableResourceKey name fields
    unless (ByteString.length (TextEncoding.encodeUtf8 key) <= maximumResourceKeyBytes) do
        Left "live resource key exceeds 2048 bytes"
    pure DurableResource { durableResourceKey = key, durableResourcePayload = payload, durableResourceValue = resource }

canonicalDurableResourceKey :: Text -> Aeson.Value -> Text
canonicalDurableResourceKey name fields =
    name <> ":" <> TextEncoding.decodeUtf8 (LazyByteString.toStrict (Aeson.encode fields))

-- | Decode a stored envelope only if it still describes a registered resource
-- with its exact field names and JSON wire shapes.
decodeDurableResource :: Text -> Aeson.Value -> Either Text DurableResource
decodeDurableResource expectedKey payload = do
    unless (LazyByteString.length (Aeson.encode payload) <= fromIntegral maximumPayloadBytes) do
        Left "live resource payload exceeds 8192 bytes"
    (version, name, fields) <-
        case payload of
            Aeson.Object object -> do
                unless (sort (map AesonKey.toText (AesonKeyMap.keys object)) == ["fields", "resource", "version"]) do
                    Left "live resource payload fields do not match envelope"
                version <- maybeToRight "live resource payload has no version" (AesonKeyMap.lookup "version" object >>= asInt)
                name <- maybeToRight "live resource payload has no resource name" (AesonKeyMap.lookup "resource" object >>= asText)
                fields <- maybeToRight "live resource payload has no fields" (AesonKeyMap.lookup "fields" object)
                pure (version, name, fields)
            _ -> Left "live resource payload must be an object"
    unless (version == codecVersion) (Left "unsupported live resource payload version")
    declaration <- maybeToRight "unknown live resource" (findResource name)
    validateFields declaration.resourceFields fields
    let resource = Resource.mkSurfaceResourceValue name fields
    encoded <- encodeDurableResource resource
    unless (encoded.durableResourceKey == expectedKey) (Left "live resource key does not match canonical payload")
    pure encoded

findResource :: Text -> Maybe Surface.ResourceIR
findResource name =
    find ((== name) . (.resourceName)) allResources
  where
    allResources = do
        surface <- registeredFrontendSurfaceContractIR.contractSurfaces
        fragment <- surface.surfaceFragments
        dependency <- Surface.optionResourceDependencies fragment.fragmentOptions
        pure dependency.dependencyResource

validateFields :: [Contract.FieldIR] -> Aeson.Value -> Either Text ()
validateFields declarations = \case
    Aeson.Object fields -> do
        let expected = map (.fieldName) declarations
        unless (sort (map AesonKey.toText (AesonKeyMap.keys fields)) == sort expected) (Left "live resource fields do not match declaration")
        forM_ declarations \field ->
            case AesonKeyMap.lookup (AesonKey.fromText field.fieldName) fields of
                Just value | validWire field.fieldWire value -> pure ()
                _ -> Left ("malformed live resource field: " <> field.fieldName)
    _ -> Left "live resource fields must be an object"

validWire :: Contract.WireIR -> Aeson.Value -> Bool
validWire wire value = case wire of
    Contract.WireTextIR -> isText value
    Contract.WireIntIR -> maybe False isIntegral (asNumber value)
    Contract.WireBoolIR -> case value of Aeson.Bool _ -> True; _ -> False
    Contract.WireUuidIR -> maybe False (isJust . UUID.fromText) (asText value)
    Contract.WireDayIR -> maybe False (isJust . (parseTimeM True defaultTimeLocale "%F" :: String -> Maybe Day)) (cs <$> asText value)
    Contract.WireClosedIR {} -> isText value
    Contract.WireUnknownIR -> False
    Contract.WireListIR child -> maybe False (all (validWire child)) (asArray value)
    Contract.WireMapIR _ child -> maybe False (all (validWire child)) (asObjectValues value)
    Contract.WireOptionalIR child -> value == Aeson.Null || validWire child value
    Contract.WireNullableIR child -> value == Aeson.Null || validWire child value
    Contract.WireRefIR _ -> case value of Aeson.Object _ -> True; _ -> False
    Contract.WireSurfaceScopeIR -> case value of Aeson.Object _ -> True; _ -> False
    Contract.WireSurfaceFragmentKeyIR -> case value of Aeson.Object _ -> True; _ -> False

asText :: Aeson.Value -> Maybe Text
asText = \case Aeson.String value -> Just value; _ -> Nothing

asInt :: Aeson.Value -> Maybe Int
asInt value = do
    number <- asNumber value
    if isIntegral number then pure (round number) else Nothing

asNumber :: Aeson.Value -> Maybe Scientific
asNumber = \case Aeson.Number value -> Just value; _ -> Nothing

isText :: Aeson.Value -> Bool
isText = isJust . asText

asArray :: Aeson.Value -> Maybe [Aeson.Value]
asArray = \case Aeson.Array values -> Just (foldr (:) [] values); _ -> Nothing

asObjectValues :: Aeson.Value -> Maybe [Aeson.Value]
asObjectValues = \case Aeson.Object values -> Just (AesonKeyMap.elems values); _ -> Nothing

isIntegral :: Scientific -> Bool
isIntegral number = fromInteger (round number) == number

maybeToRight :: Text -> Maybe a -> Either Text a
maybeToRight message = maybe (Left message) Right
