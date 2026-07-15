{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendContractCarrierExtraField where

import Application.Helper.FrontendContract.DSL (WireType (..))
import Application.Helper.FrontendContract.Wire.Carrier
import IHP.Prelude
import qualified Test.Support.FrontendContractCarrierFixture as Fixture

-- A declaration-complete record cannot append an undeclared field.
extraCarrierField =
    recordValueIn @Fixture.CarrierContracts @Fixture.CarrierRecord
        ( requiredField @Fixture.MemberIds []
            &: optionalField @Fixture.OptionalNullableNote Nothing
            &: nullableField @Fixture.RequiredNote Nothing
            &: requiredField @Fixture.NestedValues Nothing
            &: requiredField @Fixture.CarrierUserId @'WireText "extra"
            &: noFields
        )
