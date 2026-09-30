{-# LANGUAGE TypeApplications #-}

module Application.Helper.View.FilterSelection
    ( FilterSelectionOption (..)
    , renderFilterSelectionSection
    ) where

import qualified Application.Helper.FrontendContract.FilterSelection as Contract
import Application.Helper.FrontendContract.Values (domAttrValue)
import qualified Data.Text as Text
import IHP.ViewPrelude

data FilterSelectionOption = FilterSelectionOption
    { optionValue      :: !Text
    , optionLabel      :: !Text
    , optionHistorical :: !Bool
    }

-- The form owns transport; this helper owns only a deferred selection section.
renderFilterSelectionSection :: Text -> Text -> Bool -> [Text] -> [FilterSelectionOption] -> Html
renderFilterSelectionSection label fieldName initiallyOpen selected options = [hsx|
    <details class="app-filter-section" open={initiallyOpen} {...sectionAttrs}>
        <summary class="app-filter-section-header">
            {label}
            <span class="small app-muted" hidden={not (null selected)} {...allAttrs}>All</span>
            <span class="small app-muted" hidden={null selected} {...selectedAttrs}><span {...countAttrs}>{length selected}</span> selected</span>
        </summary>
        <div class="app-filter-section-options">
            <button type="button" class="btn btn-sm btn-outline-secondary" {...clearAttrs}>Clear</button>
            {forEach (sortOn (Text.toCaseFold . (.optionLabel)) options) renderOption}
        </div>
    </details>
|]
  where
    sectionAttrs, allAttrs, selectedAttrs, countAttrs, clearAttrs, itemAttrs :: [(Text, Text)]
    sectionAttrs = [(domAttrValue @Contract.FilterSelectionSection, "true")]
    allAttrs = [(domAttrValue @Contract.FilterSelectionAll, "true")]
    selectedAttrs = [(domAttrValue @Contract.FilterSelectionSelected, "true")]
    countAttrs = [(domAttrValue @Contract.FilterSelectionCount, "true")]
    clearAttrs = [(domAttrValue @Contract.FilterSelectionClear, "true")]
    itemAttrs = [(domAttrValue @Contract.FilterSelectionItem, "true")]
    historicalLabel historical = when historical [hsx|<small class="app-muted">(Archived/inactive)</small>|]
    renderOption option = [hsx|
        <label class="app-filter-option">
            <input type="checkbox" class="form-check-input" name={fieldName} value={option.optionValue} checked={option.optionValue `elem` selected} {...itemAttrs} />
            <span>{option.optionLabel} {historicalLabel option.optionHistorical}</span>
        </label>
    |]
