{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Test.Support.FrontendSurfaceFixture
    ( FixturePanel
    , FixtureScope
    , FixtureShell
    , FixtureViewState
    , ShowArchived
    , StaffFilterId
    , VenueId
    , WeekOffset
    , MoveCard
    , PanelId
    , RefreshPanel
    , SourceItemKey
    , FrontendSurfaceFixture
    , TargetDropzoneKey
    ) where

import Application.Helper.FrontendContract.Surface.DSL
import Application.Helper.FrontendContract.Surface.Interaction (CloneShadow,
                                                                DropzoneHighlight)

-- This fixture deliberately stays outside RegisteredFrontendSurfaces. It gives
-- reflection, runtime, generator, and compile-failure tests a declaration-rich
-- Surface without publishing test vocabulary to the application or browser.
data ContractFixture

data FixtureScope
data VenueId
data WeekOffset

data FixtureViewState
data ShowArchived
data StaffFilterId

data FixtureShell
data FixturePanel
data PanelId
data ContractFixtureShell
data ContractFixturePanel

data RefreshPanel
data MoveCard
data SourceItemKey
data TargetDropzoneKey

data DragSession
data DragPreview

data Dialog
data FixtureCommitted
data FixtureRoot
data FixtureDropzone
data FixturePanelInclude
data FixturePanelCustomHtmx

data FixturePayload
data FixtureRelatedPayload
data Label
data Count
data Note
data Tags
data DueDay
data MaybeRank
data MaybeMemo
data RelatedPayload

data Load
data Panel

type FixtureScopeBundle =
    '[ Scope FixtureScope
        '[ Field VenueId 'WireUUID
         , Field WeekOffset 'WireInt
         ]
        '[ 'NoAuth ]
     , MountState FixtureViewState
        '[ Field ShowArchived 'WireBool
         , OptionalField StaffFilterId 'WireUUID
         ]
     ]

type FixtureFragmentBundle =
    '[ Fragment FixtureShell '[] '[ 'MountTarget ContractFixtureShell '[], 'Eager ]
     , Fragment FixturePanel
        '[ Field PanelId 'WireUUID ]
        '[ 'MountTarget ContractFixturePanel '[]
         , 'Lazy '[ 'Trigger Load, 'Placeholder Panel ]
         ]
     , Action RefreshPanel
        '[ Field PanelId 'WireUUID ]
        '[ 'Target FixturePanel
         , 'HtmxMethod 'HtmxPost
         , 'HtmxTarget ('HtmxId ContractFixturePanel)
         , 'HtmxSwap 'HtmxOuterHTML
         , 'HtmxInclude ('HtmxId FixturePanelInclude)
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         , 'CustomHtmx FixturePanelCustomHtmx "test fixture covers auditable custom HTMX metadata"
         ]
     ]

type FixtureInteractionBundle =
    '[ Intent MoveCard
        '[ Field SourceItemKey 'WireText
         , Field TargetDropzoneKey 'WireText
         ]
        '[ 'BackedBy RefreshPanel ]
     , Session DragSession '[ 'Layer DragPreview, 'Effect (CloneShadow DragPreview), 'Effect DropzoneHighlight ]
     , ConflictPolicy DragSession FixturePanel 'Defer
     ]

type FixtureSharedBundle =
    '[ Event FixtureCommitted '[ Field PanelId 'WireUUID ]
     , DomToken FixtureRoot
     , DomToken FixtureDropzone
     , DomToken FixturePanelInclude
     , Dto FixturePayload
        '[ Field Label 'WireText
         , OptionalField Count 'WireInt
         , NullableField Note 'WireText
         , Field Tags ('WireList 'WireText)
         , Field DueDay 'WireDay
         , Field MaybeRank ('WireOptional 'WireInt)
         , Field MaybeMemo ('WireNullable 'WireText)
         , Field RelatedPayload ('WireRef FixtureRelatedPayload)
         ]
     , Dto FixtureRelatedPayload
        '[ Field Label 'WireText
         ]
     ]

type FrontendSurfaceFixture =
    Surface ContractFixture (Concat '[ FixtureScopeBundle, FixtureFragmentBundle, FixtureInteractionBundle, FixtureSharedBundle ])
