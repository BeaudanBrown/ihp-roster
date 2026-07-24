{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.Toggle
    ( ToggleContract
    , Toggle
    , TogglePresentationState
    , Checked
    , Unchecked
    , ToggleSubmissionPolicy
    , Deferred
    , Immediate
    , ToggleTarget
    , Value
    , Omitted
    , ToggleConfig
    , PresentationState
    , CheckedTarget
    , UncheckedTarget
    , TransportKey
    , SubmissionPolicy
    , BreakRegionKey
    , ToggleRoot
    , ToggleInput
    , ToggleLabelState
    , ToggleTransport
    , ToggleBreakRegion
    ) where

import Application.Helper.FrontendContract.DSL

-- | Reusable browser toggle capability. Haskell owns concrete field bindings,
-- target values, presentation state, labels, and submission policy; the browser
-- receives only this exact mechanical state/configuration boundary.
data Toggle

data TogglePresentationState
data Checked
data Unchecked

data ToggleSubmissionPolicy
data Deferred
data Immediate

data ToggleTarget
data Value
data Omitted

data ToggleConfig
data PresentationState
data CheckedTarget
data UncheckedTarget
data TransportKey
data SubmissionPolicy
data BreakRegionKey

data ToggleRoot
data ToggleInput
data ToggleLabelState
data ToggleTransport
data ToggleBreakRegion

type ToggleContract =
    Global Toggle
        '[ BrowserGuardSchema (Enum TogglePresentationState '[Checked, Unchecked])
         , BrowserGuardSchema (Enum ToggleSubmissionPolicy '[Deferred, Immediate])
         , BrowserGuardSchema (TaggedUnion ToggleTarget
            '[ Case Value '[Field Value 'WireText]
             , Case Omitted '[]
             ])
         , BrowserInboundSchema (Record ToggleConfig
            '[ Field PresentationState ('WireRef TogglePresentationState)
             , Field CheckedTarget ('WireRef ToggleTarget)
             , Field UncheckedTarget ('WireRef ToggleTarget)
             , Field TransportKey 'WireText
             , Field SubmissionPolicy ('WireRef ToggleSubmissionPolicy)
             , NullableField BreakRegionKey 'WireText
             ])
         , DomAttr ToggleRoot
         , DomAttr ToggleInput
         , DomAttr ToggleLabelState
         , DomAttr ToggleTransport
         , DomAttr ToggleBreakRegion
         , DomAttr ToggleConfig
         ]
