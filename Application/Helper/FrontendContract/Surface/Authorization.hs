module Application.Helper.FrontendContract.Surface.Authorization
    ( authorizeFrontendSurfaceScope
    , frontendSurfaceScopeAuthorizationRequirement
    , validateFrontendSurfaceLiveSubscription
    ) where

import Application.Helper.FrontendContract.Surface.AuthorizationRequirement (SurfaceScopeAuthorizationRequirement (..),
                                                                             authorizeSurfaceScopeRequirement)
import qualified Application.Helper.FrontendContract.Surface.ContractIR as SurfaceIR
import Application.Helper.FrontendContract.Surface.Contracts (registeredFrontendSurfaceContractIR)
import qualified Application.Helper.FrontendContract.Wire.LiveUpdate as Wire
import qualified Application.Helper.LiveUpdate.Internal as LiveUpdateInternal
import Application.Helper.LiveUpdate.Runtime
import Control.Monad (guard)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Aeson.Key
import qualified Data.Aeson.KeyMap as Aeson.KeyMap
import qualified Data.Aeson.Types as Aeson
import qualified Data.List as List
import qualified Data.Scientific as Scientific
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import Web.Controller.Prelude

-- | Authorizes a surface-native websocket subscription from the generated
-- FrontendSurface scope auth metadata. Unknown surfaces, malformed payloads, and
-- malformed policy fields deny by default.
authorizeFrontendSurfaceScope :: (?context :: ControllerContext, ?modelContext :: ModelContext) => SurfaceScope -> IO Bool
authorizeFrontendSurfaceScope scope =
    case frontendSurfaceScopeAuthorizationRequirement scope of
        Nothing                 -> pure False
        Just Nothing            -> pure True
        Just (Just requirement) -> authorizeSurfaceScopeRequirement requirement

-- | Resolves generated FrontendSurface scope auth metadata to the existing
-- business authorization requirement vocabulary. The outer Maybe is missing or
-- malformed generated metadata/payload; the inner Maybe is explicit NoAuth.
frontendSurfaceScopeAuthorizationRequirement :: SurfaceScope -> Maybe (Maybe SurfaceScopeAuthorizationRequirement)
frontendSurfaceScopeAuthorizationRequirement scope = do
    (surfaceName, scopePayload) <- liveScopeSurfaceAndPayload scope
    surface <- find ((== surfaceName) . (.surfaceName)) registeredFrontendSurfaceContractIR.contractSurfaces
    scopeIR <- listToMaybe surface.surfaceScopes
    auth <- listToMaybe scopeIR.scopeOptions
    authorizationRequirementFor auth scopePayload

validateFrontendSurfaceLiveSubscription :: SurfaceSubscription -> Bool
validateFrontendSurfaceLiveSubscription SurfaceSubscription { subscriptionScope, subscriptionScopeKey, subscriptionFragmentKeys } =
    fromMaybe False do
        let Wire.SurfaceScope { surface = scopeSurface, scope = scopePayload } = LiveUpdateInternal.surfaceScopeToWire subscriptionScope
        surface <- find ((== scopeSurface) . (.surfaceName)) registeredFrontendSurfaceContractIR.contractSurfaces
        scopeIR <- listToMaybe surface.surfaceScopes
        guard (subscriptionScopeKey == surfaceScopeKey subscriptionScope)
        guard (validateFields scopeIR.scopeFields scopePayload)
        guard (all (validateFragmentKey surface scopeSurface) subscriptionFragmentKeys)
        pure True

validateFragmentKey :: SurfaceIR.SurfaceIR -> Text -> SurfaceFragmentKey -> Bool
validateFragmentKey surface expectedSurface fragmentKey =
    let (fragmentSurface, fragmentKind, fragmentParams) = LiveUpdateInternal.surfaceFragmentKeyIdentity fragmentKey
     in fragmentSurface == expectedSurface
            && fromMaybe False do
                fragmentIR <- List.find ((== fragmentKind) . (.fragmentName)) surface.surfaceFragments
                guard (SurfaceIR.LiveOption `elem` fragmentIR.fragmentOptions)
                guard (validateFields fragmentIR.fragmentParams fragmentParams)
                pure True

validateFields :: [SurfaceIR.FieldIR] -> Aeson.Value -> Bool
validateFields fields = \case
    Aeson.Object object ->
        let allowed = Set.fromList (map (.fieldName) fields)
            actual = Set.fromList (map Aeson.Key.toText (Aeson.KeyMap.keys object))
         in actual `Set.isSubsetOf` allowed && all (fieldIsValid object) fields
    _ -> False
    where
        fieldIsValid object field =
            case Aeson.KeyMap.lookup (Aeson.Key.fromText field.fieldName) object of
                Nothing -> field.fieldPresence == SurfaceIR.OptionalFieldPresence
                Just Aeson.Null -> field.fieldPresence == SurfaceIR.NullableFieldPresence || validateWireAllowsNull field.fieldWire
                Just value -> validateWire field.fieldWire value

