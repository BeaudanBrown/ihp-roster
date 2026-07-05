{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.Roster
    ( RosterGlobalContract
    , RosterGlobal
    , RosterStaffSortKey
    , Name
    , Role
    , Shifts
    ) where

import Application.Helper.FrontendContract.DSL

data RosterGlobal

data RosterStaffSortKey
data Name
data Role
data Shifts

-- Feature-specific declarations move to the owning Roster Surface later. This
-- temporary Global keeps the simple current browser vocabulary DSL-owned while
-- the Surface root migration is in progress.
type RosterGlobalContract =
    Global RosterGlobal
        '[ GlobalSchema (Enum RosterStaffSortKey '[Name, Role, Shifts])
         ]
