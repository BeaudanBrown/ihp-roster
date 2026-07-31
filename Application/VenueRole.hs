{-# LANGUAGE TypeApplications #-}

module Application.VenueRole
    ( assignableVenueRolesFor
    , canAssignVenueRole
    , hasVenueRole
    , parseVenueRole
    , venueRoleLabel
    , venueRoleMailLabel
    , venueRoleToText
    ) where

import Data.List (find)
import qualified Data.Text as Text
import Generated.Types
import IHP.Prelude
import IHP.ViewPrelude (InputValue (inputValue))

parseVenueRole :: Text -> Maybe VenueRoleEnum
parseVenueRole value =
    find ((== value) . inputValue) [minBound .. maxBound]

venueRoleToText :: VenueRoleEnum -> Text
venueRoleToText = inputValue

hasVenueRole :: VenueRoleEnum -> VenueRoleEnum -> Bool
hasVenueRole actualRole minimumRole = venueRoleRank actualRole >= venueRoleRank minimumRole

venueRoleRank :: VenueRoleEnum -> Int
venueRoleRank Worker     = 0
venueRoleRank Supervisor = 1
venueRoleRank Manager    = 2
venueRoleRank VenueAdmin = 3
venueRoleRank VenueOwner = 4

assignableVenueRolesFor :: Bool -> Maybe VenueRoleEnum -> [VenueRoleEnum]
assignableVenueRolesFor actorIsSuperAdmin actorRole =
    filter canAssignTarget [minBound .. maxBound]
  where
    canAssignTarget targetRole =
        venueRoleAssignmentClass targetRole == StandardAssignable
            || actorCanAssignOwner actorIsSuperAdmin actorRole

canAssignVenueRole :: Bool -> Maybe VenueRoleEnum -> VenueRoleEnum -> VenueRoleEnum -> Bool
canAssignVenueRole actorIsSuperAdmin actorRole existingRole submittedRole =
    actorCanAssignOwner actorIsSuperAdmin actorRole
        || ( venueRoleAssignmentClass existingRole == StandardAssignable
                && venueRoleAssignmentClass submittedRole == StandardAssignable
           )

actorCanAssignOwner :: Bool -> Maybe VenueRoleEnum -> Bool
actorCanAssignOwner actorIsSuperAdmin actorRole =
    actorIsSuperAdmin || maybe False ((== OwnerAssignable) . venueRoleAssignmentClass) actorRole

data VenueRoleAssignmentClass
    = StandardAssignable
    | OwnerAssignable
    deriving (Eq)

venueRoleAssignmentClass :: VenueRoleEnum -> VenueRoleAssignmentClass
venueRoleAssignmentClass Worker     = StandardAssignable
venueRoleAssignmentClass Supervisor = StandardAssignable
venueRoleAssignmentClass Manager    = StandardAssignable
venueRoleAssignmentClass VenueAdmin = StandardAssignable
venueRoleAssignmentClass VenueOwner = OwnerAssignable

venueRoleLabel :: VenueRoleEnum -> Text
venueRoleLabel Worker     = "Worker"
venueRoleLabel Supervisor = "Supervisor"
venueRoleLabel Manager    = "Manager"
venueRoleLabel VenueAdmin = "Venue Admin"
venueRoleLabel VenueOwner = "Venue Owner"

venueRoleMailLabel :: VenueRoleEnum -> Text
venueRoleMailLabel = Text.toLower . venueRoleLabel
