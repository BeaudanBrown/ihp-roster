{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies     #-}

module Test.CompileFail.FrontendSurfaceWrongIntentField where

import Application.Helper.FrontendContract.Surface.DSL (FieldSpec (..),
                                                        WireType (..))
import Application.Helper.FrontendContract.Surface.Values
import IHP.Prelude
import qualified Test.Support.FrontendSurfaceFixture as Fixture

-- The generated production seam supplies this token and local field list. The
-- fixture declares the same operation-local boundary without registering test
-- vocabulary in production output.
data MoveCardIntentOperation

type instance IntentFieldSpecs MoveCardIntentOperation =
    '[ 'Field Fixture.SourceItemKey 'WireText
     , 'Field Fixture.TargetDropzoneKey 'WireText
     ]

moveCardIntentFields :: IntentFields MoveCardIntentOperation
moveCardIntentFields =
    intentFields
        (surfaceField @Fixture.SourceItemKey "source")
        ( surfaceField @Fixture.TargetDropzoneKey "target"
            &: noSurfaceFields
        )

-- PanelId is not carried by MoveCard. Intent field ownership must fail at
-- compile time rather than becoming an unchecked hidden input.
wrongIntentField = surfaceFieldNameFrom @Fixture.PanelId moveCardIntentFields
