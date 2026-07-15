{-# LANGUAGE ConstraintKinds      #-}
{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE PolyKinds            #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}

module Application.Helper.FrontendContract.Surface.Diagnostics
    ( AssertSurfaceFieldHead
    , AssertSurfaceFieldValue
    , AssertSurfaceFieldsEnd
    , RequireSurfaceField
    , SurfaceFieldInputWire
    , SurfaceFieldPresence (..)
    , SurfaceFieldsTail
    , SurfaceOwnershipError
    ) where

import Application.Helper.FrontendContract.Surface.DSL (FieldSpec (..),
                                                        SurfaceSpec (..),
                                                        WireType (..))
import qualified Data.Aeson as Aeson
import Data.Kind (Constraint, Type)
import Data.Text (Text)
import Data.Time (Day)
import qualified Data.UUID as UUID
import GHC.TypeLits (ErrorMessage (..), Symbol, TypeError)
import IHP.Prelude

-- | Construction-only presence tags. They let the declaration-directed field
-- builder diagnose the syntax a caller used without changing the Surface DSL.
data SurfaceFieldPresence
    = SurfaceRequired
    | SurfaceOptional
    | SurfaceNullable

-- | Keep the exact declaration as the contextual SurfaceFields index. For a
-- non-empty contract the declaration fixes the input wire; once the contract is
-- complete, the fallback preserves enough information to diagnose an extra
-- field.
type family SurfaceFieldInputWire (fields :: [FieldSpec]) (fallback :: WireType) :: WireType where
    SurfaceFieldInputWire (field ': rest) fallback = SurfaceFieldWire field
    SurfaceFieldInputWire '[] fallback = fallback

type family SurfaceFieldWire (field :: FieldSpec) :: WireType where
    SurfaceFieldWire ('Field marker wire) = wire
    SurfaceFieldWire ('OptionalField marker wire) = wire
    SurfaceFieldWire ('NullableField marker wire) = wire

type family SurfaceFieldsTail (fields :: [FieldSpec]) :: [FieldSpec] where
    SurfaceFieldsTail (field ': rest) = rest
    SurfaceFieldsTail '[] = '[]

-- | A declaration-directed terminator. A non-empty expected tail is a focused
-- missing-field error instead of a generic promoted-list unification failure.
type family AssertSurfaceFieldsEnd (fields :: [FieldSpec]) :: Constraint where
    AssertSurfaceFieldsEnd '[] = ()
    AssertSurfaceFieldsEnd (field ': rest) = TypeError
        ( 'Text "FrontendSurface field list is incomplete"
            ':$$: 'Text "Missing next field: " ':<>: RenderSurfaceField field
            ':$$: 'Text "Expected remaining fields: " ':<>: RenderSurfaceFields (field ': rest)
        )

-- | Compare the field syntax at the current declaration position. Exact
-- presence/marker matches succeed; all failures retain the compact expected
-- contract instead of exposing the implementation list representation.
type family AssertSurfaceFieldHead
    (presence :: SurfaceFieldPresence)
    (marker :: Type)
    (wire :: WireType)
    (fields :: [FieldSpec]) :: Constraint where
    AssertSurfaceFieldHead 'SurfaceRequired marker wire (('Field marker wire) ': rest) = ()
    AssertSurfaceFieldHead 'SurfaceOptional marker wire (('OptionalField marker wire) ': rest) = ()
    AssertSurfaceFieldHead 'SurfaceNullable marker wire (('NullableField marker wire) ': rest) = ()
    AssertSurfaceFieldHead presence marker wire '[] = TypeError
        ( 'Text "FrontendSurface field list has an extra field"
            ':$$: 'Text "Received field: "
                ':<>: 'ShowType marker
                ':<>: 'Text " :: "
                ':<>: RenderSurfaceFieldPresence presence
                ':<>: 'Text " (no declared wire)"
            ':$$: 'Text "Expected remaining fields: []"
        )
    AssertSurfaceFieldHead 'SurfaceRequired marker wire (('OptionalField marker wire) ': rest) =
        SurfaceFieldPresenceMismatch 'SurfaceRequired marker wire ('OptionalField marker wire) rest
    AssertSurfaceFieldHead 'SurfaceRequired marker wire (('NullableField marker wire) ': rest) =
        SurfaceFieldPresenceMismatch 'SurfaceRequired marker wire ('NullableField marker wire) rest
    AssertSurfaceFieldHead 'SurfaceOptional marker wire (('Field marker wire) ': rest) =
        SurfaceFieldPresenceMismatch 'SurfaceOptional marker wire ('Field marker wire) rest
    AssertSurfaceFieldHead 'SurfaceOptional marker wire (('NullableField marker wire) ': rest) =
        SurfaceFieldPresenceMismatch 'SurfaceOptional marker wire ('NullableField marker wire) rest
    AssertSurfaceFieldHead 'SurfaceNullable marker wire (('Field marker wire) ': rest) =
        SurfaceFieldPresenceMismatch 'SurfaceNullable marker wire ('Field marker wire) rest
    AssertSurfaceFieldHead 'SurfaceNullable marker wire (('OptionalField marker wire) ': rest) =
        SurfaceFieldPresenceMismatch 'SurfaceNullable marker wire ('OptionalField marker wire) rest
    AssertSurfaceFieldHead presence marker wire (field ': rest) = TypeError
        ( 'Text "FrontendSurface field order mismatch"
            ':$$: 'Text "Expected next field: " ':<>: RenderSurfaceField field
            ':$$: 'Text "Received field: " ':<>: RenderProvidedSurfaceField presence marker wire
            ':$$: 'Text "Expected remaining fields: " ':<>: RenderSurfaceFields (field ': rest)
        )

