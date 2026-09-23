module Application.Helper.LiveUpdate.RequestState
    ( liveUpdateRequestStateMiddleware
    , recordRequestLivePublication
    , requestLivePublicationVersion
    ) where

import Application.Helper.FrontendContract.Surface.Resource (SurfaceResourceValue)
import Data.IORef
import qualified Data.Set as Set
import qualified Data.Vault.Lazy as Vault
import IHP.ControllerSupport (ControllerContext)
import IHP.Prelude
import IHP.RequestVault.Helper (insertNewIORefVaultMiddleware,
                                lookupRequestVault)
import Network.Wai (Middleware)
import System.IO.Unsafe (unsafePerformIO)

data RequestLivePublication = RequestLivePublication
    { resources :: !(Set.Set SurfaceResourceValue)
    , version   :: !Int
    }

requestLivePublicationsKey :: Vault.Key (IORef [RequestLivePublication])
requestLivePublicationsKey = unsafePerformIO Vault.newKey
{-# NOINLINE requestLivePublicationsKey #-}

liveUpdateRequestStateMiddleware :: Middleware
liveUpdateRequestStateMiddleware =
    insertNewIORefVaultMiddleware requestLivePublicationsKey []

recordRequestLivePublication :: (?context :: ControllerContext) => Set.Set SurfaceResourceValue -> Int -> IO ()
recordRequestLivePublication resources version =
    atomicModifyIORef' (lookupRequestVault requestLivePublicationsKey ?context) \publications ->
        (RequestLivePublication { resources, version } : publications, ())

requestLivePublicationVersion :: (?context :: ControllerContext) => Set.Set SurfaceResourceValue -> IO (Maybe Int)
requestLivePublicationVersion resources = do
    publications <- readIORef (lookupRequestVault requestLivePublicationsKey ?context)
    pure $ maximumMaybe [publication.version | publication <- publications, publication.resources == resources]
  where
    maximumMaybe []     = Nothing
    maximumMaybe values = Just (maximum values)
