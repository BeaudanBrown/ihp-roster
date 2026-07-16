{-# LANGUAGE TypeFamilies #-}

-- | Typed generator ownership for Roster Surface adapters.
module Application.Helper.FrontendContract.Surface.Roster.HaskellAdapter
    ( RosterAdapterFamily
    , RosterDayTimelineAdapterFamily
    ) where

import Application.Helper.FrontendContract.Surface.HaskellAdapter.Family
import qualified Application.Helper.FrontendContract.Surface.Roster as Roster

data RosterAdapterFamily
data RosterDayTimelineAdapterFamily

instance SurfaceAdapterFamily RosterAdapterFamily where
    type AdapterFamilySurface RosterAdapterFamily = Roster.RosterSurface

instance SurfaceAdapterFamily RosterDayTimelineAdapterFamily where
    type AdapterFamilySurface RosterDayTimelineAdapterFamily = Roster.RosterDayTimelineSurface
