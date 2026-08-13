module Web.View.RosterTemplates.Designer where

import Web.View.Prelude

data DesignerView = DesignerView

instance View DesignerView where
    html DesignerView = renderAppPage AppPageConfig
        { appPageTitle = "Roster templates"
        , appPageDescription = Nothing
        , appPageActions = mempty
        , appPageHelpTopic = Just (PageHelpTopicId "roster")
        , appPageWidthClass = ""
        , appPageBody = [hsx|<p>The standalone template designer is no longer available.</p>|]
        }
