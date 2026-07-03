{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendSurface.Lab
    ( LabPanel
    , LabScope
    , LabShell
    , LabViewState
    , MoveLabCard
    , PanelId
    , RefreshPanel
    , SourceItemKey
    , SurfaceLabSurface
    , TargetDropzoneKey
    ) where

import Application.Helper.FrontendSurface.DSL

data SurfaceLab

data LabScope
data VenueId
data WeekOffset

data LabViewState
data ShowArchived
data StaffFilterId

data LabShell
data LabPanel
data PanelId

data RefreshPanel
data MoveLabCard
data SourceItemKey
data TargetDropzoneKey

data DragSession
data DragPreview
data CloneShadow
data DropzoneHighlight

data Dialog
data LabCommitted
data LabRoot
data LabDropzone
data LabPayload
data LabRelatedPayload
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

type LabScopeBundle =
    '[ Scope LabScope
        '[ Field VenueId 'WireUUID
         , Field WeekOffset 'WireInt
         ]
        '[ 'NoAuth ]
     , MountState LabViewState
        '[ Field ShowArchived 'WireBool
         , OptionalField StaffFilterId 'WireUUID
         ]
     ]

type LabFragmentBundle =
    '[ Fragment LabShell '[] '[ 'Eager ]
     , Fragment LabPanel
        '[ Field PanelId 'WireUUID ]
        '[ 'Lazy '[ 'Trigger Load, 'Placeholder Panel ] ]
     , Action RefreshPanel
        '[ Field PanelId 'WireUUID ]
        '[ 'Target LabPanel ]
     ]

type LabInteractionBundle =
    '[ Intent MoveLabCard
        '[ Field SourceItemKey 'WireText
         , Field TargetDropzoneKey 'WireText
         ]
        '[ 'BackedBy RefreshPanel ]
     , Session DragSession '[ 'Layer DragPreview, 'Effect CloneShadow '[ 'Layer DragPreview ], 'Effect DropzoneHighlight '[] ]
     , ConflictPolicy DragSession LabPanel 'Defer
     ]

type LabSharedBundle =
    '[ Event LabCommitted '[ Field PanelId 'WireUUID ]
     , DomToken LabRoot
     , DomToken LabDropzone
     , Dto LabPayload
        '[ Field Label 'WireText
         , OptionalField Count 'WireInt
         , NullableField Note 'WireText
         , Field Tags ('WireList 'WireText)
         , Field DueDay 'WireDay
         , Field MaybeRank ('WireOptional 'WireInt)
         , Field MaybeMemo ('WireNullable 'WireText)
         , Field RelatedPayload ('WireRef LabRelatedPayload)
         ]
     , Dto LabRelatedPayload
        '[ Field Label 'WireText
         ]
     ]

type SurfaceLabSurface =
    Surface SurfaceLab (Concat '[ LabScopeBundle, LabFragmentBundle, LabInteractionBundle, LabSharedBundle ])
