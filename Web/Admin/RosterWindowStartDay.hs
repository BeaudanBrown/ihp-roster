module Web.Admin.RosterWindowStartDay
    ( updateRosterWindowStartDayMutation
    , rosterWeekStartsOnTouchedResources
    ) where

import Application.Helper.FrontendContract.Surface.Admin.Resource (adminExportsResource,
                                                                   adminVenueSettingsResource,
                                                                   xeroConnectionResource)
import Application.Helper.FrontendContract.Surface.Roster.Resource (rosterWeekBoundaryConfigResource)
import Application.Helper.FrontendContract.Surface.Timesheets.Resource (timesheetWeekBoundaryConfigResource)
import Application.Helper.SurfaceResource
import Application.RosterPublication.Mutations (normalizePublishedRosterWindows,
                                                withRosterCalendarLockInCurrentTransaction)
import Generated.Types
import Web.Controller.Prelude
import Web.SurfaceInvalidation (withDurableLiveMutationOutcome)

updateRosterWindowStartDayMutation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    VenueConfig ->
    Int ->
    IO (Either Text (LiveMutationResult VenueConfig))
updateRosterWindowStartDayMutation submittedConfig proposedStartDay
    | submittedConfig.venueId /= unpackId currentVenueId = pure (Left "Choose settings from the current venue.")
    | not (validRosterWindowStartDay proposedStartDay) = pure (Left "Choose a valid roster window start day.")
    | otherwise =
        withDurableLiveMutationOutcome publicationFor do
            outcome <- withRosterCalendarLockInCurrentTransaction currentVenueId do
                currentConfig <- fetch submittedConfig.id
                if currentConfig.rosterCalendarRevision /= submittedConfig.rosterCalendarRevision
                    then pure (Left staleCalendarMessage)
                    else Right <$> applyRosterWindowStartDay currentConfig proposedStartDay
            pure (fmap (`liveMutationResult` resources) outcome)
  where
    resources = rosterWeekStartsOnTouchedResources currentVenueId
    publicationFor = either (const Nothing) (\result -> Just ("admin.venue_config.roster_window_start_day", result.liveMutationTouchedResources))

applyRosterWindowStartDay ::
    (?modelContext :: ModelContext) =>
    VenueConfig ->
    Int ->
    IO VenueConfig
applyRosterWindowStartDay currentConfig proposedStartDay
    | currentConfig.rosterWeekStartsOn == proposedStartDay = pure currentConfig
    | otherwise = do
        normalizePublishedRosterWindows (Id currentConfig.venueId) proposedStartDay
        currentConfig
            |> set #rosterWeekStartsOn proposedStartDay
            |> updateRecord

rosterWeekStartsOnTouchedResources :: Id Venue -> [SurfaceResourceValue]
rosterWeekStartsOnTouchedResources venueId =
    [ adminVenueSettingsResource unpackedVenueId
    , adminExportsResource unpackedVenueId
    , rosterWeekBoundaryConfigResource unpackedVenueId
    , timesheetWeekBoundaryConfigResource unpackedVenueId
    , xeroConnectionResource unpackedVenueId
    ]
  where
    unpackedVenueId = unpackId venueId

validRosterWindowStartDay :: Int -> Bool
validRosterWindowStartDay day = day >= 0 && day <= 6

staleCalendarMessage :: Text
staleCalendarMessage = "The roster calendar changed. Review the refreshed setting and try again."
