{-# LANGUAGE TypeApplications #-}

module Application.Helper.View.FilterSelection
    ( FilterSelectionOption (..)
    , renderFilterSelectionSection
    ) where

import qualified Application.Helper.FrontendContract.FilterSelection as Contract
import Application.Helper.FrontendContract.Values (domAttrValue)
import Application.Helper.View.Chrome (AppAccordionItemConfig (..), renderAppAccordionItem)
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
    <div {...sectionAttrs}>{renderAppAccordionItem accordion}</div>
|]
  where
    accordion = AppAccordionItemConfig
        { appAccordionItemId = "filter-" <> fieldName
        , appAccordionItemParentId = ""
        , appAccordionItemTitle = label
        , appAccordionItemIsOpen = initiallyOpen
        , appAccordionItemClass = "app-accordion-sticky"
        , appAccordionItemBodyClass = "p-0"
        , appAccordionItemButtonContent = [hsx|
            <span class="me-2">{label}</span>
            <span class="small app-muted" hidden={not (null selected)} {...allAttrs}>All</span>
            <span class="small app-muted" hidden={null selected} {...selectedAttrs}><span {...countAttrs}>{length selected}</span> selected</span>
        |]
        , appAccordionItemBody = [hsx|
            <div class="p-2"><button type="button" class="btn btn-sm btn-outline-secondary" {...clearAttrs}>Clear</button></div>
            <div class="app-filter-section-options">
                {forEach (sortOn (Text.toCaseFold . (.optionLabel)) options) renderOption}
            </div>
        |]
        }
    sectionAttrs, allAttrs, selectedAttrs, countAttrs, clearAttrs, itemAttrs :: [(Text, Text)]
    sectionAttrs = [(domAttrValue @Contract.FilterSelectionSection, "true")]
    allAttrs = [(domAttrValue @Contract.FilterSelectionAll, "true")]
    selectedAttrs = [(domAttrValue @Contract.FilterSelectionSelected, "true")]
    countAttrs = [(domAttrValue @Contract.FilterSelectionCount, "true")]
    clearAttrs = [(domAttrValue @Contract.FilterSelectionClear, "true")]
    itemAttrs = [(domAttrValue @Contract.FilterSelectionItem, "true")]
    historicalLabel historical = when historical [hsx|<small class="app-muted">(Archived/inactive)</small>|]
    renderOption option = [hsx|
        <label class="app-filter-option app-side-panel-entry app-side-panel-cell">
            <input type="checkbox" class="form-check-input" name={fieldName} value={option.optionValue} checked={option.optionValue `elem` selected} {...itemAttrs} />
            <span class="app-side-panel-name-primary">{option.optionLabel} {historicalLabel option.optionHistorical}</span>
        </label>
    |]
