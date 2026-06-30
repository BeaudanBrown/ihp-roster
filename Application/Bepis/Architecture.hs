module Application.Bepis.Architecture
    ( BepisArchitectureFactSource (..)
    , bepisArchitectureContractsJson
    , bepisArchitectureFactSourceText
    ) where

import Application.Bepis.Action (BepisActionWrapperContract (..),
                                 bepisActionKindText,
                                 bepisActionWrapperContracts,
                                 bepisResponseKindText)
import Application.Bepis.Controller (BepisControllerPolicy (..),
                                     bepisControllerPolicyText)
import Application.Bepis.Fact (BepisFactKind (..), BepisOperationKind (..),
                               BepisResponseKind (..), bepisFactKindText)
import Application.Bepis.Mutation (BepisMutationComponentContract (..),
                                   bepisMutationComponentContracts,
                                   bepisMutationSpecPolicyVocabulary)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import GHC.Generics (Generic)
import IHP.Prelude

-- | Source confidence labels shared with deterministic architecture extraction.
-- Haskell-owned contract generation uses these labels so source scanners can
-- report whether a fact came from typed app contracts, app registries, static
-- source scans, or naming fallbacks.
data BepisArchitectureFactSource
    = BepisTypedWrapperFact
    | BepisTypedContractFact
    | BepisAppRegistryFact
    | BepisStaticScanFact
    | BepisNamingFallbackFact
    deriving (Eq, Show, Generic)

bepisArchitectureFactSourceText :: BepisArchitectureFactSource -> Text
bepisArchitectureFactSourceText = \case
    BepisTypedWrapperFact -> "typed-wrapper"
    BepisTypedContractFact -> "typed-contract"
    BepisAppRegistryFact -> "app-registry"
    BepisStaticScanFact -> "heuristic-static-scan"
    BepisNamingFallbackFact -> "naming-fallback"

bepisArchitectureContractsJson :: LBS.ByteString
bepisArchitectureContractsJson = Aeson.encode bepisArchitectureContractsValue

bepisArchitectureContractsValue :: Aeson.Value
bepisArchitectureContractsValue = Aeson.object
    [ "version" Aeson..= (1 :: Int)
    , "generatedBy" Aeson..= ("Application.Bepis.Architecture" :: Text)
    , "provenance" Aeson..= bepisArchitectureFactSourceText BepisTypedContractFact
    , "actionKinds" Aeson..= actionKindContracts
    , "responseKinds" Aeson..= responseKindContracts
    , "factKinds" Aeson..= factKindContracts
    , "controllerPolicies" Aeson..= controllerPolicyContracts
    , "actionWrappers" Aeson..= actionWrapperContracts
    , "mutationPolicies" Aeson..= mutationPolicyContracts
    , "mutationComponents" Aeson..= mutationComponentContracts
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

actionWrapperContracts :: [Aeson.Value]
actionWrapperContracts = map actionWrapperContractValue bepisActionWrapperContracts

actionWrapperContractValue :: BepisActionWrapperContract -> Aeson.Value
actionWrapperContractValue contract = Aeson.object
    [ "name" Aeson..= wrapperName contract
    , "kind" Aeson..= bepisActionKindText (wrapperActionKind contract)
    , "responseKinds" Aeson..= map bepisResponseKindText (wrapperResponseKinds contract)
    , "requiresMutationSpec" Aeson..= wrapperRequiresSpec contract
    , "source" Aeson..= Aeson.object
        [ "path" Aeson..= ("Application/Bepis/Action.hs" :: Text)
        , "mechanism" Aeson..= ("typed-haskell-contract" :: Text)
        ]
    , "confidence" Aeson..= bepisArchitectureFactSourceText BepisTypedContractFact
    ]

mutationComponentContracts :: [Aeson.Value]
mutationComponentContracts = map mutationComponentContractValue bepisMutationComponentContracts

mutationComponentContractValue :: BepisMutationComponentContract -> Aeson.Value
mutationComponentContractValue contract = Aeson.object
    [ "name" Aeson..= mutationComponentName contract
    , "capability" Aeson..= mutationComponentCapability contract
    , "description" Aeson..= mutationComponentDescription contract
    , "source" Aeson..= Aeson.object
        [ "path" Aeson..= ("Application/Bepis/Mutation.hs" :: Text)
        , "mechanism" Aeson..= ("typed-haskell-contract" :: Text)
        ]
    , "confidence" Aeson..= bepisArchitectureFactSourceText BepisTypedContractFact
    ]

mutationPolicyContracts :: [Aeson.Value]
mutationPolicyContracts =
    [ Aeson.object
        [ "family" Aeson..= familyName
        , "constructor" Aeson..= constructor
        , "label" Aeson..= label
        , "source" Aeson..= Aeson.object
            [ "path" Aeson..= ("Application/Bepis/Mutation.hs" :: Text)
            , "mechanism" Aeson..= ("typed-haskell-contract" :: Text)
            ]
        , "confidence" Aeson..= bepisArchitectureFactSourceText BepisTypedContractFact
        ]
    | (familyName, constructor, label) <- bepisMutationSpecPolicyVocabulary
    ]
