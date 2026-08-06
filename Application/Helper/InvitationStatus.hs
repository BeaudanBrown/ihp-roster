{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Application.Helper.InvitationStatus
    ( invitationStatusAllowsRenewal
    ) where

import Generated.Types (InvitationStatusEnum (..))
import IHP.Prelude

-- | Whether an invitation in this lifecycle state may be renewed. Callers may
-- impose additional record-level checks such as acceptance or expiry time.
invitationStatusAllowsRenewal :: InvitationStatusEnum -> Bool
invitationStatusAllowsRenewal InvitationStatusEnumPending = True
invitationStatusAllowsRenewal Accepted                    = False
invitationStatusAllowsRenewal Revoked                     = False
