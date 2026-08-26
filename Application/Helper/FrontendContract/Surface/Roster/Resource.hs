module Application.Helper.FrontendContract.Surface.Roster.Resource
    ( matchRosterEndTimesConfigResource
    , matchRosterLayoutConfigResource
    , matchRosterTemplateDraftResource
    , matchRosterTemplateLibraryResource
    , matchRosterTemplateResource
    , matchRosterWeekBoundaryConfigResource
    , rosterDayResource
    , rosterEndTimesConfigResource
    , rosterLayoutConfigResource
    , rosterNotificationStatusResource
    , rosterGroupStaffResource
    , rosterSlotsContentResource
    , rosterSlotsStructureResource
    , rosterTemplateDraftResource
    , rosterTemplateLibraryResource
    , rosterTemplateResource
    , rosterWeekBoundaryConfigResource
    , rosterWeekResource
    , rosterWeekStructureResource
    , timePickerConfigResource
    ) where

import Application.Helper.FrontendContract.Surface.Resource (SurfaceResourceValue)
import Application.Helper.FrontendContract.Surface.Roster.Generated.Resource (rosterDayResource,
                                                                              rosterEndTimesConfigResource,
                                                                              rosterGroupStaffResource,
                                                                              rosterLayoutConfigResource,
                                                                              rosterNotificationStatusResource,
                                                                              rosterSlotsContentResource,
                                                                              rosterSlotsStructureResource,
                                                                              rosterTemplateDraftResource,
                                                                              rosterTemplateLibraryResource,
                                                                              rosterTemplateResource,
                                                                              rosterWeekBoundaryConfigResource,
                                                                              rosterWeekResource,
                                                                              rosterWeekStructureResource,
                                                                              timePickerConfigResource)
import qualified Application.Helper.FrontendContract.Surface.Roster.Generated.Resource as Generated
import qualified Data.UUID as UUID
import IHP.Prelude

matchRosterTemplateDraftResource :: SurfaceResourceValue -> Maybe UUID.UUID
matchRosterTemplateDraftResource = fmap fst . Generated.matchRosterTemplateDraftResource

matchRosterTemplateLibraryResource :: SurfaceResourceValue -> Maybe UUID.UUID
matchRosterTemplateLibraryResource = fmap fst . Generated.matchRosterTemplateLibraryResource

matchRosterTemplateResource :: SurfaceResourceValue -> Maybe UUID.UUID
matchRosterTemplateResource = fmap fst . Generated.matchRosterTemplateResource

matchRosterEndTimesConfigResource :: SurfaceResourceValue -> Maybe UUID.UUID
matchRosterEndTimesConfigResource = fmap fst . Generated.matchRosterEndTimesConfigResource

matchRosterLayoutConfigResource :: SurfaceResourceValue -> Maybe UUID.UUID
matchRosterLayoutConfigResource = fmap fst . Generated.matchRosterLayoutConfigResource

matchRosterWeekBoundaryConfigResource :: SurfaceResourceValue -> Maybe UUID.UUID
matchRosterWeekBoundaryConfigResource = fmap fst . Generated.matchRosterWeekBoundaryConfigResource
