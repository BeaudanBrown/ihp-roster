module Application.Helper.FrontendContract.Surface.DependencyPlanner
    ( planFrontendSurfaceInvalidation
    , planFrontendSurfaceWireInvalidation
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

planFrontendSurfaceWireInvalidation :: Set.Set SurfaceResourceValue -> SurfaceScope -> [SurfaceWireFragment] -> [SurfaceWireFragment]
planFrontendSurfaceWireInvalidation touchedResources scope fragments =
    filter (frontendSurfaceWireFragmentDependsOnTouchedResource touchedResources scope) fragments

frontendSurfaceFragmentDependsOnTouchedResource :: Set.Set SurfaceResourceValue -> SurfaceScope -> FrontendSurfaceMountedFragment -> Bool
frontendSurfaceFragmentDependsOnTouchedResource touchedValues scope mountedFragment =
    case mountedFragmentDependencies scope mountedFragment of
        [] -> False
        dependencies -> not (Set.null (Set.intersection touchedValues (Set.fromList dependencies)))

frontendSurfaceWireFragmentDependsOnTouchedResource :: Set.Set SurfaceResourceValue -> SurfaceScope -> SurfaceWireFragment -> Bool
frontendSurfaceWireFragmentDependsOnTouchedResource touchedValues scope fragment =
    case wireFragmentDependencies scope fragment of
        [] -> False
        dependencies -> not (Set.null (Set.intersection touchedValues (Set.fromList dependencies)))

mountedFragmentDependencies :: SurfaceScope -> FrontendSurfaceMountedFragment -> [SurfaceResourceValue]
mountedFragmentDependencies scope mountedFragment = do
    surface <- maybeToList (findSurface scopeWire.surface)
    fragment <- maybeToList (findFragment mountedFragment.mountedFragmentKey.fragmentKind surface)
    dependency <- SurfaceIR.optionResourceDependencies fragment.fragmentOptions
    maybeToList (resourceValueFromDependency scopeWire.scope mountedFragment.mountedFragmentKey.fragmentParams dependency)
    where
        scopeWire = surfaceScopeToWire scope

wireFragmentDependencies :: SurfaceScope -> SurfaceWireFragment -> [SurfaceResourceValue]
wireFragmentDependencies scope fragment = do
    let scopeWire = surfaceScopeToWire scope
    let Wire.SurfaceWireFragment { fragmentKey = Wire.SurfaceFragmentKey { surface = fragmentSurface, kind = fragmentKind, params = fragmentParams } } = surfaceWireFragmentToWire fragment
    True <- pure (fragmentSurface == scopeWire.surface)
    surface <- maybeToList (findSurface scopeWire.surface)
    fragmentIR <- maybeToList (findFragment fragmentKind surface)
    dependency <- SurfaceIR.optionResourceDependencies fragmentIR.fragmentOptions
    maybeToList (resourceValueFromDependency scopeWire.scope fragmentParams dependency)

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
