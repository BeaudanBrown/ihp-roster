{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendContractCarrierIncompleteUnionParser where

import Application.Helper.FrontendContract.Wire.Carrier
import IHP.Prelude
import qualified Test.Support.FrontendContractCarrierFixture as Fixture

-- Every declared case needs a typed parser; CarrierDeleted cannot be omitted.
incompleteUnionParser =
    parseTaggedUnionIn @Fixture.CarrierContracts @Fixture.CarrierUnion
        ( unionCase @Fixture.CarrierCreated (\(userId, ()) -> pure userId)
            |: noUnionCases
        )
