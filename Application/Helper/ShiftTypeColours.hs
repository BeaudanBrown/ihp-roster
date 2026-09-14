{-# LANGUAGE TypeApplications #-}

-- | Shift type colour defaults, palette values and roster badge CSS projection.
-- Persistence/request authority is the generated PostgreSQL enum; this module
-- owns its CSS-facing projection (no-colour stays empty, palette keys use '-').
module Application.Helper.ShiftTypeColours
    ( ShiftTypeColourKeyEnum (..)
    , blankShiftTypeColourKey
    , shiftTypeColourPaletteKeys
    , shiftTypeColourKeyCssValue
    ) where

import qualified Data.Text as Text
import Generated.Types (ShiftTypeColourKeyEnum (..))
import IHP.InputValue (InputValue (..))
import IHP.Prelude

blankShiftTypeColourKey :: ShiftTypeColourKeyEnum
blankShiftTypeColourKey = NoColour

shiftTypeColourPaletteKeys :: [ShiftTypeColourKeyEnum]
shiftTypeColourPaletteKeys = drop 1 (allEnumValues @ShiftTypeColourKeyEnum)

shiftTypeColourKeyCssValue :: ShiftTypeColourKeyEnum -> Text
shiftTypeColourKeyCssValue NoColour = ""
shiftTypeColourKeyCssValue colourKey = Text.replace "_" "-" (inputValue colourKey)
