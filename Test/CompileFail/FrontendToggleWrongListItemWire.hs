{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendToggleWrongListItemWire where

import qualified Application.Helper.FrontendContract.Surface.Profile as Surface
import qualified Application.Helper.FrontendContract.Surface.Profile.Action as ProfileAction
import Application.Helper.View.ToggleButton
import IHP.Prelude

fields =
    ProfileAction.updateProfileDetailsActionFields
        "First"
        "Last"
        ""
        ""
        3
        ""
        ""
        "details"
        Nothing
        Nothing
        Nothing
        Nothing

invalidListItemBinding :: ToggleFieldBinding
invalidListItemBinding =
    surfaceToggleListItemField @Surface.RosterGroupIdsField fields ("not-a-uuid" :: Text)
