{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendSurface.Lab
    ( SurfaceLabSurface
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
data Label
data Count
data Note

data Load
data Panel

type LabScopeBundle =
    '[ Scope LabScope
        '[ Field VenueId 'WireUUID
         , Field WeekOffset 'WireInt
         ]
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
     , HtmxAction RefreshPanel
        '[ Field PanelId 'WireUUID ]
        '[ 'Target LabPanel ]
     ]

type LabInteractionBundle =
    '[ Intent MoveLabCard
        '[ Field SourceItemKey 'WireText
         , Field TargetDropzoneKey 'WireText
         ]
        '[ 'BackedBy RefreshPanel ]
     , Session DragSession '[]
     , DisposableLayer DragPreview
     , InteractionEffect CloneShadow '[ 'Layer DragPreview ]
     , InteractionEffect DropzoneHighlight '[]
     , ConflictPolicy DragSession LabPanel 'Defer
     ]

type LabSharedBundle =
    '[ LoadPolicy Panel
     , OverlayLane Dialog
     , ClientEvent LabCommitted '[ Field PanelId 'WireUUID ]
     , DomToken LabRoot
     , DomToken LabDropzone
     , Dto LabPayload
        '[ Field Label 'WireText
         , OptionalField Count 'WireInt
         , NullableField Note 'WireText
         ]
     ]

type SurfaceLabSurface =
    Surface SurfaceLab (Concat '[ LabScopeBundle, LabFragmentBundle, LabInteractionBundle, LabSharedBundle ])
