module Test.BoundaryUtilitiesSpec where

import Application.Helper.Export.PayrollWorkbookConfiguration (PayrollWorkbookConfigurationError (..),
                                                              payrollWorkbookConfigurationPersistenceError)
import Application.Helper.OpaqueToken (hashOpaqueToken)
import Application.Helper.PasskeyRecoveryCodes (hashRecoveryCode)
import Application.Helper.NavigationContextInitialization
import Control.Concurrent.Async (withAsync, waitCatch)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import qualified Control.Exception as Exception
import Control.Monad (forM_, void)
import Data.IORef
import qualified Network.Wai as Wai
import qualified Network.Wai.Test as WaiTest
import Network.HTTP.Types (status200)
import System.Timeout (timeout)
import qualified Hasql.Errors as Hasql
import IHP.ModelSupport.Types (HasqlSessionError (..))
import IHP.Prelude
import Test.Hspec

withNavigationRequest :: (Wai.Request -> IO ()) -> IO ()
withNavigationRequest scenario = void $ WaiTest.runSession (WaiTest.request Wai.defaultRequest) $
    navigationContextInitializationMiddleware $ \request respond -> do
        scenario request
        respond (Wai.responseLBS status200 [] "")

tests :: Spec
tests = do
    describe "boundary utility encodings" do
        it "retains lowercase SHA-256 opaque-token encoding" do
            hashOpaqueToken "abc"
                `shouldBe` "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

        it "retains lowercase SHA-256 normalized recovery-code encoding" do
            hashRecoveryCode "abcd-efgh-ijkl-mnop"
                `shouldBe` "e7e8b89c2721d290cc5f55425491ecd6831355e91063f20b39c22f9ec6a71f91"

    describe "Navigation initialization exception propagation" do
        it "initializes once and keeps successful later requests in the same request ready" do
            withNavigationRequest \request -> do
                calls <- newIORef (0 :: Int)
                deferNavigationContextInitialization request (modifyIORef' calls (+ 1))
                ensureNavigationContextInitialized request
                ensureNavigationContextInitialized request
                readIORef calls `shouldReturn` 1
        it "retains the original synchronous and async failures for the owner and waiters" do
            forM_ [Exception.toException (Exception.ErrorCall "navigation fixture"), Exception.toException Exception.ThreadKilled] \failure -> do
                let sameFailure exception =
                        (Exception.fromException exception :: Maybe Exception.ErrorCall) == Exception.fromException failure
                            && (Exception.fromException exception :: Maybe Exception.AsyncException) == Exception.fromException failure
                completed <- timeout 5000000 $ withNavigationRequest \request -> do
                    started <- newEmptyMVar
                    release <- newEmptyMVar
                    deferNavigationContextInitialization request (putMVar started () >> takeMVar release >> Exception.throwIO failure)
                    withAsync (ensureNavigationContextInitialized request) \owner -> do
                        takeMVar started
                        withAsync (ensureNavigationContextInitialized request) \waiter -> do
                            putMVar release ()
                            forM_ [owner, waiter] \attempt -> do
                                result <- waitCatch attempt
                                result `shouldSatisfy` either sameFailure (const False)
                    -- Failed initialization is retained rather than silently rerun.
                    ensureNavigationContextInitialized request `shouldThrow` sameFailure
                completed `shouldBe` Just ()

    describe "PayrollWorkbookConfiguration persistence classification" do
        it "maps statement and script 23505 failures to the supplied normalized name, regardless of constraint" do
            forM_ ["venue_name", "configuration_position", "unrelated_constraint"] \constraint -> do
                let serverError = Hasql.ServerError "23505" "duplicate" (Just constraint) Nothing Nothing
                forM_ (sessionErrors serverError) \sessionError ->
                    payrollWorkbookConfigurationPersistenceError "Pay run" (HasqlSessionError sessionError)
                        `shouldBe` Just (PayrollWorkbookConfigurationNameConflict "Pay run")

        it "leaves other SQLSTATEs and non-server failures unclassified" do
            let serverErrors = concatMap (sessionErrors . (\code -> Hasql.ServerError code "failure" Nothing Nothing Nothing)) ["23514", "23503", "40001"]
            let otherErrors =
                    [ Hasql.ConnectionSessionError "connection"
                    , Hasql.DriverSessionError "driver"
                    , Hasql.MissingTypesSessionError mempty
                    , Hasql.StatementSessionError 0 0 "statement" [] True (Hasql.UnexpectedRowCountStatementError 1 1 0)
                    ]
            forM_ (serverErrors <> otherErrors) \sessionError ->
                payrollWorkbookConfigurationPersistenceError "Pay run" (HasqlSessionError sessionError)
                    `shouldBe` Nothing
  where
    sessionErrors serverError =
        [ Hasql.StatementSessionError 0 0 "statement" [] True (Hasql.ServerStatementError serverError)
        , Hasql.ScriptSessionError "script" serverError
        ]
