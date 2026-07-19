module Test.ContextLifecycleSpec where

import Control.Concurrent (forkFinally, newEmptyMVar, putMVar, takeMVar,
                           threadDelay, throwTo)
import Control.Exception (AsyncException (ThreadKilled), SomeException, try)
import Control.Monad (void)
import Data.Either (isLeft)
import IHP.ModelSupport (sqlQueryScalar)
import IHP.Prelude
import IHP.Test.Mocking (withContext)
import System.Timeout (timeout)
import Test.Hspec
import Test.Support

tests :: Spec
tests = do
    describe "database test context lifecycle" do
        it "releases connections after a successful callback" do
            withDatabaseTestContext \observer ->
                withContext
                    ( do
                        baseline <- activeDatabaseBackends
                        peak <-
                            withDatabaseTestContext \subject ->
                                withContext
                                    ( do
                                        touchDatabase
                                        activeDatabaseBackends
                                    )
                                    subject
                        peak `shouldSatisfy` (> baseline)
                        waitForBackendCount baseline
                    )
                    observer

        it "releases connections after a callback exception" do
            withDatabaseTestContext \observer ->
                withContext
                    ( do
                        baseline <- activeDatabaseBackends
                        result :: Either SomeException () <- try do
                            withDatabaseTestContext \subject ->
                                withContext
                                    ( do
                                        touchDatabase
                                        ioError (userError "context lifecycle probe")
                                    )
                                    subject
                        result `shouldSatisfy` isLeft
                        waitForBackendCount baseline
                    )
                    observer

        it "releases connections after an asynchronous interruption" do
            withDatabaseTestContext \observer ->
                withContext
                    ( do
                        baseline <- activeDatabaseBackends
                        started <- newEmptyMVar
                        finished <- newEmptyMVar
                        subjectThread <-
                            forkFinally
                                ( withDatabaseTestContext \subject ->
                                    withContext
                                        ( do
                                            touchDatabase
                                            putMVar started ()
                                            threadDelay maxBound
                                        )
                                        subject
                                )
                                (const (putMVar finished ()))

                        timeout 5_000_000 (takeMVar started) `shouldReturn` Just ()
                        peak <- activeDatabaseBackends
                        peak `shouldSatisfy` (> baseline)
                        throwTo subjectThread ThreadKilled
                        timeout 5_000_000 (takeMVar finished) `shouldReturn` Just ()
                        waitForBackendCount baseline
                    )
                    observer

activeDatabaseBackends :: (?modelContext :: ModelContext) => IO Int
activeDatabaseBackends =
    sqlQueryScalar
        "SELECT COUNT(*)::INT4 FROM pg_stat_activity WHERE datname = current_database() AND backend_type = 'client backend'"
        ()

touchDatabase :: (?modelContext :: ModelContext) => IO ()
touchDatabase = void (sqlQueryScalar "SELECT 1::INT4" () :: IO Int)

waitForBackendCount :: (?modelContext :: ModelContext) => Int -> IO ()
waitForBackendCount expected = go (100 :: Int)
  where
    go attempts = do
        actual <- activeDatabaseBackends
        if actual == expected
            then pure ()
            else
                if attempts == 0
                    then actual `shouldBe` expected
                    else threadDelay 20_000 >> go (attempts - 1)
