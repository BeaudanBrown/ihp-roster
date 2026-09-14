{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendContractUnknownConstant where

import Application.Helper.FrontendContract.Values (constantValue)
import Data.Text (Text)

unknownConstant :: Text
unknownConstant = constantValue @Text
