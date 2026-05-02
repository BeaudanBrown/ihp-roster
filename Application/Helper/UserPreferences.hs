{-# LANGUAGE TypeApplications #-}

module Application.Helper.UserPreferences
    ( defaultRosterLayoutMode
    , fetchCurrentRosterLayoutMode
    , parseRosterLayoutMode
    , rosterLayoutModeLabel
    , rosterLayoutModeValue
    , rosterLayoutModes
    , upsertCurrentUserRosterLayoutMode
    ) where

import Application.Helper.Controller (enumFromText, unsafeEnumFromText)
import Generated.Types
import IHP.ControllerPrelude

defaultRosterLayoutMode :: RosterLayoutModeEnum
defaultRosterLayoutMode = unsafeEnumFromText @RosterLayoutModeEnum "day_rows"

rosterLayoutModes :: [RosterLayoutModeEnum]
rosterLayoutModes = allEnumValues @RosterLayoutModeEnum

parseRosterLayoutMode :: Text -> Maybe RosterLayoutModeEnum
parseRosterLayoutMode = enumFromText @RosterLayoutModeEnum

rosterLayoutModeValue :: RosterLayoutModeEnum -> Text
rosterLayoutModeValue = inputValue

rosterLayoutModeLabel :: RosterLayoutModeEnum -> Text
rosterLayoutModeLabel mode =
    case rosterLayoutModeValue mode of
        "day_columns" -> "Day columns"
        _             -> "Day rows"

fetchCurrentRosterLayoutMode :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO RosterLayoutModeEnum
fetchCurrentRosterLayoutMode = do
    maybePreferences <-
        query @UserPreference
            |> filterWhere (#userId, unpackId currentUser.id)
            |> fetchOneOrNothing
    pure (maybe defaultRosterLayoutMode (.rosterLayoutMode) maybePreferences)

upsertCurrentUserRosterLayoutMode ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    RosterLayoutModeEnum ->
    IO UserPreference
upsertCurrentUserRosterLayoutMode layoutMode = do
    maybePreferences <-
        query @UserPreference
            |> filterWhere (#userId, unpackId currentUser.id)
            |> fetchOneOrNothing
    case maybePreferences of
        Just preferences ->
            preferences
                |> set #rosterLayoutMode layoutMode
                |> updateRecord
        Nothing ->
            newRecord @UserPreference
                |> set #userId (unpackId currentUser.id)
                |> set #rosterLayoutMode layoutMode
                |> createRecord
