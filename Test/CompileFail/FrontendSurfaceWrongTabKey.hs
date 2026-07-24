{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceWrongTabKey where

import qualified Application.Helper.FrontendContract.Surface.Roster as Roster
import Application.Helper.FrontendContract.Surface.TabSet
import Data.Text (Text)


badTabKey :: [(Text, Text)]
badTabKey =
    surfaceTabSetAttrs
        @Roster.RosterSurface
        @Roster.RosterStaffPanelTabs
        @Roster.NameSortKey
