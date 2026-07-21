-- | Small rendering helpers for reflected Surface browser attributes.
module Application.Helper.FrontendContract.Surface.Attributes
    ( roleAttrs
    ) where

import Application.Helper.FrontendContract.Surface.SemanticIR (BrowserAttributeIR (..))
import IHP.Prelude

roleAttrs :: BrowserAttributeIR -> [(Text, Text)]
roleAttrs role = [(role.browserAttributeDomAttribute, "true")]
