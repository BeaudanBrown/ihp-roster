{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeFamilies  #-}
{-# LANGUAGE TypeOperators #-}

module Test.Support.FrontendSurfaceAdapterFixture
    ( AdapterFixtureFamily
    , AdapterFixtureSurface
    , ArchivedAt
    , CrossKindDeclaration
    , Enabled
    , FixtureAccount
    , FixtureActionHomes
    , FixtureAdapterFamilies
    , FixtureFragmentHomes
    , FixtureHeartbeatResource
    , FixtureIntentHomes
    , FixtureResourceHomes
    , FixtureScopeHomes
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
data CrossKindDeclaration
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
        '[ Scope CrossKindDeclaration FixtureAccountFields '[ 'NoAuth ]
         , Fragment CrossKindDeclaration FixtureAccountFields
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
         , Action CrossKindDeclaration FixtureAccountFields '[]
         , Intent CrossKindDeclaration FixtureAccountFields '[]
         ]

instance SurfaceAdapterFamily AdapterFixtureFamily where
    type AdapterFamilySurface AdapterFixtureFamily = AdapterFixtureSurface

type FixtureAdapterFamilies = '[AdapterFixtureFamily]

type FixtureResourceHomes =
    '[ SurfaceResourceAdapterHome AdapterFixtureFamily FixtureAccount
     , SurfaceResourceAdapterHome AdapterFixtureFamily FixtureHeartbeatResource
     ]

type FixtureScopeHomes =
    '[SurfaceScopeAdapterHome AdapterFixtureFamily CrossKindDeclaration]

type FixtureFragmentHomes =
    '[SurfaceFragmentAdapterHome AdapterFixtureFamily CrossKindDeclaration]

type FixtureActionHomes =
    '[SurfaceActionAdapterHome AdapterFixtureFamily CrossKindDeclaration]

type FixtureIntentHomes =
    '[SurfaceIntentAdapterHome AdapterFixtureFamily CrossKindDeclaration]
