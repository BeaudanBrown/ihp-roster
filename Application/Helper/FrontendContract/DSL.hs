{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE PolyKinds            #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}

module Application.Helper.FrontendContract.DSL
    ( FrontendContract (..)
    , GlobalPrimitive (..)
    , GlobalProjection (..)
    , BrowserReachability (..)
    , AppShellActionOption (..)
    , AppShellRequestMethod (..)
    , AppShellPushUrlValue (..)
    , SchemaPrimitive (..)
    , UnionCaseSpec (..)
    , LiteralCaseSpec (..)
    , FieldSpec (..)
    , WireType (..)
    , FrontendContractSpec
    , Global
    , GlobalSchema
    , ServerSchema
    , BrowserTypeSchema
    , BrowserGuardSchema
    , BrowserInboundSchema
    , BrowserOutboundSchema
    , BrowserBidirectionalSchema
    , Record
    , Enum
    , TaggedUnion
    , TaggedUnionWithTag
    , LiteralEnum
    , ClosedScalar
    , Literal
    , Case
    , Field
    , OptionalField
    , NullableField
    , Event
    , ServerEvent
    , InboundEvent
    , DomId
    , ServerDomId
    , DomAttr
    , ServerDomAttr
    , DomValue
    , FieldName
    , DomToken
    , Constant
    , ProjectInteractionDom
    , ErrorCodes
    , AppShellAction
    , AppShellHtmxMethod
    , AppShellHtmxTrigger
    , AppShellHtmxInclude
    , AppShellHtmxSync
    , AppShellHtmxIndicator
    , AppShellHtmxConfirm
    , AppShellHtmxSelect
    , AppShellHtmxTarget
    , AppShellHtmxSwap
    , AppShellHtmxPushUrl
    , AppShellCustomHtmx
    , Append
    , Concat
    ) where

import Data.Kind (Type)
import GHC.TypeLits (Symbol)

-- | Closed browser wire universe owned by the FrontendContract DSL.
data WireType
    = WireText
    | WireInt
    | WireBool
    | WireUUID
    | WireDay
    | WireClosed Type
    | WireDomain Type
    | WireUnknown
    | WireList WireType
    | WireOptional WireType
    | WireNullable WireType
    | WireRef Type
    | WireSurfaceScope
    | WireSurfaceFragmentKey

-- | Record-like fields. Presence is part of the DSL, not renderer policy.
data FieldSpec
    = Field Type WireType
    | OptionalField Type WireType
    | NullableField Type WireType

data AppShellRequestMethod
    = AppShellGet
    | AppShellPost
    | AppShellPut
    | AppShellPatch
    | AppShellDelete

data AppShellPushUrlValue
    = AppShellPushUrlTrue
    | AppShellPushUrlFalse

-- | Browser-visible HTMX metadata for app-shell/global request initiators.
data AppShellActionOption
    = AppShellHtmxMethod AppShellRequestMethod
    | AppShellHtmxTrigger Symbol
    | AppShellHtmxInclude Symbol
    | AppShellHtmxSync Symbol
    | AppShellHtmxIndicator Symbol
    | AppShellHtmxConfirm Symbol
    | AppShellHtmxSelect Symbol
    | AppShellHtmxTarget Type
    | AppShellHtmxSwap Symbol
    | AppShellHtmxPushUrl AppShellPushUrlValue
    | AppShellCustomHtmx Type Symbol

-- | Shared schema declarations available under Global and Surface roots.
data SchemaPrimitive
    = Record Type [FieldSpec]
    | Enum Type [Type]
    | LiteralEnum Type [LiteralCaseSpec]
    | ClosedScalar Type
    | TaggedUnion Type [UnionCaseSpec]
    | TaggedUnionWithTag Type Symbol [UnionCaseSpec]

-- | Literal enums are for externally-shaped closed string vocabularies such as HTMX values.
data LiteralCaseSpec = Literal Type Symbol

-- | Tagged unions use the fixed JSON discriminator @tag@ and kebab-case case tags.
data UnionCaseSpec = Case Type [FieldSpec]

-- | Browser code generation is explicit about which runtime capability reaches
-- each declared schema or event detail. Unreachable declarations remain
-- Haskell-only; reachable types, guards, parsers, and encoders are emitted only
-- when requested.
data BrowserReachability
    = BrowserUnreachable
    | BrowserTypeOnly
    | BrowserGuard
    | BrowserInbound
    | BrowserOutbound
    | BrowserBidirectional

-- | Exceptional browser projections are explicit closed declarations rather
-- than behavior recovered from a reflected root name.
data GlobalProjection
    = InteractionDomProjection

-- | App-wide/shared browser vocabulary.
data GlobalPrimitive
    = GlobalSchema BrowserReachability SchemaPrimitive
    | Event BrowserReachability Type [FieldSpec]
    | DomId Type
    | ServerDomId Type
    | DomAttr Type
    | ServerDomAttr Type
    | DomValue Type Symbol
    | FieldName Type
    | DomToken Type
    | Constant Type Symbol
    | Project GlobalProjection
    -- | Closed domain error types whose mechanically derived codes may cross
    -- the operation-failure browser boundary.
    | ErrorCodes [Type]
    | AppShellAction Type [FieldSpec] [AppShellActionOption]

-- | Registry root for app-wide browser vocabulary. Mounted feature topology is
-- declared through the richer FrontendContract.Surface DSL and joins this root
-- only after both domain-specific registries have produced checked IR.
data FrontendContract
    = Global Type [GlobalPrimitive]

type FrontendContractSpec = FrontendContract
type Global name primitives = 'Global name primitives
-- Compatibility alias for test-only/custom contracts; production contracts
-- should choose an explicit Browser*Schema alias.
type GlobalSchema schema = 'GlobalSchema 'BrowserBidirectional schema
type ServerSchema schema = 'GlobalSchema 'BrowserUnreachable schema
type BrowserTypeSchema schema = 'GlobalSchema 'BrowserTypeOnly schema
type BrowserGuardSchema schema = 'GlobalSchema 'BrowserGuard schema
type BrowserInboundSchema schema = 'GlobalSchema 'BrowserInbound schema
type BrowserOutboundSchema schema = 'GlobalSchema 'BrowserOutbound schema
type BrowserBidirectionalSchema schema = 'GlobalSchema 'BrowserBidirectional schema
type Record name fields = 'Record name fields
type Enum name cases = 'Enum name cases
type LiteralEnum name cases = 'LiteralEnum name cases
-- | A finite Haskell scalar. Generated PostgreSQL enums and DSL-owned ADTs
-- reuse their existing constructors and canonical 'InputValue' literals.
type ClosedScalar value = 'ClosedScalar value
type Literal name value = 'Literal name value
type TaggedUnion name cases = 'TaggedUnion name cases
type TaggedUnionWithTag name tagField cases = 'TaggedUnionWithTag name tagField cases
type Case name fields = 'Case name fields
type Field name wire = 'Field name wire
type OptionalField name wire = 'OptionalField name wire
type NullableField name wire = 'NullableField name wire
type Event name detail = 'Event 'BrowserTypeOnly name detail
type ServerEvent name detail = 'Event 'BrowserUnreachable name detail
type InboundEvent name detail = 'Event 'BrowserInbound name detail
type DomId name = 'DomId name
type ServerDomId name = 'ServerDomId name
type DomAttr name = 'DomAttr name
type ServerDomAttr name = 'ServerDomAttr name
type DomValue name value = 'DomValue name value
type FieldName name = 'FieldName name
type DomToken name = 'DomToken name
type Constant name value = 'Constant name value
type ProjectInteractionDom = 'Project 'InteractionDomProjection
type ErrorCodes errors = 'ErrorCodes errors
type AppShellAction name fields options = 'AppShellAction name fields options
type AppShellHtmxMethod method = 'AppShellHtmxMethod method
type AppShellHtmxTrigger value = 'AppShellHtmxTrigger value
type AppShellHtmxInclude value = 'AppShellHtmxInclude value
type AppShellHtmxSync value = 'AppShellHtmxSync value
type AppShellHtmxIndicator value = 'AppShellHtmxIndicator value
type AppShellHtmxConfirm value = 'AppShellHtmxConfirm value
type AppShellHtmxSelect value = 'AppShellHtmxSelect value
type AppShellHtmxTarget target = 'AppShellHtmxTarget target
type AppShellHtmxSwap value = 'AppShellHtmxSwap value
type AppShellHtmxPushUrl value = 'AppShellHtmxPushUrl value
type AppShellCustomHtmx marker reason = 'AppShellCustomHtmx marker reason

type family Append (left :: [kind]) (right :: [kind]) :: [kind] where
    Append '[] right = right
    Append (first ': rest) right = first ': Append rest right

type family Concat (lists :: [[kind]]) :: [kind] where
    Concat '[] = '[]
    Concat (first ': rest) = Append first (Concat rest)
