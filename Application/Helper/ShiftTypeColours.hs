module Application.Helper.ShiftTypeColours
    ( defaultShiftTypeColourKey
    , shiftTypeColourPaletteKeys
    , assignShiftTypeColourKey
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
        activeShiftTypes <-
            query @ShiftType
                |> filterWhere (#venueId, unpackId venueId)
                |> filterWhere (#archivedAt, Nothing)
                |> filterWhere (#isActive, True)
                |> fetch
        let usedColourKeys =
                activeShiftTypes
                    |> filter (\shiftType -> Just shiftType.id /= maybeCurrentShiftTypeId)
                    |> map (.colourKey)
                    |> filter (/= defaultShiftTypeColourKey)
        pure
            if currentColourKey /= defaultShiftTypeColourKey && currentColourKey `notElem` usedColourKeys
                then currentColourKey
                else fromMaybe defaultShiftTypeColourKey (List.find (`notElem` usedColourKeys) shiftTypeColourPaletteKeys)
