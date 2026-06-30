module Web.LeaveRequests.ProfileSelfService
    ( profileLeaveRequestFormFragmentId
    , profileLeaveRequestsContentFragmentId
    , profileLeaveRequestsListFragmentId
    , profileLeaveTargetFragmentIds
    , renderProfileLeaveRequestFormFragment
    , renderProfileLeaveRequestsContentFragment
    , renderProfileLeaveRequestsContentFragmentWithSwap
    ) where

import IHP.Prelude
import Web.View.Profiles.Edit

profileLeaveTargetFragmentIds :: [Text]
profileLeaveTargetFragmentIds =
    [ profileLeaveRequestsContentFragmentId
    , profileLeaveRequestFormFragmentId
    , profileLeaveRequestsListFragmentId
    ]
