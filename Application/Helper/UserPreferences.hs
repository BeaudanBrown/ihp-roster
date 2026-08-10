{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Application.Helper.UserPreferences
    ( UserRosterPreferences (..)
    , UserTimesheetPreferences (..)
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
    , upsertCurrentUserShowRosterWarnings
    , upsertCurrentUserShowWageEstimates
    , upsertCurrentUserHighlightOwnLiveShifts
    , upsertCurrentUserTimesheetShowApproved
    , upsertCurrentUserTimesheetShowSuggestions
    , upsertCurrentUserTimesheetShowWageEstimates
    ) where

import Application.Helper.Controller (effectiveCurrentUser, fetchVenueConfig,
                                      hasRole)
import qualified Control.Exception as Exception
import Generated.Types
import qualified Hasql.Errors as Hasql
import IHP.ControllerPrelude
import IHP.ModelSupport.Types (HasqlSessionError (..))

data UserRosterPreferences = UserRosterPreferences
    { userShowRosterWarnings     :: Bool
    , userShowWageEstimates      :: Bool
    , userHighlightOwnLiveShifts :: Bool
    }

data UserTimesheetPreferences = UserTimesheetPreferences
    { userTimesheetShowApproved      :: Bool
    , userTimesheetShowSuggestions   :: Bool
    , userTimesheetShowWageEstimates :: Bool
    }
    deriving (Eq, Show)

normaliseUserRosterPreferences :: Maybe UserPreference -> UserRosterPreferences
normaliseUserRosterPreferences maybePreferences =
    UserRosterPreferences
        { -- Legacy column name is inverted for roster warning highlights: TRUE keeps
          -- conflict highlighting hidden, preserving the default disabled state.
          userShowRosterWarnings = maybe False (\preferences -> not preferences.showShiftTypeHighlights) maybePreferences
        , userShowWageEstimates = maybe False (.showWageEstimates) maybePreferences
        , userHighlightOwnLiveShifts = maybe True (.highlightOwnLiveShifts) maybePreferences
        }

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
    (.rosterLayoutMode) <$> fetchVenueConfig

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
    preferences <- fetchOrInitializeCurrentUserTimesheetPreferences
    pure UserTimesheetPreferences
        { -- The deployed column remains inverted for compatibility; positive
          -- Timesheets semantics stop at this storage boundary.
          userTimesheetShowApproved = not preferences.hideApproved
        , userTimesheetShowSuggestions = preferences.showTimesheetSuggestions
        , userTimesheetShowWageEstimates = preferences.showTimesheetWageEstimates
        }

fetchOrInitializeCurrentUserTimesheetPreferences :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO UserPreference
fetchOrInitializeCurrentUserTimesheetPreferences = do
    maybePreferences <- fetchCurrentUserPreferenceRecord
    now <- getCurrentTime
    case maybePreferences of
        Just preferences
            | isJust preferences.timesheetPreferencesInitializedAt -> pure preferences
            | otherwise ->
                preferences
                    |> set #hideApproved False
                    |> set #showTimesheetSuggestions True
                    |> set #showTimesheetWageEstimates True
                    |> set #timesheetPreferencesInitializedAt (Just now)
                    |> updateRecord
        Nothing -> do
            let initialPreferences =
                    newRecord @UserPreference
                        |> set #userId (unpackId effectiveCurrentUser.id)
                        |> set #hideApproved False
                        |> set #showTimesheetSuggestions True
                        |> set #showTimesheetWageEstimates True
                        |> set #timesheetPreferencesInitializedAt (Just now)
            result :: Either HasqlSessionError UserPreference <- Exception.try (createRecord initialPreferences)
            case result of
                Right preferences -> pure preferences
                Left sessionError
                    | isUniqueViolation sessionError ->
                        fetchCurrentUserPreferenceRecord >>= \case
                            Just preferences
                                | isJust preferences.timesheetPreferencesInitializedAt -> pure preferences
                                | otherwise -> fetchOrInitializeCurrentUserTimesheetPreferences
                            Nothing -> Exception.throwIO sessionError
                    | otherwise -> Exception.throwIO sessionError

isUniqueViolation :: HasqlSessionError -> Bool
isUniqueViolation (HasqlSessionError sessionError) =
    case sessionError of
        Hasql.StatementSessionError _ _ _ _ _ statementError -> statementErrorIsUniqueViolation statementError
        Hasql.ScriptSessionError _ serverError -> serverErrorIsUniqueViolation serverError
        Hasql.ConnectionSessionError _ -> False
        Hasql.MissingTypesSessionError _ -> False
        Hasql.DriverSessionError _ -> False
  where
    statementErrorIsUniqueViolation (Hasql.ServerStatementError serverError) = serverErrorIsUniqueViolation serverError
    statementErrorIsUniqueViolation (Hasql.UnexpectedRowCountStatementError _ _ _) = False
    statementErrorIsUniqueViolation (Hasql.UnexpectedColumnCountStatementError _ _) = False
    statementErrorIsUniqueViolation (Hasql.UnexpectedColumnTypeStatementError _ _ _) = False
    statementErrorIsUniqueViolation (Hasql.RowStatementError _ _) = False
    statementErrorIsUniqueViolation (Hasql.UnexpectedResultStatementError _) = False

    serverErrorIsUniqueViolation (Hasql.ServerError code _ _ _ _) = code == "23505"

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

upsertCurrentUserTimesheetShowApproved ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Bool ->
    IO UserPreference
upsertCurrentUserTimesheetShowApproved showApproved = do
    preferences <- fetchOrInitializeCurrentUserTimesheetPreferences
    now <- getCurrentTime
    preferences
        |> set #hideApproved (not showApproved)
        |> set #timesheetPreferencesInitializedAt (Just now)
        |> updateRecord

upsertCurrentUserTimesheetShowSuggestions ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Bool ->
    IO UserPreference
upsertCurrentUserTimesheetShowSuggestions showTimesheetSuggestions = do
    preferences <- fetchOrInitializeCurrentUserTimesheetPreferences
    now <- getCurrentTime
    preferences
        |> set #showTimesheetSuggestions showTimesheetSuggestions
        |> set #timesheetPreferencesInitializedAt (Just now)
        |> updateRecord

upsertCurrentUserTimesheetShowWageEstimates ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Bool ->
    IO UserPreference
upsertCurrentUserTimesheetShowWageEstimates showTimesheetWageEstimates = do
    preferences <- fetchOrInitializeCurrentUserTimesheetPreferences
    now <- getCurrentTime
    preferences
        |> set #showTimesheetWageEstimates showTimesheetWageEstimates
        |> set #timesheetPreferencesInitializedAt (Just now)
        |> updateRecord
