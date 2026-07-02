{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE PolyKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendSurface.Interaction
    ( CloneShadow
    , CurrentClientX
    , CurrentClientY
    , DeltaX
    , DeltaY
    , DragPreviewLayer
    , DragSession
    , DropzoneHighlight
    , PointerDragFields
    , PointerId
    , PointerType
    , SessionKind
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
    '[ Session DragSession '[]
     , DisposableLayer DragPreviewLayer
     , InteractionEffect CloneShadow '[ 'Layer DragPreviewLayer ]
     , InteractionEffect DropzoneHighlight '[]
     , HtmxAction intent DragDropFields '[ 'Target targetFragment ]
     , Intent intent DragDropFields '[ 'SessionOption DragSession, 'BackedBy intent ]
     , ConflictPolicyFor 'AnySession 'AnyFragment 'Defer
     ]

type LayoutModeInteraction (intent :: Type) (targetFragment :: Type) (layoutModeField :: Type) =
    '[ HtmxAction intent '[ Field layoutModeField 'WireText ] '[ 'Target targetFragment ]
     , Intent intent '[ Field layoutModeField 'WireText ] '[ 'BackedBy intent ]
     ]
