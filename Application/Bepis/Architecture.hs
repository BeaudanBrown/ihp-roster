module Application.Bepis.Architecture
    ( BepisArchitectureFactSource (..)
    , bepisArchitectureFactSourceText
    ) where

import GHC.Generics (Generic)
import IHP.Prelude

-- | Source confidence labels shared with deterministic architecture extraction.
-- Haskell code does not need to emit these yet; keeping the vocabulary here
-- gives scanners and future tests one app-owned contract to target.
data BepisArchitectureFactSource
    = BepisTypedWrapperFact
    | BepisAppRegistryFact
    | BepisStaticScanFact
    | BepisNamingFallbackFact
    deriving (Eq, Show, Generic)

bepisArchitectureFactSourceText :: BepisArchitectureFactSource -> Text
bepisArchitectureFactSourceText = \case
    BepisTypedWrapperFact -> "typed-wrapper"
    BepisAppRegistryFact -> "app-registry"
    BepisStaticScanFact -> "heuristic-static-scan"
    BepisNamingFallbackFact -> "naming-fallback"
