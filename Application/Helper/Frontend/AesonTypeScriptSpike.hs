{-# LANGUAGE TemplateHaskell #-}

module Application.Helper.Frontend.AesonTypeScriptSpike
    ( AesonTypeScriptSpikeMessage (..)
    , AesonTypeScriptSpikeNullableRecord (..)
    , AesonTypeScriptSpikeOptionalRecord (..)
    , AesonTypeScriptSpikeSimpleEnum (..)
    , AesonTypeScriptSpikeUnion (..)
    , AesonTypeScriptSpikeWireId (..)
    , aesonTypeScriptSpikeDeclaration
    , aesonTypeScriptSpikeTypeScript
    ) where

import Application.Helper.Frontend.AesonTypeScriptOptions (stripPrefixLower)
import Application.Helper.Frontend.TypeScript (TypeScriptDeclaration (..),
                                               aesonTypeScriptDeclaration)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.TH as Aeson
import Data.Aeson.TypeScript.Recursive (getTypeScriptDeclarationsRecursively)
import Data.Aeson.TypeScript.TH (TSDeclaration, TypeScript (..),
                                 deriveJSONAndTypeScript)
import qualified Data.List as List
import Data.Proxy (Proxy (..))
import qualified Data.Text as Text
import IHP.Prelude

-- | Spike-only representative string-like id wrapper. Real contracts can use
-- UUID-backed wrappers with the same TypeScript shape while keeping Haskell
-- parsing/validation server-side.
newtype AesonTypeScriptSpikeWireId = AesonTypeScriptSpikeWireId
    { unAesonTypeScriptSpikeWireId :: Text
    }
    deriving (Eq, Show)

instance Aeson.ToJSON AesonTypeScriptSpikeWireId where
    toJSON (AesonTypeScriptSpikeWireId value) = Aeson.String value

instance Aeson.FromJSON AesonTypeScriptSpikeWireId where
    parseJSON = Aeson.withText "AesonTypeScriptSpikeWireId" (pure . AesonTypeScriptSpikeWireId)

instance TypeScript AesonTypeScriptSpikeWireId where
    getTypeScriptType _ = "string"
    getTypeScriptKeyType _ = "string"

-- | Plain all-nullary enum. The chosen options encode this as a string union.
data AesonTypeScriptSpikeSimpleEnum
    = AesonTypeScriptSpikeAlpha
    | AesonTypeScriptSpikeBeta
    deriving (Eq, Show)

-- | Record where the key is always present and Nothing is encoded as null.
data AesonTypeScriptSpikeNullableRecord = AesonTypeScriptSpikeNullableRecord
    { nullableId   :: !AesonTypeScriptSpikeWireId
    , nullableNote :: !(Maybe Text)
    }
    deriving (Eq, Show)

-- | Record where Nothing is omitted, producing a TypeScript optional field.
data AesonTypeScriptSpikeOptionalRecord = AesonTypeScriptSpikeOptionalRecord
    { optionalLabel :: !Text
    , optionalNote  :: !(Maybe Text)
    }
    deriving (Eq, Show)

-- | Discriminated union using a stable "type" tag field.
data AesonTypeScriptSpikeUnion
    = AesonTypeScriptSpikeSelect
        { selectedId :: !AesonTypeScriptSpikeWireId
        }
    | AesonTypeScriptSpikeClear
        { reason :: !Text
        }
    deriving (Eq, Show)

-- | Nested browser wire message containing enum, union, nullable, optional,
-- custom string-like id, and repeated child shapes.
data AesonTypeScriptSpikeMessage = AesonTypeScriptSpikeMessage
    { messageId        :: !AesonTypeScriptSpikeWireId
    , messageMode      :: !AesonTypeScriptSpikeSimpleEnum
    , messageIntent    :: !AesonTypeScriptSpikeUnion
    , messageNullable  :: !AesonTypeScriptSpikeNullableRecord
    , messageOptional  :: !AesonTypeScriptSpikeOptionalRecord
    , messageFragments :: ![AesonTypeScriptSpikeNullableRecord]
    }
    deriving (Eq, Show)

$(deriveJSONAndTypeScript
    Aeson.defaultOptions
        { Aeson.constructorTagModifier = stripPrefixLower "AesonTypeScriptSpike"
        , Aeson.allNullaryToStringTag = True
        }
    ''AesonTypeScriptSpikeSimpleEnum)

$(deriveJSONAndTypeScript
    Aeson.defaultOptions
        { Aeson.omitNothingFields = False
        }
    ''AesonTypeScriptSpikeNullableRecord)

$(deriveJSONAndTypeScript
    Aeson.defaultOptions
        { Aeson.omitNothingFields = True
        }
    ''AesonTypeScriptSpikeOptionalRecord)

$(deriveJSONAndTypeScript
    Aeson.defaultOptions
        { Aeson.constructorTagModifier = stripPrefixLower "AesonTypeScriptSpike"
        , Aeson.sumEncoding = Aeson.TaggedObject { Aeson.tagFieldName = "type", Aeson.contentsFieldName = "contents" }
        }
    ''AesonTypeScriptSpikeUnion)

$(deriveJSONAndTypeScript
    Aeson.defaultOptions
    ''AesonTypeScriptSpikeMessage)

aesonTypeScriptSpikeDeclaration :: TypeScriptDeclaration
aesonTypeScriptSpikeDeclaration =
    aesonTypeScriptDeclaration
        "AesonTypeScriptSpike"
        [ "// Spike proof-of-viability for aeson-typescript-generated browser wire contracts."
        , "// Keep this narrow until the live-update/interaction protocol migrates in later tickets."
        ]
        aesonTypeScriptSpikeDeclarations

aesonTypeScriptSpikeTypeScript :: Text
aesonTypeScriptSpikeTypeScript =
    aesonTypeScriptSpikeDeclaration.source

aesonTypeScriptSpikeDeclarations :: [TSDeclaration]
aesonTypeScriptSpikeDeclarations =
    List.nub $
        getTypeScriptDeclarationsRecursively (Proxy :: Proxy AesonTypeScriptSpikeMessage)
            <> getTypeScriptDeclarationsRecursively (Proxy :: Proxy AesonTypeScriptSpikeOptionalRecord)
