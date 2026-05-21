-- | Central shift type colour-key policy for admin mutations and roster badges.
-- Active shift types in a venue get unique non-default palette keys while any
-- excess active types and all inactive types use the reusable default key.
module Application.Helper.ShiftTypeColours
    ( defaultShiftTypeColourKey
    , shiftTypeColourPaletteKeys
    , assignShiftTypeColourKey
    , normalizeShiftTypeColourKey
    , shiftTypeColourKeyIsAvailable
    ) where

import qualified Data.List as List
import Web.Controller.Prelude

defaultShiftTypeColourKey :: Text
defaultShiftTypeColourKey = "default"

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
assignShiftTypeColourKey venueId maybeCurrentShiftTypeId willBeActive currentColourKey
    | not willBeActive = pure defaultShiftTypeColourKey
    | otherwise = do
        usedColourKeys <- activeNonDefaultShiftTypeColourKeys venueId maybeCurrentShiftTypeId
        pure
            if currentColourKey /= defaultShiftTypeColourKey && currentColourKey `notElem` usedColourKeys
                then currentColourKey
                else fromMaybe defaultShiftTypeColourKey (List.find (`notElem` usedColourKeys) shiftTypeColourPaletteKeys)

normalizeShiftTypeColourKey :: Text -> Text
normalizeShiftTypeColourKey colourKey
    | colourKey `elem` (defaultShiftTypeColourKey : shiftTypeColourPaletteKeys) = colourKey
    | otherwise = defaultShiftTypeColourKey

shiftTypeColourKeyIsAvailable ::
    (?modelContext :: ModelContext) =>
    Id Venue ->
    Maybe (Id ShiftType) ->
    Bool ->
    Text ->
    IO Bool
shiftTypeColourKeyIsAvailable venueId maybeCurrentShiftTypeId willBeActive colourKey
    | not willBeActive = pure True
    | colourKey == defaultShiftTypeColourKey = pure True
    | otherwise = do
        usedColourKeys <- activeNonDefaultShiftTypeColourKeys venueId maybeCurrentShiftTypeId
        pure (colourKey `notElem` usedColourKeys)

activeNonDefaultShiftTypeColourKeys ::
    (?modelContext :: ModelContext) =>
    Id Venue ->
    Maybe (Id ShiftType) ->
    IO [Text]
activeNonDefaultShiftTypeColourKeys venueId maybeCurrentShiftTypeId = do
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
            |> filter (/= defaultShiftTypeColourKey)
        )