type family SurfaceFieldPresenceMismatch
    (presence :: SurfaceFieldPresence)
    (marker :: Type)
    (wire :: WireType)
    (expected :: FieldSpec)
    (rest :: [FieldSpec]) :: Constraint where
    SurfaceFieldPresenceMismatch presence marker wire expected rest = TypeError
        ( 'Text "FrontendSurface field presence mismatch"
            ':$$: 'Text "Expected next field: " ':<>: RenderSurfaceField expected
            ':$$: 'Text "Received field: " ':<>: RenderProvidedSurfaceField presence marker wire
            ':$$: 'Text "Expected remaining fields: " ':<>: RenderSurfaceFields (expected ': rest)
        )

-- | Check the Haskell value at the same declaration-directed seam. The equality
-- retained by Surface.Values keeps the old inference behavior; this family adds
-- the marker, presence, and declared wire when that equality cannot hold.
type family AssertSurfaceFieldValue
    (presence :: SurfaceFieldPresence)
    (marker :: Type)
    (wire :: WireType)
    (value :: Type) :: Constraint where
    AssertSurfaceFieldValue 'SurfaceRequired marker wire value =
        CheckSurfaceWireValue 'SurfaceRequired marker wire wire value value
    AssertSurfaceFieldValue 'SurfaceOptional marker wire (Maybe value) =
        CheckSurfaceWireValue 'SurfaceOptional marker wire wire value (Maybe value)
    AssertSurfaceFieldValue 'SurfaceNullable marker wire (Maybe value) =
        CheckSurfaceWireValue 'SurfaceNullable marker wire wire value (Maybe value)

