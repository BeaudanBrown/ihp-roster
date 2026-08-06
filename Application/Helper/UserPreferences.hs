{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Application.Helper.UserPreferences
    ( UserRosterPreferences (..)
    , UserTimesheetPreferences (..)
    , defaultRosterLayoutMode
    , fetchCurrentRosterLayoutMode
    , fetchCurrentUserRosterPreferences
    , fetchCurrentUserShowRosterWarnings
    , fetchCurrentUserShowWageEstimates
    , fetchCurrentUserHighlightOwnLiveShifts
    , fetchCurrentUserTimesheetPreferences
    , rosterLayoutModeIsDayColumns
    , rosterLayoutModeLabel
    , rosterLayoutModeValue
    , rosterLayoutModes
    , upsertCurrentUserRosterLayoutMode
    , upsertCurrentUserShowRosterWarnings
    , upsertCurrentUserShowWageEstimates
    , upsertCurrentUserHighlightOwnLiveShifts
    , upsertCurrentUserTimesheetHideApproved
    , upsertCurrentUserTimesheetShowSuggestions
    ) where

import Application.Helper.Controller (effectiveCurrentUser, enumFromText,
                                      hasRole)
import Generated.Types
import IHP.ControllerPrelude

data UserRosterPreferences = UserRosterPreferences
    { userRosterLayoutMode       :: RosterLayoutModeEnum
    , userShowRosterWarnings     :: Bool
    , userShowWageEstimates      :: Bool
    , userHighlightOwnLiveShifts :: Bool
    }

data UserTimesheetPreferences = UserTimesheetPreferences
    { userTimesheetHideApproved    :: Bool
    , userTimesheetShowSuggestions :: Bool
    }
    deriving (Eq, Show)

normaliseUserRosterPreferences :: Maybe UserPreference -> UserRosterPreferences
normaliseUserRosterPreferences maybePreferences =
    UserRosterPreferences
        { userRosterLayoutMode = maybe defaultRosterLayoutMode (.rosterLayoutMode) maybePreferences
        -- Legacy column name is inverted for roster warning highlights: TRUE keeps
        -- conflict highlighting hidden, preserving the default disabled state.
        , userShowRosterWarnings = maybe False (\preferences -> not preferences.showShiftTypeHighlights) maybePreferences
        , userShowWageEstimates = maybe False (.showWageEstimates) maybePreferences
        , userHighlightOwnLiveShifts = maybe True (.highlightOwnLiveShifts) maybePreferences
        }

defaultRosterLayoutMode :: RosterLayoutModeEnum
defaultRosterLayoutMode = DayRows

rosterLayoutModes :: [RosterLayoutModeEnum]
rosterLayoutModes = allEnumValues @RosterLayoutModeEnum


rosterLayoutModeValue :: RosterLayoutModeEnum -> Text
rosterLayoutModeValue = inputValue

rosterLayoutModeIsDayColumns :: RosterLayoutModeEnum -> Bool
rosterLayoutModeIsDayColumns DayRows    = False
rosterLayoutModeIsDayColumns DayColumns = True

rosterLayoutModeLabel :: RosterLayoutModeEnum -> Text
rosterLayoutModeLabel DayRows    = "Day rows"
rosterLayoutModeLabel DayColumns = "Day columns"

fetchCurrentUserPreferenceRecord :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO (Maybe UserPreference)
fetchCurrentUserPreferenceRecord =
    query @UserPreference
        |> filterWhere (#userId, unpackId effectiveCurrentUser.id)
        |> fetchOneOrNothing

fetchCurrentUserRosterPreferences :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO UserRosterPreferences
fetchCurrentUserRosterPreferences =
    normaliseUserRosterPreferences <$> fetchCurrentUserPreferenceRecord

fetchCurrentRosterLayoutMode :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO RosterLayoutModeEnum
fetchCurrentRosterLayoutMode =
    (.userRosterLayoutMode) <$> fetchCurrentUserRosterPreferences

fetchCurrentUserShowRosterWarnings :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO Bool
fetchCurrentUserShowRosterWarnings
    | not (hasRole Manager) = pure False
    | otherwise = (.userShowRosterWarnings) <$> fetchCurrentUserRosterPreferences

fetchCurrentUserShowWageEstimates :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO Bool
fetchCurrentUserShowWageEstimates =
    (.userShowWageEstimates) <$> fetchCurrentUserRosterPreferences

fetchCurrentUserHighlightOwnLiveShifts :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO Bool
fetchCurrentUserHighlightOwnLiveShifts =
    (.userHighlightOwnLiveShifts) <$> fetchCurrentUserRosterPreferences

fetchCurrentUserTimesheetPreferences :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO UserTimesheetPreferences
fetchCurrentUserTimesheetPreferences = do
    maybePreferences <- fetchCurrentUserPreferenceRecord
    pure UserTimesheetPreferences
        { userTimesheetHideApproved = maybe True (.hideApproved) maybePreferences
        , userTimesheetShowSuggestions = maybe True (.showTimesheetSuggestions) maybePreferences
        }

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
                |> set #userId (unpackId effectiveCurrentUser.id)
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
                |> set #userId (unpackId effectiveCurrentUser.id)
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
                |> set #userId (unpackId effectiveCurrentUser.id)
                |> set #showWageEstimates showWageEstimates
                |> createRecord

upsertCurrentUserHighlightOwnLiveShifts ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Bool ->
    IO UserPreference
upsertCurrentUserHighlightOwnLiveShifts highlightOwnLiveShifts = do
    maybePreferences <- fetchCurrentUserPreferenceRecord
    case maybePreferences of
        Just preferences ->
            preferences
                |> set #highlightOwnLiveShifts highlightOwnLiveShifts
                |> updateRecord
        Nothing ->
            newRecord @UserPreference
                |> set #userId (unpackId currentUser.id)
                |> set #highlightOwnLiveShifts highlightOwnLiveShifts
                |> createRecord

upsertCurrentUserTimesheetHideApproved ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Bool ->
    IO UserPreference
upsertCurrentUserTimesheetHideApproved hideApproved = do
    maybePreferences <- fetchCurrentUserPreferenceRecord
    case maybePreferences of
        Just preferences ->
            preferences
                |> set #hideApproved hideApproved
                |> updateRecord
        Nothing ->
            newRecord @UserPreference
                |> set #userId (unpackId currentUser.id)
                |> set #hideApproved hideApproved
                |> createRecord

upsertCurrentUserTimesheetShowSuggestions ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Bool ->
    IO UserPreference
upsertCurrentUserTimesheetShowSuggestions showTimesheetSuggestions = do
    maybePreferences <- fetchCurrentUserPreferenceRecord
    case maybePreferences of
        Just preferences ->
            preferences
                |> set #showTimesheetSuggestions showTimesheetSuggestions
                |> updateRecord
        Nothing ->
            newRecord @UserPreference
                |> set #userId (unpackId currentUser.id)
                |> set #showTimesheetSuggestions showTimesheetSuggestions
                |> createRecord
