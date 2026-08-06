{-# LANGUAGE TypeApplications #-}

-- | Central shift type colour-key policy for admin mutations and roster badges.
-- Persistence/request authority is the generated PostgreSQL enum; this module
-- owns its CSS-facing projection (no-colour stays empty, palette keys use '-').
module Application.Helper.ShiftTypeColours
    ( ShiftTypeColourKeyEnum (..)
    , blankShiftTypeColourKey
    , shiftTypeColourPaletteKeys
    , assignShiftTypeColourKey
    , normalizeShiftTypeColourKey
    , shiftTypeColourKeyCssValue
    ) where

import qualified Data.Text as Text
import Generated.Types (ShiftTypeColourKeyEnum (..))
import Web.Controller.Prelude

blankShiftTypeColourKey :: ShiftTypeColourKeyEnum
blankShiftTypeColourKey = NoColour

shiftTypeColourPaletteKeys :: [ShiftTypeColourKeyEnum]
shiftTypeColourPaletteKeys = drop 1 (allEnumValues @ShiftTypeColourKeyEnum)

shiftTypeColourKeyCssValue :: ShiftTypeColourKeyEnum -> Text
shiftTypeColourKeyCssValue NoColour = ""
shiftTypeColourKeyCssValue colourKey = Text.replace "_" "-" (inputValue colourKey)

assignShiftTypeColourKey ::
    (?modelContext :: ModelContext) =>
    Id Venue ->
    Maybe (Id ShiftType) ->
    Bool ->
    ShiftTypeColourKeyEnum ->
    IO ShiftTypeColourKeyEnum
assignShiftTypeColourKey _venueId _maybeCurrentShiftTypeId _willBeActive =
    pure . normalizeShiftTypeColourKey

normalizeShiftTypeColourKey :: ShiftTypeColourKeyEnum -> ShiftTypeColourKeyEnum
normalizeShiftTypeColourKey colourKey = colourKey
