{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- | The single versioned server persistence format. Domain constructors own
-- definition structure; formula payloads exclusively use the existing DSL wire
-- schema. JSON instances live at this serialization seam, not in domain logic.
-- This is not a browser request DTO: designer actions remain generated DSL
-- contracts and call typed domain mutations rather than posting opaque JSON.
module Application.Daysheet.DefinitionCodec
    ( encodeDefinition, decodeDefinition, DefinitionCodecError (..)
    ) where

import Prelude
import Application.Daysheet.Contract
import Application.Daysheet.Validation
import Application.Daysheet.Wire (expressionJson, parseExpressionJson)
import Data.Aeson
import qualified Data.Aeson.Types as Aeson
import qualified Data.ByteString.Lazy as ByteString
import GHC.Generics (Generic)

data DefinitionCodecError = DefinitionTooLarge | MalformedDefinition | InvalidStoredDefinition ContractError
    deriving (Eq, Show)

options :: Options
options = defaultOptions { rejectUnknownFields = True }

encodeDefinition :: Definition -> Either DefinitionCodecError Value
encodeDefinition definition = do
    either (Left . InvalidStoredDefinition) Right (validateDefinition definition)
    let value = toJSON definition
    if ByteString.length (encode value) > fromIntegral (maxDefinitionBytes limits)
        then Left DefinitionTooLarge else Right value

decodeDefinition :: Value -> Either DefinitionCodecError Definition
decodeDefinition value = do
    if ByteString.length (encode value) > fromIntegral (maxDefinitionBytes limits)
        then Left DefinitionTooLarge else Right ()
    definition <- either (const (Left MalformedDefinition)) Right (Aeson.parseEither parseJSON value)
    either (Left . InvalidStoredDefinition) (const (Right definition)) (validateDefinition definition)

instance ToJSON FieldId where toJSON (FieldId key) = toJSON key
instance FromJSON FieldId where parseJSON value = FieldId <$> parseJSON value
instance ToJSON ListId where toJSON (ListId key) = toJSON key
instance FromJSON ListId where parseJSON value = ListId <$> parseJSON value
instance ToJSON ChoiceId where toJSON (ChoiceId key) = toJSON key
instance FromJSON ChoiceId where parseJSON value = ChoiceId <$> parseJSON value
instance ToJSON SectionId where toJSON (SectionId key) = toJSON key
instance FromJSON SectionId where parseJSON value = SectionId <$> parseJSON value
instance ToJSON ReportId where toJSON (ReportId key) = toJSON key
instance FromJSON ReportId where parseJSON value = ReportId <$> parseJSON value
instance ToJSON Expression where toJSON = expressionJson
instance FromJSON Expression where parseJSON = parseExpressionJson

deriving instance Generic Choice
instance ToJSON Choice where toJSON = genericToJSON options
instance FromJSON Choice where parseJSON = genericParseJSON options
deriving instance Generic FieldType
instance ToJSON FieldType where toJSON = genericToJSON options
instance FromJSON FieldType where parseJSON = genericParseJSON options
deriving instance Generic FieldSource
instance ToJSON FieldSource where toJSON = genericToJSON options
instance FromJSON FieldSource where parseJSON = genericParseJSON options
deriving instance Generic Field
instance ToJSON Field where toJSON = genericToJSON options
instance FromJSON Field where parseJSON = genericParseJSON options
deriving instance Generic ListMode
instance ToJSON ListMode where toJSON = genericToJSON options
instance FromJSON ListMode where parseJSON = genericParseJSON options
deriving instance Generic RecordList
instance ToJSON RecordList where toJSON = genericToJSON options
instance FromJSON RecordList where parseJSON = genericParseJSON options
deriving instance Generic Advisory
instance ToJSON Advisory where toJSON = genericToJSON options
instance FromJSON Advisory where parseJSON = genericParseJSON options
deriving instance Generic SortDirection
instance ToJSON SortDirection where toJSON = genericToJSON options
instance FromJSON SortDirection where parseJSON = genericParseJSON options
deriving instance Generic Block
instance ToJSON Block where toJSON = genericToJSON options
instance FromJSON Block where parseJSON = genericParseJSON options
deriving instance Generic Section
instance ToJSON Section where toJSON = genericToJSON options
instance FromJSON Section where parseJSON = genericParseJSON options
deriving instance Generic Output
instance ToJSON Output where toJSON = genericToJSON options
instance FromJSON Output where parseJSON = genericParseJSON options
deriving instance Generic Report
instance ToJSON Report where toJSON = genericToJSON options
instance FromJSON Report where parseJSON = genericParseJSON options
deriving instance Generic Definition
instance ToJSON Definition where toJSON = genericToJSON options
instance FromJSON Definition where parseJSON = genericParseJSON options
