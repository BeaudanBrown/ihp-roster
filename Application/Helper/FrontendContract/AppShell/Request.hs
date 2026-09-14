{-# LANGUAGE AllowAmbiguousTypes  #-}
{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE PolyKinds            #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE TypeApplications     #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}

-- | Nominal AppShell request fields derived directly from 'AppShellContract'.
-- Field evaluation, diagnostics, serialization, and parsing reuse the Surface
-- request machinery; this module only selects the owning AppShell declaration.
module Application.Helper.FrontendContract.AppShell.Request
    ( AppShellActionFieldSpecs
    , AppShellActionFields
    , appShellActionFields
    , appShellActionFor
    , noAppShellActionFields
    , parseAppShellActionParamPairs
    , parseAppShellActionParams
    ) where

import Application.Helper.FrontendContract.AppShell (AppShellContract)
import Application.Helper.FrontendContract.AppShell.Runtime (RegisteredAppShellAction,
                                                             appShellActionByMarker)
import qualified Application.Helper.FrontendContract.DSL as Global
import Application.Helper.FrontendContract.IR (AppShellActionIR)
import Application.Helper.FrontendContract.Surface.Diagnostics (AssertSurfaceFieldHead,
                                                                AssertSurfaceFieldsEnd,
                                                                SurfaceFieldInputWire,
                                                                SurfaceFieldsTail)
import qualified Application.Helper.FrontendContract.Surface.DSL as Surface
import Application.Helper.FrontendContract.Surface.Request (KnownSurfaceRequestFields,
                                                            SurfaceRequestFieldError,
                                                            parseDeclaredRequestParamPairs,
                                                            parseDeclaredRequestParams)
import Application.Helper.FrontendContract.Surface.Values (ConsSurfaceField,
                                                           DeclaredRequestFields,
                                                           SurfaceFieldInput,
                                                           SurfaceFields,
                                                           declaredRequestFields,
                                                           noDeclaredRequestFields)
import Application.Helper.FrontendContract.TypeError (BepisTypeError)
import GHC.TypeLits (ErrorMessage (..))
import IHP.Prelude
import Network.Wai (Request)

type AppShellActionFields action =
    DeclaredRequestFields action (AppShellActionFieldSpecs action)

type AppShellActionFieldSpecs action =
    AppShellSurfaceFieldSpecs (FindAppShellActionFields action AppShellContract)

type family FindAppShellActionFields (action :: Type) (contract :: Global.FrontendContract) :: [Global.FieldSpec] where
    FindAppShellActionFields action ('Global.Global root primitives) =
        FindAppShellPrimitiveFields action primitives

type family FindAppShellPrimitiveFields (action :: Type) (primitives :: [Global.GlobalPrimitive]) :: [Global.FieldSpec] where
    FindAppShellPrimitiveFields action (('Global.AppShellAction action fields options) ': rest) = fields
    FindAppShellPrimitiveFields action (primitive ': rest) =
        FindAppShellPrimitiveFields action rest
    FindAppShellPrimitiveFields action '[] =
        BepisTypeError "BEPIS-FC-014"
            ( 'Text "AppShell contract does not declare action marker "
                ':<>: 'ShowType action
            )

-- AppShell remains authored in the global DSL, while all value evaluation is
-- delegated to the existing Surface field engine through this type-only view.
type family AppShellSurfaceFieldSpecs (fields :: [Global.FieldSpec]) :: [Surface.FieldSpec] where
    AppShellSurfaceFieldSpecs '[] = '[]
    AppShellSurfaceFieldSpecs (('Global.Field marker wire) ': rest) =
        'Surface.Field marker (AppShellSurfaceWire wire) ': AppShellSurfaceFieldSpecs rest
    AppShellSurfaceFieldSpecs (('Global.OptionalField marker wire) ': rest) =
        'Surface.OptionalField marker (AppShellSurfaceWire wire) ': AppShellSurfaceFieldSpecs rest
    AppShellSurfaceFieldSpecs (('Global.NullableField marker wire) ': rest) =
        'Surface.NullableField marker (AppShellSurfaceWire wire) ': AppShellSurfaceFieldSpecs rest

type family AppShellSurfaceWire (wire :: Global.WireType) :: Surface.WireType where
    AppShellSurfaceWire 'Global.WireText = 'Surface.WireText
    AppShellSurfaceWire 'Global.WireInt = 'Surface.WireInt
    AppShellSurfaceWire 'Global.WireBool = 'Surface.WireBool
    AppShellSurfaceWire 'Global.WireUUID = 'Surface.WireUUID
    AppShellSurfaceWire 'Global.WireDay = 'Surface.WireDay
    AppShellSurfaceWire ('Global.WireClosed value) = 'Surface.WireClosed value
    AppShellSurfaceWire ('Global.WireDomain value) = 'Surface.WireDomain value
    AppShellSurfaceWire ('Global.WireList inner) = 'Surface.WireList (AppShellSurfaceWire inner)
    AppShellSurfaceWire ('Global.WireOptional inner) = 'Surface.WireOptional (AppShellSurfaceWire inner)
    AppShellSurfaceWire ('Global.WireNullable inner) = 'Surface.WireNullable (AppShellSurfaceWire inner)
    AppShellSurfaceWire ('Global.WireRef dto) = 'Surface.WireRef dto
    AppShellSurfaceWire wire =
        BepisTypeError "BEPIS-FC-015"
            ( 'Text "AppShell request fields do not support wire "
                ':<>: 'ShowType wire
            )

noAppShellActionFields ::
    forall action.
    AssertSurfaceFieldsEnd (AppShellActionFieldSpecs action) =>
    AppShellActionFields action
noAppShellActionFields =
    noDeclaredRequestFields @action @(AppShellActionFieldSpecs action)

appShellActionFields ::
    forall action presence fieldMarker fallback.
    ( AssertSurfaceFieldHead
        presence
        fieldMarker
        (SurfaceFieldInputWire (AppShellActionFieldSpecs action) fallback)
        (AppShellActionFieldSpecs action)
    , ConsSurfaceField presence fieldMarker (SurfaceFieldInputWire (AppShellActionFieldSpecs action) fallback) (AppShellActionFieldSpecs action)
    ) =>
    SurfaceFieldInput
        presence
        fieldMarker
        (SurfaceFieldInputWire (AppShellActionFieldSpecs action) fallback) ->
    SurfaceFields (SurfaceFieldsTail (AppShellActionFieldSpecs action)) ->
    AppShellActionFields action
appShellActionFields =
    declaredRequestFields
        @action
        @(AppShellActionFieldSpecs action)
        @presence
        @fieldMarker
        @fallback

appShellActionFor ::
    forall action.
    ( Typeable action
    , RegisteredAppShellAction action
    ) =>
    AppShellActionFields action ->
    AppShellActionIR
appShellActionFor _ = appShellActionByMarker @action

parseAppShellActionParams ::
    forall action.
    ( ?request :: Request
    , KnownSurfaceRequestFields (AppShellActionFieldSpecs action)
    ) =>
    Either [SurfaceRequestFieldError] (AppShellActionFields action)
parseAppShellActionParams =
    parseDeclaredRequestParams @action @(AppShellActionFieldSpecs action)

parseAppShellActionParamPairs ::
    forall action.
    KnownSurfaceRequestFields (AppShellActionFieldSpecs action) =>
    [(ByteString, Maybe ByteString)] ->
    Either [SurfaceRequestFieldError] (AppShellActionFields action)
parseAppShellActionParamPairs =
    parseDeclaredRequestParamPairs @action @(AppShellActionFieldSpecs action)
