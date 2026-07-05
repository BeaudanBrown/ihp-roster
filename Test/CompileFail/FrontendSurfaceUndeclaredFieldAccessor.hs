{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Test.CompileFail.FrontendSurfaceUndeclaredFieldAccessor where

import Application.Helper.FrontendContract.Surface.DSL
import Application.Helper.FrontendContract.Surface.Runtime
import IHP.Prelude

data PanelId
data WeekOffset

-- This fixture intentionally asks for a field that is not declared in the
-- handler's field list. It should fail at compile time before any runtime JSON
-- parsing can happen.
missingFieldAccessor :: FrontendSurfaceFieldValues '[Field PanelId 'WireUUID] -> Maybe Int
missingFieldAccessor = getSurfaceField @WeekOffset
