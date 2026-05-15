module Web.RosterWeeks.LiveUpdates
    ( broadcastRosterWeekInvalidation
    , coalesceRosterWeekFragmentRefs
    ) where

import Application.Helper.LiveUpdate (LiveFragmentKey (..),
                                      LiveFragmentRef (..),
                                      broadcastLiveInvalidation,
                                      coalesceLiveFragmentRefs,
                                      liveUpdateSourceClientId)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.UUID as UUID
import Web.Controller.Prelude
import Web.RosterWeeks.Projection (buildRosterContentFragmentRef,
                                   buildRosterDaySectionFragmentRef,
                                   buildRosterWeekScope)
import Web.RosterWeeks.RenderData (keepCurrentRosterWeekProjectionHot)

broadcastRosterWeekInvalidation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id RosterGroup ->
    Int ->
    [LiveFragmentRef] ->
    IO ()
broadcastRosterWeekInvalidation rosterGroupId weekOffset fragments =
    unless (null coalescedFragments) do
        liftIO $
            broadcastLiveInvalidation
                (buildRosterWeekScope rosterGroupId weekOffset)
                liveUpdateSourceClientId
                coalescedFragments
        keepCurrentRosterWeekProjectionHot rosterGroupId weekOffset
    where
        coalescedFragments =
            coalesceRosterWeekFragmentRefs rosterGroupId weekOffset fragments

coalesceRosterWeekFragmentRefs ::
    (?context :: ControllerContext) =>
    Id RosterGroup ->
    Int ->
    [LiveFragmentRef] ->
    [LiveFragmentRef]
coalesceRosterWeekFragmentRefs rosterGroupId weekOffset fragments
    | hasRosterContent =
        coalesceLiveFragmentRefs (filter (not . isCoveredByRosterContent) dedupedFragments)
    | Set.size coveredDayIds >= rosterContentCollapseDayThreshold =
        coalesceLiveFragmentRefs (buildRosterContentFragmentRef rosterGroupId weekOffset : filter (not . isRosterDayOrRow) dedupedFragments)
    | otherwise =
        coalesceLiveFragmentRefs (collapseRowsToDaySections coveredDayIds dedupedFragments)
    where
        dedupedFragments =
            coalesceLiveFragmentRefs fragments

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
                            ( daySectionRef dayId fragment : kept
                            , Set.insert dayId emittedDayIds
                            )
                _ ->
                    (fragment : kept, emittedDayIds)

        daySectionRef dayId fragment =
            case fragment.fragmentKey of
                RosterDaySectionFragment {} -> fragment
                _                            -> buildRosterDaySectionFragmentRef rosterGroupId weekOffset dayId

rosterRowCollapseThreshold :: Int
rosterRowCollapseThreshold =
    3

rosterContentCollapseDayThreshold :: Int
rosterContentCollapseDayThreshold =
    4

isRosterContent :: LiveFragmentRef -> Bool
isRosterContent fragment =
    case fragment.fragmentKey of
        RosterContentFragment -> True
        _                     -> False

isRosterDayOrRow :: LiveFragmentRef -> Bool
isRosterDayOrRow fragment =
    isJust (rosterCoveredDayId fragment)

isCoveredByRosterContent :: LiveFragmentRef -> Bool
isCoveredByRosterContent fragment =
    case fragment.fragmentKey of
        RosterDaySectionFragment {} -> True
        RosterRowFragment {}        -> True
        _                           -> False

rosterCoveredDayId :: LiveFragmentRef -> Maybe UUID.UUID
rosterCoveredDayId fragment =
    rosterDaySectionId fragment <|> rosterRowDayId fragment

rosterDaySectionId :: LiveFragmentRef -> Maybe UUID.UUID
rosterDaySectionId fragment =
    case fragment.fragmentKey of
        RosterDaySectionFragment { rosterDayId = dayId } -> Just dayId
        _                                                -> Nothing

rosterRowDayId :: LiveFragmentRef -> Maybe UUID.UUID
rosterRowDayId fragment =
    case fragment.fragmentKey of
        RosterRowFragment { rosterDayId = dayId } -> Just dayId
        _                                        -> Nothing
