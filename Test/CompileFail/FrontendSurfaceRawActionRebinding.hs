module Test.CompileFail.FrontendSurfaceRawActionRebinding where

import Application.Helper.FrontendContract.Surface.Diagnostics (SurfaceFieldPresence (..))
import Application.Helper.FrontendContract.Surface.DSL
import Application.Helper.FrontendContract.Surface.Values
import IHP.Prelude

data SameShapeSurfaceName

data FirstAction

data SecondAction

data SharedField

type SameShapeSurface =
    Surface
        SameShapeSurfaceName
        '[ Action FirstAction '[ Field SharedField 'WireText ] '[]
         , Action SecondAction '[ Field SharedField 'WireText ] '[]
         ]

rawFirstActionFields :: SurfaceFields (SurfaceActionFieldSpecs SameShapeSurface FirstAction)
rawFirstActionFields =
    surfaceField @SharedField "first"
        &: noSurfaceFields

reboundSecondActionFields :: SurfaceActionFields SameShapeSurface SecondAction
reboundSecondActionFields = rebindRawActionFields rawFirstActionFields

rebindRawActionFields ::
    SurfaceFields (SurfaceActionFieldSpecs SameShapeSurface FirstAction) ->
    SurfaceActionFields SameShapeSurface SecondAction
rebindRawActionFields (field :& rest) =
    surfaceActionFields
        @SameShapeSurface
        @SecondAction
        @'SurfaceRequired
        @SharedField
        @'WireText
        field
        rest
