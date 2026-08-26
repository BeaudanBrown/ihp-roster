{-# LANGUAGE DataKinds #-}

module Application.Helper.FrontendContract.LiveUpdate
    ( LiveUpdateContract
    , LiveUpdateSocketPath
    , SurfaceAction
    , SurfaceConfig
    , SurfaceSubscription
    , Scope
    , ScopeKey
    , Fragments
    , RenderedDependencyWatermark
    , LiveUpdateCommand
    , Subscribe
    , Unsubscribe
    , Subscription
    , LastSeenVersion
    , LiveUpdateMessage
    , Subscribed
    , Invalidate
    , Error
    , CurrentVersion
    , Resync
    , Version
    , Message
    ) where

import Application.Helper.FrontendContract.DSL hiding (Scope)

-- Live update websocket and actor-local protocol. Surface scope and fragment
-- key payloads are semantic wire forms derived from registered Surface
-- declarations. Executable mount descriptors are deliberately not part of
-- this contract.
data LiveUpdate

data LiveUpdateSocketPath
data SurfaceConfig
data SurfaceAction

data SurfaceSubscription
data Scope
data ScopeKey
data Fragments
data RenderedDependencyWatermark

data LiveUpdateCommand
data Subscribe
data Unsubscribe
data Subscription
data LastSeenVersion

data LiveUpdateMessage
data Subscribed
data Invalidate
data Error
data CurrentVersion
data Resync
data Version
data Message

type LiveUpdateContract =
    Global LiveUpdate
        '[ Constant LiveUpdateSocketPath "live-updates"
         , DomAttr SurfaceConfig
         , DomAttr SurfaceAction
         , BrowserTypeSchema (Record SurfaceSubscription
            '[ Field Scope 'WireSurfaceScope
             , Field ScopeKey 'WireText
             , Field Fragments ('WireList 'WireSurfaceFragmentKey)
             , Field RenderedDependencyWatermark 'WireInt
             ])
         , BrowserOutboundSchema (TaggedUnionWithTag LiveUpdateCommand "type"
            '[ Case Subscribe
                '[ Field Subscription ('WireRef SurfaceSubscription)
                 , NullableField LastSeenVersion 'WireInt
                 ]
             , Case Unsubscribe
                '[ Field Subscription ('WireRef SurfaceSubscription)
                 ]
             ])
         , BrowserInboundSchema (TaggedUnionWithTag LiveUpdateMessage "type"
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
                 , Field Fragments ('WireList 'WireSurfaceFragmentKey)
                 ]
             , Case Error
                '[ Field Message 'WireText
                 ]
             ])
         ]
