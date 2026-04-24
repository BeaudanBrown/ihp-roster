module Test.SurfaceProjectionSpec where

import Application.Helper.LiveUpdate (LiveFragmentRef (..))
import Application.Helper.SurfaceProjection
import Data.IORef
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock
import IHP.Prelude
import Test.Hspec
import qualified Text.Blaze.Html5 as Html5

tests :: Spec
tests = describe "SurfaceProjection helper" do
    it "reuses cached snapshots on a cache hit" do
        clock <- newClock
        store <- newStore clock
        viewerRef <- newIORef "manager"
        versionRef <- newIORef 0
        loadCountRef <- newIORef (0 :: Int)
        let definition = testDefinition viewerRef versionRef loadCountRef defaultSurfaceProjectionCachePolicy

        first <- loadSurfaceProjectionFromStore store definition (0 :: Int)
        second <- loadSurfaceProjectionFromStore store definition 0
        stats <- readSurfaceProjectionCacheStatsFromStore store
        loadCount <- readIORef loadCountRef

        first `shouldBe` ("projection-1" :: Text)
        second `shouldBe` "projection-1"
        loadCount `shouldBe` 1
        stats.hits `shouldBe` 1
        stats.misses `shouldBe` 1
        stats.loads `shouldBe` 1

    it "separates snapshots by viewer context" do
        clock <- newClock
        store <- newStore clock
        viewerRef <- newIORef "manager"
        versionRef <- newIORef 0
        loadCountRef <- newIORef (0 :: Int)
        let definition = testDefinition viewerRef versionRef loadCountRef defaultSurfaceProjectionCachePolicy

        managerSnapshot <- loadSurfaceProjectionFromStore store definition (0 :: Int)
        writeIORef viewerRef "worker"
        workerSnapshot <- loadSurfaceProjectionFromStore store definition 0
        loadCount <- readIORef loadCountRef

        managerSnapshot `shouldBe` ("projection-1" :: Text)
        workerSnapshot `shouldBe` "projection-2"
        loadCount `shouldBe` 2

    it "invalidates cached snapshots when the scope version changes" do
        clock <- newClock
        store <- newStore clock
        viewerRef <- newIORef "manager"
        versionRef <- newIORef 0
        loadCountRef <- newIORef (0 :: Int)
        let definition = testDefinition viewerRef versionRef loadCountRef defaultSurfaceProjectionCachePolicy

        snapshotA <- loadSurfaceProjectionFromStore store definition (0 :: Int)
        writeIORef versionRef 1
        snapshotB <- loadSurfaceProjectionFromStore store definition 0
        stats <- readSurfaceProjectionCacheStatsFromStore store

        snapshotA `shouldBe` ("projection-1" :: Text)
        snapshotB `shouldBe` "projection-2"
        stats.loads `shouldBe` 2
        stats.evictions `shouldBe` 1

    it "keeps newer scope versions cached when an older version is loaded later" do
        clock <- newClock
        store <- newStore clock
        viewerRef <- newIORef "manager"
        versionRef <- newIORef 2
        loadCountRef <- newIORef (0 :: Int)
        let definition = testDefinition viewerRef versionRef loadCountRef defaultSurfaceProjectionCachePolicy

        newerSnapshot <- loadSurfaceProjectionFromStore store definition (0 :: Int)
        writeIORef versionRef 1
        olderSnapshot <- loadSurfaceProjectionFromStore store definition 0
        writeIORef versionRef 2
        cachedNewerSnapshot <- loadSurfaceProjectionFromStore store definition 0
        stats <- readSurfaceProjectionCacheStatsFromStore store
        loadCount <- readIORef loadCountRef

        newerSnapshot `shouldBe` ("projection-1" :: Text)
        olderSnapshot `shouldBe` "projection-2"
        cachedNewerSnapshot `shouldBe` "projection-1"
        loadCount `shouldBe` 2
        stats.hits `shouldBe` 1
        stats.loads `shouldBe` 2
        stats.evictions `shouldBe` 0

    it "warms a projection without forcing a second load on the next read" do
        clock <- newClock
        store <- newStore clock
        viewerRef <- newIORef "manager"
        versionRef <- newIORef 0
        loadCountRef <- newIORef (0 :: Int)
        let definition = testDefinition viewerRef versionRef loadCountRef defaultSurfaceProjectionCachePolicy

        warmSurfaceProjectionFromStore store definition (0 :: Int)
        snapshot <- loadSurfaceProjectionFromStore store definition 0
        stats <- readSurfaceProjectionCacheStatsFromStore store
        loadCount <- readIORef loadCountRef

        snapshot `shouldBe` ("projection-1" :: Text)
        loadCount `shouldBe` 1
        stats.warms `shouldBe` 1
        stats.hits `shouldBe` 1

    it "evicts expired snapshots after the TTL" do
        clock <- newClock
        store <- newStore clock
        viewerRef <- newIORef "manager"
        versionRef <- newIORef 0
        loadCountRef <- newIORef (0 :: Int)
        let policy = SurfaceProjectionCachePolicy { ttl = 10, maxEntriesPerSurface = 10 }
        let definition = testDefinition viewerRef versionRef loadCountRef policy

        _ <- loadSurfaceProjectionFromStore store definition (0 :: Int)
        advanceClock clock 11
        snapshot <- loadSurfaceProjectionFromStore store definition 0
        stats <- readSurfaceProjectionCacheStatsFromStore store

        snapshot `shouldBe` ("projection-2" :: Text)
        stats.loads `shouldBe` 2
        stats.evictions `shouldBe` 1

    it "trims least-recently-used snapshots per surface when over capacity" do
        clock <- newClock
        store <- newStore clock
        viewerRef <- newIORef "manager"
        versionRef <- newIORef 0
        loadCountRef <- newIORef (0 :: Int)
        let policy = SurfaceProjectionCachePolicy { ttl = 600, maxEntriesPerSurface = 2 }
        let definition = testDefinition viewerRef versionRef loadCountRef policy

        _ <- loadSurfaceProjectionFromStore store definition (1 :: Int)
        advanceClock clock 1
        _ <- loadSurfaceProjectionFromStore store definition 2
        advanceClock clock 1
        _ <- loadSurfaceProjectionFromStore store definition 2
        advanceClock clock 1
        _ <- loadSurfaceProjectionFromStore store definition 3
        advanceClock clock 1
        reloaded <- loadSurfaceProjectionFromStore store definition 1
        stats <- readSurfaceProjectionCacheStatsFromStore store

        reloaded `shouldBe` ("projection-4" :: Text)
        stats.evictions `shouldBe` 2

