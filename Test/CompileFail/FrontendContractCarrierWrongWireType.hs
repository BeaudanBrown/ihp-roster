{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendContractCarrierWrongWireType where

import Application.Helper.FrontendContract.Wire.Carrier
import IHP.Prelude
import qualified Test.Support.FrontendContractCarrierFixture as Fixture

-- MemberIds is declared WireList WireUUID, not scalar Text.
wrongCarrierWireType =
    recordValueIn @Fixture.CarrierContracts @Fixture.CarrierRecord
        ( requiredField @Fixture.MemberIds ("not-a-list" :: Text)
            &: optionalField @Fixture.OptionalNullableNote Nothing
            &: nullableField @Fixture.RequiredNote Nothing
            &: requiredField @Fixture.NestedValues Nothing
            &: noFields
        )
