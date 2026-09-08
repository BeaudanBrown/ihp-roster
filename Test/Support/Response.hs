{-# LANGUAGE ImplicitParams #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeApplications #-}

module Test.Support.Response (captureStoppedResponses) where

import qualified Control.Exception as Exception
import Data.IORef (modifyIORef', newIORef, readIORef)
import qualified Data.Vault.Lazy as Vault
import IHP.Controller.Response (EarlyReturnException, responseHeadersVaultKey)
import IHP.ControllerSupport (Respond)
import IHP.Prelude
import qualified Network.Wai as Wai
import Network.Wai.Internal (ResponseReceived (..))

-- Capture real callback responses and the separate early-exit token. Never
-- recover a response from an exception or supply a fallback after a send.
captureStoppedResponses :: Wai.Request -> ((?request :: Wai.Request, ?respond :: Respond) => IO a) -> IO (Either EarlyReturnException a, [Wai.Response])
captureStoppedResponses request action = do
    responses <- newIORef []
    headers <- newIORef []
    let ?request = request { Wai.vault = Vault.insert responseHeadersVaultKey headers request.vault }
    let ?respond = \response -> do
            modifyIORef' responses (response :)
            pure ResponseReceived
    result <- Exception.try @EarlyReturnException action
    captured <- reverse <$> readIORef responses
    pure (result, captured)
