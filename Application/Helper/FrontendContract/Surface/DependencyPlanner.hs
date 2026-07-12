module Application.Helper.FrontendContract.Surface.DependencyPlanner
    ( planFrontendSurfaceInvalidation
    , planFrontendSurfaceKeyInvalidation
    , frontendSurfaceFragmentDependsOnTouchedResource
    ) where

import qualified Application.Helper.FrontendContract.Surface.ContractIR as SurfaceIR
import Application.Helper.FrontendContract.Surface.Reflect (reflectRegisteredFrontendSurfaces)
import Application.Helper.FrontendContract.Surface.Resource (SurfaceResourceValue (..))
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceFragmentKey (..),
                                                            FrontendSurfaceMountedFragment (..))
import qualified Application.Helper.FrontendContract.Wire.LiveUpdate as Wire
import Application.Helper.LiveUpdate.Runtime
import Application.Helper.SurfaceResource
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Aeson.Key
import qualified Data.Aeson.KeyMap as Aeson.KeyMap
import qualified Data.List as List
import qualified Data.Set as Set
import IHP.Prelude

planFrontendSurfaceInvalidation :: Set.Set SurfaceResourceValue -> SurfaceScope -> [FrontendSurfaceMountedFragment] -> [FrontendSurfaceMountedFragment]
planFrontendSurfaceInvalidation touchedResources scope candidates =
    filter (frontendSurfaceFragmentDependsOnTouchedResource touchedValues scope) candidates
    where
        touchedValues = touchedResources

planFrontendSurfaceKeyInvalidation :: Set.Set SurfaceResourceValue -> SurfaceScope -> [SurfaceFragmentKey] -> [SurfaceFragmentKey]
planFrontendSurfaceKeyInvalidation touchedResources scope fragmentKeys =
    filter (frontendSurfaceFragmentKeyDependsOnTouchedResource touchedResources scope) fragmentKeys

frontendSurfaceFragmentDependsOnTouchedResource :: Set.Set SurfaceResourceValue -> SurfaceScope -> FrontendSurfaceMountedFragment -> Bool
frontendSurfaceFragmentDependsOnTouchedResource touchedValues scope mountedFragment =
    case mountedFragmentDependencies scope mountedFragment of
        [] -> False
        dependencies -> not (Set.null (Set.intersection touchedValues (Set.fromList dependencies)))

frontendSurfaceFragmentKeyDependsOnTouchedResource :: Set.Set SurfaceResourceValue -> SurfaceScope -> SurfaceFragmentKey -> Bool
frontendSurfaceFragmentKeyDependsOnTouchedResource touchedValues scope fragmentKey =
    case fragmentKeyDependencies scope fragmentKey of
        [] -> False
        dependencies -> not (Set.null (Set.intersection touchedValues (Set.fromList dependencies)))

mountedFragmentDependencies :: SurfaceScope -> FrontendSurfaceMountedFragment -> [SurfaceResourceValue]
mountedFragmentDependencies scope mountedFragment = do
    surface <- maybeToList (findSurface scopeSurface)
    fragment <- maybeToList (findFragment mountedFragment.mountedFragmentKey.fragmentKind surface)
    dependency <- SurfaceIR.optionResourceDependencies fragment.fragmentOptions
    maybeToList (resourceValueFromDependency scopePayload mountedFragment.mountedFragmentKey.fragmentParams dependency)
  where
    Wire.SurfaceScope { surface = scopeSurface, scope = scopePayload } = surfaceScopeToWire scope

fragmentKeyDependencies :: SurfaceScope -> SurfaceFragmentKey -> [SurfaceResourceValue]
fragmentKeyDependencies scope fragmentKey = do
    let Wire.SurfaceScope { surface = scopeSurface, scope = scopePayload } = surfaceScopeToWire scope
    True <- pure (fragmentKey.surfaceFragmentSurface == scopeSurface)
    surface <- maybeToList (findSurface scopeSurface)
    fragmentIR <- maybeToList (findFragment fragmentKey.surfaceFragmentWireKind surface)
    dependency <- SurfaceIR.optionResourceDependencies fragmentIR.fragmentOptions
    maybeToList (resourceValueFromDependency scopePayload fragmentKey.surfaceFragmentParams dependency)

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
