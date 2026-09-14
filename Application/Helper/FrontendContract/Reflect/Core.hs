{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE PolyKinds           #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeOperators       #-}

-- | Kind-polymorphic reflection mechanics shared without transferring
-- ownership between the nominal Global and Surface DSLs.
module Application.Helper.FrontendContract.Reflect.Core
    ( ReflectBrowserReachability (..)
    , ReflectField (..)
    , ReflectFieldList (..)
    , ReflectWire (..)
    , reflectedFieldWith
    ) where

import Application.Helper.FrontendContract.Core
import Application.Helper.FrontendContract.DSL (BrowserReachability (..))
import Data.Typeable (tyConName, typeRep, typeRepTyCon)
import IHP.Prelude

class ReflectBrowserReachability (reachability :: BrowserReachability) where
    reflectBrowserReachability :: BrowserReachabilityIR

instance ReflectBrowserReachability 'BrowserUnreachable where reflectBrowserReachability = BrowserUnreachableIR
instance ReflectBrowserReachability 'BrowserTypeOnly where reflectBrowserReachability = BrowserTypeOnlyIR
instance ReflectBrowserReachability 'BrowserGuard where reflectBrowserReachability = BrowserGuardIR
instance ReflectBrowserReachability 'BrowserInbound where reflectBrowserReachability = BrowserInboundIR
instance ReflectBrowserReachability 'BrowserOutbound where reflectBrowserReachability = BrowserOutboundIR
instance ReflectBrowserReachability 'BrowserBidirectional where reflectBrowserReachability = BrowserBidirectionalIR

class ReflectFieldList (fields :: [fieldKind]) where
    reflectFieldList :: [FieldIR]

instance ReflectFieldList '[] where
    reflectFieldList = []

instance (ReflectField field, ReflectFieldList rest) => ReflectFieldList (field ': rest) where
    reflectFieldList = reflectField @_ @field : reflectFieldList @_ @rest

class ReflectField (field :: fieldKind) where
    reflectField :: FieldIR

class ReflectWire (wire :: wireKind) where
    reflectWire :: WireIR

reflectedFieldWith :: forall marker wire. (Typeable marker, ReflectWire wire) => (Text -> Text) -> FieldPresence -> FieldIR
reflectedFieldWith fieldNameFor presence = FieldIR marker (fieldNameFor marker) (reflectWire @_ @wire) presence
  where
    marker = cs (tyConName (typeRepTyCon (typeRep (Proxy @marker))))
