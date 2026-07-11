module Web.LeaveRequests.ProfileSelfService
    ( profileLeaveRequestFormFragmentId
    , profileLeaveRequestsListFragmentId
    , profileLeaveTargetFragmentIds
    , renderProfileLeaveRequestFormFragment
    ) where

import IHP.Prelude
import Web.View.Profiles.Edit

profileLeaveTargetFragmentIds :: [Text]
profileLeaveTargetFragmentIds =
    [ profileLeaveRequestFormFragmentId
    , profileLeaveRequestsListFragmentId
    ]
