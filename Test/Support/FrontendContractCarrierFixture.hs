{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Test.Support.FrontendContractCarrierFixture
    ( CarrierContracts
    , CarrierRecord
    , MemberIds
    , OptionalNullableNote
    , RequiredNote
    , NestedValues
    , CarrierUnion
    , CarrierCreated
    , CarrierDeleted
    , CarrierUserId
    , CarrierOtherCase
    ) where

import Application.Helper.FrontendContract.DSL

-- Test-only declarations for the public schema-indexed Haskell carrier seam.
data CarrierRoot

data CarrierRecord
data MemberIds
data OptionalNullableNote
data RequiredNote
data NestedValues

data CarrierUnion
data CarrierCreated
data CarrierDeleted
data CarrierUserId
data CarrierOtherCase

type CarrierContracts =
    '[ Global CarrierRoot
        '[ ServerSchema (Record CarrierRecord
            '[ Field MemberIds ('WireList 'WireUUID)
             , OptionalField OptionalNullableNote ('WireNullable 'WireText)
             , NullableField RequiredNote 'WireText
             , Field NestedValues ('WireOptional ('WireList ('WireNullable 'WireText)))
             ])
         , ServerSchema (TaggedUnionWithTag CarrierUnion "kind"
            '[ Case CarrierCreated '[Field CarrierUserId 'WireUUID]
             , Case CarrierDeleted '[Field CarrierUserId 'WireUUID]
             ])
         ]
     ]
