module Web.View.RosterTemplates.DraftOccupied where

import Web.View.Prelude

data DraftOccupiedView = DraftOccupiedView

instance View DraftOccupiedView where
    html DraftOccupiedView = renderAppPage AppPageConfig
        { appPageTitle = "Roster templates"
        , appPageDescription = Nothing
        , appPageActions = mempty
        , appPageHelpTopic = Just (PageHelpTopicId "roster")
        , appPageWidthClass = ""
        , appPageBody = [hsx|<p>Private template drafts are no longer used.</p>|]
        }
