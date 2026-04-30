module Application.Helper.View.Oob
    ( OobSwapAttr
    , innerHtmlOobSwap
    , noOobSwap
    , outerHtmlOobSwap
    ) where

import IHP.ViewPrelude

type OobSwapAttr = Maybe Text

noOobSwap :: OobSwapAttr
noOobSwap = Nothing

outerHtmlOobSwap :: OobSwapAttr
outerHtmlOobSwap = Just "outerHTML"

innerHtmlOobSwap :: OobSwapAttr
innerHtmlOobSwap = Just "innerHTML"
