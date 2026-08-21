{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

-- | Rollback-only adapters between the explicit roster-window runtime and the
-- retained legacy roster-week schema. Runtime callers must not interpret an
-- offset themselves; #374 owns eventual removal of this module.
module Web.RosterWeeks.LegacyCompatibility
    ( fetchLegacyRosterWeekForScope
    , legacyPlanningRosterWeekForScope
    ) where

import Application.Helper.RosterOffsetCompatibility (applyLegacyRosterWeekOffset)
import Data.Maybe (mapMaybe)
import Web.Controller.Prelude
import Web.RosterWeeks.DateRange (RosterWindowScope (..))

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
                    |> applyLegacyRosterWeekOffset venueConfig scope.rosterWindowStart
                    |> set #isLive isPublished
