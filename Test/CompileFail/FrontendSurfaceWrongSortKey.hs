{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceWrongSortKey where

import Application.Helper.FrontendContract.Surface.CompleteSetSort
import qualified Application.Helper.FrontendContract.Surface.Roster as Roster
import Data.Text (Text)


badSortKey :: [(Text, Text)]
badSortKey =
    surfaceCompleteSetSortControlAttrs
        @Roster.RosterSurface
        @Roster.RosterStaffPanelSort
        @Roster.StaffTabKey