validateWireAllowsNull :: SurfaceIR.WireIR -> Bool
validateWireAllowsNull = \case
    SurfaceIR.WireNullableIR _ -> True
    _                         -> False

validateWire :: SurfaceIR.WireIR -> Aeson.Value -> Bool
validateWire wire value =
    case wire of
        SurfaceIR.WireTextIR -> isString value
        SurfaceIR.WireIntIR -> case value of
            Aeson.Number number -> isJust (Scientific.toBoundedInteger @Int number)
            _ -> False
        SurfaceIR.WireBoolIR -> case value of
            Aeson.Bool _ -> True
            _            -> False
        SurfaceIR.WireUuidIR -> case value of
            Aeson.String text -> isJust (UUID.fromText (Text.strip text))
            _                 -> False
        SurfaceIR.WireDayIR -> case value of
            Aeson.String text -> not (Text.null text)
            _                 -> False
        SurfaceIR.WireClosedIR {} -> isString value
        SurfaceIR.WireDomainIR {} -> isString value
        SurfaceIR.WireListIR inner -> case value of
            Aeson.Array values -> all (validateWire inner) values
            _                  -> False
        SurfaceIR.WireMapIR _ valueWire -> case value of
            Aeson.Object object -> all (validateWire valueWire) (Aeson.KeyMap.elems object)
            _ -> False
        SurfaceIR.WireOptionalIR inner -> validateWire inner value
        SurfaceIR.WireNullableIR inner -> value == Aeson.Null || validateWire inner value
        SurfaceIR.WireRefIR _ -> True
        SurfaceIR.WireUnknownIR -> True
        SurfaceIR.WireSurfaceScopeIR -> False
        SurfaceIR.WireSurfaceFragmentKeyIR -> False
    where
        isString = \case
            Aeson.String _ -> True
            _              -> False

liveScopeSurfaceAndPayload :: SurfaceScope -> Maybe (Text, Aeson.Value)
liveScopeSurfaceAndPayload = Just . LiveUpdateInternal.surfaceScopeIdentity

authorizationRequirementFor :: SurfaceIR.ScopeAuthIR -> Aeson.Value -> Maybe (Maybe SurfaceScopeAuthorizationRequirement)
authorizationRequirementFor auth payload =
    case auth of
        SurfaceIR.AuthorizeCurrentVenueIR venueIdField ->
            authorize (RequireCurrentVenue <$> uuidField venueIdField)
        SurfaceIR.AuthorizeCurrentVenueUserIR venueIdField userIdField ->
            authorize (RequireCurrentVenueUser <$> uuidField venueIdField <*> uuidField userIdField)
        SurfaceIR.AuthorizeCurrentVenueStaffIR venueIdField staffIdField ->
            authorize (RequireCurrentVenueStaff <$> uuidField venueIdField <*> uuidField staffIdField)
        SurfaceIR.AuthorizeCurrentVenueRosterGroupIR venueIdField rosterGroupIdField ->
            authorize (RequireCurrentVenueRosterGroup <$> uuidField venueIdField <*> uuidField rosterGroupIdField)
        SurfaceIR.AuthorizeCurrentVenueAdminIR venueIdField ->
            authorize (RequireCurrentVenueAdmin <$> uuidField venueIdField)
        SurfaceIR.AuthorizeCurrentVenueManagerIR venueIdField ->
            authorize (RequireCurrentVenueManager <$> uuidField venueIdField)
        SurfaceIR.AuthorizeCurrentVenueOwnerIR venueIdField ->
            authorize (RequireCurrentVenueOwner <$> uuidField venueIdField)
        SurfaceIR.AuthorizeCurrentVenueAdminRosterGroupIR venueIdField rosterGroupIdField ->
            authorize (RequireCurrentVenueAdminRosterGroup <$> uuidField venueIdField <*> uuidField rosterGroupIdField)
        SurfaceIR.AuthorizeSupportSuperAdminIR -> Just (Just RequireSupportSuperAdmin)
        SurfaceIR.NoAuthIR -> Just Nothing
        SurfaceIR.InvalidAuthorizeIR {} -> Nothing
    where
        authorize = fmap Just
        uuidField name = parseUuidField name payload

parseUuidField :: Text -> Aeson.Value -> Maybe UUID.UUID
parseUuidField fieldName =
    Aeson.parseMaybe (Aeson.withObject "FrontendSurface live scope" (Aeson..: Aeson.Key.fromText fieldName))
