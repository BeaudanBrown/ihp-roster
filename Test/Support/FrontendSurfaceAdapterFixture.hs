{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies     #-}
{-# LANGUAGE TypeOperators    #-}

module Test.Support.FrontendSurfaceAdapterFixture
    ( AdapterFixtureFamily
    , AdapterFixtureSurface
    , CollisionAdapterFamilies
    , CollisionScopeHomes
    , ArchivedAt
    , CrossKindDeclaration
    , Enabled
    , FixtureAccount
    , FixtureActionHomes
    , FixtureActorOnlyPanel
    , FixtureAdapterFamilies
    , FixtureFragmentHomes
    , FixtureHeartbeatResource
    , FixtureIntentHomes
    , FixtureResourceHomes
    , FixtureScopeHomes
    , Label
    , LiveCollisionSurfaces
    , MaybeIds
    , MaybeNote
    , MemberIds
    , RetryCount
    , fixtureActorOnlyFragments
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
data FixtureActorOnlyPanel
data FixtureActorOnlyPanelTarget

data LiveCollisionOne
data LiveCollisionTwo
data LiveCollisionFamilyOne
data LiveCollisionFamilyTwo
data Shared
data SharedScope

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
        '[ Scope CrossKindDeclaration '[] '[ 'NoAuth ]
         , Fragment CrossKindDeclaration FixtureAccountFields
            '[ 'MountTarget AdapterFixturePanelTarget '[]
             , 'Live
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
         , Fragment FixtureActorOnlyPanel '[]
            '[ 'MountTarget FixtureActorOnlyPanelTarget '[]
             , 'Eager
             ]
         , Action CrossKindDeclaration FixtureAccountFields '[]
         , Intent CrossKindDeclaration FixtureAccountFields '[]
         ]

instance SurfaceAdapterFamily AdapterFixtureFamily where
    type AdapterFamilySurface AdapterFixtureFamily = AdapterFixtureSurface

type LiveCollisionOneSurface =
    Surface LiveCollisionOne '[ Scope Shared '[] '[ 'NoAuth ] ]

type LiveCollisionTwoSurface =
    Surface LiveCollisionTwo '[ Scope SharedScope '[] '[ 'NoAuth ] ]

type LiveCollisionSurfaces =
    '[LiveCollisionOneSurface, LiveCollisionTwoSurface]

instance SurfaceAdapterFamily LiveCollisionFamilyOne where
    type AdapterFamilySurface LiveCollisionFamilyOne = LiveCollisionOneSurface

instance SurfaceAdapterFamily LiveCollisionFamilyTwo where
    type AdapterFamilySurface LiveCollisionFamilyTwo = LiveCollisionTwoSurface

type CollisionAdapterFamilies =
    '[LiveCollisionFamilyOne, LiveCollisionFamilyTwo]

type CollisionScopeHomes =
    '[ SurfaceScopeAdapterHome LiveCollisionFamilyOne Shared
     , SurfaceScopeAdapterHome LiveCollisionFamilyTwo SharedScope
     ]

type FixtureAdapterFamilies = '[AdapterFixtureFamily]

type FixtureResourceHomes =
    '[ SurfaceResourceAdapterHome AdapterFixtureFamily FixtureAccount
     , SurfaceResourceAdapterHome AdapterFixtureFamily FixtureHeartbeatResource
     ]

type FixtureScopeHomes =
    '[SurfaceScopeAdapterHome AdapterFixtureFamily CrossKindDeclaration]

type FixtureFragmentHomes =
    '[ SurfaceFragmentAdapterHome AdapterFixtureFamily CrossKindDeclaration
     , SurfaceFragmentAdapterHome AdapterFixtureFamily FixtureActorOnlyPanel
     ]

fixtureActorOnlyFragments :: [ActorOnlyFragmentAdapterMetadata]
fixtureActorOnlyFragments =
    [ surfaceActorOnlyFragmentAdapter
        @AdapterFixtureFamily
        @FixtureActorOnlyPanel
        "Actor-local fixture refreshes still construct this semantic key"
    ]

type FixtureActionHomes =
    '[SurfaceActionAdapterHome AdapterFixtureFamily CrossKindDeclaration]

type FixtureIntentHomes =
    '[SurfaceIntentAdapterHome AdapterFixtureFamily CrossKindDeclaration]
