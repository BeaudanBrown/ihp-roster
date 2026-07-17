{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | Stable all-kind generator facade. Focused renderers remain pure; this
-- composer validates and returns the complete managed module set before the
-- script writes anything or performs stale-file cleanup.
module Application.Helper.FrontendContract.Surface.HaskellAdapter.Generator
    ( GeneratedHaskellModule (..)
    , GeneratedSurfaceAdapterLane (..)
    , composeGeneratedSurfaceAdapterModules
    , generateSurfaceActionAdapterModules
    , generateSurfaceAdapterModules
    , generateSurfaceIntentAdapterModules
    , generateSurfaceLiveAdapterModules
    , generateSurfaceResourceAdapterModules
    ) where

import Application.Helper.FrontendContract.Surface.ContractIR
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Action (generateSurfaceActionAdapterModules)
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Core (GeneratedHaskellModule (..),
                                                                        stableDiagnostics)
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Family
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Intent (generateSurfaceIntentAdapterModules)
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Live (generateSurfaceLiveAdapterModules)
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Resource (generateSurfaceResourceAdapterModules)
import Data.Either (lefts)
import qualified Data.List as List
import qualified Data.Text as Text
import IHP.Prelude

-- | Closed bookkeeping lanes for every private Surface adapter namespace.
data GeneratedSurfaceAdapterLane
    = GeneratedResourceAdapterLane ![GeneratedHaskellModule]
    | GeneratedLiveAdapterLane ![GeneratedHaskellModule]
    | GeneratedActionAdapterLane ![GeneratedHaskellModule]
    | GeneratedIntentAdapterLane ![GeneratedHaskellModule]
    deriving (Eq, Show)

-- | Generate every adapter kind and compose one atomic managed set. Resource,
-- Live, Action, and Intent publication is mandatory: empty or partial homes fail
-- checked-IR completeness before any managed module is exposed.
generateSurfaceAdapterModules ::
    SurfaceContractIR ->
    SurfaceAdapterRegistry ->
    Either [ContractDiagnostic] [GeneratedHaskellModule]
generateSurfaceAdapterModules contract registry =
    composeGeneratedSurfaceAdapterModules
        [ GeneratedResourceAdapterLane
            <$> generateSurfaceResourceAdapterModules contract registry
        , GeneratedLiveAdapterLane
            <$> generateSurfaceLiveAdapterModules contract registry
        , GeneratedActionAdapterLane
            <$> generateSurfaceActionAdapterModules contract registry
        , GeneratedIntentAdapterLane
            <$> generateSurfaceIntentAdapterModules contract registry
        ]

-- | Accumulate focused-lane diagnostics, reject duplicate physical modules
-- across the complete set, and expose modules only after all lanes validate.
composeGeneratedSurfaceAdapterModules ::
    [Either [ContractDiagnostic] GeneratedSurfaceAdapterLane] ->
    Either [ContractDiagnostic] [GeneratedHaskellModule]
composeGeneratedSurfaceAdapterModules laneResults =
    case stableDiagnostics (focusedDiagnostics <> collisionDiagnostics) of
        []          -> Right (map snd (List.sortOn moduleSortKey moduleRows))
        diagnostics -> Left diagnostics
  where
    focusedDiagnostics = concat (lefts laneResults)
    moduleRows =
        [ (laneLabel lane, generated)
        | Right lane <- laneResults
        , generated <- laneModules lane
        ]
    collisionDiagnostics =
        duplicateModuleDiagnostics
            "generated-adapter-path-collision"
            "physical path"
            (.generatedModulePath)
            moduleRows
            <> duplicateModuleDiagnostics
                "generated-adapter-module-collision"
                "module name"
                (.generatedModuleName)
                moduleRows
    moduleSortKey (lane, generated) =
        (generated.generatedModulePath, generated.generatedModuleName, lane)

laneLabel :: GeneratedSurfaceAdapterLane -> Text
laneLabel = \case
    GeneratedResourceAdapterLane _ -> "Resource"
    GeneratedLiveAdapterLane _     -> "Live"
    GeneratedActionAdapterLane _   -> "Action"
    GeneratedIntentAdapterLane _   -> "Intent"

laneModules :: GeneratedSurfaceAdapterLane -> [GeneratedHaskellModule]
laneModules = \case
    GeneratedResourceAdapterLane modules -> modules
    GeneratedLiveAdapterLane modules     -> modules
    GeneratedActionAdapterLane modules   -> modules
    GeneratedIntentAdapterLane modules   -> modules

duplicateModuleDiagnostics ::
    (Ord key, Show key) =>
    Text ->
    Text ->
    (GeneratedHaskellModule -> key) ->
    [(Text, GeneratedHaskellModule)] ->
    [ContractDiagnostic]
duplicateModuleDiagnostics code label keyOf rows =
    rows
        |> List.sortOn (keyOf . snd)
        |> List.groupBy (\left right -> keyOf (snd left) == keyOf (snd right))
        |> concatMap \case
            group@((_, first) : _)
                | length group > 1 ->
                    [ ContractDiagnostic
                        { diagnosticCode = code
                        , diagnosticMessage =
                            "Generated Surface adapter " <> label <> " " <> cs (show (keyOf first))
                                <> " is produced by lanes "
                                <> Text.intercalate ", " (map fst group)
                        }
                    ]
            _ -> []
