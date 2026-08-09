module Web.RosterWeeks.VenueSettings
    ( setVenueRosterLayoutMode
    ) where

import Application.Helper.FrontendContract.Surface.Roster.Resource (rosterLayoutConfigResource)
import Application.Helper.SurfaceResource (LiveMutationResult,
                                           liveMutationResult)
import Web.Controller.Prelude
import Web.SurfaceInvalidation (invalidateTouchedResources)

setVenueRosterLayoutMode ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    VenueConfig ->
    RosterLayoutModeEnum ->
    IO (LiveMutationResult VenueConfig)
setVenueRosterLayoutMode venueConfig layoutMode = do
    updated <-
        venueConfig
            |> set #rosterLayoutMode layoutMode
            |> updateRecord
    invalidateTouchedResources
        "roster.venue_config.layout_mode"
        (liveMutationResult updated [rosterLayoutConfigResource (unpackId currentVenueId)])
