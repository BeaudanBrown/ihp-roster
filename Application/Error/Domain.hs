{-# LANGUAGE AllowAmbiguousTypes  #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE KindSignatures       #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE TypeApplications     #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}

module Application.Error.Domain
    ( AppErrorProjection (..)
    , DomainError (..)
    , domainErrorCode
    , domainErrorCodes
    , projectDomainError
    ) where

import Application.Error.Types
import Application.Error.Types.Internal (mkAppError)
import Application.Helper.FrontendContract.Naming (nameToKebab)
import Data.Kind (Type)
import qualified Data.Text as Text
import Data.Typeable (tyConModule, tyConName, typeRep, typeRepTyCon)
import GHC.Generics
import IHP.Prelude

-- | The exhaustive, safe projection supplied by each closed domain error.
-- Pattern matching belongs in the instance; no domain value survives in
-- 'AppError'.
data AppErrorProjection = AppErrorProjection
    { safeMessage    :: !Text
    , severity       :: !ErrorSeverity
    , recovery       :: !Recovery
    , retryDirective :: !RetryDirective
    }
    deriving (Eq, Show)

class (Generic domainError, Typeable domainError, GenericErrorConstructors (Rep domainError)) => DomainError domainError where
    appErrorProjection :: domainError -> AppErrorProjection

projectDomainError :: forall domainError. DomainError domainError => domainError -> AppError
projectDomainError domainError =
    mkAppError
        (domainErrorCode domainError)
        projection.safeMessage
        projection.severity
        projection.recovery
        projection.retryDirective
  where
    projection = appErrorProjection domainError

domainErrorCode :: forall domainError. DomainError domainError => domainError -> Text
domainErrorCode domainError = domainErrorNamespace @domainError <> "/" <> nameToKebab (genericConstructorName (from domainError))

domainErrorCodes :: forall domainError. DomainError domainError => [Text]
domainErrorCodes =
    map ((domainErrorNamespace @domainError <> "/") <>) (genericConstructorNames (Proxy @(Rep domainError)))

domainErrorNamespace :: forall domainError. Typeable domainError => Text
domainErrorNamespace = moduleNamespace <> "." <> typeNamespace
  where
    tyCon = typeRepTyCon (typeRep (Proxy @domainError))
    moduleNamespace =
        tyConModule tyCon
            |> Text.pack
            |> Text.splitOn "."
            |> map nameToKebab
            |> Text.intercalate "."
    typeName = Text.pack (tyConName tyCon)
    typeNamespace = nameToKebab (fromMaybe typeName (Text.stripSuffix "Error" typeName))

class GenericErrorConstructors (representation :: Type -> Type) where
    genericConstructorName :: representation value -> Text
    genericConstructorNames :: proxy representation -> [Text]

instance GenericErrorConstructors constructors => GenericErrorConstructors (M1 D metadata constructors) where
    genericConstructorName (M1 value) = genericConstructorName value
    genericConstructorNames _ = genericConstructorNames (Proxy @constructors)

instance (GenericErrorConstructors left, GenericErrorConstructors right) => GenericErrorConstructors (left :+: right) where
    genericConstructorName (L1 value) = genericConstructorName value
    genericConstructorName (R1 value) = genericConstructorName value
    genericConstructorNames _ =
        genericConstructorNames (Proxy @left) <> genericConstructorNames (Proxy @right)

instance Constructor constructor => GenericErrorConstructors (M1 C constructor fields) where
    genericConstructorName constructor = Text.pack (conName constructor)
    genericConstructorNames _ = [nameToKebab (Text.pack (conName (undefined :: M1 C constructor fields ())))]
