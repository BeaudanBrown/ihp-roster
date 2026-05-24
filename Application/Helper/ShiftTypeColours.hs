-- | Central shift type colour-key policy for admin mutations and roster badges.
-- Shift type colours are reusable visual labels. New shift types prefer the
-- first unused palette colour, then wrap to the first palette colour.
module Application.Helper.ShiftTypeColours
    ( shiftTypeColourPaletteKeys
    , assignShiftTypeColourKey
    , normalizeShiftTypeColourKey
    ) where

import qualified Data.List as List
import Web.Controller.Prelude

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
assignShiftTypeColourKey venueId maybeCurrentShiftTypeId _willBeActive currentColourKey
    | currentColourKey `elem` shiftTypeColourPaletteKeys = pure currentColourKey
    | otherwise = suggestShiftTypeColourKey venueId maybeCurrentShiftTypeId

normalizeShiftTypeColourKey :: Text -> Text
normalizeShiftTypeColourKey colourKey
    | colourKey `elem` shiftTypeColourPaletteKeys = colourKey
    | otherwise = firstShiftTypeColourKey

suggestShiftTypeColourKey ::
    (?modelContext :: ModelContext) =>
    Id Venue ->
    Maybe (Id ShiftType) ->
    IO Text
suggestShiftTypeColourKey venueId maybeCurrentShiftTypeId = do
    usedColourKeys <- activeShiftTypeColourKeys venueId maybeCurrentShiftTypeId
    pure (fromMaybe firstShiftTypeColourKey (List.find (`notElem` usedColourKeys) shiftTypeColourPaletteKeys))

activeShiftTypeColourKeys ::
    (?modelContext :: ModelContext) =>
    Id Venue ->
    Maybe (Id ShiftType) ->
    IO [Text]
activeShiftTypeColourKeys venueId maybeCurrentShiftTypeId = do
    activeShiftTypes <-
        query @ShiftType
            |> filterWhere (#venueId, unpackId venueId)
            |> filterWhere (#archivedAt, Nothing)
            |> filterWhere (#isActive, True)
            |> fetch
    pure
        ( activeShiftTypes
            |> filter (\shiftType -> Just shiftType.id /= maybeCurrentShiftTypeId)
            |> map (.colourKey)
            |> filter (`elem` shiftTypeColourPaletteKeys)
        )

firstShiftTypeColourKey :: Text
firstShiftTypeColourKey =
    fromMaybe "palette-1" (listToMaybe shiftTypeColourPaletteKeys)
