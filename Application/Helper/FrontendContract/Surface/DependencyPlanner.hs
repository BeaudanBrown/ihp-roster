module Application.Helper.FrontendContract.Surface.DependencyPlanner
    ( SurfaceInvalidationTarget (..)
    , planFrontendSurfaceInvalidations
    ) where

import qualified Application.Helper.FrontendContract.Surface.ContractIR as SurfaceIR
import Application.Helper.FrontendContract.Surface.Reflect (reflectRegisteredFrontendSurfaces)
import Application.Helper.FrontendContract.Surface.Resource (SurfaceResourceValue (..))
import qualified Application.Helper.FrontendContract.Wire.LiveUpdate as Wire
import qualified Application.Helper.LiveUpdate.Internal as LiveUpdateInternal
import Application.Helper.LiveUpdate.Runtime
import Application.Helper.SurfaceResource
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
    grouped = Map.fromListWith (<>)
        [ (subscription.subscriptionScope, affectedFragments)
        | subscription <- subscriptions
        , let affectedFragments =
                filter
                    (frontendSurfaceFragmentKeyDependsOnTouchedResource touchedResources subscription.subscriptionScope)
                    subscription.subscriptionFragmentKeys
        , not (null affectedFragments)
        ]

frontendSurfaceFragmentKeyDependsOnTouchedResource :: Set.Set SurfaceResourceValue -> SurfaceScope -> SurfaceFragmentKey -> Bool
frontendSurfaceFragmentKeyDependsOnTouchedResource touchedValues scope fragmentKey =
    case fragmentKeyDependencies scope fragmentKey of
        [] -> False
        dependencies -> not (Set.null (Set.intersection touchedValues (Set.fromList dependencies)))

fragmentKeyDependencies :: SurfaceScope -> SurfaceFragmentKey -> [SurfaceResourceValue]
fragmentKeyDependencies scope fragmentKey = do
    let Wire.SurfaceScope { surface = scopeSurface, scope = scopePayload } = LiveUpdateInternal.surfaceScopeToWire scope
    let (fragmentSurface, fragmentKind, fragmentParams) = LiveUpdateInternal.surfaceFragmentKeyIdentity fragmentKey
    True <- pure (fragmentSurface == scopeSurface)
    surface <- maybeToList (findSurface scopeSurface)
    fragmentIR <- maybeToList (findFragment fragmentKind surface)
    dependency <- SurfaceIR.optionResourceDependencies fragmentIR.fragmentOptions
    maybeToList (resourceValueFromDependency scopePayload fragmentParams dependency)

findSurface :: Text -> Maybe SurfaceIR.SurfaceIR
findSurface surfaceName =
    List.find ((== surfaceName) . (.surfaceName)) reflectRegisteredFrontendSurfaces.contractSurfaces

findFragment :: Text -> SurfaceIR.SurfaceIR -> Maybe SurfaceIR.FragmentIR
findFragment fragmentKind surface =
    List.find ((== fragmentKind) . (.fragmentName)) surface.surfaceFragments

resourceValueFromDependency :: Aeson.Value -> Aeson.Value -> SurfaceIR.ResourceDependencyIR -> Maybe SurfaceResourceValue
resourceValueFromDependency scopeValue fragmentValue dependency = do
    fieldPairs <- mapM sourceFieldValue (zip dependency.dependencyResource.resourceFields dependency.dependencySources)
    pure SurfaceResourceValue
        { resourceValueName = dependency.dependencyResource.resourceName
        , resourceValueFields = Aeson.object fieldPairs
        }
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
