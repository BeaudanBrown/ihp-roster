{-# LANGUAGE TypeApplications #-}

-- | Curated Haskell rendering boundary for roster column-edit controls.
-- Surface declarations own every role, state attribute, and closed state value;
-- browser code retains only mechanical focus and delayed-blur behavior.
module Application.Helper.FrontendContract.Surface.Roster.Chrome
    ( RosterColumnEditingState (..)
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

data RosterColumnEditingState
    = RosterColumnEditingInactive
    | RosterColumnEditingActive
    deriving (Eq, Show)

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

columnEditingStateValue :: RosterColumnEditingState -> Text
columnEditingStateValue = \case
    RosterColumnEditingInactive ->
        surfaceBrowserClosedStateLiteral @Roster.RosterSurface @Roster.ColumnEditingState @Roster.Inactive
    RosterColumnEditingActive ->
        surfaceBrowserClosedStateLiteral @Roster.RosterSurface @Roster.ColumnEditingState @Roster.Active

closedStateAttrs :: BrowserClosedStateIR -> Text -> [(Text, Text)]
closedStateAttrs state value =
    [(state.browserClosedStateAttribute.browserAttributeDomAttribute, value)]
