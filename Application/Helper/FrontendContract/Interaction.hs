{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.Interaction
    ( InteractionContract
    , Interaction
    ) where

import qualified Application.Helper.FrontendContract.App as App
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
data DropzoneHighlight
data Source
data ClassName
data PreserveGrabOffset
data Kind

data InteractionSessionEffects
data Global
data Contextual

data InteractionSessionSelector
data Any
data Session

data InteractionFragmentSelector
data LiveFragment

data InteractionMountMetadata
data MountId

data ServerLayerContract
data Name
data DomId

data DisposableLayerContract

data SessionKindContract
data Description

data IntentFieldSchema
data Presence
data DefaultValue

data Value

data InteractionIntentTarget
data MountLocal
data Target

data IntentFormContract
data Method
data Action
data Trigger
data Swap
data Fields
data HiddenFields
data Sync
data DisabledElement

data InteractionConflictPolicy
data Fragment
data Resolution
data TimeoutMs

data InteractionCapabilityContract
data Mount
data ServerLayers
data DisposableLayers
data SessionKinds
data IntentForms

data InteractionStaticServerLayer
data DomIdSuffix

data InteractionStaticDisposableLayer

data InteractionStaticSessionKind
data Effects

data InteractionStaticIntent

data InteractionStaticSchema
data Intents

data Surface
data SurfaceFamily
data ScopeKey
data MountKey
data SessionDisabled
data SessionReadOnly
data SessionThreshold
data SessionTimeoutMs
data InteractionActive
data ServerLayer
data DisposableLayer
data Layer
data ConflictPolicies
data IntentForm
data Intent
data IntentField
data FieldPresence
data IntentHiddenField

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
        '[ GlobalSchema (Enum InteractionActivationTrigger '[Click, Change, KeydownEnter, KeydownSpace])
         , GlobalSchema (Enum InteractionFieldPresence '[Required, Optional])
         , GlobalSchema (Enum InteractionConflictResolution '[Apply, Defer, Cancel])
         , GlobalSchema (Enum InteractionEffectSource '[PointerMarker])
         , GlobalSchema (TaggedUnionWithTag InteractionSessionEffect "kind"
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
         , GlobalSchema (Record InteractionSessionEffects
            '[ Field Global ('WireList ('WireRef InteractionSessionEffect))
             , Field Contextual ('WireList ('WireRef InteractionSessionEffect))
             ])
         , GlobalSchema (TaggedUnionWithTag InteractionSessionSelector "kind"
            '[ Case Any '[]
             , Case Session
                '[ Field Session 'WireText
                 ]
             ])
         , GlobalSchema (TaggedUnionWithTag InteractionFragmentSelector "kind"
            '[ Case Any '[]
             , Case LiveFragment
                '[ Field Fragment 'WireSurfaceFragmentKey
                 ]
             ])
         , GlobalSchema (Record InteractionMountMetadata
            '[ Field SurfaceFamily 'WireText
             , Field ScopeKey 'WireText
             , Field MountKey 'WireText
             , Field MountId 'WireText
             ])
         , GlobalSchema (Record ServerLayerContract
            '[ Field Name 'WireText
             , Field DomId 'WireText
             ])
         , GlobalSchema (Record DisposableLayerContract
            '[ Field Kind 'WireText
             , Field Name 'WireText
             , Field DomId 'WireText
             ])
         , GlobalSchema (Record SessionKindContract
            '[ Field Kind 'WireText
             , Field Description 'WireText
             ])
         , GlobalSchema (Record IntentFieldSchema
            '[ Field Name 'WireText
             , Field Presence ('WireRef InteractionFieldPresence)
             , OptionalField DefaultValue ('WireNullable 'WireText)
             ])
         , GlobalSchema (Record IntentHiddenField
            '[ Field Name 'WireText
             , Field Value 'WireText
             ])
         , GlobalSchema (TaggedUnionWithTag InteractionIntentTarget "kind"
            '[ Case LiveFragment
                '[ Field Fragment 'WireSurfaceWireFragment
                 ]
             , Case MountLocal
                '[ Field Target 'WireText
                 ]
             ])
         , GlobalSchema (Record IntentFormContract
            '[ Field Intent 'WireText
             , Field Name 'WireText
             , Field Action 'WireText
             , Field Method ('WireRef App.HtmxActionMethod)
             , Field Trigger 'WireText
             , Field Target ('WireRef InteractionIntentTarget)
             , Field Swap ('WireRef App.HtmxActionSwap)
             , Field Fields ('WireList ('WireRef IntentFieldSchema))
             , Field HiddenFields ('WireList ('WireRef IntentHiddenField))
             , OptionalField Sync ('WireNullable 'WireText)
             , OptionalField DisabledElement ('WireNullable 'WireText)
             ])
         , GlobalSchema (Record InteractionConflictPolicy
            '[ Field Session ('WireRef InteractionSessionSelector)
             , Field Fragment ('WireRef InteractionFragmentSelector)
             , Field Resolution ('WireRef InteractionConflictResolution)
             , OptionalField TimeoutMs ('WireNullable 'WireInt)
             ])
         , GlobalSchema (Record InteractionCapabilityContract
            '[ Field Mount ('WireRef InteractionMountMetadata)
             , Field ServerLayers ('WireList ('WireRef ServerLayerContract))
             , Field DisposableLayers ('WireList ('WireRef DisposableLayerContract))
             , Field SessionKinds ('WireList ('WireRef SessionKindContract))
             , Field IntentForms ('WireList ('WireRef IntentFormContract))
             , Field ConflictPolicies ('WireList ('WireRef InteractionConflictPolicy))
             ])
         , GlobalSchema (Record InteractionStaticServerLayer
            '[ Field Name 'WireText
             , Field DomIdSuffix 'WireText
             ])
         , GlobalSchema (Record InteractionStaticDisposableLayer
            '[ Field Name 'WireText
             , Field DomIdSuffix 'WireText
             ])
         , GlobalSchema (Record InteractionStaticSessionKind
            '[ Field Kind 'WireText
             , Field Description 'WireText
             , Field Effects ('WireRef InteractionSessionEffects)
             ])
         , GlobalSchema (Record InteractionStaticIntent
            '[ Field Name 'WireText
             , Field Fields ('WireList ('WireRef IntentFieldSchema))
             ])
         , GlobalSchema (Record InteractionStaticSchema
            '[ Field ServerLayers ('WireList ('WireRef InteractionStaticServerLayer))
             , Field DisposableLayers ('WireList ('WireRef InteractionStaticDisposableLayer))
             , Field SessionKinds ('WireList ('WireRef InteractionStaticSessionKind))
             , Field Intents ('WireList ('WireRef InteractionStaticIntent))
             , Field ConflictPolicies ('WireList ('WireRef InteractionConflictPolicy))
             ])
         , DomAttr Surface
         , DomAttr SurfaceFamily
         , DomAttr ScopeKey
         , DomAttr MountKey
         , DomAttr SessionDisabled
         , DomAttr SessionReadOnly
         , DomAttr SessionThreshold
         , DomAttr SessionTimeoutMs
         , DomAttr InteractionActive
         , DomAttr ServerLayer
         , DomAttr DisposableLayer
         , DomAttr Layer
         , DomAttr ConflictPolicies
         , DomAttr IntentForm
         , DomAttr Intent
         , DomAttr IntentField
         , DomAttr FieldPresence
         , DomAttr IntentHiddenField
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
         , FieldName SourceItemKey
         , FieldName TargetDropzoneKey
         ]
