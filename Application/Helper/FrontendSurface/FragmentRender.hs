module Application.Helper.FrontendSurface.FragmentRender
    ( FragmentRenderMode (..)
    ) where

import IHP.Prelude

data FragmentRenderMode
    = FragmentPlain
    | FragmentOob !(Maybe Text)
    deriving (Eq, Show)
