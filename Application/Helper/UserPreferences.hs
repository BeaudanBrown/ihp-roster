{-# LANGUAGE TypeApplications #-}

module Application.Helper.UserPreferences
    ( UserRosterPreferences (..)
    , defaultRosterLayoutMode
    , fetchCurrentRosterLayoutMode
    , fetchCurrentUserRosterPreferences
    , parseRosterLayoutMode
    , rosterLayoutModeLabel
    , rosterLayoutModeValue
    , rosterLayoutModes
    , upsertCurrentUserRosterLayoutMode
    ) where

import Application.Helper.Controller (enumFromText, unsafeEnumFromText)
import Generated.Types
import IHP.ControllerPrelude

data UserRosterPreferences = UserRosterPreferences
    { userRosterLayoutMode :: RosterLayoutModeEnum
    }

normaliseUserRosterPreferences :: Maybe UserPreference -> UserRosterPreferences
normaliseUserRosterPreferences maybePreferences =
    UserRosterPreferences
        { userRosterLayoutMode = maybe defaultRosterLayoutMode (.rosterLayoutMode) maybePreferences
        }

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

fetchCurrentUserPreferenceRecord :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO (Maybe UserPreference)
fetchCurrentUserPreferenceRecord =
    query @UserPreference
        |> filterWhere (#userId, unpackId currentUser.id)
        |> fetchOneOrNothing

fetchCurrentUserRosterPreferences :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO UserRosterPreferences
fetchCurrentUserRosterPreferences =
    fetchCurrentUserPreferenceRecord
        >>= pure . normaliseUserRosterPreferences

fetchCurrentRosterLayoutMode :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO RosterLayoutModeEnum
fetchCurrentRosterLayoutMode =
    (.userRosterLayoutMode) <$> fetchCurrentUserRosterPreferences

upsertCurrentUserRosterLayoutMode ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    RosterLayoutModeEnum ->
    IO UserPreference
upsertCurrentUserRosterLayoutMode layoutMode = do
    maybePreferences <- fetchCurrentUserPreferenceRecord
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
