module Application.Helper.SurfaceProjection
    ( SurfaceProjectionCachePolicy (..)
    , SurfaceProjectionCacheStats (..)
    , SurfaceProjectionDefinition (..)
    , SurfaceProjectionStore
    , defaultSurfaceProjectionCachePolicy
    , loadSurfaceProjection
    , loadSurfaceProjectionFromStore
    , newSurfaceProjectionStore
    , newSurfaceProjectionStoreWithClock
    , surfaceProjectionCacheDeltaDetail
    , readSurfaceProjectionCacheStats
    , readSurfaceProjectionCacheStatsFromStore
    , renderSurfaceProjectionFragment
    , renderSurfaceProjectionFragmentFromStore
    , surfaceProjectionFragmentRef
    , surfaceProjectionFragmentRefs
    , warmSurfaceProjection
    , warmSurfaceProjectionFromStore
    ) where

import Application.Helper.LiveUpdate.Internal (LiveFragmentRef)
import qualified Data.Dynamic as Dynamic
import Data.IORef
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Time.Clock
import IHP.Prelude
import System.IO.Unsafe (unsafePerformIO)
import qualified Text.Blaze.Html as Blaze

data SurfaceProjectionCachePolicy = SurfaceProjectionCachePolicy
    { ttl                  :: !NominalDiffTime
    , maxEntriesPerSurface :: !Int
    }
    deriving (Eq, Show)

data SurfaceProjectionCacheStats = SurfaceProjectionCacheStats
    { hits      :: !Int
    , misses    :: !Int
    , loads     :: !Int
    , warms     :: !Int
    , evictions :: !Int
    }
    deriving (Eq, Show)

data SurfaceProjectionDefinition scope snapshot fragment = SurfaceProjectionDefinition
    { surfaceName      :: !Text
    , cachePolicy      :: !SurfaceProjectionCachePolicy
    , scopeKey         :: scope -> Text
    , viewerKey        :: IO Text
    , currentVersion   :: scope -> IO Int
    , loadProjection   :: scope -> IO snapshot
    , renderFragment   :: snapshot -> fragment -> Maybe Blaze.Html
    , buildFragmentRef :: scope -> fragment -> LiveFragmentRef
    }

data SurfaceProjectionStore = SurfaceProjectionStore
    { stateRef    :: !(IORef SurfaceProjectionCacheState)
    , currentTime :: !(IO UTCTime)
    }

data SurfaceProjectionCacheState = SurfaceProjectionCacheState
    { entries :: !(Map.Map SurfaceProjectionCacheKey SurfaceProjectionCacheEntry)
    , stats :: !SurfaceProjectionCacheStats
    }

data SurfaceProjectionCacheKey = SurfaceProjectionCacheKey
    { keySurfaceName :: !Text
    , keyViewer      :: !Text
    , keyScope       :: !Text
    , keyVersion     :: !Int
    }
    deriving (Eq, Ord, Show)

data SurfaceProjectionCacheEntry = SurfaceProjectionCacheEntry
    { storedAt       :: !UTCTime
    , lastAccessedAt :: !UTCTime
    , entryTtl       :: !NominalDiffTime
    , snapshot       :: !Dynamic.Dynamic
    }

defaultSurfaceProjectionCachePolicy :: SurfaceProjectionCachePolicy
defaultSurfaceProjectionCachePolicy =
    SurfaceProjectionCachePolicy
        { ttl = 600
        , maxEntriesPerSurface = 200
        }

