module Test.CompileFail.FrontendSurfaceRawResource where

import Application.Helper.SurfaceResource
import qualified Data.Aeson as Aeson

-- Public resource facades expose the carrier opaquely. Feature code cannot
-- construct a free resource name or arbitrary JSON fields.
rawSurfaceResource = SurfaceResourceValue "timesheet-day" (Aeson.object [])
