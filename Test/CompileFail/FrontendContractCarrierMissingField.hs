{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendContractCarrierMissingField where

import Application.Helper.FrontendContract.Wire.Carrier
import IHP.Prelude
import qualified Test.Support.FrontendContractCarrierFixture as Fixture

-- CarrierRecord requires NestedValues after the nullable RequiredNote field.
missingCarrierField =
    recordValueIn @Fixture.CarrierContracts @Fixture.CarrierRecord
        ( requiredField @Fixture.MemberIds []
            &: optionalField @Fixture.OptionalNullableNote Nothing
            &: nullableField @Fixture.RequiredNote Nothing
            &: noFields
        )
