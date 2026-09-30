{-# LANGUAGE DataKinds #-}

module Application.Helper.FrontendContract.FilterSelection where

import Application.Helper.FrontendContract.DSL

-- Deferred native checkbox state, independent of feature identities or transport.
data FilterSelection
data FilterSelectionSection
data FilterSelectionItem
data FilterSelectionClear
data FilterSelectionAll
data FilterSelectionSelected
data FilterSelectionCount

type FilterSelectionContract =
    Global FilterSelection
        '[ DomAttr FilterSelectionSection
         , DomAttr FilterSelectionItem
         , DomAttr FilterSelectionClear
         , DomAttr FilterSelectionAll
         , DomAttr FilterSelectionSelected
         , DomAttr FilterSelectionCount
         ]
