{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE PolyKinds            #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}

module Application.Helper.FrontendContract.Surface.DSL
    ( SurfaceSpec (..)
    , SurfacePrimitive (..)
    , DependencySource (..)
    , FieldSpec (..)
    , ResourceSpec (..)
    , ScopeOption (..)
    , AuthPolicy (..)
    , InteractionEffect (..)
    , InteractionSessionOption (..)
    , LinkedHighlightActivation (..)
    , LinkedHighlightEffect (..)
    , CompleteSetSortValueType (..)
    , CompleteSetSortComparatorDirection (..)
    , CompleteSetSortComparator (..)
    , CompleteSetSortKeySpec (..)
    , CompleteSetSortDirection (..)
    , CloneShadowStyle (..)
    , BrowserReachability (..)
    , WireType (..)
    , PrimitiveOption (..)
    , HtmxMethod (..)
    , HtmxPushUrl (..)
    , HtmxSelectorSpec (..)
    , HtmxSwapSpec (..)
    , HtmxSyncSpec (..)
    , HtmxSyncStrategy (..)
    , HtmxTriggerSpec (..)
    , ConflictResolution (..)
    , FragmentSelector (..)
    , SessionSelector (..)
    , Surface
    , Scope
    , Fragment
    , Resource
    , Action
    , Intent
    , Field
    , OptionalField
    , NullableField
    , MountState
    , Session
    , SourceRef
    , DropzoneRef
    , ActivationRef
    , BrowserRole
    , BrowserState
    , BrowserClosedState
    , LinkedHighlight
    , CompleteSetSort
    , TabSet
    , SidePanel
    , ConflictPolicy
    , ConflictPolicyFor
    , Event
    , DomToken
    , BrowserDomToken
    , Dto
    , BrowserTypeDto
    , BrowserGuardDto
    , BrowserInboundDto
    , BrowserOutboundDto
    , BrowserBidirectionalDto
    , ContainsSurface
    , DependsOnFragment
    , Append
    , Concat
    ) where

import Application.Helper.FrontendContract.DSL (BrowserReachability (..))
import Data.Kind (Type)
import GHC.TypeLits (Symbol)

data WireType
    = WireText
    | WireInt
    | WireBool
    | WireUUID
    | WireDay
    | WireClosed Type
    | WireDomain Type
    | WireList WireType
    | WireOptional WireType
    | WireNullable WireType
    | WireRef Type

data FieldSpec
    = Field Type WireType
    | OptionalField Type WireType
    | NullableField Type WireType

data ResourceSpec
    = Resource Type [FieldSpec]

data HtmxMethod
    = HtmxGet
    | HtmxPost
    | HtmxPut
    | HtmxPatch
    | HtmxDelete

data HtmxPushUrl
    = HtmxPushUrlTrue
    | HtmxPushUrlFalse

data HtmxSelectorSpec
    = HtmxId Type
    | HtmxClass Type
    | HtmxClosest HtmxSelectorSpec
    | HtmxFind HtmxSelectorSpec
    | HtmxThis
    | HtmxDocument
    | HtmxWindow
    | HtmxBody
    | HtmxRawSelector Symbol Symbol

data HtmxTriggerSpec
    = HtmxClick
    | HtmxChange
    | HtmxLoad
    | HtmxCustomEvent Type
    | HtmxRawTrigger Symbol Symbol

data HtmxSwapSpec
    = HtmxInnerHTML
    | HtmxOuterHTML
    | HtmxBeforeEnd
    | HtmxAfterBegin
    | HtmxNoSwap
    | HtmxRawSwap Symbol Symbol

data HtmxSyncStrategy
    = HtmxSyncDrop
    | HtmxSyncAbort
    | HtmxSyncReplace
    | HtmxSyncQueueFirst
    | HtmxSyncQueueAll
    | HtmxSyncQueueLast

data HtmxSyncSpec
    = HtmxSyncOn HtmxSelectorSpec HtmxSyncStrategy
    | HtmxRawSync Symbol Symbol

data DependencySource
    = FromScope Type
    | FromFragment Type

data AuthPolicy
    = CurrentVenue
    | CurrentVenueUser
    | CurrentVenueStaff
    | CurrentVenueRosterGroup
    | CurrentVenueAdmin
    | CurrentVenueManager
    | CurrentVenueOwner
    | CurrentVenueAdminRosterGroup
    | SupportSuperAdmin

data ScopeOption
    = Authorize AuthPolicy [Type]
    | NoAuth

data CloneShadowStyle
    = StandardCloneShadow
    | CopyCloneShadow

data InteractionEffect
    = CloneShadowEffect CloneShadowStyle Type
    | DropzoneHighlightEffect

data InteractionSessionOption
    = Layer Type
    | Effect InteractionEffect

-- | Closed activation mechanics supported by the generic linked-highlight
-- runtime. A pin activation names the Surface-owned browser role rendered on
-- the matching toggle controls.
data LinkedHighlightActivation
    = ActivateOnHover
    | ActivateOnFocus
    | ActivateOnKeyboard
    | ActivateWithPin Type
    | ActivateWithDefault Type

-- | Closed presentation effects supported by linked highlighting. CSS class
-- names remain browser-module-owned transient state; Haskell selects only the
-- allowed mechanical effect. Ordered bounds name the Surface-owned state attr
-- carrying an opaque order-group key.
data LinkedHighlightEffect
    = HighlightMatchingSource
    | HighlightMatchingMember
    | HighlightOrderedMemberBounds Type

-- | Value interpretation is closed so the browser can compare generated row
-- payloads without recovering semantics from field or feature names.
data CompleteSetSortValueType
    = SortText
    | SortInteger
    | SortOpaque

-- | A comparator either follows the selected ascending/descending direction or
-- remains ascending as a deterministic tie-breaker.
data CompleteSetSortComparatorDirection
    = FollowSortDirection
    | AlwaysAscending

data CompleteSetSortComparator
    = SortComparator Type CompleteSetSortValueType CompleteSetSortComparatorDirection

data CompleteSetSortKeySpec
    = SortKey Type [CompleteSetSortComparator]

data CompleteSetSortDirection
    = SortAscending
    | SortDescending

data PrimitiveOption
    = Eager
    | Lazy [PrimitiveOption]
    | Live
    | ResyncOnly
    | Trigger Type
    | Placeholder Type
    | DependsOn ResourceSpec [DependencySource]
    | DependsOnFragment Type
    | MountTarget Type [FieldSpec]
    | Target Type
    | BackedBy Type
    | ModifierVariant Type Type [InteractionEffect]
    | SessionOption Type
    | Submits Type
    | SourceField Type
    | TargetField Type
    | CompatibleDropzone Type
    | ValueField Type
    | Emits Type
    | Contains Type
    | ContainsSurface Type
    | UsesDto Type
    | HtmxMethod HtmxMethod
    | HtmxTrigger HtmxTriggerSpec
    | HtmxInclude HtmxSelectorSpec
    | HtmxSync HtmxSyncSpec
    | HtmxIndicator HtmxSelectorSpec
    | HtmxConfirm Type
    | HtmxSelect HtmxSelectorSpec
    | HtmxTarget HtmxSelectorSpec
    | HtmxSwap HtmxSwapSpec
    | HtmxPushUrl HtmxPushUrl
    | CustomHtmx Type Symbol

data SessionSelector
    = AnySession
    | SessionKind Type

data FragmentSelector
    = AnyFragment
    | FragmentKind Type
    | FragmentSubtree Type

data ConflictResolution
    = Apply
    | Defer
    | Cancel

data SurfacePrimitive
    = Scope Type [FieldSpec] [ScopeOption]
    | Fragment Type [FieldSpec] [PrimitiveOption]
    | Action Type [FieldSpec] [PrimitiveOption]
    | Intent Type [FieldSpec] [PrimitiveOption]
    | MountState Type [FieldSpec]
    | Session Type [InteractionSessionOption]
    | SourceRef Type [PrimitiveOption]
    | DropzoneRef Type [PrimitiveOption]
    | ActivationRef Type [PrimitiveOption]
    | BrowserRole Type
    | BrowserState Type
    | BrowserClosedState Type [Type]
    | LinkedHighlight Type Type Type [LinkedHighlightActivation] [LinkedHighlightEffect]
    | CompleteSetSort Type Type Type Type Type [CompleteSetSortKeySpec] Type CompleteSetSortDirection
    | TabSet Type Type [Type] Type
    | SidePanel Type Type Type Type Type Type Type Type Type
    | ConflictPolicy SessionSelector FragmentSelector ConflictResolution
    | Event Type [FieldSpec]
    | DomToken Type
    | BrowserDomToken Type
    | SurfaceDto BrowserReachability Type [FieldSpec]

data SurfaceSpec
    = Surface Type [SurfacePrimitive]

type Surface name capabilities = 'Surface name capabilities
type Scope name fields options = 'Scope name fields options
type Fragment name params options = 'Fragment name params options
type Resource name fields = 'Resource name fields
type Action name fields options = 'Action name fields options
type Intent name fields options = 'Intent name fields options
type Field name wire = 'Field name wire
type OptionalField name wire = 'OptionalField name wire
type NullableField name wire = 'NullableField name wire
type MountState name fields = 'MountState name fields
type Session name options = 'Session name options
type SourceRef name options = 'SourceRef name options
type DropzoneRef name options = 'DropzoneRef name options
type ActivationRef name options = 'ActivationRef name options
type BrowserRole name = 'BrowserRole name
type BrowserState name = 'BrowserState name
type BrowserClosedState name values = 'BrowserClosedState name values
type LinkedHighlight name sourceRole memberRole activations effects = 'LinkedHighlight name sourceRole memberRole activations effects
type CompleteSetSort name rootRole rowRole controlRole rowDto keys defaultKey defaultDirection =
    'CompleteSetSort name rootRole rowRole controlRole rowDto keys defaultKey defaultDirection
type TabSet name tabRole keys defaultKey = 'TabSet name tabRole keys defaultKey
type SidePanel name rootRole mainRole panelRole toggleRole labelRole state collapsed expanded =
    'SidePanel name rootRole mainRole panelRole toggleRole labelRole state collapsed expanded
type ConflictPolicy session fragment resolution = 'ConflictPolicy ('SessionKind session) ('FragmentKind fragment) resolution
type ConflictPolicyFor sessionSelector fragmentSelector resolution = 'ConflictPolicy sessionSelector fragmentSelector resolution
type Event name detail = 'Event name detail
type DomToken name = 'DomToken name
type BrowserDomToken name = 'BrowserDomToken name
-- | Surface DTOs stay Haskell-only unless their alias explicitly selects a
-- browser reachability. Browser inbound DTOs emit an exact type, guard, and
-- parser for server-rendered JSON consumed by TypeScript.
type Dto name fields = 'SurfaceDto 'BrowserUnreachable name fields
type BrowserTypeDto name fields = 'SurfaceDto 'BrowserTypeOnly name fields
type BrowserGuardDto name fields = 'SurfaceDto 'BrowserGuard name fields
type BrowserInboundDto name fields = 'SurfaceDto 'BrowserInbound name fields
type BrowserOutboundDto name fields = 'SurfaceDto 'BrowserOutbound name fields
type BrowserBidirectionalDto name fields = 'SurfaceDto 'BrowserBidirectional name fields
type ContainsSurface name = 'ContainsSurface name
type DependsOnFragment name = 'DependsOnFragment name

type family Append (left :: [kind]) (right :: [kind]) :: [kind] where
    Append '[] right = right
    Append (first ': rest) right = first ': Append rest right

type family Concat (lists :: [[kind]]) :: [kind] where
    Concat '[] = '[]
    Concat (first ': rest) = Append first (Concat rest)
