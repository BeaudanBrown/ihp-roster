{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE PolyKinds            #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}

module Application.Helper.FrontendContract.DSL
    ( FrontendContract (..)
    , GlobalPrimitive (..)
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
    , Record
    , Enum
    , TaggedUnion
    , TaggedUnionWithTag
    , LiteralEnum
    , Literal
    , Case
    , Field
    , OptionalField
    , NullableField
    , Event
    , DomId
    , DomAttr
    , DomValue
    , FieldName
    , DomToken
    , Constant
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
    | TaggedUnion Type [UnionCaseSpec]
    | TaggedUnionWithTag Type Symbol [UnionCaseSpec]

-- | Literal enums are for externally-shaped closed string vocabularies such as HTMX values.
data LiteralCaseSpec = Literal Type Symbol

-- | Tagged unions use the fixed JSON discriminator @tag@ and kebab-case case tags.
data UnionCaseSpec = Case Type [FieldSpec]

-- | App-wide/shared browser vocabulary.
data GlobalPrimitive
    = GlobalSchema SchemaPrimitive
    | Event Type [FieldSpec]
    | DomId Type
    | DomAttr Type
    | DomValue Type Symbol
    | FieldName Type
    | DomToken Type
    | Constant Type Symbol
    | AppShellAction Type [FieldSpec] [AppShellActionOption]

-- | Registry root for app-wide browser vocabulary. Mounted feature topology is
-- declared through the richer FrontendContract.Surface DSL and joins this root
-- only after both domain-specific registries have produced checked IR.
data FrontendContract
    = Global Type [GlobalPrimitive]

type FrontendContractSpec = FrontendContract
type Global name primitives = 'Global name primitives
type GlobalSchema schema = 'GlobalSchema schema
type Record name fields = 'Record name fields
type Enum name cases = 'Enum name cases
type LiteralEnum name cases = 'LiteralEnum name cases
type Literal name value = 'Literal name value
type TaggedUnion name cases = 'TaggedUnion name cases
type TaggedUnionWithTag name tagField cases = 'TaggedUnionWithTag name tagField cases
type Case name fields = 'Case name fields
type Field name wire = 'Field name wire
type OptionalField name wire = 'OptionalField name wire
type NullableField name wire = 'NullableField name wire
type Event name detail = 'Event name detail
type DomId name = 'DomId name
type DomAttr name = 'DomAttr name
type DomValue name value = 'DomValue name value
type FieldName name = 'FieldName name
type DomToken name = 'DomToken name
type Constant name value = 'Constant name value
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
    Append (head ': tail) right = head ': Append tail right

type family Concat (lists :: [[kind]]) :: [kind] where
    Concat '[] = '[]
    Concat (head ': tail) = Append head (Concat tail)
