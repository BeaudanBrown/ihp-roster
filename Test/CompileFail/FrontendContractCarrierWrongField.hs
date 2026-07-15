{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendContractCarrierWrongField where

import Application.Helper.FrontendContract.Wire.Carrier
import IHP.Prelude
import qualified Test.Support.FrontendContractCarrierFixture as Fixture

-- CarrierUserId belongs to a union case, not CarrierRecord's MemberIds field.
wrongCarrierField =
    recordValueIn @Fixture.CarrierContracts @Fixture.CarrierRecord
        ( requiredField @Fixture.CarrierUserId []
            &: optionalField @Fixture.OptionalNullableNote Nothing
            &: nullableField @Fixture.RequiredNote Nothing
            &: requiredField @Fixture.NestedValues Nothing
            &: noFields
        )
