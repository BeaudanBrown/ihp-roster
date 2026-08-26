module Application.Helper.LiveUpdate.DurableState
    ( advanceDurableListenerCursor
    , advanceDurableResourceVersions
    , currentDurableCursor
    , currentDurableDependencyWatermark
    , durableStateIsHydrated
    , fetchDurableDependencyWatermark
    , replaceDurableResourceVersions
    ) where

import Application.Helper.FrontendContract.Surface.DependencyPlanner (surfaceSubscriptionDependencyIdentities)
import Application.Helper.LiveUpdate.DurableCodec (canonicalDurableResourceKey)
import Application.Helper.LiveUpdate.Runtime (SurfaceSubscription)
import Data.IORef
import qualified Data.Map.Strict as Map
import Generated.Types
import IHP.Fetch (fetchOneOrNothing)
import IHP.ModelSupport.Types (Id' (Id))
import IHP.Prelude
import IHP.QueryBuilder (filterWhereId, query)
import System.IO.Unsafe (unsafePerformIO)

data DurableState = DurableState
    { resourceVersions :: !(Map.Map Text Int)
    , cursor           :: !Int
    , hydrated         :: !Bool
    }

durableStateRef :: IORef DurableState
durableStateRef = unsafePerformIO (newIORef DurableState { resourceVersions = Map.empty, cursor = 0, hydrated = False })
{-# NOINLINE durableStateRef #-}

replaceDurableResourceVersions :: [(Text, Int)] -> Int -> IO ()
replaceDurableResourceVersions versions cursor =
    writeIORef durableStateRef DurableState { resourceVersions = Map.fromList versions, cursor, hydrated = True }

-- Ordered listener replay advances resource freshness before its cursor.
advanceDurableResourceVersions :: [(Text, Int)] -> Int -> IO ()
advanceDurableResourceVersions versions eventSequence =
    atomicModifyIORef' durableStateRef \state ->
        ( state
            { resourceVersions = foldl' (\current (key, _) -> Map.insertWith max key eventSequence current) state.resourceVersions versions
            }
        , ()
        )

advanceDurableListenerCursor :: Int -> IO Bool
advanceDurableListenerCursor eventSequence =
    atomicModifyIORef' durableStateRef \state ->
        if eventSequence <= state.cursor
            then (state, False)
            else (state { cursor = eventSequence }, True)

currentDurableCursor :: IO Int
currentDurableCursor = (.cursor) <$> readIORef durableStateRef

durableStateIsHydrated :: IO Bool
durableStateIsHydrated = (.hydrated) <$> readIORef durableStateRef

fetchDurableDependencyWatermark :: (?modelContext :: ModelContext) => SurfaceSubscription -> IO Int
fetchDurableDependencyWatermark subscription = do
    versions <- forM dependencyKeys \key -> do
        version <- query @LiveResourceVersion |> filterWhereId (Id key) |> fetchOneOrNothing
        pure (maybe 0 (.latestEventSequence) version)
    pure (maximum (0 : versions))
  where
    dependencyKeys = map (uncurry canonicalDurableResourceKey) (surfaceSubscriptionDependencyIdentities subscription)

currentDurableDependencyWatermark :: SurfaceSubscription -> IO Int
currentDurableDependencyWatermark subscription = do
    state <- readIORef durableStateRef
    pure $ maximum (0 : map (\identity -> Map.findWithDefault 0 (uncurry canonicalDurableResourceKey identity) state.resourceVersions) (surfaceSubscriptionDependencyIdentities subscription))
