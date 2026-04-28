module Web.View.Admin.Common where

import Data.Time.Format (defaultTimeLocale, formatTime)
import Web.View.Prelude

renderConfigSection :: Text -> Text -> Text -> Html -> Html -> Html -> Html
renderConfigSection anchorId title description summary createForm rows = [hsx|
    <div class="app-accordion-section" id={anchorId}>
        <header class="app-accordion-section-header">
            <h2 class="app-panel-title h5">{title}</h2>
            <p class="app-panel-description">{description}</p>
        </header>
        <div class="app-accordion-section-body">
            {summary}
            {createForm}
            <div class="mt-3">
                {rows}
            </div>
        </div>
    </div>
|]

formatTimestamp :: UTCTime -> Text
formatTimestamp = cs . formatTime defaultTimeLocale "%Y-%m-%d %H:%M UTC"
