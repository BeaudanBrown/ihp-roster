{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendToggleScalarListField where

import qualified Application.Helper.FrontendContract.Surface.Profile as Surface
import qualified Application.Helper.FrontendContract.Surface.Profile.Action as ProfileAction
import Application.Helper.View.ToggleButton
import IHP.Prelude

fields = ProfileAction.updateProfileShiftPreferencesActionFields "preferences" (Just ["monday"])

invalidScalarListBinding :: ToggleFieldBinding
invalidScalarListBinding =
    surfaceToggleScalarField @Surface.ShiftPreferenceKeysField fields ["monday"] []
