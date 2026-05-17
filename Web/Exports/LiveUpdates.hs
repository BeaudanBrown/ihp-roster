module Web.Exports.LiveUpdates
    ( refreshAdminExports
    ) where

import Application.Helper.LiveSurface (broadcastSurfaceFragments)
import Web.Controller.Prelude
import Web.View.Admin.Exports (AdminExportsLiveFragment (..),
                               adminExportsLiveSurfaceDefinition)

refreshAdminExports :: (?context :: ControllerContext, ?request :: Request) => UUID -> IO ()
refreshAdminExports _venueId =
    broadcastSurfaceFragments
        adminExportsLiveSurfaceDefinition
        ()
        [AdminExportsLiveFragment]
