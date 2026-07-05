module Application.Helper.FrontendContract.Surface.Ghc.Raw
    ( RawRegistry (..)
    , RawSurface (..)
    , RawType (..)
    , rawRegistryToJson
    , rawSurfaceToJson
    , rawTypeToJson
    ) where

import qualified Data.Aeson as Aeson
import IHP.Prelude

data RawRegistry = RawRegistry
    { rawRegistryModule   :: !String
    , rawRegistryExport   :: !String
    , rawRegistrySource   :: !String
    , rawRegistryKind     :: !String
    , rawRegistryRhs      :: !RawType
    , rawRegistrySurfaces :: ![RawSurface]
    }
    deriving (Eq, Show)

data RawSurface = RawSurface
    { rawSurfaceName       :: !String
    , rawSurfaceSource     :: !String
    , rawSurfaceReference  :: !RawType
    , rawSurfaceExpanded   :: !RawType
    , rawSurfaceNormalized :: !RawType
    }
    deriving (Eq, Show)

data RawType = RawType
    { rawTypeNode   :: !String
    , rawTypePretty :: !String
    , rawTypeName   :: !(Maybe String)
    , rawTypeSource :: !(Maybe String)
    , rawTypeArgs   :: ![RawType]
    }
    deriving (Eq, Show)

rawRegistryToJson :: RawRegistry -> Aeson.Value
rawRegistryToJson rawRegistry =
    Aeson.object
        [ "module" Aeson..= rawRegistry.rawRegistryModule
        , "export" Aeson..= rawRegistry.rawRegistryExport
        , "source" Aeson..= rawRegistry.rawRegistrySource
        , "kind" Aeson..= rawRegistry.rawRegistryKind
        , "rhs" Aeson..= rawTypeToJson rawRegistry.rawRegistryRhs
        , "surfaces" Aeson..= map rawSurfaceToJson rawRegistry.rawRegistrySurfaces
        ]

rawSurfaceToJson :: RawSurface -> Aeson.Value
rawSurfaceToJson surface =
    Aeson.object
        [ "name" Aeson..= surface.rawSurfaceName
        , "source" Aeson..= surface.rawSurfaceSource
        , "reference" Aeson..= rawTypeToJson surface.rawSurfaceReference
        , "expanded" Aeson..= rawTypeToJson surface.rawSurfaceExpanded
        , "normalized" Aeson..= rawTypeToJson surface.rawSurfaceNormalized
        ]

rawTypeToJson :: RawType -> Aeson.Value
rawTypeToJson rawType =
    Aeson.object
        [ "node" Aeson..= rawType.rawTypeNode
        , "pretty" Aeson..= rawType.rawTypePretty
        , "name" Aeson..= rawType.rawTypeName
        , "source" Aeson..= rawType.rawTypeSource
        , "args" Aeson..= map rawTypeToJson rawType.rawTypeArgs
        ]
