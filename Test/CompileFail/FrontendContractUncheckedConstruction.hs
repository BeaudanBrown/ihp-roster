module Test.CompileFail.FrontendContractUncheckedConstruction where

import Application.Helper.FrontendContract.IR

uncheckedContract :: CheckedFrontendContract
uncheckedContract = FrontendContractIR [] []
