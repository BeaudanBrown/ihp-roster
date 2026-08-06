module Application.Bepis.Architecture
    ( BepisArchitectureFactSource (..)
    , bepisArchitectureContractsValue
    , bepisArchitectureFactSourceText
    ) where

import Application.Bepis.Action (bepisActionKindText, bepisResponseKindText)
import Application.Bepis.Controller (BepisControllerPolicy (..),
                                     bepisControllerPolicyText)
import Application.Bepis.Fact (BepisFactKind (..), BepisOperationKind (..),
                               BepisResponseKind (..), bepisFactKindText)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
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
actionKindContracts =
    [ Aeson.object ["constructor" Aeson..= constructor, "label" Aeson..= bepisActionKindText value]
    | (constructor, value) <-
        ([ ("BepisPageAction", BepisPageAction)
        , ("BepisFragmentAction", BepisFragmentAction)
        , ("BepisDialogAction", BepisDialogAction)
        , ("BepisMutationAction", BepisMutationAction)
        , ("BepisFormAction", BepisFormAction)
        , ("BepisPreferenceAction", BepisPreferenceAction)
        , ("BepisIntegrationAction", BepisIntegrationAction)
        , ("BepisExportAction", BepisExportAction)
        ] :: [(Text, BepisOperationKind)])
    ]

responseKindContracts :: [Aeson.Value]
responseKindContracts =
    [ Aeson.object ["constructor" Aeson..= constructor, "label" Aeson..= bepisResponseKindText value]
    | (constructor, value) <-
        ([ ("BepisHtmlResponse", BepisHtmlResponse)
        , ("BepisHtmxFragmentResponse", BepisHtmxFragmentResponse)
        , ("BepisDialogResponse", BepisDialogResponse)
        , ("BepisRedirectResponse", BepisRedirectResponse)
        , ("BepisJsonResponse", BepisJsonResponse)
        , ("BepisFileResponse", BepisFileResponse)
        ] :: [(Text, BepisResponseKind)])
    ]

factKindContracts :: [Aeson.Value]
factKindContracts =
    [ Aeson.object ["constructor" Aeson..= constructor, "label" Aeson..= bepisFactKindText value]
    | (constructor, value) <-
        ([ ("BepisActionFactKind", BepisActionFactKind)
        , ("BepisScopeFactKind", BepisScopeFactKind)
        , ("BepisAuditFactKind", BepisAuditFactKind)
        , ("BepisLiveFactKind", BepisLiveFactKind)
        , ("BepisResponseFactKind", BepisResponseFactKind)
        ] :: [(Text, BepisFactKind)])
    ]

controllerPolicyContracts :: [Aeson.Value]
controllerPolicyContracts =
    [ Aeson.object ["constructor" Aeson..= constructor, "label" Aeson..= bepisControllerPolicyText value]
    | (constructor, value) <-
        ([ ("BepisPublicController", BepisPublicController)
        , ("BepisAuthenticatedController", BepisAuthenticatedController)
        , ("BepisAuthenticatedVenueController", BepisAuthenticatedVenueController)
        , ("BepisAdminVenueController", BepisAdminVenueController)
        , ("BepisSupportController", BepisSupportController)
        ] :: [(Text, BepisControllerPolicy)])
    ]
