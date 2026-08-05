{-# LANGUAGE AllowAmbiguousTypes  #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE TypeApplications     #-}
{-# LANGUAGE UndecidableInstances #-}

-- | Canonical Haskell projection for finite request/browser scalar values.
module Application.Helper.FrontendContract.ClosedScalar
    ( KnownClosedScalar
    , closedScalarLiteral
    , closedScalarLiterals
    , closedScalarSourceModule
    , parseClosedScalarLiteral
    ) where

import Data.Typeable (tyConModule, typeRep, typeRepTyCon)
import IHP.ModelSupport (InputValue (..))
import IHP.Prelude

-- | One finite Haskell authority with an exact canonical wire projection.
-- Generated PostgreSQL enums already satisfy this through their generated
-- Bounded, Enum, and InputValue instances; DSL-owned ADTs use the same seam.
class (Bounded value, Enum value, InputValue value) => KnownClosedScalar value

instance (Bounded value, Enum value, InputValue value) => KnownClosedScalar value

closedScalarLiteral :: KnownClosedScalar value => value -> Text
closedScalarLiteral = inputValue

closedScalarLiterals :: forall value. KnownClosedScalar value => [Text]
closedScalarLiterals = map closedScalarLiteral (allEnumValues @value)

-- | Generated enum constructors are authored in @Generated.Enums@ but the
-- warning-suppressed public application boundary is @Generated.Types@.
closedScalarSourceModule :: forall value. Typeable value => Text
closedScalarSourceModule =
    case cs (tyConModule (typeRepTyCon (typeRep (Proxy @value)))) of
        "Generated.Enums" -> "Generated.Types"
        sourceModule      -> sourceModule

parseClosedScalarLiteral :: forall value. KnownClosedScalar value => Text -> Maybe value
parseClosedScalarLiteral literal =
    find ((== literal) . closedScalarLiteral) (allEnumValues @value)
