module Application.Helper.LiveResource
    ( LiveMutationResult (..)
    , LiveResource (..)
    , liveMutationResult
    , recordLiveMutationDiagnostics
    ) where

import qualified Data.Set as Set
import qualified Data.Text.IO as TextIO
import Data.UUID (UUID)
import IHP.Prelude
import System.Environment (lookupEnv)

data LiveResource
    = LeaveRequestsResource !UUID
    | StaffLeaveRequestsResource !UUID
    | LeaveCalendarResource !UUID !Int
    | TimesheetWeekResource !UUID !Int
    | TimesheetDayResource !UUID !Int !Int
    | StaffTimesheetResource !UUID
    | StaffProfileResource !UUID
    | StaffPreferencesResource !UUID
    | StaffRosterMembershipResource !UUID
    | StaffPayProfileResource !UUID
    | StaffRsaDocumentsResource !UUID
    | RosterWeekResource !UUID !Int
    | RosterDayResource !UUID
    | RosterSlotResource !UUID
    | AdminVenueSettingsResource !UUID
    | RosterEndTimesConfigResource !UUID
    | RosterWeekBoundaryConfigResource !UUID
    | TimesheetWeekBoundaryConfigResource !UUID
    | AdminRosterGroupsResource !UUID
    | AdminShiftTypesResource !UUID
    | AdminInvitesResource !UUID
    | AdminExportsResource !UUID
    | BillingResource !UUID
    | SupportAwardRatesResource
    | SupportPublicHolidaysResource
    | XeroConnectionResource !UUID
    | XeroMappingsResource !UUID
    | XeroPayItemsResource !UUID
    | XeroTimesheetsResource !UUID
    deriving (Eq, Ord, Show)

data LiveMutationResult a = LiveMutationResult
    { liveMutationValue            :: !a
    , liveMutationTouchedResources :: !(Set.Set LiveResource)
    }
    deriving (Eq, Show)

liveMutationResult :: a -> [LiveResource] -> LiveMutationResult a
liveMutationResult value resources =
    LiveMutationResult
        { liveMutationValue = value
        , liveMutationTouchedResources = Set.fromList resources
        }

recordLiveMutationDiagnostics :: Text -> LiveMutationResult a -> IO (LiveMutationResult a)
recordLiveMutationDiagnostics label result = do
    enabled <- liveMutationDiagnosticsEnabled
    when enabled do
        TextIO.putStrLn $
            "live_mutation_touches label="
                <> label
                <> " resources="
                <> tshow (Set.toAscList (liveMutationTouchedResources result))
    pure result

liveMutationDiagnosticsEnabled :: IO Bool
liveMutationDiagnosticsEnabled = do
    value <- lookupEnv "LIVE_MUTATION_DIAGNOSTICS"
    pure (maybe False isEnabled value)
    where
        isEnabled raw = raw `elem` ["1", "true", "TRUE", "yes", "YES"]
