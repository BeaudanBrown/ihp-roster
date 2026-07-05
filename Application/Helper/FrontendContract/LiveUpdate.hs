{-# LANGUAGE DataKinds #-}

module Application.Helper.FrontendContract.LiveUpdate
    ( LiveUpdateContract
    ) where

import Application.Helper.FrontendContract.DSL hiding (Scope)

-- Live update websocket protocol. Surface scope and fragment key payloads are
-- semantic wire forms derived from registered Surface declarations by the
-- FrontendContract renderer.
data LiveUpdate

data SurfaceFragmentProtection
data None
data FocusedField

data ActiveSelector
data FieldKeyAttr
data FieldNameFallback
data ContainerSelector

data SurfaceWireFragment
data FragmentKey
data TargetId
data Url
data DeferUntilBlur
data ProtectionPolicy

data SurfaceSubscription
data Scope
data ScopeKey
data MountedFragments

data LiveUpdateCommand
data Subscribe
data Unsubscribe
data Subscription
data ClientId
data LastSeenVersion

data LiveUpdateMessage
data Subscribed
data Invalidate
data Error
data CurrentVersion
data Resync
data Version
data Fragments
data SourceClientId
data Message

type LiveUpdateContract =
    Global LiveUpdate
        '[ GlobalSchema (TaggedUnionWithTag SurfaceFragmentProtection "kind"
            '[ Case None '[]
             , Case FocusedField
                '[ Field ActiveSelector 'WireText
                 , Field FieldKeyAttr 'WireText
                 , Field FieldNameFallback 'WireBool
                 , NullableField ContainerSelector 'WireText
                 ]
             ])
         , GlobalSchema (Record SurfaceWireFragment
            '[ Field FragmentKey 'WireSurfaceFragmentKey
             , Field TargetId 'WireText
             , Field Url 'WireText
             , Field DeferUntilBlur 'WireBool
             , Field ProtectionPolicy ('WireRef SurfaceFragmentProtection)
             ])
         , GlobalSchema (Record SurfaceSubscription
            '[ Field Scope 'WireSurfaceScope
             , Field ScopeKey 'WireText
             , Field MountedFragments ('WireList ('WireRef SurfaceWireFragment))
             ])
         , GlobalSchema (TaggedUnionWithTag LiveUpdateCommand "type"
            '[ Case Subscribe
                '[ Field Subscription ('WireRef SurfaceSubscription)
                 , Field ClientId 'WireText
                 , NullableField LastSeenVersion 'WireInt
                 ]
             , Case Unsubscribe
                '[ Field Subscription ('WireRef SurfaceSubscription)
                 ]
             ])
         , GlobalSchema (TaggedUnionWithTag LiveUpdateMessage "type"
            '[ Case Subscribed
                '[ Field Scope 'WireSurfaceScope
                 , Field ScopeKey 'WireText
                 , Field CurrentVersion 'WireInt
                 , Field Resync 'WireBool
                 ]
             , Case Invalidate
                '[ Field Scope 'WireSurfaceScope
                 , Field ScopeKey 'WireText
                 , Field Version 'WireInt
                 , Field Fragments ('WireList ('WireRef SurfaceWireFragment))
                 , NullableField SourceClientId 'WireText
                 ]
             , Case Error
                '[ Field Message 'WireText
                 ]
             ])
         ]
