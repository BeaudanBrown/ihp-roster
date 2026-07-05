{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE PolyKinds           #-}
{-# LANGUAGE TypeOperators       #-}

module Application.Helper.FrontendContract.Surface.Interaction
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
    , frontendSurfaceActivationRefAttribute
    , frontendSurfaceDropzoneKeyAttribute
    , frontendSurfaceDropzoneRefAttribute
    , frontendSurfaceSourceKeyAttribute
    , frontendSurfaceSourceRefAttribute
    , renderFrontendSurfaceActivationRef
    , renderFrontendSurfaceDropzoneRef
    , renderFrontendSurfaceSourceRef
    , withFrontendSurfaceActivationRef
    , withFrontendSurfaceDropzoneRef
    , withFrontendSurfaceSourceRef
    ) where

import Application.Helper.FrontendContract.Surface.ContractIR
import Application.Helper.FrontendContract.Surface.DSL
import Data.Kind (Type)
import IHP.Prelude
import qualified Text.Blaze.Html as Blaze
import qualified Text.Blaze.Html5 as Html5
import Text.Blaze.Html5 ((!))

type Html = Blaze.Html

frontendSurfaceSourceRefAttribute :: Text
frontendSurfaceSourceRefAttribute = "data-bepis-source-ref"

frontendSurfaceSourceKeyAttribute :: Text
frontendSurfaceSourceKeyAttribute = "data-bepis-source-key"

frontendSurfaceDropzoneRefAttribute :: Text
frontendSurfaceDropzoneRefAttribute = "data-bepis-dropzone-ref"

frontendSurfaceDropzoneKeyAttribute :: Text
frontendSurfaceDropzoneKeyAttribute = "data-bepis-dropzone-key"

frontendSurfaceActivationRefAttribute :: Text
frontendSurfaceActivationRefAttribute = "data-bepis-activation-ref"

renderFrontendSurfaceSourceRef :: InteractionSourceRefIR -> Text -> Html -> Html
renderFrontendSurfaceSourceRef ref key =
    Html5.div
        ! attr frontendSurfaceSourceRefAttribute ref.sourceRefName
        ! attr frontendSurfaceSourceKeyAttribute key

withFrontendSurfaceSourceRef :: InteractionSourceRefIR -> Text -> Html -> Html
withFrontendSurfaceSourceRef ref key html =
    html
        ! attr frontendSurfaceSourceRefAttribute ref.sourceRefName
        ! attr frontendSurfaceSourceKeyAttribute key

renderFrontendSurfaceDropzoneRef :: InteractionDropzoneRefIR -> Text -> Html -> Html
renderFrontendSurfaceDropzoneRef ref key =
    Html5.div
        ! attr frontendSurfaceDropzoneRefAttribute ref.dropzoneRefName
        ! attr frontendSurfaceDropzoneKeyAttribute key

withFrontendSurfaceDropzoneRef :: InteractionDropzoneRefIR -> Text -> Html -> Html
withFrontendSurfaceDropzoneRef ref key html =
    html
        ! attr frontendSurfaceDropzoneRefAttribute ref.dropzoneRefName
        ! attr frontendSurfaceDropzoneKeyAttribute key

renderFrontendSurfaceActivationRef :: InteractionActivationRefIR -> Html -> Html
renderFrontendSurfaceActivationRef ref =
    Html5.div
        ! attr frontendSurfaceActivationRefAttribute ref.activationRefName

withFrontendSurfaceActivationRef :: InteractionActivationRefIR -> Html -> Html
withFrontendSurfaceActivationRef ref html =
    html ! attr frontendSurfaceActivationRefAttribute ref.activationRefName

attr :: Text -> Text -> Blaze.Attribute
attr name value =
    Blaze.customAttribute (Blaze.textTag name) (Blaze.toValue value)

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
