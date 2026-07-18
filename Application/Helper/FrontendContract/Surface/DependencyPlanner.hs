module Application.Helper.FrontendContract.Surface.DependencyPlanner
    ( SurfaceInvalidationTarget (..)
    , planFrontendSurfaceInvalidations
    ) where

import qualified Application.Helper.FrontendContract.Surface.ContractIR as SurfaceIR
import Application.Helper.FrontendContract.Surface.Contracts (registeredFrontendSurfaceContractIR)
import Application.Helper.FrontendContract.Surface.Resource (SurfaceResourceValue)
import qualified Application.Helper.FrontendContract.Surface.Resource.Internal as ResourceInternal
import qualified Application.Helper.FrontendContract.Wire.LiveUpdate as Wire
import qualified Application.Helper.LiveUpdate.Internal as LiveUpdateInternal
import Application.Helper.LiveUpdate.Runtime
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Aeson.Key
import qualified Data.Aeson.KeyMap as Aeson.KeyMap
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import IHP.Prelude

data SurfaceInvalidationTarget = SurfaceInvalidationTarget
    { targetScope     :: !SurfaceScope
    , targetFragments :: ![SurfaceFragmentKey]
    }
    deriving (Eq, Show)

-- | The singular actor/passive dependency-planning seam. Callers provide the
-- exact semantic keys currently mounted or subscribed; the reflected Surface
-- dependency graph selects and coalesces concrete refresh targets.
planFrontendSurfaceInvalidations :: Set.Set SurfaceResourceValue -> [SurfaceSubscription] -> [SurfaceInvalidationTarget]
planFrontendSurfaceInvalidations touchedResources subscriptions =
    [ SurfaceInvalidationTarget scope (coalesceSurfaceFragmentKeys fragments)
    | (scope, fragments) <- Map.toAscList grouped
    ]
  where
    touchedIdentities = Set.map ResourceInternal.surfaceResourceIdentity touchedResources
    grouped = Map.fromListWith (<>)
        [ (subscription.subscriptionScope, affectedFragments)
        | subscription <- subscriptions
        , let affectedFragments =
                filter
                    (frontendSurfaceFragmentKeyDependsOnTouchedResource touchedIdentities subscription.subscriptionScope)
                    subscription.subscriptionFragmentKeys
        , not (null affectedFragments)
        ]

frontendSurfaceFragmentKeyDependsOnTouchedResource :: Set.Set (Text, Aeson.Value) -> SurfaceScope -> SurfaceFragmentKey -> Bool
frontendSurfaceFragmentKeyDependsOnTouchedResource touchedIdentities scope fragmentKey =
    any (`Set.member` touchedIdentities) (fragmentKeyDependencyIdentities scope fragmentKey)

-- Dependency identities are projected directly from checked reflected IR and
-- exact live identities. The planner never constructs a free resource value;
-- every touched value entered through a marker-indexed feature constructor.
fragmentKeyDependencyIdentities :: SurfaceScope -> SurfaceFragmentKey -> [(Text, Aeson.Value)]
fragmentKeyDependencyIdentities scope fragmentKey = do
    let Wire.SurfaceScope { surface = scopeSurface, scope = scopePayload } = LiveUpdateInternal.surfaceScopeToWire scope
    let (fragmentSurface, fragmentKind, fragmentParams) = LiveUpdateInternal.surfaceFragmentKeyIdentity fragmentKey
    True <- pure (fragmentSurface == scopeSurface)
    surface <- maybeToList (findSurface scopeSurface)
    fragmentIR <- maybeToList (findFragment fragmentKind surface)
    dependency <- SurfaceIR.optionResourceDependencies fragmentIR.fragmentOptions
    maybeToList (resourceIdentityFromDependency scopePayload fragmentParams dependency)

findSurface :: Text -> Maybe SurfaceIR.SurfaceIR
findSurface surfaceName =
    List.find ((== surfaceName) . (.surfaceName)) registeredFrontendSurfaceContractIR.contractSurfaces

findFragment :: Text -> SurfaceIR.SurfaceIR -> Maybe SurfaceIR.FragmentIR
findFragment fragmentKind surface =
    List.find ((== fragmentKind) . (.fragmentName)) surface.surfaceFragments

resourceIdentityFromDependency :: Aeson.Value -> Aeson.Value -> SurfaceIR.ResourceDependencyIR -> Maybe (Text, Aeson.Value)
resourceIdentityFromDependency scopeValue fragmentValue dependency = do
    fieldPairs <- mapM sourceFieldValue (zip dependency.dependencyResource.resourceFields dependency.dependencySources)
    pure (dependency.dependencyResource.resourceName, Aeson.object fieldPairs)
    where
        sourceFieldValue (resourceField, source) = do
            value <- case source of
                SurfaceIR.FromScopeIR sourceField -> lookupObjectField sourceField scopeValue
                SurfaceIR.FromFragmentIR sourceField -> lookupObjectField sourceField fragmentValue
            pure (Aeson.Key.fromText resourceField.fieldName, value)

lookupObjectField :: Text -> Aeson.Value -> Maybe Aeson.Value
lookupObjectField fieldName = \case
    Aeson.Object object -> Aeson.KeyMap.lookup (Aeson.Key.fromText fieldName) object
    _ -> Nothing
