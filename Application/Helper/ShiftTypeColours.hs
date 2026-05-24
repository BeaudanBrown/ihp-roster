-- | Central shift type colour-key policy for admin mutations and roster badges.
-- Shift type colours are optional reusable visual labels. Blank means no
-- highlight; palette keys opt a shift type into roster colour accents.
module Application.Helper.ShiftTypeColours
    ( blankShiftTypeColourKey
    , shiftTypeColourPaletteKeys
    , assignShiftTypeColourKey
    , normalizeShiftTypeColourKey
    ) where

import qualified Data.Text as Text
import Web.Controller.Prelude

blankShiftTypeColourKey :: Text
blankShiftTypeColourKey = ""

shiftTypeColourPaletteKeys :: [Text]
shiftTypeColourPaletteKeys =
    [ "palette-1"
    , "palette-2"
    , "palette-3"
    , "palette-4"
    , "palette-5"
    , "palette-6"
    , "palette-7"
    , "palette-8"
    , "palette-9"
    , "palette-10"
    ]

assignShiftTypeColourKey ::
    (?modelContext :: ModelContext) =>
    Id Venue ->
    Maybe (Id ShiftType) ->
    Bool ->
    Text ->
    IO Text
assignShiftTypeColourKey _venueId _maybeCurrentShiftTypeId _willBeActive currentColourKey =
    pure (normalizeShiftTypeColourKey currentColourKey)

normalizeShiftTypeColourKey :: Text -> Text
normalizeShiftTypeColourKey colourKey
    | colourKey `elem` shiftTypeColourPaletteKeys = colourKey
    | Text.strip colourKey == "default" = blankShiftTypeColourKey
    | Text.null (Text.strip colourKey) = blankShiftTypeColourKey
    | otherwise = blankShiftTypeColourKey
