module Application.Helper.FrontendSurface.Authorization
    ( authorizeFrontendSurfaceLiveScope
    , frontendSurfaceScopeAuthorizationRequirement
    ) where

import qualified Application.Helper.FrontendSurface.ContractIR as SurfaceIR
import Application.Helper.FrontendSurface.Reflect (reflectRegisteredFrontendSurfaces)
import Application.Helper.LiveSurface (LiveScopeAuthorizationRequirement (..),
                                       authorizeLiveScopeRequirement)
import Application.Helper.LiveUpdate.Runtime (LiveUpdateScope)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Aeson.Key
import qualified Data.Aeson.KeyMap as Aeson.KeyMap
import qualified Data.Aeson.Types as Aeson
import qualified Data.UUID as UUID
import Web.Controller.Prelude

-- | Authorizes a surface-native websocket subscription from the generated
-- FrontendSurface scope auth metadata. Unknown surfaces, malformed payloads, and
-- malformed policy fields deny by default.
authorizeFrontendSurfaceLiveScope :: (?context :: ControllerContext, ?modelContext :: ModelContext) => LiveUpdateScope -> IO Bool
authorizeFrontendSurfaceLiveScope scope =
    case frontendSurfaceScopeAuthorizationRequirement scope of
        Nothing                 -> pure False
        Just Nothing            -> pure True
        Just (Just requirement) -> authorizeLiveScopeRequirement requirement

-- | Resolves generated FrontendSurface scope auth metadata to the existing
-- business authorization requirement vocabulary. The outer Maybe is missing or
-- malformed generated metadata/payload; the inner Maybe is explicit NoAuth.
frontendSurfaceScopeAuthorizationRequirement :: LiveUpdateScope -> Maybe (Maybe LiveScopeAuthorizationRequirement)
frontendSurfaceScopeAuthorizationRequirement scope = do
    (surfaceName, scopePayload) <- liveScopeSurfaceAndPayload scope
    surface <- find ((== surfaceName) . (.surfaceName)) reflectRegisteredFrontendSurfaces.contractSurfaces
    scopeIR <- listToMaybe surface.surfaceScopes
    auth <- listToMaybe scopeIR.scopeOptions
    case auth of
        SurfaceIR.NoAuthIR -> Just Nothing
        SurfaceIR.AuthorizeIR policy fields -> Just <$> requirementFor policy fields scopePayload

liveScopeSurfaceAndPayload :: LiveUpdateScope -> Maybe (Text, Aeson.Value)
liveScopeSurfaceAndPayload scope = do
    object <- case Aeson.toJSON scope of
        Aeson.Object object -> Just object
        _                   -> Nothing
    surfaceName <- lookupText "surface" object
    scopePayload <- Aeson.KeyMap.lookup "scope" object
    pure (surfaceName, scopePayload)

requirementFor :: Text -> [Text] -> Aeson.Value -> Maybe LiveScopeAuthorizationRequirement
requirementFor policy fields payload =
    case policy of
        "current-venue" -> RequireCurrentVenue <$> uuidField "venueId"
        "current-venue-user" -> RequireCurrentVenueUser <$> uuidField "venueId" <*> uuidField "userId"
        "current-venue-staff" -> RequireCurrentVenueStaff <$> uuidField "venueId" <*> uuidField "staffId"
        "current-venue-roster-group" -> RequireCurrentVenueRosterGroup <$> uuidField "venueId" <*> uuidField "rosterGroupId"
        "current-venue-admin" -> RequireCurrentVenueAdmin <$> uuidField "venueId"
        "current-venue-manager" -> RequireCurrentVenueManager <$> uuidField "venueId"
        "current-venue-owner" -> RequireCurrentVenueOwner <$> uuidField "venueId"
        "current-venue-admin-roster-group" -> RequireCurrentVenueAdminRosterGroup <$> uuidField "venueId" <*> uuidField "rosterGroupId"
        "support-super-admin" -> Just RequireSupportSuperAdmin
        _ -> Nothing
    where
        uuidField name
            | name `elem` fields = parseUuidField name payload
            | otherwise = Nothing

parseUuidField :: Text -> Aeson.Value -> Maybe UUID.UUID
parseUuidField fieldName =
    Aeson.parseMaybe (Aeson.withObject "FrontendSurface live scope" (Aeson..: Aeson.Key.fromText fieldName))

lookupText :: Text -> Aeson.Object -> Maybe Text
lookupText key object = do
    value <- Aeson.KeyMap.lookup (Aeson.Key.fromText key) object
    case value of
        Aeson.String text -> Just text
        _                 -> Nothing
