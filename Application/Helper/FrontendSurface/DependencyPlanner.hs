module Application.Helper.FrontendSurface.DependencyPlanner
    ( planFrontendSurfaceInvalidation
    , frontendSurfaceFragmentDependsOnTouchedResource
    ) where

import qualified Application.Helper.Frontend.LiveUpdateSchema as Wire
import qualified Application.Helper.FrontendSurface.ContractIR as SurfaceIR
import Application.Helper.FrontendSurface.Reflect (reflectRegisteredFrontendSurfaces)
import Application.Helper.FrontendSurface.Resource (FrontendSurfaceResourceValue (..),
                                                    liveResourcesToFrontendSurfaceResourceValues)
import Application.Helper.FrontendSurface.Runtime (FrontendSurfaceFragmentKey (..),
                                                   FrontendSurfaceMountedFragment (..))
import Application.Helper.LiveResource (LiveResource)
import Application.Helper.LiveUpdate.Runtime (LiveUpdateScope,
                                              liveUpdateScopeToWire)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Aeson.Key
import qualified Data.Aeson.KeyMap as Aeson.KeyMap
import qualified Data.List as List
import qualified Data.Set as Set
import IHP.Prelude

planFrontendSurfaceInvalidation :: Set.Set LiveResource -> LiveUpdateScope -> [FrontendSurfaceMountedFragment] -> [FrontendSurfaceMountedFragment]
planFrontendSurfaceInvalidation touchedResources scope candidates =
    filter (frontendSurfaceFragmentDependsOnTouchedResource touchedValues scope) candidates
    where
        touchedValues = liveResourcesToFrontendSurfaceResourceValues touchedResources

frontendSurfaceFragmentDependsOnTouchedResource :: Set.Set FrontendSurfaceResourceValue -> LiveUpdateScope -> FrontendSurfaceMountedFragment -> Bool
frontendSurfaceFragmentDependsOnTouchedResource touchedValues scope mountedFragment =
    case mountedFragmentDependencies scope mountedFragment of
        [] -> False
        dependencies -> not (Set.null (Set.intersection touchedValues (Set.fromList dependencies)))

mountedFragmentDependencies :: LiveUpdateScope -> FrontendSurfaceMountedFragment -> [FrontendSurfaceResourceValue]
mountedFragmentDependencies scope mountedFragment = do
    surface <- maybeToList (findSurface scopeWire.surface)
    fragment <- maybeToList (findFragment mountedFragment.mountedFragmentKey.fragmentKind surface)
    dependency <- SurfaceIR.optionResourceDependencies fragment.fragmentOptions
    maybeToList (resourceValueFromDependency scopeWire.scope mountedFragment.mountedFragmentKey.fragmentParams dependency)
    where
        scopeWire = liveUpdateScopeToWire scope

findSurface :: Text -> Maybe SurfaceIR.SurfaceIR
findSurface surfaceName =
    List.find ((== surfaceName) . (.surfaceName)) reflectRegisteredFrontendSurfaces.contractSurfaces

findFragment :: Text -> SurfaceIR.SurfaceIR -> Maybe SurfaceIR.FragmentIR
findFragment fragmentKind surface =
    List.find ((== fragmentKind) . (.fragmentName)) surface.surfaceFragments

resourceValueFromDependency :: Aeson.Value -> Aeson.Value -> SurfaceIR.ResourceDependencyIR -> Maybe FrontendSurfaceResourceValue
resourceValueFromDependency scopeValue fragmentValue dependency = do
    fieldPairs <- mapM sourceFieldValue (zip dependency.dependencyResource.resourceFields dependency.dependencySources)
    pure FrontendSurfaceResourceValue
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
