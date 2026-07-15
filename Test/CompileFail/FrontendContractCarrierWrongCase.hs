{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendContractCarrierWrongCase where

import Application.Helper.FrontendContract.Wire.Carrier
import qualified Test.Support.FrontendContractCarrierFixture as Fixture

-- CarrierOtherCase is not owned by CarrierUnion.
wrongCarrierCase =
    taggedUnionValueIn @Fixture.CarrierContracts @Fixture.CarrierUnion @Fixture.CarrierOtherCase noFields
