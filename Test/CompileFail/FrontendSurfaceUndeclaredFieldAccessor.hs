{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Test.CompileFail.FrontendSurfaceUndeclaredFieldAccessor where

import Application.Helper.FrontendSurface.DSL
import Application.Helper.FrontendSurface.Runtime
import IHP.Prelude

data PanelId
data WeekOffset

-- This fixture intentionally asks for a field that is not declared in the
-- handler's field list. It should fail at compile time before any runtime JSON
-- parsing can happen.
missingFieldAccessor :: FrontendSurfaceFieldValues '[Field PanelId 'WireUUID] -> Maybe Int
missingFieldAccessor = getSurfaceField @WeekOffset
