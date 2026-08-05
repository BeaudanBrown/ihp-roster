{-# LANGUAGE TypeApplications #-}

module Application.Helper.FrontendContract.Surface.Roster.TemplateApplication
    ( rosterTemplateApplicationFormAttrs
    , rosterTemplateCancelAttrs
    , rosterTemplateCardAttrs
    , rosterTemplateDayTargetAttrs
    , rosterTemplateTargetInputAttrs
    , rosterTemplateWeekTargetAttrs
    ) where

import Application.Helper.FrontendContract.Surface.ContractIR (BrowserAttributeIR (..))
import Application.Helper.FrontendContract.Surface.Dto (surfaceBrowserDtoRoleAttrs)
import qualified Application.Helper.FrontendContract.Surface.Roster as Roster
import Application.Helper.FrontendContract.Surface.Values
import qualified Data.UUID as UUID
import IHP.Prelude

rosterTemplateCardAttrs :: UUID.UUID -> Text -> Text -> [(Text, Text)]
rosterTemplateCardAttrs templateId templateName templateScale =
    roleAttrs (surfaceBrowserRoleValue @Roster.RosterSurface @Roster.TemplateCardRole)
        <> surfaceBrowserDtoRoleAttrs @Roster.RosterSurface @Roster.TemplateCardConfigRole @Roster.TemplateApplicationCardConfig
            ( surfaceField @Roster.TemplateId templateId
                &: surfaceField @Roster.TemplateName templateName
                &: surfaceField @Roster.TemplateScale templateScale
                &: noSurfaceFields
            )

rosterTemplateApplicationFormAttrs :: [(Text, Text)]
rosterTemplateApplicationFormAttrs = roleAttrs (surfaceBrowserRoleValue @Roster.RosterSurface @Roster.TemplateApplicationFormRole)

rosterTemplateTargetInputAttrs :: [(Text, Text)]
rosterTemplateTargetInputAttrs = roleAttrs (surfaceBrowserRoleValue @Roster.RosterSurface @Roster.TemplateTargetInputRole)

rosterTemplateCancelAttrs :: [(Text, Text)]
rosterTemplateCancelAttrs = roleAttrs (surfaceBrowserRoleValue @Roster.RosterSurface @Roster.TemplateCancelRole)

rosterTemplateDayTargetAttrs :: [(Text, Text)]
rosterTemplateDayTargetAttrs = roleAttrs (surfaceBrowserRoleValue @Roster.RosterSurface @Roster.TemplateDayTargetRole)

rosterTemplateWeekTargetAttrs :: [(Text, Text)]
rosterTemplateWeekTargetAttrs = roleAttrs (surfaceBrowserRoleValue @Roster.RosterSurface @Roster.TemplateWeekTargetRole)

roleAttrs :: BrowserAttributeIR -> [(Text, Text)]
roleAttrs role = [(role.browserAttributeDomAttribute, "true")]
