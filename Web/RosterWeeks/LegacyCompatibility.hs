{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

-- | Rollback-only adapters between the explicit roster-window runtime and the
-- retained legacy roster-week schema. Runtime callers must not interpret an
-- offset themselves; #374 owns eventual removal of this module.
module Web.RosterWeeks.LegacyCompatibility
    ( fetchLegacyRosterWeekForScope
    , legacyPlanningRosterWeekForDay
    , legacyPlanningRosterWeekForScope
    , legacyRosterWindowScopeForOffset
    ) where

import Application.Helper.WeekBoundaries (venueWeekOffsetForDay,
                                          venueWeekStartDate)
import Data.Maybe (mapMaybe)
import Web.Controller.Prelude
import Web.RosterWeeks.DateRange (RosterWindowScope (..), fetchRosterWindow,
                                  rosterWindowIsPublished,
                                  rosterWindowScopeForAnchor)

fetchLegacyRosterWeekForScope :: (?modelContext :: ModelContext) => RosterWindowScope -> IO (Maybe RosterWeek)
fetchLegacyRosterWeekForScope scope = do
    datedDays <- query @RosterDay
        |> filterWhere (#venueId, unpackId scope.rosterWindowVenueId)
        |> filterWhere (#rosterGroupId, unpackId scope.rosterWindowRosterGroupId)
        |> filterWhereGreaterThanOrEqualTo (#operationalDate, scope.rosterWindowStart)
        |> filterWhereLessThan (#operationalDate, scope.rosterWindowEnd)
        |> orderByAsc #operationalDate
        |> fetch
    case listToMaybe (mapMaybe (.rosterWeekId) datedDays) of
        Just rosterWeekId -> query @RosterWeek
            |> filterWhere (#id, Id rosterWeekId)
            |> fetchOneOrNothing
        Nothing -> pure Nothing

legacyPlanningRosterWeekForDay :: (?modelContext :: ModelContext) => RosterDay -> IO RosterWeek
legacyPlanningRosterWeekForDay rosterDay = do
    venueConfig <- query @VenueConfig
        |> filterWhere (#venueId, rosterDay.venueId)
        |> fetchOne
    let scope = rosterWindowScopeForAnchor venueConfig (Id rosterDay.rosterGroupId) rosterDay.operationalDate
    window <- fetchRosterWindow scope.rosterWindowVenueId scope.rosterWindowRosterGroupId scope.rosterWindowStart
    legacyPlanningRosterWeekForScope scope (rosterWindowIsPublished window)

legacyPlanningRosterWeekForScope :: (?modelContext :: ModelContext) => RosterWindowScope -> Bool -> IO RosterWeek
legacyPlanningRosterWeekForScope scope isPublished = do
    fetchLegacyRosterWeekForScope scope >>= \case
        Just rosterWeek -> pure (rosterWeek |> set #isLive isPublished)
        Nothing -> do
            venueConfig <- query @VenueConfig
                |> filterWhere (#venueId, unpackId scope.rosterWindowVenueId)
                |> fetchOne
            pure $
                newRecord @RosterWeek
                    |> set #venueId (unpackId scope.rosterWindowVenueId)
                    |> set #rosterGroupId (unpackId scope.rosterWindowRosterGroupId)
                    |> set #weekOffset (venueWeekOffsetForDay venueConfig scope.rosterWindowStart)
                    |> set #isLive isPublished

legacyRosterWindowScopeForOffset :: (?modelContext :: ModelContext) => Id RosterGroup -> Int -> IO RosterWindowScope
legacyRosterWindowScopeForOffset rosterGroupId legacyWeekOffset = do
    rosterGroup <- fetch rosterGroupId
    venueConfig <- query @VenueConfig
        |> filterWhere (#venueId, rosterGroup.venueId)
        |> fetchOne
    pure (rosterWindowScopeForAnchor venueConfig rosterGroupId (venueWeekStartDate venueConfig legacyWeekOffset))