type family CheckSurfaceWireValue
    (presence :: SurfaceFieldPresence)
    (marker :: Type)
    (declaredWire :: WireType)
    (remainingWire :: WireType)
    (remainingValue :: Type)
    (providedValue :: Type) :: Constraint where
    CheckSurfaceWireValue presence marker declaredWire 'WireText Text providedValue = ()
    CheckSurfaceWireValue presence marker declaredWire 'WireInt Int providedValue = ()
    CheckSurfaceWireValue presence marker declaredWire 'WireBool Bool providedValue = ()
    CheckSurfaceWireValue presence marker declaredWire 'WireUUID UUID.UUID providedValue = ()
    CheckSurfaceWireValue presence marker declaredWire 'WireDay Day providedValue = ()
    CheckSurfaceWireValue presence marker declaredWire ('WireList inner) [value] providedValue =
        CheckSurfaceWireValue presence marker declaredWire inner value providedValue
    CheckSurfaceWireValue presence marker declaredWire ('WireOptional inner) (Maybe value) providedValue =
        CheckSurfaceWireValue presence marker declaredWire inner value providedValue
    CheckSurfaceWireValue presence marker declaredWire ('WireNullable inner) (Maybe value) providedValue =
        CheckSurfaceWireValue presence marker declaredWire inner value providedValue
    CheckSurfaceWireValue presence marker declaredWire ('WireRef dto) Aeson.Value providedValue = ()
    CheckSurfaceWireValue presence marker declaredWire remainingWire remainingValue providedValue = TypeError
        ( 'Text "FrontendSurface field wire mismatch"
            ':$$: 'Text "Declared field: " ':<>: RenderProvidedSurfaceField presence marker declaredWire
            ':$$: 'Text "Received Haskell value: " ':<>: RenderSurfaceHaskellType providedValue
        )

-- | Compact ownership failure shared by scope/fragment/action/intent/ref/token
-- and resource lookups. Matching on Surface exposes only its marker, never the
-- expanded primitive declaration list.
type family SurfaceOwnershipError
    (spec :: SurfaceSpec)
    (declarationKind :: Symbol)
    (marker :: Type) :: result where
    SurfaceOwnershipError ('Surface owner primitives) declarationKind marker = TypeError
        ( 'Text "FrontendSurface "
            ':<>: 'ShowType owner
            ':<>: 'Text " does not declare "
            ':<>: 'Text declarationKind
            ':<>: 'Text " marker "
            ':<>: 'ShowType marker
        )

-- | Field-name accessors report their compact owner marker and the complete
-- declared shape when a marker is absent.
type family RequireSurfaceField
    (owner :: Type)
    (marker :: Type)
    (fields :: [FieldSpec]) :: Constraint where
    RequireSurfaceField owner marker fields = RequireSurfaceFieldFrom owner marker fields fields

type family RequireSurfaceFieldFrom
    (owner :: Type)
    (marker :: Type)
    (declared :: [FieldSpec])
    (remaining :: [FieldSpec]) :: Constraint where
    RequireSurfaceFieldFrom owner marker declared (('Field marker wire) ': rest) = ()
    RequireSurfaceFieldFrom owner marker declared (('OptionalField marker wire) ': rest) = ()
    RequireSurfaceFieldFrom owner marker declared (('NullableField marker wire) ': rest) = ()
    RequireSurfaceFieldFrom owner marker declared (field ': rest) =
        RequireSurfaceFieldFrom owner marker declared rest
    RequireSurfaceFieldFrom owner marker declared '[] = TypeError
        ( 'Text "FrontendSurface declaration "
            ':<>: 'ShowType owner
            ':<>: 'Text " does not declare field marker "
            ':<>: 'ShowType marker
            ':$$: 'Text "Declared fields: " ':<>: RenderSurfaceFields declared
        )

type family RenderSurfaceFields (fields :: [FieldSpec]) :: ErrorMessage where
    RenderSurfaceFields fields =
        'Text "[" ':<>: RenderSurfaceFieldList fields ':<>: 'Text "]"

type family RenderSurfaceFieldList (fields :: [FieldSpec]) :: ErrorMessage where
    RenderSurfaceFieldList '[] = 'Text ""
    RenderSurfaceFieldList '[field] = RenderSurfaceField field
    RenderSurfaceFieldList (field ': rest) =
        RenderSurfaceField field ':<>: 'Text ", " ':<>: RenderSurfaceFieldList rest

type family RenderSurfaceField (field :: FieldSpec) :: ErrorMessage where
    RenderSurfaceField ('Field marker wire) =
        RenderProvidedSurfaceField 'SurfaceRequired marker wire
    RenderSurfaceField ('OptionalField marker wire) =
        RenderProvidedSurfaceField 'SurfaceOptional marker wire
    RenderSurfaceField ('NullableField marker wire) =
        RenderProvidedSurfaceField 'SurfaceNullable marker wire

type family RenderProvidedSurfaceField
    (presence :: SurfaceFieldPresence)
    (marker :: Type)
    (wire :: WireType) :: ErrorMessage where
    RenderProvidedSurfaceField presence marker wire =
        'ShowType marker
            ':<>: 'Text " :: "
            ':<>: RenderSurfaceFieldPresence presence
            ':<>: 'Text " "
            ':<>: RenderSurfaceWire wire

type family RenderSurfaceFieldPresence (presence :: SurfaceFieldPresence) :: ErrorMessage where
    RenderSurfaceFieldPresence 'SurfaceRequired = 'Text "required"
    RenderSurfaceFieldPresence 'SurfaceOptional = 'Text "optional"
    RenderSurfaceFieldPresence 'SurfaceNullable = 'Text "nullable"

type family RenderSurfaceWire (wire :: WireType) :: ErrorMessage where
    RenderSurfaceWire 'WireText = 'Text "WireText"
    RenderSurfaceWire 'WireInt = 'Text "WireInt"
    RenderSurfaceWire 'WireBool = 'Text "WireBool"
    RenderSurfaceWire 'WireUUID = 'Text "WireUUID"
    RenderSurfaceWire 'WireDay = 'Text "WireDay"
    RenderSurfaceWire ('WireList inner) =
        'Text "WireList (" ':<>: RenderSurfaceWire inner ':<>: 'Text ")"
    RenderSurfaceWire ('WireOptional inner) =
        'Text "WireOptional (" ':<>: RenderSurfaceWire inner ':<>: 'Text ")"
    RenderSurfaceWire ('WireNullable inner) =
        'Text "WireNullable (" ':<>: RenderSurfaceWire inner ':<>: 'Text ")"
    RenderSurfaceWire ('WireRef dto) =
        'Text "WireRef " ':<>: 'ShowType dto

type family RenderSurfaceHaskellType (value :: Type) :: ErrorMessage where
    RenderSurfaceHaskellType Text = 'Text "Text"
    RenderSurfaceHaskellType Int = 'Text "Int"
    RenderSurfaceHaskellType Bool = 'Text "Bool"
    RenderSurfaceHaskellType UUID.UUID = 'Text "UUID"
    RenderSurfaceHaskellType Day = 'Text "Day"
    RenderSurfaceHaskellType Aeson.Value = 'Text "Aeson.Value"
    RenderSurfaceHaskellType [value] =
        'Text "[" ':<>: RenderSurfaceHaskellType value ':<>: 'Text "]"
    RenderSurfaceHaskellType (Maybe value) =
        'Text "Maybe " ':<>: RenderSurfaceHaskellType value
    RenderSurfaceHaskellType value = 'ShowType value
