{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.Interaction
    ( InteractionContract
    , Interaction
    , Surface
    , SurfaceFamily
    , SessionDisabled
    , SessionReadOnly
    , SessionThreshold
    , SessionTimeoutMs
    , InteractionActive
    , DisposableLayer
    , ConflictPolicies
    , IntentForm
    , Intent
    , IntentField
    , FieldPresence
    , SourceRef
    , SourceKey
    , DropzoneRef
    , DropzoneKey
    , ActivationRef
    , ActiveSourceRef
    , CloneShadow
    , CloneShadowCopy
    , DropzoneHighlight
    , PointerMarker
    , BepisPointerCloneShadow
    , BepisPointerCloneShadowCopy
    , BepisDropzoneHighlight
    ) where

import Application.Helper.FrontendContract.DSL hiding (Action, DomId, Fragment,
                                                Global, Intent, Surface)
import qualified Application.Helper.FrontendContract.DSL as DSL

data Interaction

data InteractionActivationTrigger
data Click
data Change
data KeydownEnter
data KeydownSpace

data InteractionFieldPresence
data Required
data Optional

data InteractionConflictResolution
data Apply
data Defer
data Cancel

data InteractionEffectSource
data PointerMarker

data InteractionSessionEffect
data CloneShadow
data CloneShadowCopy
data DropzoneHighlight
data BepisPointerCloneShadow
data BepisPointerCloneShadowCopy
data BepisDropzoneHighlight
data Source
data ClassName
data PreserveGrabOffset
data Surface
data SurfaceFamily
data SessionDisabled
data SessionReadOnly
data SessionThreshold
data SessionTimeoutMs
data InteractionActive
data DisposableLayer
data Layer
data ConflictPolicies
data IntentForm
data Intent
data IntentField
data FieldPresence
data SourceRef
data SourceKey
data DropzoneRef
data DropzoneKey
data ActivationRef
data ActiveSourceRef

data Enabled

data SessionKind
data PointerId
data PointerType
data StartClientX
data StartClientY
data CurrentClientX
data CurrentClientY
data DeltaX
data DeltaY
data SourceItemKey
data TargetDropzoneKey

type InteractionContract =
    DSL.Global Interaction
        '[ BrowserTypeSchema (Enum InteractionActivationTrigger '[Click, Change, KeydownEnter, KeydownSpace])
         , BrowserGuardSchema (Enum InteractionFieldPresence '[Required, Optional])
         , BrowserGuardSchema (Enum InteractionConflictResolution '[Apply, Defer, Cancel])
         , BrowserTypeSchema (Enum InteractionEffectSource '[PointerMarker])
         , BrowserTypeSchema (TaggedUnionWithTag InteractionSessionEffect "kind"
            '[ Case CloneShadow
                '[ Field Layer 'WireText
                 , Field Source ('WireRef InteractionEffectSource)
                 , Field ClassName 'WireText
                 , Field PreserveGrabOffset 'WireBool
                 ]
             , Case DropzoneHighlight
                '[ Field ClassName 'WireText
                 ]
             ])
         , DomAttr Surface
         , DomAttr SurfaceFamily
         , DomAttr SessionDisabled
         , DomAttr SessionReadOnly
         , DomAttr SessionThreshold
         , DomAttr SessionTimeoutMs
         , DomAttr InteractionActive
         , DomAttr DisposableLayer
         , DomAttr ConflictPolicies
         , DomAttr IntentForm
         , DomAttr Intent
         , DomAttr IntentField
         , DomAttr FieldPresence
         , DomAttr SourceRef
         , DomAttr SourceKey
         , DomAttr DropzoneRef
         , DomAttr DropzoneKey
         , DomAttr ActivationRef
         , DomAttr ActiveSourceRef
         , DomValue Enabled "true"
         , FieldName SessionKind
         , FieldName PointerId
         , FieldName PointerType
         , FieldName StartClientX
         , FieldName StartClientY
         , FieldName CurrentClientX
         , FieldName CurrentClientY
         , FieldName DeltaX
         , FieldName DeltaY
         , ProjectInteractionDom
         ]
