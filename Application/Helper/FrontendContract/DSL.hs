{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE PolyKinds            #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}

module Application.Helper.FrontendContract.DSL
    ( FrontendContract (..)
    , GlobalPrimitive (..)
    , SurfacePrimitive (..)
    , SchemaPrimitive (..)
    , UnionCaseSpec (..)
    , LiteralCaseSpec (..)
    , FieldSpec (..)
    , WireType (..)
    , FrontendContractSpec
    , Global
    , Surface
    , GlobalSchema
    , SurfaceSchema
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
    , Scope
    , Fragment
    , Action
    , Intent
    , MountState
    , Dto
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
    | WireSurfaceWireFragment

-- | Record-like fields. Presence is part of the DSL, not renderer policy.
data FieldSpec
    = Field Type WireType
    | OptionalField Type WireType
    | NullableField Type WireType

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

-- | Mounted feature UI semantics. This starts intentionally small; later tickets
-- port the full FrontendSurface primitive family here.
data SurfacePrimitive
    = SurfaceSchema SchemaPrimitive
    | Scope Type [FieldSpec]
    | Fragment Type [FieldSpec]
    | Action Type [FieldSpec]
    | Intent Type [FieldSpec]
    | MountState Type [FieldSpec]
    | Dto Type [FieldSpec]

-- | Registry root. Globals may be referenced by surfaces; globals should not
-- depend on concrete surfaces except through generated semantic wire forms.
data FrontendContract
    = Global Type [GlobalPrimitive]
    | Surface Type [SurfacePrimitive]

type FrontendContractSpec = FrontendContract
type Global name primitives = 'Global name primitives
type Surface name primitives = 'Surface name primitives
type GlobalSchema schema = 'GlobalSchema schema
type SurfaceSchema schema = 'SurfaceSchema schema
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
type Scope name fields = 'Scope name fields
type Fragment name fields = 'Fragment name fields
type Action name fields = 'Action name fields
type Intent name fields = 'Intent name fields
type MountState name fields = 'MountState name fields
type Dto name fields = 'Dto name fields

type family Append (left :: [kind]) (right :: [kind]) :: [kind] where
    Append '[] right = right
    Append (head ': tail) right = head ': Append tail right

type family Concat (lists :: [[kind]]) :: [kind] where
    Concat '[] = '[]
    Concat (head ': tail) = Append head (Concat tail)
