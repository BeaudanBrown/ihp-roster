module Web.RosterWeeks.LiveUpdates
    ( coalesceRosterWeekFragmentRefs
    , refreshRosterContent
    , refreshRosterContentAndStaffPanel
    , refreshRosterDaySections
    , refreshRosterFragments
    , refreshRosterFragmentsAndSetActorRefresh
    , refreshRosterRows
    ) where

import Application.Helper.LiveSurface (LiveSurfaceMutation (..),
                                       broadcastSurfaceFragments,
                                       performTypedLiveSurfaceMutationAndSetActorRefresh)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.UUID as UUID
import Web.Controller.Prelude
import Web.RosterWeeks.Projection (buildRosterProjectionScope,
                                   rosterContentAndStaffPanelFragments,
                                   rosterContentFragment,
                                   rosterDaySectionFragment,
                                   rosterDaySectionFragments,
                                   rosterRowFragments)
import Web.RosterWeeks.LiveSurface (rosterLiveSurfaceDefinition)
import Web.RosterWeeks.RenderData (keepCurrentRosterWeekProjectionHot)
import Web.RosterWeeks.Types (RosterProjectionFragment (..))

refreshRosterFragments ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id RosterGroup ->
    Int ->
    [RosterProjectionFragment] ->
    IO ()
refreshRosterFragments rosterGroupId weekOffset fragments =
    unless (null coalescedFragments) do
        broadcastSurfaceFragments
            rosterLiveSurfaceDefinition
            (buildRosterProjectionScope rosterGroupId weekOffset)
            coalescedFragments
        keepCurrentRosterWeekProjectionHot rosterGroupId weekOffset
    where
        coalescedFragments =
            coalesceRosterWeekFragmentRefs rosterGroupId weekOffset fragments

refreshRosterFragmentsAndSetActorRefresh ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id RosterGroup ->
    Int ->
    [RosterProjectionFragment] ->
    IO ()
refreshRosterFragmentsAndSetActorRefresh rosterGroupId weekOffset actorFragments =
    unless (null passiveFragments && null actorFragments) do
        _ <-
            performTypedLiveSurfaceMutationAndSetActorRefresh
                rosterLiveSurfaceDefinition
                LiveSurfaceMutation
                    { liveMutationScope = buildRosterProjectionScope rosterGroupId weekOffset
                    , liveMutationActorFragments = actorFragments
                    , liveMutationPassiveFragments = passiveFragments
                    }
        unless (null passiveFragments) do
            keepCurrentRosterWeekProjectionHot rosterGroupId weekOffset
    where
        passiveFragments =
            coalesceRosterWeekFragmentRefs rosterGroupId weekOffset actorFragments

refreshRosterContent ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id RosterGroup ->
    Int ->
    IO ()
refreshRosterContent rosterGroupId weekOffset =
    refreshRosterFragments rosterGroupId weekOffset [rosterContentFragment]

refreshRosterContentAndStaffPanel ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id RosterGroup ->
    Int ->
    IO ()
refreshRosterContentAndStaffPanel rosterGroupId weekOffset =
    refreshRosterFragments rosterGroupId weekOffset rosterContentAndStaffPanelFragments

refreshRosterRows ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id RosterGroup ->
    Int ->
    [(UUID.UUID, Int)] ->
    IO ()
refreshRosterRows rosterGroupId weekOffset rowKeys =
    refreshRosterFragments rosterGroupId weekOffset (rosterRowFragments rowKeys)

refreshRosterDaySections ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id RosterGroup ->
    Int ->
    [UUID.UUID] ->
    IO ()
refreshRosterDaySections rosterGroupId weekOffset dayIds =
    refreshRosterFragments rosterGroupId weekOffset (rosterDaySectionFragments dayIds)

coalesceRosterWeekFragmentRefs ::
    Id RosterGroup ->
    Int ->
    [RosterProjectionFragment] ->
    [RosterProjectionFragment]
coalesceRosterWeekFragmentRefs rosterGroupId weekOffset fragments
    | hasRosterContent =
        filter (not . isCoveredByRosterContent) dedupedFragments
    | Set.size coveredDayIds >= rosterContentCollapseDayThreshold =
        rosterContentFragment : filter (not . isRosterDayOrRow) dedupedFragments
    | otherwise =
        collapseRowsToDaySections coveredDayIds dedupedFragments
    where
        dedupedFragments =
            nub fragments

        hasRosterContent =
            any isRosterContent dedupedFragments

        explicitDayIds =
            Set.fromList (mapMaybe rosterDaySectionId dedupedFragments)

        hotRowDayIds =
            Map.keysSet (Map.filter (>= rosterRowCollapseThreshold) rowDayCounts)

        rowDayCounts =
            Map.fromListWith (+) [(dayId, 1 :: Int) | dayId <- mapMaybe rosterRowDayId dedupedFragments]

        coveredDayIds =
            Set.union explicitDayIds hotRowDayIds

        collapseRowsToDaySections coveredDayIds' =
            reverse . fst . foldl' (collapseOne coveredDayIds') ([], Set.empty)

        collapseOne coveredDayIds' (kept, emittedDayIds) fragment =
            case rosterCoveredDayId fragment of
                Just dayId | Set.member dayId coveredDayIds' ->
                    if Set.member dayId emittedDayIds
                        then (kept, emittedDayIds)
                        else
                            ( daySectionRef dayId : kept
                            , Set.insert dayId emittedDayIds
                            )
                _ ->
                    (fragment : kept, emittedDayIds)

        daySectionRef =
            rosterDaySectionFragment

rosterRowCollapseThreshold :: Int
rosterRowCollapseThreshold =
    3

rosterContentCollapseDayThreshold :: Int
rosterContentCollapseDayThreshold =
    4

isRosterContent :: RosterProjectionFragment -> Bool
isRosterContent RosterProjectionContent = True
isRosterContent _ = False

isRosterDayOrRow :: RosterProjectionFragment -> Bool
isRosterDayOrRow fragment =
    isJust (rosterCoveredDayId fragment)

isCoveredByRosterContent :: RosterProjectionFragment -> Bool
isCoveredByRosterContent RosterProjectionDaySection {} = True
isCoveredByRosterContent RosterProjectionRow {} = True
isCoveredByRosterContent _ = False

rosterCoveredDayId :: RosterProjectionFragment -> Maybe UUID.UUID
rosterCoveredDayId fragment =
    rosterDaySectionId fragment <|> rosterRowDayId fragment

rosterDaySectionId :: RosterProjectionFragment -> Maybe UUID.UUID
rosterDaySectionId (RosterProjectionDaySection dayId) = Just dayId
rosterDaySectionId _ = Nothing

rosterRowDayId :: RosterProjectionFragment -> Maybe UUID.UUID
rosterRowDayId (RosterProjectionRow dayId _) = Just dayId
rosterRowDayId _ = Nothing
