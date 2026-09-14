module Application.Bepis.Architecture
    ( BepisArchitectureFactSource (..)
    , bepisArchitectureContractsValue
    , bepisArchitectureFactSourceText
    ) where

import Application.Bepis.Action (bepisActionKindText, bepisResponseKindText)
import Application.Bepis.Controller (bepisControllerPolicyText)
import Application.Bepis.Fact (bepisFactKindText)
import qualified Data.Aeson as Aeson
import GHC.Generics (Generic)
import IHP.Prelude

-- | Source confidence labels shared with deterministic architecture extraction.
-- Haskell-owned contract generation uses these labels so source scanners can
-- report whether a fact came from typed app contracts, app registries, static
-- source scans, or naming fallbacks.
data BepisArchitectureFactSource
    = BepisTypedRunnerFact
    | BepisTypedContractFact
    | BepisAppRegistryFact
    | BepisStaticScanFact
    | BepisNamingFallbackFact
    deriving (Eq, Show, Generic)

bepisArchitectureFactSourceText :: BepisArchitectureFactSource -> Text
bepisArchitectureFactSourceText = \case
    BepisTypedRunnerFact -> "typed-runner"
    BepisTypedContractFact -> "typed-contract"
    BepisAppRegistryFact -> "app-registry"
    BepisStaticScanFact -> "heuristic-static-scan"
    BepisNamingFallbackFact -> "naming-fallback"


bepisArchitectureContractsValue :: Aeson.Value
bepisArchitectureContractsValue = Aeson.object
    [ "version" Aeson..= (2 :: Int)
    , "generatedBy" Aeson..= ("Application.Bepis.Architecture" :: Text)
    , "provenance" Aeson..= bepisArchitectureFactSourceText BepisTypedContractFact
    , "operationKinds" Aeson..= actionKindContracts
    , "actionKinds" Aeson..= actionKindContracts
    , "responseKinds" Aeson..= responseKindContracts
    , "factKinds" Aeson..= factKindContracts
    , "controllerPolicies" Aeson..= controllerPolicyContracts
    , "runner" Aeson..= runnerContract
    ]

runnerContract :: Aeson.Value
runnerContract = Aeson.object
    [ "name" Aeson..= ("runBepis" :: Text)
    , "source" Aeson..= Aeson.object
        [ "path" Aeson..= ("Application/Bepis/Action.hs" :: Text)
        , "mechanism" Aeson..= ("typed-haskell-runner" :: Text)
        ]
    , "confidence" Aeson..= bepisArchitectureFactSourceText BepisTypedContractFact
    ]

actionKindContracts :: [Aeson.Value]
actionKindContracts = closedKindContracts bepisActionKindText

responseKindContracts :: [Aeson.Value]
responseKindContracts = closedKindContracts bepisResponseKindText

factKindContracts :: [Aeson.Value]
factKindContracts = closedKindContracts bepisFactKindText

controllerPolicyContracts :: [Aeson.Value]
controllerPolicyContracts = closedKindContracts bepisControllerPolicyText

closedKindContracts :: (Bounded kind, Enum kind, Show kind) => (kind -> Text) -> [Aeson.Value]
closedKindContracts label =
    [ Aeson.object
        [ "constructor" Aeson..= (cs (show value) :: Text)
        , "label" Aeson..= label value
        ]
    | value <- [minBound .. maxBound]
    ]
