{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.Profiles.LeaveFragments
    ( FragmentRenderMode (..)
    , ProfileLeaveFragmentModel (..)
    , fetchProfileLeaveFragmentModel
    , renderProfileLeaveFragment
    ) where

import Application.Helper.FrontendContract.Surface.FragmentRender (FragmentRenderMode (..))
import Application.Helper.ProfileLeave (buildDefaultLeaveRequest,
                                        fetchStaffLeaveRequests)
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.Profiles.LiveUpdates
import Web.View.Profiles.Edit (renderProfileleaveRequestsContentLiveFragmentWithSwap)

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
    renderProfileleaveRequestsContentLiveFragmentWithSwap
        maybeSwap
        model.profileLeaveModelStaff
        model.profileLeaveModelForm
        model.profileLeaveModelRequests
    where
        maybeSwap = case renderMode of
            FragmentPlain        -> Nothing
            FragmentOob swapAttr -> swapAttr
