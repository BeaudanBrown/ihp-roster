module Web.LeaveRequests.ProfileSelfService
    ( profileLeaveRequestFormFragmentId
    , profileLeaveRequestsContentFragmentId
    , profileLeaveRequestsListFragmentId
    , profileLeaveTargetFragmentIds
    , renderProfileLeaveRequestFormFragment
    , renderProfileLeaveRequestsContentFragment
    , renderProfileLeaveRequestsListFragmentOob
    ) where

import IHP.Prelude
import Web.View.Profiles.Edit

profileLeaveTargetFragmentIds :: [Text]
profileLeaveTargetFragmentIds =
    [ profileLeaveRequestsContentFragmentId
    , profileLeaveRequestFormFragmentId
    , profileLeaveRequestsListFragmentId
    ]
