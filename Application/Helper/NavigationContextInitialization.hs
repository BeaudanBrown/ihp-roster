{-# OPTIONS_GHC -fno-cse -fno-full-laziness #-}

module Application.Helper.NavigationContextInitialization
    ( deferNavigationContextInitialization
    , ensureNavigationContextInitialized
    , navigationContextInitializationMiddleware
    ) where

import Control.Concurrent.MVar (MVar, newEmptyMVar, putMVar, readMVar)
import qualified Control.Exception as Exception
import qualified Data.Vault.Lazy as Vault
import IHP.ControllerPrelude
import IHP.RequestVault.Helper (insertNewIORefVaultMiddleware)
import Network.Wai (Middleware, vault)
import System.IO.Unsafe (unsafePerformIO)

data NavigationInitialization
    = NavigationInitializationReady
    | NavigationInitializationDeferred (IO ())
    | NavigationInitializationRunning (MVar (Either SomeException ()))

data InitializationDecision
    = InitializationNotRequired
    | RunInitialization (IO ()) (MVar (Either SomeException ()))
    | WaitForInitialization (MVar (Either SomeException ()))

navigationInitializationKey :: Vault.Key (IORef NavigationInitialization)
navigationInitializationKey = unsafePerformIO Vault.newKey
{-# NOINLINE navigationInitializationKey #-}

navigationContextInitializationMiddleware :: Middleware
navigationContextInitializationMiddleware =
    insertNewIORefVaultMiddleware navigationInitializationKey NavigationInitializationReady

deferNavigationContextInitialization :: Request -> IO () -> IO ()
deferNavigationContextInitialization request initialize =
    forM_ (Vault.lookup navigationInitializationKey (vault request)) \stateRef ->
        atomicWriteIORef stateRef (NavigationInitializationDeferred initialize)

ensureNavigationContextInitialized :: Request -> IO ()
ensureNavigationContextInitialized request =
    forM_ (Vault.lookup navigationInitializationKey (vault request)) \stateRef ->
        Exception.mask \restore -> do
            completion <- newEmptyMVar
            decision <- atomicModifyIORef' stateRef \case
                NavigationInitializationReady ->
                    (NavigationInitializationReady, InitializationNotRequired)
                NavigationInitializationDeferred initialize ->
                    (NavigationInitializationRunning completion, RunInitialization initialize completion)
                running@(NavigationInitializationRunning existingCompletion) ->
                    (running, WaitForInitialization existingCompletion)
            case decision of
                InitializationNotRequired -> pure ()
                RunInitialization initialize initialized -> do
                    result <- Exception.try (restore initialize)
                    putMVar initialized result
                    case result of
                        Right () -> atomicWriteIORef stateRef NavigationInitializationReady
                        Left exception -> Exception.throwIO exception
                WaitForInitialization initialized ->
                    restore (readMVar initialized) >>= either Exception.throwIO pure
