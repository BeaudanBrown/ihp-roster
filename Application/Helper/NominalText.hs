{-# LANGUAGE AllowAmbiguousTypes #-}

-- | Domain-owned nominal values whose external protocol representation is text.
module Application.Helper.NominalText
    ( NominalText (..)
    ) where

import IHP.Prelude

class NominalText value where
    renderNominalText :: value -> Text
    parseNominalText :: Text -> Either Text value
