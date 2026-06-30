{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.Profiles.LeaveFragments
    ( ProfileLeaveFragmentModel (..)
    , fetchProfileLeaveFragmentModel
    , renderProfileLeaveFragment
    , respondWithProfileLeaveFragments
    ) where

import Application.Helper.LiveSurface (FragmentRenderMode (..),
                                       normalizeTypedLiveSurfaceFragments)
import Application.Helper.ProfileLeave (buildDefaultLeaveRequest,
                                        fetchStaffLeaveRequests)
import Application.Helper.Profiling (respondHtmlProfiled)
import Application.Helper.View.Oob (outerHtmlOobSwap)
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.Profiles.LiveUpdates
import Web.View.Profiles.Edit (renderProfileLeaveRequestsContentFragmentWithSwap)

data ProfileLeaveFragmentModel = ProfileLeaveFragmentModel
    { profileLeaveModelStaff    :: !Staff
    , profileLeaveModelForm     :: !LeaveRequest
    , profileLeaveModelRequests :: ![LeaveRequest]
    }

fetchProfileLeaveFragmentModel :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Staff -> IO ProfileLeaveFragmentModel
fetchProfileLeaveFragmentModel staff = do
    ensureRecordInCurrentVenue staff.venueId
    profileLeaveModelForm <- buildDefaultLeaveRequest
    profileLeaveModelRequests <- fetchStaffLeaveRequests staff
    pure ProfileLeaveFragmentModel
        { profileLeaveModelStaff = staff
        , profileLeaveModelForm
        , profileLeaveModelRequests
        }

renderProfileLeaveFragment :: (?context :: ControllerContext, ?request :: Request) => FragmentRenderMode -> ProfileLeaveFragmentModel -> ProfileLeaveFragment -> Blaze.Html
renderProfileLeaveFragment renderMode model ProfileLeaveRequestsLiveFragment =
    renderProfileLeaveRequestsContentFragmentWithSwap
        maybeSwap
        model.profileLeaveModelStaff
        model.profileLeaveModelForm
        model.profileLeaveModelRequests
    where
        maybeSwap = case renderMode of
            FragmentPlain        -> Nothing
            FragmentOob swapAttr -> swapAttr

respondWithProfileLeaveFragments :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Staff -> [ProfileLeaveFragment] -> Blaze.Html -> IO ()
respondWithProfileLeaveFragments staff fragments extraHtml = do
    model <- fetchProfileLeaveFragmentModel staff
    let surfaceKey = currentProfileLeaveSurfaceKey staff
    let normalizedFragments = normalizeTypedLiveSurfaceFragments profileLeaveRequestsLiveSurfaceDefinition surfaceKey fragments
    respondHtmlProfiled $
        mconcat (map (renderProfileLeaveFragment (FragmentOob outerHtmlOobSwap) model) normalizedFragments)
            <> extraHtml
