module Test.CompileFail.FrontendSurfaceRawIntentRebinding where

import Application.Helper.FrontendContract.Surface.Diagnostics (SurfaceFieldPresence (..))
import Application.Helper.FrontendContract.Surface.DSL
import Application.Helper.FrontendContract.Surface.Values
import IHP.Prelude

data SameShapeSurfaceName

data FirstIntent

data SecondIntent

data SharedField

type SameShapeSurface =
    Surface
        SameShapeSurfaceName
        '[ Intent FirstIntent '[ Field SharedField 'WireText ] '[]
         , Intent SecondIntent '[ Field SharedField 'WireText ] '[]
         ]

rawFirstIntentFields :: SurfaceFields (SurfaceIntentFieldSpecs SameShapeSurface FirstIntent)
rawFirstIntentFields =
    surfaceField @SharedField "first"
        &: noSurfaceFields

reboundSecondIntentFields :: SurfaceIntentFields SameShapeSurface SecondIntent
reboundSecondIntentFields = rebindRawIntentFields rawFirstIntentFields

rebindRawIntentFields ::
    SurfaceFields (SurfaceIntentFieldSpecs SameShapeSurface FirstIntent) ->
    SurfaceIntentFields SameShapeSurface SecondIntent
rebindRawIntentFields (field :& rest) =
    surfaceIntentFields
        @SameShapeSurface
        @SecondIntent
        @'SurfaceRequired
        @SharedField
        @'WireText
        field
        rest
