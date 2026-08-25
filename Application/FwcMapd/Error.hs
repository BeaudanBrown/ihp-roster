module Application.FwcMapd.Error
    ( MapdSyncError (..)
    , mapdSyncErrorSafeMessage
    ) where

import qualified Control.Exception as Exception
import IHP.Prelude

data MapdSyncError
    = MapdProviderUnavailable
    | MapdResponseMalformed
    | MapdSnapshotInvalid
    deriving (Eq, Show)

instance Exception.Exception MapdSyncError

mapdSyncErrorSafeMessage :: MapdSyncError -> Text
mapdSyncErrorSafeMessage = \case
    MapdProviderUnavailable -> "FWC MAPD provider request could not be completed."
    MapdResponseMalformed -> "FWC MAPD provider response could not be read."
    MapdSnapshotInvalid -> "FWC MAPD candidate failed validation."
