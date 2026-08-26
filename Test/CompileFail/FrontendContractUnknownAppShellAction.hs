{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendContractUnknownAppShellAction where

import Application.Helper.FrontendContract.AppShell.Runtime (appShellActionByMarker)
import Application.Helper.FrontendContract.IR (AppShellActionIR)
import Data.Text (Text)

unknownAction :: AppShellActionIR
unknownAction = appShellActionByMarker @Text
