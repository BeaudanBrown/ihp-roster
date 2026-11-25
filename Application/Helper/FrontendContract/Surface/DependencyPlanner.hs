module Application.Helper.FrontendContract.Surface.DependencyPlanner
    ( SurfaceInvalidationTarget (..)
    , surfaceSubscriptionDependencyIdentities
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
    [ SurfaceInvalidationTarget scope (normalizeContainedFragmentKeys fragments)
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
surfaceSubscriptionDependencyIdentities :: SurfaceSubscription -> [(Text, Aeson.Value)]
surfaceSubscriptionDependencyIdentities subscription =
    Set.toAscList . Set.fromList $
        concatMap (fragmentKeyDependencyIdentities subscription.subscriptionScope) subscription.subscriptionFragmentKeys

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

-- Fragment keys are normalized while containment metadata is still available
-- on the server. This prevents the browser from receiving overlapping swaps.
-- Parameter matching matters for repeated fragments: a day section contains
-- only rows carrying that same day id, not every row of the same kind.
normalizeContainedFragmentKeys :: [SurfaceFragmentKey] -> [SurfaceFragmentKey]
normalizeContainedFragmentKeys fragmentKeys =
    filter (not . hasSelectedAncestor) coalescedKeys
  where
    coalescedKeys = coalesceSurfaceFragmentKeys fragmentKeys
    hasSelectedAncestor descendantKey =
        any (`fragmentKeyContains` descendantKey) coalescedKeys

fragmentKeyContains :: SurfaceFragmentKey -> SurfaceFragmentKey -> Bool
fragmentKeyContains ancestorKey descendantKey
    | ancestorKey == descendantKey = False
    | ancestorSurface /= descendantSurface = False
    | otherwise = fromMaybe False do
        surface <- findSurface ancestorSurface
        ancestorFragment <- findFragment ancestorKind surface
        descendantFragment <- findFragment descendantKind surface
        pure
            ( fragmentKindContains surface ancestorKind descendantKind
                && fragmentParamsContain ancestorFragment ancestorParams descendantFragment descendantParams
            )
  where
    (ancestorSurface, ancestorKind, ancestorParams) = LiveUpdateInternal.surfaceFragmentKeyIdentity ancestorKey
    (descendantSurface, descendantKind, descendantParams) = LiveUpdateInternal.surfaceFragmentKeyIdentity descendantKey

fragmentKindContains :: SurfaceIR.SurfaceIR -> Text -> Text -> Bool
fragmentKindContains surface ancestorKind descendantKind =
    walk Set.empty ancestorKind
  where
    walk visited fragmentKind
        | fragmentKind `Set.member` visited = False
        | otherwise =
            any
                (\childKind -> childKind == descendantKind || walk (Set.insert fragmentKind visited) childKind)
                (containedFragmentKinds surface fragmentKind)

containedFragmentKinds :: SurfaceIR.SurfaceIR -> Text -> [Text]
containedFragmentKinds surface fragmentKind =
    maybe [] (concatMap containedKind . (.fragmentOptions)) (findFragment fragmentKind surface)
  where
    containedKind = \case
        SurfaceIR.ContainsOption childKind -> [childKind]
        SurfaceIR.LazyOption options -> concatMap containedKind options
        _ -> []

fragmentParamsContain :: SurfaceIR.FragmentIR -> Aeson.Value -> SurfaceIR.FragmentIR -> Aeson.Value -> Bool
fragmentParamsContain ancestorFragment ancestorParams descendantFragment descendantParams =
    case (ancestorParams, descendantParams) of
        (Aeson.Object ancestorObject, Aeson.Object descendantObject) ->
            all (fieldMatches ancestorObject descendantObject) ancestorFragment.fragmentParams
        _ -> null ancestorFragment.fragmentParams
  where
    descendantFieldNames = Set.fromList (map (.fieldName) descendantFragment.fragmentParams)
    fieldMatches ancestorObject descendantObject field =
        field.fieldName `Set.member` descendantFieldNames
            && let key = Aeson.Key.fromText field.fieldName
               in case (Aeson.KeyMap.lookup key ancestorObject, Aeson.KeyMap.lookup key descendantObject) of
                    (Just ancestorValue, Just descendantValue) -> ancestorValue == descendantValue
                    _ -> False

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
