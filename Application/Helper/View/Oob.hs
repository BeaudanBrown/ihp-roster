module Application.Helper.View.Oob
    ( OobSwapAttr
    , innerHtmlOobSwap
    , noOobSwap
    ) where

import IHP.ViewPrelude

type OobSwapAttr = Maybe Text

noOobSwap :: OobSwapAttr
noOobSwap = Nothing

innerHtmlOobSwap :: OobSwapAttr
innerHtmlOobSwap = Just "innerHTML"
