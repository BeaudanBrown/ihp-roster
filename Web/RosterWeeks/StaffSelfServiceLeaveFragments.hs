{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.RosterWeeks.StaffSelfServiceLeaveFragments
    ( RosterStaffSelfServiceLeaveFragment (..)
    , RosterStaffSelfServiceLeaveFragmentModel (..)
    , buildDefaultRosterStaffSelfServiceLeaveRequest
    , fetchRosterStaffSelfServiceLeaveFragmentModel
    , renderRosterStaffSelfServiceLeaveFragment
    , respondWithRosterStaffSelfServiceLeaveFragments
    ) where

import Application.Helper.FrontendSurface.FragmentRender (FragmentRenderMode (..))
import Application.Helper.Profiling (respondHtmlProfiled)
import Application.Helper.View.Oob (outerHtmlOobSwap)
import qualified Data.List as List
import qualified Data.Time.Calendar as Calendar
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.View.RosterWeeks.StaffSelfServicePanel (renderRosterStaffSelfServiceLeaveFormFragmentWithSwap)

data RosterStaffSelfServiceLeaveFragment
    = RosterStaffSelfServiceLeaveFormFragment
    deriving (Eq, Show)

newtype RosterStaffSelfServiceLeaveFragmentModel = RosterStaffSelfServiceLeaveFragmentModel
    { rosterStaffSelfServiceLeaveModelForm :: LeaveRequest
    }

buildDefaultRosterStaffSelfServiceLeaveRequest :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO LeaveRequest
buildDefaultRosterStaffSelfServiceLeaveRequest = do
    venueConfig <- fetchVenueConfig
    operationalDay <- currentOperationalDayForVenue venueConfig
    pure $
        newRecord @LeaveRequest
            |> set #startDate operationalDay
            |> set #endDate (Calendar.addDays 1 operationalDay)

fetchRosterStaffSelfServiceLeaveFragmentModel :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO RosterStaffSelfServiceLeaveFragmentModel
fetchRosterStaffSelfServiceLeaveFragmentModel = do
    rosterStaffSelfServiceLeaveModelForm <- buildDefaultRosterStaffSelfServiceLeaveRequest
    pure RosterStaffSelfServiceLeaveFragmentModel { rosterStaffSelfServiceLeaveModelForm }

renderRosterStaffSelfServiceLeaveFragment :: (?context :: ControllerContext, ?request :: Request) => FragmentRenderMode -> RosterStaffSelfServiceLeaveFragmentModel -> RosterStaffSelfServiceLeaveFragment -> Blaze.Html
renderRosterStaffSelfServiceLeaveFragment renderMode model RosterStaffSelfServiceLeaveFormFragment =
    renderRosterStaffSelfServiceLeaveFormFragmentWithSwap maybeSwap model.rosterStaffSelfServiceLeaveModelForm
    where
        maybeSwap = case renderMode of
            FragmentPlain        -> Nothing
            FragmentOob swapAttr -> swapAttr

respondWithRosterStaffSelfServiceLeaveFragments :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => [RosterStaffSelfServiceLeaveFragment] -> Blaze.Html -> IO ()
respondWithRosterStaffSelfServiceLeaveFragments fragments extraHtml = do
    model <- fetchRosterStaffSelfServiceLeaveFragmentModel
    setHeader ("HX-Reswap", "none")
    respondHtmlProfiled $
        mconcat (map (renderRosterStaffSelfServiceLeaveFragment (FragmentOob outerHtmlOobSwap) model) (List.nub fragments))
            <> extraHtml
