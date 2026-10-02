{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Application.Daysheet.ReferenceCodec
    ( encodeReferenceData, decodeReferenceData, ReferenceCodecError (..)
    ) where

import Prelude
import Application.Daysheet.Contract
import Application.Daysheet.DefinitionCodec ()
import qualified Application.Daysheet.Evaluation as E
import Application.Daysheet.References
import Application.Daysheet.Wire (literalJson, parseLiteralJson)
import Data.Aeson
import qualified Data.Aeson.Types as Aeson
import qualified Data.ByteString.Lazy as ByteString
import GHC.Generics (Generic)

data ReferenceCodecError = ReferencePayloadTooLarge | MalformedReferencePayload deriving (Eq, Show)

options :: Options
options = defaultOptions { rejectUnknownFields = True }

-- The object envelope is deliberately versioned with the containing definition.
-- Draft documents can retain type-incompatible old values while an admin makes
-- corrections. Publication/capture MUST call validateReferences separately.
encodeReferenceData :: ReferenceData -> Either ReferenceCodecError Value
encodeReferenceData value = do
    let encoded = object ["lists" .= value]
    if ByteString.length (encode encoded) > fromIntegral (maxDefinitionBytes limits)
        then Left ReferencePayloadTooLarge else Right encoded

decodeReferenceData :: Value -> Either ReferenceCodecError ReferenceData
decodeReferenceData value = do
    if ByteString.length (encode value) > fromIntegral (maxDefinitionBytes limits)
        then Left ReferencePayloadTooLarge else Right ()
    either (const (Left MalformedReferencePayload)) Right (Aeson.parseEither parser value)
  where
    parser = withObject "Daysheet references" \record -> do
        if length record /= 1 then fail "invalid reference envelope" else record .: "lists"

instance ToJSON E.RowId where toJSON (E.RowId key) = toJSON key
instance FromJSON E.RowId where parseJSON value = E.RowId <$> parseJSON value
instance ToJSON Literal where toJSON = literalJson
instance FromJSON Literal where parseJSON = parseLiteralJson

deriving instance Generic ReferenceKey
instance ToJSON ReferenceKey where toJSON = genericToJSON options
instance FromJSON ReferenceKey where parseJSON = genericParseJSON options
deriving instance Generic ReferenceValue
instance ToJSON ReferenceValue where toJSON = genericToJSON options
instance FromJSON ReferenceValue where parseJSON = genericParseJSON options
deriving instance Generic ReferenceRecord
instance ToJSON ReferenceRecord where toJSON = genericToJSON options
instance FromJSON ReferenceRecord where parseJSON = genericParseJSON options
deriving instance Generic ReferenceList
instance ToJSON ReferenceList where toJSON = genericToJSON options
instance FromJSON ReferenceList where parseJSON = genericParseJSON options
deriving instance Generic ReferenceData
instance ToJSON ReferenceData where toJSON = genericToJSON options
instance FromJSON ReferenceData where parseJSON = genericParseJSON options
