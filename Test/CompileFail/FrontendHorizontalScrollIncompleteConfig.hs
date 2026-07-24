{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Test.CompileFail.FrontendHorizontalScrollIncompleteConfig where

import qualified Application.Helper.FrontendContract.HorizontalScroll as HorizontalScroll
import Application.Helper.FrontendContract.HorizontalScroll.Runtime ()
import Application.Helper.FrontendContract.Wire.Carrier
import IHP.Prelude

incompleteHorizontalSnapConfig =
    recordValue @HorizontalScroll.HorizontalSnapConfig
        ( requiredField @HorizontalScroll.SnapMode ("nearest-item" :: Text)
            &: nullableField @HorizontalScroll.ItemSelector (Just ".panel")
            &: nullableField @HorizontalScroll.GroupCount (Nothing :: Maybe Int)
            &: nullableField @HorizontalScroll.GroupProperty (Nothing :: Maybe Text)
            &: noFields
        )
