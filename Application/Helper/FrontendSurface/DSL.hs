{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE PolyKinds            #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}

module Application.Helper.FrontendSurface.DSL
    ( SurfaceSpec (..)
    , SurfacePrimitive (..)
    , FieldSpec (..)
    , WireType (..)
    , PrimitiveOption (..)
    , ConflictResolution (..)
    , FragmentSelector (..)
    , SessionSelector (..)
    , Surface
    , Scope
    , Fragment
    , HtmxAction
    , Intent
    , Field
    , OptionalField
    , NullableField
    , MountState
    , Session
    , DisposableLayer
    , InteractionEffect
    , ConflictPolicy
    , ConflictPolicyFor
    , LoadPolicy
    , OverlayLane
    , ClientEvent
    , DomToken
    , Dto
    , Append
    , Concat
    ) where

import Data.Kind (Type)

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

data FieldSpec
    = Field Type WireType
    | OptionalField Type WireType
    | NullableField Type WireType

data PrimitiveOption
    = Eager
    | Lazy [PrimitiveOption]
    | Trigger Type
    | Placeholder Type
    | DependsOn Type
    | Target Type
    | BackedBy Type
    | Layer Type
    | SessionOption Type
    | Emits Type
    | Contains Type
    | UsesDto Type

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
    = Scope Type [FieldSpec]
    | Fragment Type [FieldSpec] [PrimitiveOption]
    | HtmxAction Type [FieldSpec] [PrimitiveOption]
    | Intent Type [FieldSpec] [PrimitiveOption]
    | MountState Type [FieldSpec]
    | Session Type [PrimitiveOption]
    | DisposableLayer Type
    | InteractionEffect Type [PrimitiveOption]
    | ConflictPolicy SessionSelector FragmentSelector ConflictResolution
    | LoadPolicy Type
    | OverlayLane Type
    | ClientEvent Type [FieldSpec]
    | DomToken Type
    | Dto Type [FieldSpec]

data SurfaceSpec
    = Surface Type [SurfacePrimitive]

type Surface name capabilities = 'Surface name capabilities
type Scope name fields = 'Scope name fields
type Fragment name params options = 'Fragment name params options
type HtmxAction name fields options = 'HtmxAction name fields options
type Intent name fields options = 'Intent name fields options
type Field name wire = 'Field name wire
type OptionalField name wire = 'OptionalField name wire
type NullableField name wire = 'NullableField name wire
type MountState name fields = 'MountState name fields
type Session name options = 'Session name options
type DisposableLayer name = 'DisposableLayer name
type InteractionEffect kind options = 'InteractionEffect kind options
type ConflictPolicy session fragment resolution = 'ConflictPolicy ('SessionKind session) ('FragmentKind fragment) resolution
type ConflictPolicyFor sessionSelector fragmentSelector resolution = 'ConflictPolicy sessionSelector fragmentSelector resolution
type LoadPolicy kind = 'LoadPolicy kind
type OverlayLane name = 'OverlayLane name
type ClientEvent name detail = 'ClientEvent name detail
type DomToken name = 'DomToken name
type Dto name fields = 'Dto name fields

type family Append (left :: [kind]) (right :: [kind]) :: [kind] where
    Append '[] right = right
    Append (head ': tail) right = head ': Append tail right

type family Concat (lists :: [[kind]]) :: [kind] where
    Concat '[] = '[]
    Concat (head ': tail) = Append head (Concat tail)