testDefinition :: IORef Text -> IORef Int -> IORef Int -> SurfaceProjectionCachePolicy -> SurfaceProjectionDefinition Int Text Int
testDefinition viewerRef versionRef loadCountRef cachePolicy =
    SurfaceProjectionDefinition
        { surfaceName = "test-surface"
        , cachePolicy
        , scopeKey = tshow
        , viewerKey = readIORef viewerRef
        , currentVersion = const (readIORef versionRef)
        , loadProjection = \_ -> do
            loadCount <- atomicModifyIORef' loadCountRef \count ->
                let nextCount = count + 1
                 in (nextCount, nextCount)
            pure ("projection-" <> tshow loadCount)
        , renderFragment = \snapshot fragment -> Just (Html5.toHtml (snapshot <> "-fragment-" <> tshow fragment))
        , buildFragmentRef = \scope _ ->
            LiveFragmentRef
                { targetId = "target-" <> tshow scope
                , url = "/surface/" <> tshow scope
                , deferUntilBlur = False
                }
        }

newClock :: IO (IORef UTCTime)
newClock =
    newIORef (UTCTime (fromGregorian 2026 4 8) 0)

newStore :: IORef UTCTime -> IO SurfaceProjectionStore
newStore clock =
    newSurfaceProjectionStoreWithClock (readIORef clock)

advanceClock :: IORef UTCTime -> NominalDiffTime -> IO ()
advanceClock clock seconds =
    modifyIORef' clock (\time -> addUTCTime seconds time)
