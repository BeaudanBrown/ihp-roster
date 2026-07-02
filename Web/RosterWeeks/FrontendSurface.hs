{-# LANGUAGE BlockArguments   #-}
{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE LambdaCase       #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Web.RosterWeeks.FrontendSurface
    ( RosterMountedFragmentPlan (..)
    , RosterSurfaceFragment (..)
    , RosterWeekScopeValue (..)
    , rosterAffectedMountedFragments
    , rosterCandidateMountedFragments
    , rosterFragmentDependencies
    , rosterLegacyLiveSurfaceConfig
    , rosterLiveUpdateScope
    , rosterMountedFragmentPlanFromRenderData
    , rosterSurfaceImpl
    , rosterSurfaceMountConfig
    , rosterSurfaceScopeKey
    , rosterSurfaceWireFragments
    ) where

import Application.Helper.FrontendSurface.DSL
import qualified Application.Helper.FrontendSurface.Roster as Surface
import Application.Helper.FrontendSurface.Runtime
import Application.Helper.LiveResource (LiveResource (..))
import Application.Helper.LiveSurface (LiveSurfaceConfig (..))
import Application.Helper.LiveUpdate.Runtime (LiveFragmentKey (..),
                                              LiveFragmentProtection (..),
                                              LiveUpdateScope (..),
                                              LiveUpdateWireFragment (..),
                                              liveUpdateScopeKey)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as Aeson
import Data.Coerce (coerce)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.UUID as UUID
import Generated.Types
import Web.Controller.Prelude
import Web.RosterWeeks.Dom
import Web.RosterWeeks.Paths (rosterWeekContentFragmentUrl,
                              rosterWeekDayColumnsFragmentUrl,
                              rosterWeekDayRailFragmentUrl,
                              rosterWeekDaySectionFragmentUrl,
                              rosterWeekGridFrameFragmentUrl,
                              rosterWeekGridToolbarFragmentUrl,
                              rosterWeekRowFragmentUrl,
                              rosterWeekSlotsGridFragmentUrl,
                              rosterWeekStaffPanelFragmentUrl,
                              rosterWeekWageRailFragmentUrl)
import Web.RosterWeeks.Types (RosterRenderIndexes (..))

-- | Logical roster week live invalidation scope. Viewer-specific preferences and
-- visibility stay server-owned; the scope identifies the authorized data slice.
data RosterWeekScopeValue = RosterWeekScopeValue
    { rosterWeekVenueId    :: !UUID.UUID
    , rosterWeekGroupId    :: !(Id RosterGroup)
    , rosterWeekWeekOffset :: !Int
    }
    deriving (Eq, Show)

data RosterMountedFragmentPlan = RosterMountedFragmentPlan
    { rosterMountedDayIds :: ![Id RosterDay]
    , rosterMountedRows   :: ![(Id RosterDay, Int)]
    }
    deriving (Eq, Show)

data RosterSurfaceFragment
    = RosterSurfaceContent
    | RosterSurfaceGridToolbar
    | RosterSurfaceGridFrame
    | RosterSurfaceDayColumns
    | RosterSurfaceDayRail
    | RosterSurfaceWageRail
    | RosterSurfaceSlotsGrid
    | RosterSurfaceStaffPanel
    | RosterSurfaceDaySection !UUID.UUID
    | RosterSurfaceRow !UUID.UUID !Int
    deriving (Eq, Show)

rosterMountedFragmentPlanFromRenderData :: [RosterDay] -> RosterRenderIndexes -> RosterMountedFragmentPlan
rosterMountedFragmentPlanFromRenderData rosterDays renderIndexes =
    RosterMountedFragmentPlan
        { rosterMountedDayIds = map (.id) rosterDays
        , rosterMountedRows = do
            rosterDay <- rosterDays
            (rowIndex, _) <- fromMaybe [] (Map.lookup (unpackId rosterDay.id) renderIndexes.rosterDayRowsByDayId)
            pure (rosterDay.id, rowIndex)
        }

rosterSurfaceImpl :: RosterWeekScopeValue -> RosterMountedFragmentPlan -> SurfaceImpl Surface.RosterSurface
rosterSurfaceImpl scope plan =
    let impl = mkSurfaceImpl "roster" (rosterSurfaceMountConfig scope plan) (rosterSurfaceHandlers scope plan)
     in impl { surfaceImplMountConfig = impl.surfaceImplMountConfig { mountFragments = rosterCandidateMountedFragments scope plan } }

rosterSurfaceMountConfig :: RosterWeekScopeValue -> RosterMountedFragmentPlan -> FrontendSurfaceMountConfig
rosterSurfaceMountConfig scope plan =
    FrontendSurfaceMountConfig
        { mountSurfaceName = "roster"
        , mountScopeKey = rosterSurfaceScopeKey scope
        , mountKey = "primary"
        , mountState = Aeson.object []
        , mountFragments = rosterCandidateMountedFragments scope plan
        }

rosterSurfaceScopeKey :: RosterWeekScopeValue -> Text
rosterSurfaceScopeKey scope =
    "roster:" <> tshow scope.rosterWeekVenueId <> ":" <> tshow scope.rosterWeekGroupId <> ":" <> tshow scope.rosterWeekWeekOffset

rosterLiveUpdateScope :: RosterWeekScopeValue -> LiveUpdateScope
rosterLiveUpdateScope scope =
    RosterWeekScope
        { venueId = scope.rosterWeekVenueId
        , rosterGroupId = unpackId scope.rosterWeekGroupId
        , weekOffset = scope.rosterWeekWeekOffset
        }

rosterLegacyLiveSurfaceConfig :: SurfaceImpl Surface.RosterSurface -> RosterWeekScopeValue -> LiveSurfaceConfig
rosterLegacyLiveSurfaceConfig impl scope =
    let wireScope = rosterLiveUpdateScope scope
     in LiveSurfaceConfig
            { feature = "roster"
            , socketPath = "/live-updates"
            , scope = wireScope
            , scopeKey = liveUpdateScopeKey wireScope
            , resyncFragments = rosterSurfaceWireFragments (rosterDefaultLiveMountedFragments impl.surfaceImplMountConfig.mountFragments)
            , decorateRequestsWithin = ["#" <> rosterWeekShellId]
            }

rosterSurfaceWireFragments :: [FrontendSurfaceMountedFragment] -> [LiveUpdateWireFragment]
rosterSurfaceWireFragments =
    mapMaybe mountedFragmentToWireFragment

rosterCandidateMountedFragments :: RosterWeekScopeValue -> RosterMountedFragmentPlan -> [FrontendSurfaceMountedFragment]
rosterCandidateMountedFragments scope plan =
    [ rosterContentMountedFragment scope
    , rosterGridToolbarMountedFragment scope
    , rosterGridFrameMountedFragment scope
    , rosterDayColumnsMountedFragment scope
    , rosterDayRailMountedFragment scope
    , rosterWageRailMountedFragment scope
    , rosterSlotsGridMountedFragment scope
    , rosterStaffPanelMountedFragment scope
    ]
        <> map (rosterDaySectionMountedFragment scope) plan.rosterMountedDayIds
        <> map (uncurry (rosterRowMountedFragment scope)) plan.rosterMountedRows

rosterAffectedMountedFragments :: RosterWeekScopeValue -> RosterMountedFragmentPlan -> Set.Set LiveResource -> [FrontendSurfaceMountedFragment]
rosterAffectedMountedFragments scope plan touchedResources =
    rosterCandidateMountedFragments scope plan
        |> filter (fragmentDependsOnTouchedResource scope touchedResources . mountedFragmentToSurfaceFragment)

rosterDefaultLiveMountedFragments :: [FrontendSurfaceMountedFragment] -> [FrontendSurfaceMountedFragment]
rosterDefaultLiveMountedFragments =
    filter \fragment -> fragment.mountedFragmentKey.fragmentKind `elem` defaultLiveFragmentKinds
    where
        defaultLiveFragmentKinds = ["roster-grid-toolbar", "roster-day-columns", "roster-day-rail", "roster-wage-rail", "roster-slots-grid", "roster-staff-panel"]

mountedFragmentToSurfaceFragment :: FrontendSurfaceMountedFragment -> RosterSurfaceFragment
mountedFragmentToSurfaceFragment fragment =
    case fragment.mountedFragmentKey.fragmentKind of
        "roster-content" -> RosterSurfaceContent
        "roster-grid-toolbar" -> RosterSurfaceGridToolbar
        "roster-grid-frame" -> RosterSurfaceGridFrame
        "roster-day-columns" -> RosterSurfaceDayColumns
        "roster-day-rail" -> RosterSurfaceDayRail
        "roster-wage-rail" -> RosterSurfaceWageRail
        "roster-slots-grid" -> RosterSurfaceSlotsGrid
        "roster-staff-panel" -> RosterSurfaceStaffPanel
        "roster-day-section" -> maybe RosterSurfaceGridFrame RosterSurfaceDaySection (parseFragmentRosterDayId fragment.mountedFragmentKey.fragmentParams)
        "roster-row" ->
            let params = fragment.mountedFragmentKey.fragmentParams
             in case (parseFragmentRosterDayId params, parseFragmentRowIndex params) of
                    (Just rosterDayId, Just rowIndex) -> RosterSurfaceRow rosterDayId rowIndex
                    _ -> RosterSurfaceGridFrame
        _ -> RosterSurfaceGridFrame

parseFragmentRosterDayId :: Aeson.Value -> Maybe UUID.UUID
parseFragmentRosterDayId value = do
    raw <- Aeson.parseMaybe (Aeson.withObject "RosterDayFragment" (.: "rosterDayId")) value
    UUID.fromString (cs (raw :: Text))

parseFragmentRowIndex :: Aeson.Value -> Maybe Int
parseFragmentRowIndex value =
    Aeson.parseMaybe (Aeson.withObject "RosterRowFragment" (.: "rowIndex")) value

fragmentDependsOnTouchedResource :: RosterWeekScopeValue -> Set.Set LiveResource -> RosterSurfaceFragment -> Bool
fragmentDependsOnTouchedResource scope touchedResources fragment =
    not (Set.null (Set.intersection touchedResources (Set.fromList (rosterFragmentDependencies scope fragment))))

rosterFragmentDependencies :: RosterWeekScopeValue -> RosterSurfaceFragment -> [LiveResource]
rosterFragmentDependencies scope = \case
    RosterSurfaceContent -> rosterWeekDependencies scope
    RosterSurfaceGridToolbar -> rosterWeekDependencies scope
    RosterSurfaceGridFrame -> rosterWeekDependencies scope
    RosterSurfaceDayColumns -> rosterWeekDependencies scope
    RosterSurfaceDayRail -> rosterWeekDependencies scope
    RosterSurfaceWageRail -> rosterWeekDependencies scope
    RosterSurfaceSlotsGrid -> rosterWeekDependencies scope
    RosterSurfaceStaffPanel -> [RosterWeekResource (unpackId scope.rosterWeekGroupId) scope.rosterWeekWeekOffset]
    RosterSurfaceDaySection rosterDayId -> rosterDayDependencies scope rosterDayId
    RosterSurfaceRow rosterDayId _ -> rosterDayDependencies scope rosterDayId

rosterWeekDependencies :: RosterWeekScopeValue -> [LiveResource]
rosterWeekDependencies scope =
    [ RosterWeekResource (unpackId scope.rosterWeekGroupId) scope.rosterWeekWeekOffset
    , RosterEndTimesConfigResource scope.rosterWeekVenueId
    , RosterWeekBoundaryConfigResource scope.rosterWeekVenueId
    ]

rosterDayDependencies :: RosterWeekScopeValue -> UUID.UUID -> [LiveResource]
rosterDayDependencies scope rosterDayId =
    [ RosterDayResource rosterDayId
    , RosterEndTimesConfigResource scope.rosterWeekVenueId
    , RosterWeekBoundaryConfigResource scope.rosterWeekVenueId
    ]

mountedFragmentToWireFragment :: FrontendSurfaceMountedFragment -> Maybe LiveUpdateWireFragment
mountedFragmentToWireFragment fragment = do
    fragmentKey <- mountedFragmentLiveKey fragment
    pure LiveUpdateWireFragment
        { fragmentKey
        , targetId = fragment.mountedFragmentTargetId
        , url = fragment.mountedFragmentUrl
        , deferUntilBlur = False
        , protectionPolicy = mountedFragmentProtectionPolicy fragment.mountedFragmentProtection
        }

mountedFragmentLiveKey :: FrontendSurfaceMountedFragment -> Maybe LiveFragmentKey
mountedFragmentLiveKey fragment =
    case fragment.mountedFragmentKey.fragmentKind of
        "roster-content" -> Just RosterContentFragment
        "roster-grid-toolbar" -> Just RosterGridToolbarFragment
        "roster-grid-frame" -> Just RosterGridFrameFragment
        "roster-day-columns" -> Just RosterDayColumnsFragment
        "roster-day-rail" -> Just RosterDayRailFragment
        "roster-wage-rail" -> Just RosterWageRailFragment
        "roster-slots-grid" -> Just RosterSlotsGridFragment
        "roster-staff-panel" -> Just RosterStaffPanelFragment
        "roster-day-section" -> RosterDaySectionFragment <$> parseFragmentRosterDayId fragment.mountedFragmentKey.fragmentParams
        "roster-row" -> RosterRowFragment <$> parseFragmentRosterDayId fragment.mountedFragmentKey.fragmentParams <*> parseFragmentRowIndex fragment.mountedFragmentKey.fragmentParams
        _ -> Nothing

mountedFragmentProtectionPolicy :: FrontendSurfaceProtection -> LiveFragmentProtection
mountedFragmentProtectionPolicy = \case
    FrontendSurfaceReplace -> NoProtection
    FrontendSurfaceFocusedField -> NoProtection

rosterSurfaceHandlers :: RosterWeekScopeValue -> RosterMountedFragmentPlan -> SurfaceImplHandlers Surface.RosterSurface
rosterSurfaceHandlers scope _plan =
    SurfaceImplHandlers
        { surfaceScopeHandlers =
            FrontendSurfaceScopeHandler
                { scopeHandlerDefaultValue = rosterWeekScopeFields scope
                , scopeHandlerKey = \fields ->
                    let venueId = fromMaybe (tshow scope.rosterWeekVenueId) (getSurfaceField @Surface.VenueId fields)
                        rosterGroupId = fromMaybe (tshow scope.rosterWeekGroupId) (getSurfaceField @Surface.RosterGroupId fields)
                        weekOffset = fromMaybe scope.rosterWeekWeekOffset (getSurfaceField @Surface.WeekOffset fields)
                     in "roster:" <> venueId <> ":" <> rosterGroupId <> ":" <> tshow weekOffset
                }
                `HandlerCons` HandlerNil
        , surfaceMountStateHandlers = HandlerNil
        , surfaceFragmentHandlers =
            FrontendSurfaceFragmentHandler
                { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                , fragmentHandlerMountedFragment = const (rosterContentMountedFragment scope)
                , fragmentHandlerRender = const mempty
                }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                    , fragmentHandlerMountedFragment = const (rosterGridToolbarMountedFragment scope)
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                    , fragmentHandlerMountedFragment = const (rosterGridFrameMountedFragment scope)
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                    , fragmentHandlerMountedFragment = const (rosterDayColumnsMountedFragment scope)
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                    , fragmentHandlerMountedFragment = const (rosterDayRailMountedFragment scope)
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                    , fragmentHandlerMountedFragment = const (rosterWageRailMountedFragment scope)
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                    , fragmentHandlerMountedFragment = const (rosterSlotsGridMountedFragment scope)
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                    , fragmentHandlerMountedFragment = const (rosterStaffPanelMountedFragment scope)
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues (Aeson.object ["rosterDayId" Aeson..= tshow placeholderRosterDayId])
                    , fragmentHandlerMountedFragment = \fields ->
                        let rosterDayId = maybe (coerce placeholderRosterDayId) coerce (getSurfaceField @Surface.RosterDayId fields >>= UUID.fromString . cs)
                         in rosterDaySectionMountedFragment scope rosterDayId
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues (Aeson.object ["rosterDayId" Aeson..= tshow placeholderRosterDayId, "rowIndex" Aeson..= (0 :: Int)])
                    , fragmentHandlerMountedFragment = \fields ->
                        let rosterDayId = maybe (coerce placeholderRosterDayId) coerce (getSurfaceField @Surface.RosterDayId fields >>= UUID.fromString . cs)
                            rowIndex = fromMaybe 0 (getSurfaceField @Surface.RowIndex fields)
                         in rosterRowMountedFragment scope rosterDayId rowIndex
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` HandlerNil
        , surfaceActionHandlers = HandlerNil
        , surfaceIntentHandlers = HandlerNil
        }

rosterWeekScopeFields :: RosterWeekScopeValue -> FrontendSurfaceFieldValues '[ 'Field Surface.VenueId 'WireUUID, 'Field Surface.RosterGroupId 'WireUUID, 'Field Surface.WeekOffset 'WireInt]
rosterWeekScopeFields scope =
    frontendSurfaceFieldValues (Aeson.object
        [ "venueId" Aeson..= tshow scope.rosterWeekVenueId
        , "rosterGroupId" Aeson..= tshow scope.rosterWeekGroupId
        , "weekOffset" Aeson..= scope.rosterWeekWeekOffset
        ])

placeholderRosterDayId :: UUID.UUID
placeholderRosterDayId = fromMaybe (error "invalid placeholder roster day id") (UUID.fromString "00000000-0000-0000-0000-000000000000")

rosterContentMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterContentMountedFragment scope =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey "roster-content" Aeson.Null
        , mountedFragmentTargetId = rosterContentFragmentId
        , mountedFragmentUrl = rosterWeekContentFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLoadPolicy = "eager"
        }

rosterGridToolbarMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterGridToolbarMountedFragment scope =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey "roster-grid-toolbar" Aeson.Null
        , mountedFragmentTargetId = rosterGridToolbarFragmentId
        , mountedFragmentUrl = rosterWeekGridToolbarFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLoadPolicy = "eager"
        }

rosterGridFrameMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterGridFrameMountedFragment scope =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey "roster-grid-frame" Aeson.Null
        , mountedFragmentTargetId = rosterGridFrameFragmentId
        , mountedFragmentUrl = rosterWeekGridFrameFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLoadPolicy = "eager"
        }

rosterDayColumnsMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterDayColumnsMountedFragment scope =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey "roster-day-columns" Aeson.Null
        , mountedFragmentTargetId = rosterDayColumnsFragmentId
        , mountedFragmentUrl = rosterWeekDayColumnsFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLoadPolicy = "eager"
        }

rosterDayRailMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterDayRailMountedFragment scope =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey "roster-day-rail" Aeson.Null
        , mountedFragmentTargetId = rosterDayRailFragmentId
        , mountedFragmentUrl = rosterWeekDayRailFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLoadPolicy = "eager"
        }

rosterWageRailMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterWageRailMountedFragment scope =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey "roster-wage-rail" Aeson.Null
        , mountedFragmentTargetId = rosterWageRailFragmentId
        , mountedFragmentUrl = rosterWeekWageRailFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLoadPolicy = "eager"
        }

rosterSlotsGridMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterSlotsGridMountedFragment scope =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey "roster-slots-grid" Aeson.Null
        , mountedFragmentTargetId = rosterSlotsGridFragmentId
        , mountedFragmentUrl = rosterWeekSlotsGridFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLoadPolicy = "eager"
        }

rosterStaffPanelMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterStaffPanelMountedFragment scope =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey "roster-staff-panel" Aeson.Null
        , mountedFragmentTargetId = rosterStaffPanelFragmentId
        , mountedFragmentUrl = rosterWeekStaffPanelFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLoadPolicy = "lazy"
        }

rosterDaySectionMountedFragment :: RosterWeekScopeValue -> Id RosterDay -> FrontendSurfaceMountedFragment
rosterDaySectionMountedFragment scope rosterDayId =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey "roster-day-section" (Aeson.object ["rosterDayId" Aeson..= tshow rosterDayId])
        , mountedFragmentTargetId = rosterDaySectionDomId rosterDayId
        , mountedFragmentUrl = rosterWeekDaySectionFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId rosterDayId
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLoadPolicy = "lazy"
        }

rosterRowMountedFragment :: RosterWeekScopeValue -> Id RosterDay -> Int -> FrontendSurfaceMountedFragment
rosterRowMountedFragment scope rosterDayId rowIndex =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey "roster-row" (Aeson.object ["rosterDayId" Aeson..= tshow rosterDayId, "rowIndex" Aeson..= rowIndex])
        , mountedFragmentTargetId = rosterRowDomIdText rosterDayId rowIndex
        , mountedFragmentUrl = rosterWeekRowFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId rosterDayId rowIndex
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLoadPolicy = "lazy"
        }
