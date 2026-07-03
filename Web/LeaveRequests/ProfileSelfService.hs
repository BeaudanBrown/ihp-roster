module Web.LeaveRequests.ProfileSelfService
    ( profileLeaveRequestFormFragmentId
    , profileleaveRequestsContentLiveFragmentId
    , profileLeaveRequestsListFragmentId
    , profileLeaveTargetFragmentIds
    , renderProfileLeaveRequestFormFragment
    , renderProfileleaveRequestsContentLiveFragment
    , renderProfileleaveRequestsContentLiveFragmentWithSwap
    ) where

import IHP.Prelude
import Web.View.Profiles.Edit

profileLeaveTargetFragmentIds :: [Text]
profileLeaveTargetFragmentIds =
    [ profileleaveRequestsContentLiveFragmentId
    , profileLeaveRequestFormFragmentId
    , profileLeaveRequestsListFragmentId
    ]
