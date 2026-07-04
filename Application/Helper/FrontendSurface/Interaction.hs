{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE PolyKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendSurface.Interaction
    ( CloneShadow
    , CurrentClientX
    , CurrentClientY
    , DeltaX
    , DeltaY
    , DragDropzoneRef
    , DragPreviewLayer
    , DragSession
    , DragSourceRef
    , DropzoneHighlight
    , PointerDragFields
    , PointerId
    , PointerType
    , SessionKind
    , RosterLayoutModeActivationRef
    , SourceItemKey
    , StartClientX
    , StartClientY
    , TargetDropzoneKey
    , DragDropInteraction
    , LayoutModeInteraction
    ) where

import Application.Helper.FrontendSurface.DSL
import Data.Kind (Type)

-- | Reusable browser interaction markers. Feature surfaces compose these via
-- type aliases such as 'DragDropInteraction' instead of re-declaring the common
-- pointer/session field vocabulary.
data DragSession
data DragPreviewLayer
data CloneShadow
data DropzoneHighlight
data DragSourceRef
data DragDropzoneRef
data RosterLayoutModeActivationRef

data SourceItemKey
data TargetDropzoneKey
data SessionKind
data PointerId
data PointerType
data StartClientX
data StartClientY
data CurrentClientX
data CurrentClientY
data DeltaX
data DeltaY

type PointerDragFields =
    '[ OptionalField SessionKind 'WireText
     , OptionalField PointerId 'WireText
     , OptionalField PointerType 'WireText
     , OptionalField StartClientX 'WireText
     , OptionalField StartClientY 'WireText
     , OptionalField CurrentClientX 'WireText
     , OptionalField CurrentClientY 'WireText
     , OptionalField DeltaX 'WireText
     , OptionalField DeltaY 'WireText
     ]

type DragDropFields =
    Concat
        '[ '[ Field SourceItemKey 'WireText
            , Field TargetDropzoneKey 'WireText
            ]
         , PointerDragFields
         ]

type DragDropInteraction (intent :: Type) (targetFragment :: Type) =
    '[ Session DragSession '[ 'Layer DragPreviewLayer, 'Effect CloneShadow '[ 'Layer DragPreviewLayer ], 'Effect DropzoneHighlight '[] ]
     , SourceRef DragSourceRef '[ 'SessionOption DragSession, 'Submits intent, 'SourceField SourceItemKey ]
     , DropzoneRef DragDropzoneRef '[ 'SessionOption DragSession, 'TargetField TargetDropzoneKey ]
     , Action intent DragDropFields '[ 'Target targetFragment ]
     , Intent intent DragDropFields '[ 'SessionOption DragSession, 'BackedBy intent ]
     , ConflictPolicyFor ('SessionKind DragSession) 'AnyFragment 'Defer
     ]

type LayoutModeInteraction (intent :: Type) (targetFragment :: Type) (layoutModeField :: Type) =
    '[ ActivationRef RosterLayoutModeActivationRef '[ 'Submits intent, 'ValueField layoutModeField ]
     , Action intent '[ Field layoutModeField 'WireText ] '[ 'Target targetFragment ]
     , Intent intent '[ Field layoutModeField 'WireText ] '[ 'BackedBy intent ]
     ]
