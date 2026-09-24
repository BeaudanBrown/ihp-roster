{-# LANGUAGE TypeApplications #-}

module Application.Helper.ManagementMode
    ( initManagementModeContext
    , managementModeContextFor
    , upsertCurrentUserManagerMode
    ) where

import Application.Error.Runtime (throwExternalRuntime)
import Application.Helper.ControllerContext
import Application.Helper.Hasql (isUniqueViolation)
import qualified Control.Exception as Exception
import Generated.Types
import IHP.ControllerPrelude

initManagementModeContext :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO ()
initManagementModeContext = do
    maybePreference <-
        query @UserPreference
            |> filterWhere (#userId, unpackId effectiveCurrentUser.id)
            |> fetchOneOrNothing
    let preferenceEnabled = maybe True (.managerModeEnabled) maybePreference
    let managementMode =
            managementModeContextFor
                currentUserIsUnimpersonatedSuperAdmin
                effectiveVenueRoleOrNothing
                (isJust effectiveStaffOrNothing)
                preferenceEnabled
    managementMode `seq` modifyRequestVenueState (\state -> state { managementMode })

managementModeContextFor :: Bool -> Maybe VenueRoleEnum -> Bool -> Bool -> ManagementModeContext
managementModeContextFor unimpersonatedSupport effectiveRole hasActiveLinkedStaff preferenceEnabled =
    ManagementModeContext
        { managementModeEffective =
            unimpersonatedSupport
                || (roleEligible && (not toggleEnabled || preferenceEnabled))
        , managementModePreferenceEnabled = preferenceEnabled
        , managementModeToggleVisible = toggleVisible
        , managementModeToggleEnabled = toggleEnabled
        }
  where
    roleEligible = effectiveRole `elem` map Just [Manager, VenueAdmin, VenueOwner]
    toggleVisible = roleEligible && not unimpersonatedSupport
    toggleEnabled = toggleVisible && hasActiveLinkedStaff

upsertCurrentUserManagerMode :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Bool -> IO Bool
upsertCurrentUserManagerMode enabled
    | not managerModeToggleEnabled = pure False
    | otherwise = do
        maybePreference <-
            query @UserPreference
                |> filterWhere (#userId, unpackId effectiveCurrentUser.id)
                |> fetchOneOrNothing
        case maybePreference of
            Just preference -> do
                _ <- preference |> set #managerModeEnabled enabled |> updateRecord
                pure True
            Nothing -> do
                let preference =
                        newRecord @UserPreference
                            |> set #userId (unpackId effectiveCurrentUser.id)
                            |> set #managerModeEnabled enabled
                result :: Either HasqlSessionError UserPreference <- Exception.try (createRecord preference)
                case result of
                    Right _ -> pure True
                    Left sessionError
                        | isUniqueViolation sessionError -> upsertCurrentUserManagerMode enabled
                        | otherwise -> throwExternalRuntime sessionError
