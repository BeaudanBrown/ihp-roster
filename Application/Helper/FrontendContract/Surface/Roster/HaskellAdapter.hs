{-# LANGUAGE TypeFamilies #-}

-- | Typed generator ownership for Roster Surface adapters.
module Application.Helper.FrontendContract.Surface.Roster.HaskellAdapter
    ( RosterAdapterFamily
    , RosterPersonalAdapterFamily
    , RosterDayTimelineAdapterFamily
    ) where

import Application.Helper.FrontendContract.Surface.HaskellAdapter.Association
import qualified Application.Helper.FrontendContract.Surface.Roster as Roster

data RosterAdapterFamily
data RosterPersonalAdapterFamily
instance SurfaceAdapterFamily RosterPersonalAdapterFamily where
    type AdapterFamilySurface RosterPersonalAdapterFamily = Roster.RosterPersonalSurface

data RosterDayTimelineAdapterFamily

instance SurfaceAdapterFamily RosterAdapterFamily where
    type AdapterFamilySurface RosterAdapterFamily = Roster.RosterSurface

instance SurfaceAdapterFamily RosterDayTimelineAdapterFamily where
    type AdapterFamilySurface RosterDayTimelineAdapterFamily = Roster.RosterDayTimelineSurface
