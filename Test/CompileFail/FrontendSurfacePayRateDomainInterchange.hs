{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Test.CompileFail.FrontendSurfacePayRateDomainInterchange where

import Application.Helper.FrontendContract.Surface.DSL
import Application.Helper.FrontendContract.Surface.Request.Runtime (frontendSurfaceAction)
import Application.Helper.FrontendContract.Surface.Values
import Application.PayRateSelection


data Fixture
data PayRate
data UpdateShift

type FixtureSurface =
    Surface Fixture
        '[ Action UpdateShift
            '[ Field PayRate ('WireDomain ShiftTypePayRateSelection) ]
            '[]
         ]

-- Staff and shift-type selections intentionally share text encodings, but their
-- nominal request values must never be interchangeable.
wrongPayRateDomain =
    frontendSurfaceAction @FixtureSurface @UpdateShift
        ( surfaceActionFields
            (surfaceField @PayRate StaffPayRateRosterOnly)
            noSurfaceFields
        )
