{-# LANGUAGE TypeApplications #-}

-- | Curated Haskell rendering boundary for roster fullscreen and column-edit
-- controls. Surface declarations own every role, state attribute, and closed
-- state value; browser code retains only mechanical focus, keyboard, icon, and
-- delayed-blur behavior.
module Application.Helper.FrontendContract.Surface.Roster.Chrome
    ( RosterFullscreenState (..)
    , RosterColumnEditingState (..)
    , rosterFullscreenRootAttrs
    , rosterFullscreenToggleAttrs
    , rosterFullscreenLabelAttrs
    , rosterColumnEditorAttrs
    , rosterColumnEditStartAttrs
    , rosterColumnEditDoneAttrs
    ) where

import Application.Helper.FrontendContract.Surface.Attributes (roleAttrs)
import Application.Helper.FrontendContract.Surface.ContractIR (BrowserClosedStateIR (..))
import qualified Application.Helper.FrontendContract.Surface.Roster as Roster
import Application.Helper.FrontendContract.Surface.SemanticIR (BrowserAttributeIR (..))
import Application.Helper.FrontendContract.Surface.Values
import IHP.Prelude

data RosterFullscreenState
    = RosterFullscreenCollapsed
    | RosterFullscreenExpanded
    deriving (Eq, Show)

data RosterColumnEditingState
    = RosterColumnEditingInactive
    | RosterColumnEditingActive
    deriving (Eq, Show)

rosterFullscreenRootAttrs :: RosterFullscreenState -> [(Text, Text)]
rosterFullscreenRootAttrs state =
    roleAttrs (surfaceBrowserRoleValue @Roster.RosterSurface @Roster.FullscreenRootRole)
        <> closedStateAttrs
            (surfaceBrowserClosedStateValue @Roster.RosterSurface @Roster.FullscreenState)
            (fullscreenStateValue state)

rosterFullscreenToggleAttrs :: [(Text, Text)]
rosterFullscreenToggleAttrs =
    roleAttrs (surfaceBrowserRoleValue @Roster.RosterSurface @Roster.FullscreenToggleRole)

rosterFullscreenLabelAttrs :: [(Text, Text)]
rosterFullscreenLabelAttrs =
    roleAttrs (surfaceBrowserRoleValue @Roster.RosterSurface @Roster.FullscreenLabelRole)

rosterColumnEditorAttrs :: RosterColumnEditingState -> [(Text, Text)]
rosterColumnEditorAttrs state =
    roleAttrs (surfaceBrowserRoleValue @Roster.RosterSurface @Roster.ColumnEditorRole)
        <> closedStateAttrs
            (surfaceBrowserClosedStateValue @Roster.RosterSurface @Roster.ColumnEditingState)
            (columnEditingStateValue state)

rosterColumnEditStartAttrs :: [(Text, Text)]
rosterColumnEditStartAttrs =
    roleAttrs (surfaceBrowserRoleValue @Roster.RosterSurface @Roster.ColumnEditStartRole)

rosterColumnEditDoneAttrs :: [(Text, Text)]
rosterColumnEditDoneAttrs =
    roleAttrs (surfaceBrowserRoleValue @Roster.RosterSurface @Roster.ColumnEditDoneRole)

fullscreenStateValue :: RosterFullscreenState -> Text
fullscreenStateValue = \case
    RosterFullscreenCollapsed ->
        surfaceBrowserClosedStateLiteral @Roster.RosterSurface @Roster.FullscreenState @Roster.Collapsed
    RosterFullscreenExpanded ->
        surfaceBrowserClosedStateLiteral @Roster.RosterSurface @Roster.FullscreenState @Roster.Expanded

columnEditingStateValue :: RosterColumnEditingState -> Text
columnEditingStateValue = \case
    RosterColumnEditingInactive ->
        surfaceBrowserClosedStateLiteral @Roster.RosterSurface @Roster.ColumnEditingState @Roster.Inactive
    RosterColumnEditingActive ->
        surfaceBrowserClosedStateLiteral @Roster.RosterSurface @Roster.ColumnEditingState @Roster.Active

closedStateAttrs :: BrowserClosedStateIR -> Text -> [(Text, Text)]
closedStateAttrs state value =
    [(state.browserClosedStateAttribute.browserAttributeDomAttribute, value)]
