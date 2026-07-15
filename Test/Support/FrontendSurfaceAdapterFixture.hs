{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeFamilies  #-}
{-# LANGUAGE TypeOperators #-}

module Test.Support.FrontendSurfaceAdapterFixture
    ( AdapterFixtureFamily
    , AdapterFixtureSurface
    , ArchivedAt
    , Enabled
    , FixtureAccount
    , FixtureAdapterFamilies
    , FixtureHeartbeatResource
    , FixtureResourceHomes
    , Label
    , MaybeIds
    , MaybeNote
    , MemberIds
    , RetryCount
    ) where

import Application.Helper.FrontendContract.Surface.DSL
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Family

-- This declaration-rich fixture stays outside RegisteredFrontendSurfaces. It
-- exercises generated Haskell source types without publishing test vocabulary
-- to the application or browser registries.
data AdapterFixture
data AdapterFixtureFamily
data AdapterFixtureScope
data AdapterFixturePanel
data AdapterFixturePanelTarget

data FixtureAccount
data FixtureHeartbeatResource

data Label
data RetryCount
data ArchivedAt
data MemberIds
data MaybeNote
data MaybeIds
data Enabled

type FixtureAccountFields =
    '[ Field Label 'WireText
     , OptionalField RetryCount 'WireInt
     , NullableField ArchivedAt 'WireDay
     , Field MemberIds ('WireList 'WireUUID)
     , OptionalField MaybeNote ('WireNullable 'WireText)
     , NullableField MaybeIds ('WireList 'WireUUID)
     , Field Enabled 'WireBool
     ]

type FixtureAccountResource = Resource FixtureAccount FixtureAccountFields

type FixtureHeartbeat = Resource FixtureHeartbeatResource '[]

type AdapterFixtureSurface =
    Surface AdapterFixture
        '[ Scope AdapterFixtureScope '[] '[ 'NoAuth ]
         , Fragment AdapterFixturePanel FixtureAccountFields
            '[ 'MountTarget AdapterFixturePanelTarget '[]
             , 'DependsOn FixtureAccountResource
                '[ 'FromFragment Label
                 , 'FromFragment RetryCount
                 , 'FromFragment ArchivedAt
                 , 'FromFragment MemberIds
                 , 'FromFragment MaybeNote
                 , 'FromFragment MaybeIds
                 , 'FromFragment Enabled
                 ]
             , 'DependsOn FixtureHeartbeat '[]
             ]
         ]

instance SurfaceAdapterFamily AdapterFixtureFamily where
    type AdapterFamilySurface AdapterFixtureFamily = AdapterFixtureSurface

type FixtureAdapterFamilies = '[AdapterFixtureFamily]

type FixtureResourceHomes =
    '[ SurfaceResourceAdapterHome AdapterFixtureFamily FixtureAccount
     , SurfaceResourceAdapterHome AdapterFixtureFamily FixtureHeartbeatResource
     ]
