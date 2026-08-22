module Web.Admin.RosterWindowStartDay
    ( RosterWindowStartDayImpact (..)
    , confirmRosterWindowStartDayMutation
    , previewRosterWindowStartDayMutation
    , rosterWeekStartsOnTouchedResources
    ) where

import Application.Helper.FrontendContract.Surface.Admin.Resource (adminExportsResource,
                                                                   adminVenueSettingsResource,
                                                                   xeroConnectionResource)
import Application.Helper.FrontendContract.Surface.Roster.Resource (rosterWeekBoundaryConfigResource)
import Application.Helper.FrontendContract.Surface.Timesheets.Resource (timesheetWeekBoundaryConfigResource)
import Application.Helper.RosterOffsetCompatibility (applyLegacyWeekOffsetEpoch)
import Application.Helper.SurfaceResource
import Application.Helper.WeekBoundaries (startOfWeekFor)
import Application.RosterPublication.Mutations (normalizePublishedRosterWindows,
                                                withRosterCalendarLock,
                                                withRosterCalendarLockInCurrentTransaction)
import qualified Data.Map.Strict as Map
import Generated.Types
import Web.Controller.Prelude
import Web.SurfaceInvalidation (withDurableLiveMutationOutcome)

data RosterWindowStartDayImpact = RosterWindowStartDayImpact
    { currentRosterWindowStartDay  :: !Int
    , proposedRosterWindowStartDay :: !Int
    , rosterCalendarRevision       :: !Int
    , mixedPublishedWindowCount    :: !Int
    , affectedPublishedDayCount    :: !Int
    , affectedShiftCount           :: !Int
    }
    deriving (Eq, Show)

previewRosterWindowStartDayMutation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    VenueConfig ->
    Int ->
    IO (Either Text RosterWindowStartDayImpact)
previewRosterWindowStartDayMutation submittedConfig proposedStartDay
    | not (validRosterWindowStartDay proposedStartDay) = pure (Left "Choose a valid roster window start day.")
    | submittedConfig.venueId /= unpackId currentVenueId = pure (Left "Choose settings from the current venue.")
    | otherwise =
        withRosterCalendarLock currentVenueId do
            currentConfig <- fetch submittedConfig.id
            if currentConfig.rosterCalendarRevision /= submittedConfig.rosterCalendarRevision
                then pure (Left staleCalendarMessage)
                else Right <$> calculateRosterWindowStartDayImpact currentConfig proposedStartDay

confirmRosterWindowStartDayMutation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    VenueConfig ->
    RosterWindowStartDayImpact ->
    IO (Either Text (LiveMutationResult VenueConfig))
confirmRosterWindowStartDayMutation submittedConfig expectedImpact
    | submittedConfig.venueId /= unpackId currentVenueId = pure (Left "Choose settings from the current venue.")
    | not (validRosterWindowStartDay expectedImpact.proposedRosterWindowStartDay) = pure (Left "Choose a valid roster window start day.")
    | otherwise =
        withDurableLiveMutationOutcome publicationFor do
            outcome <- withRosterCalendarLockInCurrentTransaction currentVenueId do
                currentConfig <- fetch submittedConfig.id
                if currentConfig.rosterCalendarRevision /= expectedImpact.rosterCalendarRevision
                    || currentStartDay currentConfig /= expectedImpact.currentRosterWindowStartDay
                    then pure (Left staleCalendarMessage)
                    else do
                        currentImpact <- calculateRosterWindowStartDayImpact currentConfig expectedImpact.proposedRosterWindowStartDay
                        if currentImpact /= expectedImpact
                            then pure (Left staleImpactMessage)
                            else do
                                updated <- applyRosterWindowStartDay currentConfig expectedImpact.proposedRosterWindowStartDay
                                pure (Right updated)
            pure (fmap (\updated -> liveMutationResult updated resources) outcome)
  where
    currentStartDay config = config.rosterWeekStartsOn
    resources = rosterWeekStartsOnTouchedResources currentVenueId
    publicationFor = either (const Nothing) (\result -> Just ("admin.venue_config.roster_window_start_day", result.liveMutationTouchedResources))

calculateRosterWindowStartDayImpact ::
    (?modelContext :: ModelContext) =>
    VenueConfig ->
    Int ->
    IO RosterWindowStartDayImpact
calculateRosterWindowStartDayImpact venueConfig proposedStartDay
    | venueConfig.rosterWeekStartsOn == proposedStartDay = pure (impactFromCounts 0 0 0)
    | otherwise = do
        publishedDays <- query @RosterDay
            |> filterWhere (#venueId, venueConfig.venueId)
            |> filterWhere (#publicationState, Published)
            |> fetch
        let publishedWindows = Map.fromListWith (<>)
                [ ((day.rosterGroupId, startOfWeekFor proposedStartDay day.operationalDate), [day.id])
                | day <- publishedDays
                ]
        let mixedPublishedWindows = Map.filter ((< 7) . length) publishedWindows
        let affectedDayIds = concat (Map.elems mixedPublishedWindows)
        affectedShifts <-
            if null affectedDayIds
                then pure 0
                else query @RosterSlot
                    |> filterWhereIn (#rosterDayId, map unpackId affectedDayIds)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetchCount
        pure (impactFromCounts (Map.size mixedPublishedWindows) (length affectedDayIds) affectedShifts)
  where
    impactFromCounts mixedWindows affectedDays affectedShifts =
        RosterWindowStartDayImpact
            { currentRosterWindowStartDay = venueConfig.rosterWeekStartsOn
            , proposedRosterWindowStartDay = proposedStartDay
            , rosterCalendarRevision = venueConfig.rosterCalendarRevision
            , mixedPublishedWindowCount = mixedWindows
            , affectedPublishedDayCount = affectedDays
            , affectedShiftCount = affectedShifts
            }

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
            |> applyLegacyWeekOffsetEpoch proposedStartDay
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

staleImpactMessage :: Text
staleImpactMessage = "The roster calendar impact changed. Review the refreshed confirmation and try again."
