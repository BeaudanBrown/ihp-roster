{-# LANGUAGE TypeApplications #-}

module Web.RosterTemplates.FrontendSurface
    ( RosterTemplateDesignerScopeValue (..)
    , rosterTemplateDesignerContentId
    , rosterTemplateDesignerSurfaceImpl
    , rosterTemplateReferenceTargetAttrs
    ) where

import Application.Helper.FrontendContract.Surface.Attributes (roleAttrs)
import Application.Helper.FrontendContract.Surface.ContractIR (BrowserClosedStateIR (..))
import qualified Application.Helper.FrontendContract.Surface.Roster as Surface
import Application.Helper.FrontendContract.Surface.Runtime
import Application.Helper.FrontendContract.Surface.SemanticIR (BrowserAttributeIR (..))
import Application.Helper.FrontendContract.Surface.Values
import Data.UUID (UUID)
import IHP.Prelude

data RosterTemplateDesignerScopeValue = RosterTemplateDesignerScopeValue
    { templateDesignerVenueId       :: !UUID
    , templateDesignerRosterGroupId :: !UUID
    , templateDesignerUserId        :: !UUID
    }

rosterTemplateDesignerContentId :: Text
rosterTemplateDesignerContentId =
    surfaceFragmentTargetId @Surface.RosterTemplateDesignerSurface @Surface.RosterTemplateDesignerContent noSurfaceFields

rosterTemplateDesignerSurfaceImpl :: RosterTemplateDesignerScopeValue -> SurfaceImpl Surface.RosterTemplateDesignerSurface
rosterTemplateDesignerSurfaceImpl scope =
    mkSurfaceImplFromValues @Surface.RosterTemplateDesignerSurface @Surface.RosterTemplateDesignerScope
        "primary"
        ( surfaceField @Surface.VenueId scope.templateDesignerVenueId
            &: surfaceField @Surface.RosterGroupId scope.templateDesignerRosterGroupId
            &: surfaceField @Surface.UserId scope.templateDesignerUserId
            &: noSurfaceFields
        )
        noSurfaceFields
        []

rosterTemplateReferenceTargetAttrs :: [(Text, Text)]
rosterTemplateReferenceTargetAttrs =
    roleAttrs (surfaceBrowserRoleValue @Surface.RosterTemplateDesignerSurface @Surface.TemplateReferenceTargetRole)
        <> [(compatibilityState.browserClosedStateAttribute.browserAttributeDomAttribute, compatibleValue)]
  where
    compatibilityState = surfaceBrowserClosedStateValue @Surface.RosterTemplateDesignerSurface @Surface.TemplateReferenceCompatibility
    compatibleValue = surfaceBrowserClosedStateLiteral @Surface.RosterTemplateDesignerSurface @Surface.TemplateReferenceCompatibility @Surface.Compatible
