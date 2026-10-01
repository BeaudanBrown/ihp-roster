module Test.ContextLifecycleSpec where

import Control.Concurrent (forkFinally, newEmptyMVar, putMVar, readMVar,
                           takeMVar, threadDelay, throwTo)
import Control.Exception (AsyncException (ThreadKilled), IOException, bracket,
                          try)
import Data.IORef (newIORef, readIORef, writeIORef)
import IHP.ModelSupport (unsafeSqlQueryScalar, unsafeSqlQuerySingleRow)
import IHP.Prelude
import IHP.Test.Mocking (withContext)
import System.IO.Error (ioeGetErrorString)
import System.Timeout (timeout)
import Test.Hspec
import Test.Support

-- Include backend_start so a recycled PID cannot be mistaken for this subject.
-- These probes inspect PostgreSQL's activity catalog, not application tables.
type BackendIdentity = (Int, UTCTime)

tests :: Spec
tests = do
    describe "database test context lifecycle" do
        it "releases connections after a successful callback" do
            withDatabaseTestContext \observer ->
                withContext
                    ( do
                        observerBackend <- currentBackend
                        subjectBackend <- withDatabaseTestContext \subject -> do
                            identity <- withContext currentBackend subject
                            assertSubjectIsLive observerBackend identity
                            pure identity
                        waitForBackendRelease subjectBackend `shouldReturn` True
                    )
                    observer

        it "releases connections after a callback exception" do
            withDatabaseTestContext \observer ->
                withContext
                    ( do
                        observerBackend <- currentBackend
                        captured <- newIORef Nothing
                        result :: Either IOException () <- try do
                            withDatabaseTestContext \subject -> do
                                identity <- withContext currentBackend subject
                                assertSubjectIsLive observerBackend identity
                                writeIORef captured (Just identity)
                                ioError (userError "context lifecycle probe")
                        fmap ioeGetErrorString (either Just (const Nothing) result)
                            `shouldBe` Just "context lifecycle probe"
                        readIORef captured >>= \case
                            Nothing -> expectationFailure "subject backend was not captured"
                            Just identity -> waitForBackendRelease identity `shouldReturn` True
                    )
                    observer

        it "releases connections after an asynchronous interruption" do
            withDatabaseTestContext \observer ->
                withContext
                    ( do
                        observerBackend <- currentBackend
                        started <- newEmptyMVar
                        finished <- newEmptyMVar
                        -- Always stop and reap our subject, including when a readiness
                        -- or visibility assertion fails. Never leave a diagnostic child.
                        bracket
                            (forkFinally
                                (withDatabaseTestContext \subject -> do
                                    identity <- withContext currentBackend subject
                                    putMVar started identity
                                    threadDelay maxBound)
                                (const (putMVar finished ())))
                            (\subjectThread -> do
                                throwTo subjectThread ThreadKilled
                                timeout 5_000_000 (readMVar finished) `shouldReturn` Just ())
                            (\subjectThread -> do
                                timeout 5_000_000 (takeMVar started) >>= \case
                                    Nothing -> expectationFailure "subject backend did not become ready"
                                    Just identity -> do
                                        assertSubjectIsLive observerBackend identity
                                        throwTo subjectThread ThreadKilled
                                        timeout 5_000_000 (readMVar finished) `shouldReturn` Just ()
                                        waitForBackendRelease identity `shouldReturn` True)
                    )
                    observer

        it "ignores unrelated connection departures and arrivals" do
            withDatabaseTestContext \observer ->
                withContext
                    ( do
                        observerBackend <- currentBackend
                        retired <- withDatabaseTestContext (withContext currentBackend)
                        retired `shouldNotBe` observerBackend
                        waitForBackendRelease retired `shouldReturn` True
                        subjectBackend <- withDatabaseTestContext \subject -> do
                            identity <- withContext currentBackend subject
                            assertSubjectIsLive observerBackend identity
                            pure identity
                        -- Another live connection must not mask subject release or
                        -- make the release oracle require the old database-wide count.
                        withDatabaseTestContext \unrelated -> do
                            unrelatedBackend <- withContext currentBackend unrelated
                            assertSubjectIsLive observerBackend unrelatedBackend
                            unrelatedBackend `shouldNotBe` subjectBackend
                            waitForBackendRelease subjectBackend `shouldReturn` True
                            backendExists unrelatedBackend `shouldReturn` True
                    )
                    observer

        it "does not report a still-live subject as released" do
            withDatabaseTestContext \observer ->
                withContext
                    ( do
                        observerBackend <- currentBackend
                        subjectBackend <- withDatabaseTestContext \subject -> do
                            identity <- withContext currentBackend subject
                            assertSubjectIsLive observerBackend identity
                            waitForBackendRelease identity `shouldReturn` False
                            backendExists identity `shouldReturn` True
                            pure identity
                        waitForBackendRelease subjectBackend `shouldReturn` True
                    )
                    observer

currentBackend :: (?modelContext :: ModelContext) => IO BackendIdentity
currentBackend =
    unsafeSqlQuerySingleRow
        "SELECT pid::INT4, backend_start FROM pg_stat_activity WHERE pid = pg_backend_pid()"
        ()

backendExists :: (?modelContext :: ModelContext) => BackendIdentity -> IO Bool
backendExists identity =
    unsafeSqlQueryScalar
        "SELECT EXISTS (SELECT 1 FROM pg_stat_activity WHERE datname = current_database() AND backend_type = 'client backend' AND pid = ? AND backend_start = ?)"
        identity

assertSubjectIsLive :: (?modelContext :: ModelContext) => BackendIdentity -> BackendIdentity -> Expectation
assertSubjectIsLive observer subject = do
    subject `shouldNotBe` observer
    backendExists subject `shouldReturn` True

-- Preserve the original 100 x 20ms release-poll bound. Return the verdict so a
-- live-connection negative control exercises the exact same release oracle.
waitForBackendRelease :: (?modelContext :: ModelContext) => BackendIdentity -> IO Bool
waitForBackendRelease identity = go (100 :: Int)
  where
    go attempts = do
        present <- backendExists identity
        if not present
            then pure True
            else
                if attempts == 0
                    then pure False
                    else threadDelay 20_000 >> go (attempts - 1)
