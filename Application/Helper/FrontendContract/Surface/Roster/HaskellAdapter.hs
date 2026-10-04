{-# LANGUAGE TypeFamilies #-}

-- | Typed generator ownership for Roster Surface adapters.
module Application.Helper.FrontendContract.Surface.Roster.HaskellAdapter
    ( RosterAdapterFamily
    ) where

import Application.Helper.FrontendContract.Surface.HaskellAdapter.Association
import qualified Application.Helper.FrontendContract.Surface.Roster as Roster

data RosterAdapterFamily

instance SurfaceAdapterFamily RosterAdapterFamily where
    type AdapterFamilySurface RosterAdapterFamily = Roster.RosterSurface
