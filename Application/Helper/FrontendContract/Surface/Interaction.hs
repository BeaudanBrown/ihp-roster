{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE PolyKinds           #-}
{-# LANGUAGE QuasiQuotes         #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeFamilies        #-}
{-# LANGUAGE TypeOperators       #-}

module Application.Helper.FrontendContract.Surface.Interaction
    ( CloneShadow
    , CloneShadowCopy
    , Copy
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
    , CompatibleDropzoneOptions
    , DragDropFields
    , DragDropIntent
    , DragDropIntentWithExtraFields
    , DragDropInteraction
    , DragDropInteractionWithExtraFields
    , DragDropInteractionWithRefs
    , DragDropInteractionWithRefsAndVariants
    , DragDropInteractionWithRefsVariantsAndExtraFields
    , DragDropInteractionWithVariants
    , DragDropzoneRefFor
    , DragSessionDefinition
    , DragSourceRefFor
    , LayoutModeInteraction
    , frontendSurfaceActivationRefAttribute
    , frontendSurfaceDropzoneKeyAttribute
    , frontendSurfaceDropzoneRefAttribute
    , frontendSurfaceSourceKeyAttribute
    , frontendSurfaceSourceRefAttribute
    , renderFrontendSurfaceActivationRef
    , renderFrontendSurfaceDropzoneRef
    , renderFrontendSurfaceSourceRef
    , frontendSurfaceActivationRefAttrs
    , frontendSurfaceDropzoneRefAttrs
    , frontendSurfaceSourceRefAttrs
    ) where

import qualified Application.Helper.FrontendContract.Interaction as Interaction
import Application.Helper.FrontendContract.Naming (deriveDomAttributeTypeName)
import Application.Helper.FrontendContract.Surface.ContractIR
import Application.Helper.FrontendContract.Surface.DSL
import IHP.Prelude
import IHP.HSX.MarkupQQ (hsx)
import IHP.HSX.Markup (Html)

frontendSurfaceSourceRefAttribute :: Text
frontendSurfaceSourceRefAttribute = deriveDomAttributeTypeName @Interaction.SourceRef

frontendSurfaceSourceKeyAttribute :: Text
frontendSurfaceSourceKeyAttribute = deriveDomAttributeTypeName @Interaction.SourceKey

frontendSurfaceDropzoneRefAttribute :: Text
frontendSurfaceDropzoneRefAttribute = deriveDomAttributeTypeName @Interaction.DropzoneRef

frontendSurfaceDropzoneKeyAttribute :: Text
frontendSurfaceDropzoneKeyAttribute = deriveDomAttributeTypeName @Interaction.DropzoneKey

frontendSurfaceActivationRefAttribute :: Text
frontendSurfaceActivationRefAttribute = deriveDomAttributeTypeName @Interaction.ActivationRef

renderFrontendSurfaceSourceRef :: InteractionSourceRefIR -> Text -> Html -> Html
renderFrontendSurfaceSourceRef ref key body =
    [hsx|<div {...(frontendSurfaceSourceRefAttrs ref key)}>{body}</div>|]

frontendSurfaceSourceRefAttrs :: InteractionSourceRefIR -> Text -> [(Text, Text)]
frontendSurfaceSourceRefAttrs ref key =
    [ (frontendSurfaceSourceRefAttribute, ref.sourceRefName)
    , (frontendSurfaceSourceKeyAttribute, key)
    ]

renderFrontendSurfaceDropzoneRef :: InteractionDropzoneRefIR -> Text -> Html -> Html
renderFrontendSurfaceDropzoneRef ref key body =
    [hsx|<div {...(frontendSurfaceDropzoneRefAttrs ref key)}>{body}</div>|]

frontendSurfaceDropzoneRefAttrs :: InteractionDropzoneRefIR -> Text -> [(Text, Text)]
frontendSurfaceDropzoneRefAttrs ref key =
    [ (frontendSurfaceDropzoneRefAttribute, ref.dropzoneRefName)
    , (frontendSurfaceDropzoneKeyAttribute, key)
    ]

renderFrontendSurfaceActivationRef :: InteractionActivationRefIR -> Html -> Html
renderFrontendSurfaceActivationRef ref body =
    [hsx|<div {...(frontendSurfaceActivationRefAttrs ref)}>{body}</div>|]

frontendSurfaceActivationRefAttrs :: InteractionActivationRefIR -> [(Text, Text)]
frontendSurfaceActivationRefAttrs ref =
    [(frontendSurfaceActivationRefAttribute, ref.activationRefName)]

-- | Reusable browser interaction markers. Feature surfaces compose these via
-- type aliases such as 'DragDropInteraction' instead of re-declaring the common
-- pointer/session field vocabulary.
data DragSession
data DragPreviewLayer

type CloneShadow layer = 'CloneShadowEffect 'StandardCloneShadow layer
type CloneShadowCopy layer = 'CloneShadowEffect 'CopyCloneShadow layer
type DropzoneHighlight = 'DropzoneHighlightEffect

data Copy
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

type family CompatibleDropzoneOptions (dropzoneRefs :: [Type]) :: [PrimitiveOption] where
    CompatibleDropzoneOptions '[] = '[]
    CompatibleDropzoneOptions (dropzoneRef ': rest) = 'CompatibleDropzone dropzoneRef ': CompatibleDropzoneOptions rest

type DragSessionDefinition =
    Session DragSession '[ 'Layer DragPreviewLayer, 'Effect (CloneShadow DragPreviewLayer), 'Effect DropzoneHighlight ]

type DragSourceRefFor (sourceRef :: Type) (intent :: Type) (compatibleDropzoneRefs :: [Type]) (variants :: [PrimitiveOption]) =
    SourceRef sourceRef (Concat '[ '[ 'SessionOption DragSession, 'Submits intent, 'SourceField SourceItemKey ], CompatibleDropzoneOptions compatibleDropzoneRefs, variants ])

type DragDropzoneRefFor (dropzoneRef :: Type) =
    DropzoneRef dropzoneRef '[ 'SessionOption DragSession, 'TargetField TargetDropzoneKey ]

type DragDropIntent (intent :: Type) (targetFragment :: Type) =
    DragDropIntentWithExtraFields intent targetFragment '[]

type DragDropIntentWithExtraFields (intent :: Type) (targetFragment :: Type) (extraFields :: [FieldSpec]) =
    '[ Action intent (Concat '[ DragDropFields, extraFields ]) '[ 'Target targetFragment ]
     , Intent intent (Concat '[ DragDropFields, extraFields ]) '[ 'SessionOption DragSession, 'BackedBy intent ]
     ]

type DragDropInteraction (intent :: Type) (targetFragment :: Type) =
    DragDropInteractionWithVariants intent targetFragment '[]

type DragDropInteractionWithExtraFields (intent :: Type) (targetFragment :: Type) (extraFields :: [FieldSpec]) =
    DragDropInteractionWithRefsVariantsAndExtraFields DragSourceRef DragDropzoneRef intent targetFragment '[] extraFields

type DragDropInteractionWithVariants (intent :: Type) (targetFragment :: Type) (variants :: [PrimitiveOption]) =
    DragDropInteractionWithRefsAndVariants DragSourceRef DragDropzoneRef intent targetFragment variants

type DragDropInteractionWithRefs (sourceRef :: Type) (dropzoneRef :: Type) (intent :: Type) (targetFragment :: Type) =
    DragDropInteractionWithRefsAndVariants sourceRef dropzoneRef intent targetFragment '[]

type DragDropInteractionWithRefsAndVariants (sourceRef :: Type) (dropzoneRef :: Type) (intent :: Type) (targetFragment :: Type) (variants :: [PrimitiveOption]) =
    DragDropInteractionWithRefsVariantsAndExtraFields sourceRef dropzoneRef intent targetFragment variants '[]

type DragDropInteractionWithRefsVariantsAndExtraFields (sourceRef :: Type) (dropzoneRef :: Type) (intent :: Type) (targetFragment :: Type) (variants :: [PrimitiveOption]) (extraFields :: [FieldSpec]) =
    '[ DragSessionDefinition
     , SourceRef sourceRef (Concat '[ '[ 'SessionOption DragSession, 'Submits intent, 'SourceField SourceItemKey, 'CompatibleDropzone dropzoneRef ], variants ])
     , DragDropzoneRefFor dropzoneRef
     , Action intent (Concat '[ DragDropFields, extraFields ]) '[ 'Target targetFragment ]
     , Intent intent (Concat '[ DragDropFields, extraFields ]) '[ 'SessionOption DragSession, 'BackedBy intent ]
     , ConflictPolicyFor ('SessionKind DragSession) 'AnyFragment 'Defer
     ]

type LayoutModeInteraction (intent :: Type) (targetFragment :: Type) (layoutModeField :: Type) (layoutModeWire :: WireType) =
    '[ ActivationRef RosterLayoutModeActivationRef '[ 'Submits intent, 'ValueField layoutModeField ]
     , Action intent '[ Field layoutModeField layoutModeWire ] '[ 'Target targetFragment ]
     , Intent intent '[ Field layoutModeField layoutModeWire ] '[ 'BackedBy intent ]
     ]