surfaceProjectionStore :: SurfaceProjectionStore
surfaceProjectionStore = unsafePerformIO newSurfaceProjectionStore
{-# NOINLINE surfaceProjectionStore #-}

newSurfaceProjectionStore :: IO SurfaceProjectionStore
newSurfaceProjectionStore =
    newSurfaceProjectionStoreWithClock getCurrentTime

newSurfaceProjectionStoreWithClock :: IO UTCTime -> IO SurfaceProjectionStore
newSurfaceProjectionStoreWithClock clock = do
    stateRef <- newIORef emptySurfaceProjectionCacheState
    pure SurfaceProjectionStore { stateRef, currentTime = clock }

emptySurfaceProjectionCacheState :: SurfaceProjectionCacheState
emptySurfaceProjectionCacheState =
    SurfaceProjectionCacheState
        { entries = Map.empty
        , stats = zeroSurfaceProjectionCacheStats
        }

zeroSurfaceProjectionCacheStats :: SurfaceProjectionCacheStats
zeroSurfaceProjectionCacheStats =
    SurfaceProjectionCacheStats
        { hits = 0
        , misses = 0
        , loads = 0
        , warms = 0
        , evictions = 0
        }

loadSurfaceProjection ::
    forall scope snapshot fragment.
    (Dynamic.Typeable snapshot) =>
    SurfaceProjectionDefinition scope snapshot fragment ->
    scope ->
    IO snapshot
loadSurfaceProjection =
    loadSurfaceProjectionFromStore surfaceProjectionStore

loadSurfaceProjectionFromStore ::
    forall scope snapshot fragment.
    (Dynamic.Typeable snapshot) =>
    SurfaceProjectionStore ->
    SurfaceProjectionDefinition scope snapshot fragment ->
    scope ->
    IO snapshot
loadSurfaceProjectionFromStore store definition scope = do
    viewer <- definition.viewerKey
    version <- definition.currentVersion scope
    now <- store.currentTime
    let key =
            SurfaceProjectionCacheKey
                { keySurfaceName = definition.surfaceName
                , keyViewer = viewer
                , keyScope = definition.scopeKey scope
                , keyVersion = version
                }
    cacheLookup <- lookupSurfaceProjection store key now
    case cacheLookup of
        Just cachedSnapshot -> pure cachedSnapshot
        Nothing -> do
            snapshot <- definition.loadProjection scope
            insertedAt <- store.currentTime
            insertSurfaceProjection store definition key insertedAt snapshot
            pure snapshot

warmSurfaceProjection ::
    forall scope snapshot fragment.
    (Dynamic.Typeable snapshot) =>
    SurfaceProjectionDefinition scope snapshot fragment ->
    scope ->
    IO ()
warmSurfaceProjection =
    warmSurfaceProjectionFromStore surfaceProjectionStore

warmSurfaceProjectionFromStore ::
    forall scope snapshot fragment.
    (Dynamic.Typeable snapshot) =>
    SurfaceProjectionStore ->
    SurfaceProjectionDefinition scope snapshot fragment ->
    scope ->
    IO ()
warmSurfaceProjectionFromStore store definition scope = do
    atomicModifyIORef' store.stateRef \state ->
        (state { stats = incrementWarms state.stats }, ())
    _ <- loadSurfaceProjectionFromStore store definition scope
    pure ()

renderSurfaceProjectionFragment ::
    forall scope snapshot fragment.
    (Dynamic.Typeable snapshot) =>
    SurfaceProjectionDefinition scope snapshot fragment ->
    scope ->
    fragment ->
    IO (Maybe Blaze.Html)
renderSurfaceProjectionFragment =
    renderSurfaceProjectionFragmentFromStore surfaceProjectionStore

renderSurfaceProjectionFragmentFromStore ::
    forall scope snapshot fragment.
    (Dynamic.Typeable snapshot) =>
    SurfaceProjectionStore ->
    SurfaceProjectionDefinition scope snapshot fragment ->
    scope ->
    fragment ->
    IO (Maybe Blaze.Html)
renderSurfaceProjectionFragmentFromStore store definition scope fragment = do
    snapshot <- loadSurfaceProjectionFromStore store definition scope
    pure (definition.renderFragment snapshot fragment)

surfaceProjectionFragmentRef :: SurfaceProjectionDefinition scope snapshot fragment -> scope -> fragment -> LiveFragmentRef
surfaceProjectionFragmentRef definition scope fragment =
    definition.buildFragmentRef scope fragment

surfaceProjectionFragmentRefs :: SurfaceProjectionDefinition scope snapshot fragment -> scope -> [fragment] -> [LiveFragmentRef]
surfaceProjectionFragmentRefs definition scope =
    map (surfaceProjectionFragmentRef definition scope)

readSurfaceProjectionCacheStats :: IO SurfaceProjectionCacheStats
readSurfaceProjectionCacheStats =
    readSurfaceProjectionCacheStatsFromStore surfaceProjectionStore

readSurfaceProjectionCacheStatsFromStore :: SurfaceProjectionStore -> IO SurfaceProjectionCacheStats
readSurfaceProjectionCacheStatsFromStore store =
    (.stats) <$> readIORef store.stateRef

surfaceProjectionCacheDeltaDetail :: SurfaceProjectionCacheStats -> SurfaceProjectionCacheStats -> Maybe Text
surfaceProjectionCacheDeltaDetail before after
    | null parts = Nothing
    | otherwise = Just (Text.intercalate "," parts)
    where
        parts =
            catMaybes
                [ renderDelta "hits" before.hits after.hits
                , renderDelta "misses" before.misses after.misses
                , renderDelta "loads" before.loads after.loads
                , renderDelta "warms" before.warms after.warms
                , renderDelta "evictions" before.evictions after.evictions
                ]
        renderDelta label beforeValue afterValue =
            let delta = afterValue - beforeValue
             in if delta == 0 then Nothing else Just (label <> "=" <> tshow delta)

lookupSurfaceProjection ::
    forall snapshot.
    (Dynamic.Typeable snapshot) =>
    SurfaceProjectionStore ->
    SurfaceProjectionCacheKey ->
    UTCTime ->
    IO (Maybe snapshot)
lookupSurfaceProjection store key now =
    atomicModifyIORef' store.stateRef \state ->
        let (cleanedEntries, expiredCount) = dropExpiredEntries now state.entries
            cleanedState = addEvictions expiredCount state { entries = cleanedEntries }
         in case Map.lookup key cleanedEntries of
                Just entry
                    | Just typedSnapshot <- Dynamic.fromDynamic entry.snapshot ->
                        let touchedEntry = entry { lastAccessedAt = now }
                            nextState =
                                cleanedState
                                    { entries = Map.insert key touchedEntry cleanedEntries
                                    , stats = incrementHits cleanedState.stats
                                    }
                         in (nextState, Just typedSnapshot)
                _ ->
                    let nextState =
                            cleanedState
                                { stats = incrementMisses cleanedState.stats
                                }
                     in (nextState, Nothing)

insertSurfaceProjection ::
    forall scope snapshot fragment.
    (Dynamic.Typeable snapshot) =>
    SurfaceProjectionStore ->
    SurfaceProjectionDefinition scope snapshot fragment ->
    SurfaceProjectionCacheKey ->
    UTCTime ->
    snapshot ->
    IO ()
insertSurfaceProjection store definition key now projection =
    atomicModifyIORef' store.stateRef \state ->
        let (withoutExpired, expiredCount) = dropExpiredEntries now state.entries
            (withoutOlderVersions, olderVersionCount) = dropOlderScopeVersions key withoutExpired
            nextEntry =
                SurfaceProjectionCacheEntry
                    { storedAt = now
                    , lastAccessedAt = now
                    , entryTtl = definition.cachePolicy.ttl
                    , snapshot = Dynamic.toDyn projection
                    }
            withInserted = Map.insert key nextEntry withoutOlderVersions
            (trimmedEntries, lruEvictionCount) =
                trimSurfaceEntries definition.surfaceName definition.cachePolicy.maxEntriesPerSurface withInserted
            nextStats =
                state.stats
                    |> incrementLoads
                    |> addEvictionCount expiredCount
                    |> addEvictionCount olderVersionCount
                    |> addEvictionCount lruEvictionCount
         in ( state
                { entries = trimmedEntries
                , stats = nextStats
                }
            , ()
            )

dropExpiredEntries :: UTCTime -> Map.Map SurfaceProjectionCacheKey SurfaceProjectionCacheEntry -> (Map.Map SurfaceProjectionCacheKey SurfaceProjectionCacheEntry, Int)
dropExpiredEntries now cacheEntries =
    let (expiredEntries, activeEntries) =
            Map.partition (\entry -> diffUTCTime now entry.lastAccessedAt > entry.entryTtl) cacheEntries
     in (activeEntries, Map.size expiredEntries)

dropOlderScopeVersions :: SurfaceProjectionCacheKey -> Map.Map SurfaceProjectionCacheKey SurfaceProjectionCacheEntry -> (Map.Map SurfaceProjectionCacheKey SurfaceProjectionCacheEntry, Int)
dropOlderScopeVersions key cacheEntries =
    let isOlderScopeVersion candidateKey =
            candidateKey.keySurfaceName == key.keySurfaceName
                && candidateKey.keyViewer == key.keyViewer
                && candidateKey.keyScope == key.keyScope
                && candidateKey.keyVersion < key.keyVersion
        (staleEntries, retainedEntries) = Map.partitionWithKey (\candidateKey _ -> isOlderScopeVersion candidateKey) cacheEntries
     in (retainedEntries, Map.size staleEntries)

trimSurfaceEntries :: Text -> Int -> Map.Map SurfaceProjectionCacheKey SurfaceProjectionCacheEntry -> (Map.Map SurfaceProjectionCacheKey SurfaceProjectionCacheEntry, Int)
trimSurfaceEntries surfaceName maxEntries cacheEntries
    | maxEntries <= 0 =
        let keysToDrop = map fst matchingEntries
         in (foldr Map.delete cacheEntries keysToDrop, length keysToDrop)
    | length matchingEntries <= maxEntries = (cacheEntries, 0)
    | otherwise =
        let entriesToDropCount = length matchingEntries - maxEntries
            keysToDrop =
                matchingEntries
                    |> sortOn (lastAccessedAt . snd)
                    |> take entriesToDropCount
                    |> map fst
            trimmedEntries = foldr Map.delete cacheEntries keysToDrop
         in (trimmedEntries, length keysToDrop)
    where
        matchingEntries =
            cacheEntries
                |> Map.toList
                |> filter (\(key, _) -> key.keySurfaceName == surfaceName)

incrementHits :: SurfaceProjectionCacheStats -> SurfaceProjectionCacheStats
incrementHits stats = stats { hits = stats.hits + 1 }

incrementMisses :: SurfaceProjectionCacheStats -> SurfaceProjectionCacheStats
incrementMisses stats = stats { misses = stats.misses + 1 }

incrementLoads :: SurfaceProjectionCacheStats -> SurfaceProjectionCacheStats
incrementLoads stats = stats { loads = stats.loads + 1 }

incrementWarms :: SurfaceProjectionCacheStats -> SurfaceProjectionCacheStats
incrementWarms stats = stats { warms = stats.warms + 1 }

addEvictions :: Int -> SurfaceProjectionCacheState -> SurfaceProjectionCacheState
addEvictions count state
    | count <= 0 = state
    | otherwise = state { stats = addEvictionCount count state.stats }

addEvictionCount :: Int -> SurfaceProjectionCacheStats -> SurfaceProjectionCacheStats
addEvictionCount count stats
    | count <= 0 = stats
    | otherwise = stats { evictions = stats.evictions + count }
