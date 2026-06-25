{-# LANGUAGE TypeApplications #-}

module Application.Helper.UserPreferences
    ( UserRosterPreferences (..)
    , defaultRosterLayoutMode
    , fetchCurrentRosterLayoutMode
    , fetchCurrentUserRosterPreferences
    , fetchCurrentUserShowRosterWarnings
    , fetchCurrentUserShowWageEstimates
    , parseRosterLayoutMode
    , rosterLayoutModeLabel
    , rosterLayoutModeValue
    , rosterLayoutModes
    , upsertCurrentUserRosterLayoutMode
    , upsertCurrentUserShowRosterWarnings
    , upsertCurrentUserShowWageEstimates
    ) where

import Application.Helper.Controller (VenueRole (ManagerRole'), enumFromText,
                                      hasRole, unsafeEnumFromText)
import Generated.Types
import IHP.ControllerPrelude

data UserRosterPreferences = UserRosterPreferences
    { userRosterLayoutMode   :: RosterLayoutModeEnum
    , userShowRosterWarnings :: Bool
    , userShowWageEstimates  :: Bool
    }

normaliseUserRosterPreferences :: Maybe UserPreference -> UserRosterPreferences
normaliseUserRosterPreferences maybePreferences =
    UserRosterPreferences
        { userRosterLayoutMode = maybe defaultRosterLayoutMode (.rosterLayoutMode) maybePreferences
        -- Legacy column name is inverted for roster warning highlights: TRUE keeps
        -- conflict highlighting hidden, preserving the default disabled state.
        , userShowRosterWarnings = maybe False (\preferences -> not preferences.showShiftTypeHighlights) maybePreferences
        , userShowWageEstimates = maybe False (.showWageEstimates) maybePreferences
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

fetchCurrentUserShowRosterWarnings :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO Bool
fetchCurrentUserShowRosterWarnings
    | not (hasRole ManagerRole') = pure False
    | otherwise = (.userShowRosterWarnings) <$> fetchCurrentUserRosterPreferences

fetchCurrentUserShowWageEstimates :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO Bool
fetchCurrentUserShowWageEstimates =
    (.userShowWageEstimates) <$> fetchCurrentUserRosterPreferences

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

upsertCurrentUserShowRosterWarnings ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Bool ->
    IO UserPreference
upsertCurrentUserShowRosterWarnings showRosterWarnings = do
    maybePreferences <- fetchCurrentUserPreferenceRecord
    let hideRosterWarnings = not showRosterWarnings
    case maybePreferences of
        Just preferences ->
            preferences
                |> set #showShiftTypeHighlights hideRosterWarnings
                |> updateRecord
        Nothing ->
            newRecord @UserPreference
                |> set #userId (unpackId currentUser.id)
                |> set #showShiftTypeHighlights hideRosterWarnings
                |> createRecord

upsertCurrentUserShowWageEstimates ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Bool ->
    IO UserPreference
upsertCurrentUserShowWageEstimates showWageEstimates = do
    maybePreferences <- fetchCurrentUserPreferenceRecord
    case maybePreferences of
        Just preferences ->
            preferences
                |> set #showWageEstimates showWageEstimates
                |> updateRecord
        Nothing ->
            newRecord @UserPreference
                |> set #userId (unpackId currentUser.id)
                |> set #showWageEstimates showWageEstimates
                |> createRecord
