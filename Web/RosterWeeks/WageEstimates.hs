module Web.RosterWeeks.WageEstimates
    ( RosterPayAudience (..)
    , rosterPayAudienceFor
    , rosterPayAudienceForCurrentUser
    , rosterPayAudienceLabel
    , rosterWageSlotsForAudience
    ) where

import Generated.Types
import Web.Controller.Prelude

data RosterPayAudience = PersonalRosterPayAudience | ManagementRosterPayAudience
    deriving (Eq, Show)

rosterPayAudienceFor :: Bool -> Maybe VenueRoleEnum -> Bool -> Bool -> Maybe RosterPayAudience
rosterPayAudienceFor unimpersonatedSupport effectiveRole managementMode hasLinkedStaff
    | unimpersonatedSupport = Just ManagementRosterPayAudience
    | managementMode && effectiveRole `elem` map Just [VenueAdmin, VenueOwner] = Just ManagementRosterPayAudience
    | hasLinkedStaff && effectiveRole `elem` map Just [Worker, Supervisor, Manager, VenueAdmin, VenueOwner] = Just PersonalRosterPayAudience
    | otherwise = Nothing

rosterPayAudienceForCurrentUser :: (?context :: ControllerContext) => Maybe (RosterPayAudience, Maybe (Id Staff))
rosterPayAudienceForCurrentUser = do
    audience <- rosterPayAudienceFor currentUserIsUnimpersonatedSuperAdmin effectiveVenueRoleOrNothing hasManagementMode (isJust effectiveStaffOrNothing)
    let staffId = case audience of
            ManagementRosterPayAudience -> Nothing
            PersonalRosterPayAudience -> (.id) <$> effectiveStaffOrNothing
    pure (audience, staffId)

rosterPayAudienceLabel :: RosterPayAudience -> Text
rosterPayAudienceLabel PersonalRosterPayAudience = "Your expected pay"
rosterPayAudienceLabel ManagementRosterPayAudience = "Expected gross wages"

rosterWageSlotsForAudience :: (RosterPayAudience, Maybe (Id Staff)) -> [RosterSlot] -> [RosterSlot]
rosterWageSlotsForAudience (ManagementRosterPayAudience, _) slots = slots
rosterWageSlotsForAudience (PersonalRosterPayAudience, Just staffId) slots =
    filter ((== Just (unpackId staffId)) . (.staffId)) slots
rosterWageSlotsForAudience (PersonalRosterPayAudience, Nothing) _ = []
