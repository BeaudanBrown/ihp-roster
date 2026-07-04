{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE PolyKinds            #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}

module Application.Helper.FrontendSurface.DSL
    ( SurfaceSpec (..)
    , SurfacePrimitive (..)
    , DependencySource (..)
    , FieldSpec (..)
    , ResourceSpec (..)
    , ScopeOption (..)
    , AuthPolicy (..)
    , WireType (..)
    , PrimitiveOption (..)
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
    , ConflictPolicy
    , ConflictPolicyFor
    , Event
    , DomToken
    , Dto
    , ContainsSurface
    , DependsOnFragment
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

data ResourceSpec
    = Resource Type [FieldSpec]

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

data PrimitiveOption
    = Eager
    | Lazy [PrimitiveOption]
    | Live
    | ResyncOnly
    | Trigger Type
    | Placeholder Type
    | DependsOn ResourceSpec [DependencySource]
    | DependsOnFragment Type
    | Target Type
    | BackedBy Type
    | Layer Type
    | Effect Type [PrimitiveOption]
    | SessionOption Type
    | Submits Type
    | SourceField Type
    | TargetField Type
    | ValueField Type
    | Emits Type
    | Contains Type
    | ContainsSurface Type
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
    = Scope Type [FieldSpec] [ScopeOption]
    | Fragment Type [FieldSpec] [PrimitiveOption]
    | Action Type [FieldSpec] [PrimitiveOption]
    | Intent Type [FieldSpec] [PrimitiveOption]
    | MountState Type [FieldSpec]
    | Session Type [PrimitiveOption]
    | SourceRef Type [PrimitiveOption]
    | DropzoneRef Type [PrimitiveOption]
    | ActivationRef Type [PrimitiveOption]
    | ConflictPolicy SessionSelector FragmentSelector ConflictResolution
    | Event Type [FieldSpec]
    | DomToken Type
    | Dto Type [FieldSpec]

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
type ConflictPolicy session fragment resolution = 'ConflictPolicy ('SessionKind session) ('FragmentKind fragment) resolution
type ConflictPolicyFor sessionSelector fragmentSelector resolution = 'ConflictPolicy sessionSelector fragmentSelector resolution
type Event name detail = 'Event name detail
type DomToken name = 'DomToken name
type Dto name fields = 'Dto name fields
type ContainsSurface name = 'ContainsSurface name
type DependsOnFragment name = 'DependsOnFragment name

type family Append (left :: [kind]) (right :: [kind]) :: [kind] where
    Append '[] right = right
    Append (head ': tail) right = head ': Append tail right

type family Concat (lists :: [[kind]]) :: [kind] where
    Concat '[] = '[]
    Concat (head ': tail) = Append head (Concat tail)
