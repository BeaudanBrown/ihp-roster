module Test.CompileFail.FrontendSurfaceRawLiveIdentity where

import Application.Helper.LiveUpdate.Runtime
import qualified Data.Aeson as Aeson

-- Public live runtime facades expose identity carriers opaquely. Feature code
-- cannot construct raw Surface names, JSON payloads, or stable keys.
rawLiveScope = FrontendSurfaceScope "timesheets" (Aeson.object []) "timesheets"
