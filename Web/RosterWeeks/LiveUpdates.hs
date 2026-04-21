module Web.RosterWeeks.LiveUpdates
    ( broadcastRosterWeekInvalidation
    ) where

import Application.Helper.LiveUpdate (LiveFragmentRef, broadcastLiveInvalidation)
import Web.Controller.Prelude
import Web.RosterWeeks.Projection (buildRosterWeekScope)
import Web.RosterWeeks.RenderData (keepCurrentRosterWeekProjectionHot)

broadcastRosterWeekInvalidation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id RosterGroup ->
    Int ->
    [LiveFragmentRef] ->
    IO ()
broadcastRosterWeekInvalidation rosterGroupId weekOffset fragments =
    unless (null fragments) do
        liftIO $
            broadcastLiveInvalidation
                (buildRosterWeekScope rosterGroupId weekOffset)
                (cs <$> getHeader "X-Live-Update-Client-Id")
                fragments
        keepCurrentRosterWeekProjectionHot rosterGroupId weekOffset
