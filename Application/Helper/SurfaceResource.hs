module Application.Helper.SurfaceResource
    ( SurfaceResourceValue (..)
    , LiveMutationResult (..)
    , adminExportsResource
    , adminInvitesResource
    , adminRosterGroupsResource
    , archivedLeaveRequestsResource
    , approvedLeaveRequestsResource
    , adminShiftTypesResource
    , adminVenueSettingsResource
    , billingResource
    , deniedLeaveRequestsResource
    , leaveRequestsSectionResource
    , pendingLeaveRequestsResource
    , liveMutationResult
    , recordLiveMutationDiagnostics
    , resourceFieldInt
    , resourceFieldIntFor
    , resourceFieldText
    , resourceFieldUuid
    , resourceFieldUuidFor
    , resourceForSurface
    , resourceMatches
    , resourceMatchesFor
    , rosterDayResource
    , rosterEndTimesConfigResource
    , rosterWeekBoundaryConfigResource
    , rosterWeekResource
    , staffLeaveRequestsResource
    , staffPreferencesResource
    , staffProfileResource
    , staffRsaDocumentsResource
    , supportAwardRatesResource
    , supportPublicHolidaysResource
    , timesheetDayResource
    , timesheetWeekBoundaryConfigResource
    , timesheetWeekResource
    , timePickerConfigResource
    , xeroConnectionResource
    , xeroMappingsResource
    , xeroPayItemsResource
    , xeroTimesheetsResource
    ) where

import Application.Helper.FrontendContract.Surface.Resource
import qualified Data.Set as Set
import qualified Data.Text.IO as TextIO
import IHP.Prelude
import System.Environment (lookupEnv)

data LiveMutationResult a = LiveMutationResult
    { liveMutationValue            :: !a
    , liveMutationTouchedResources :: !(Set.Set SurfaceResourceValue)
    }
    deriving (Eq, Show)

liveMutationResult :: a -> [SurfaceResourceValue] -> LiveMutationResult a
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
