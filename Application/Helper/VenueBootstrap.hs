module Application.Helper.VenueBootstrap
    ( createVenueWithBootstrapConfig
    , createVenueWithBootstrapConfigInCurrentTransaction
    , defaultStaffNameFromEmail
    , defaultVenueBootstrapTimezone
    , ensureLinkedStaffRecord
    , provisionVenueMembership
    , provisionVenueUser
    ) where

import Application.Helper.Controller (defaultWeekOffsetEpochForStartDay,
                                      unsafeEnumFromText)
import Application.Helper.RosterGroups (ensureVenueDefaultRosterGroup,
                                        ensureVenueRosterDefaults)
import qualified Data.Char as Char
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude

defaultVenueBootstrapTimezone :: Text
defaultVenueBootstrapTimezone = "Australia/Melbourne"

createVenueWithBootstrapConfig :: (?modelContext :: ModelContext) => Text -> Text -> Int -> IO (Venue, VenueConfig)
createVenueWithBootstrapConfig name timezone rosterWeekStartsOn =
    withTransaction do
        createVenueWithBootstrapConfigInCurrentTransaction name timezone rosterWeekStartsOn

createVenueWithBootstrapConfigInCurrentTransaction :: (?modelContext :: ModelContext) => Text -> Text -> Int -> IO (Venue, VenueConfig)
createVenueWithBootstrapConfigInCurrentTransaction name timezone rosterWeekStartsOn = do
    venue <-
        newRecord @Venue
            |> set #name name
            |> set #status (unsafeEnumFromText @VenueStatusEnum "active")
            |> createRecord
    venueConfig <-
        newRecord @VenueConfig
            |> set #venueId (unpackId venue.id)
            |> set #timezone timezone
            |> set #rosterWeekStartsOn rosterWeekStartsOn
            |> set #weekOffsetEpoch (defaultWeekOffsetEpochForStartDay rosterWeekStartsOn)
            |> set #lateToEarlyMinStartGapMinutes 600
            |> set #staffTimesheetEditWindowDays 7
            |> createRecord
    _ <- ensureVenueRosterDefaults venue
    pure (venue, venueConfig)

provisionVenueMembership :: (?modelContext :: ModelContext) => Venue -> User -> Text -> IO VenueMembership
provisionVenueMembership venue user venueRole =
    query @VenueMembership
        |> filterWhere (#venueId, unpackId venue.id)
        |> filterWhere (#userId, unpackId user.id)
        |> fetchOneOrNothing
        >>= \case
            Just membership ->
                membership
                    |> set #venueRole (unsafeEnumFromText @VenueRoleEnum venueRole)
                    |> updateRecord
            Nothing ->
                newRecord @VenueMembership
                    |> set #venueId (unpackId venue.id)
                    |> set #userId (unpackId user.id)
                    |> set #venueRole (unsafeEnumFromText @VenueRoleEnum venueRole)
                    |> createRecord

provisionVenueUser :: (?modelContext :: ModelContext) => Venue -> User -> Text -> Text -> Text -> IO (VenueMembership, Staff)
provisionVenueUser venue user venueRole firstName lastName = do
    membership <- provisionVenueMembership venue user venueRole
    staff <- ensureLinkedStaffRecord venue user firstName lastName
    pure (membership, staff)

ensureLinkedStaffRecord :: (?modelContext :: ModelContext) => Venue -> User -> Text -> Text -> IO Staff
ensureLinkedStaffRecord venue user firstName lastName =
    query @Staff
        |> filterWhere (#venueId, unpackId venue.id)
        |> filterWhere (#userId, Just (unpackId user.id))
        |> fetchOneOrNothing
        >>= \case
            Just staff ->
                if staff.isActive
                    then pure staff
                    else staff
                        |> set #isActive True
                        |> updateRecord
            Nothing ->
                createLinkedPlaceholderStaffRecord venue user firstName lastName

createLinkedPlaceholderStaffRecord :: (?modelContext :: ModelContext) => Venue -> User -> Text -> Text -> IO Staff
createLinkedPlaceholderStaffRecord venue user firstName lastName = do
    staff <-
        newRecord @Staff
            |> set #venueId (unpackId venue.id)
            |> set #userId (Just (unpackId user.id))
            |> set #firstName firstName
            |> set #lastName lastName
            |> set #preferredName Nothing
            |> set #phone "0400000000"
            |> set #emergencyContactName "Emergency Contact"
            |> set #emergencyContactPhone "0411111111"
            |> set #idealShiftsPerWeek 0
            |> set #isActive True
            |> createRecord
    rosterGroup <- ensureVenueDefaultRosterGroup venue
    _ <-
        newRecord @StaffRosterGroup
            |> set #staffId (unpackId staff.id)
            |> set #rosterGroupId (unpackId rosterGroup.id)
            |> createRecord
    pure staff

defaultStaffNameFromEmail :: Text -> (Text, Text)
defaultStaffNameFromEmail emailAddress =
    case filter (not . Text.null) (Text.split (not . Char.isAlphaNum) localPart) of
        []                   -> ("Invited", "User")
        [firstName]          -> (toTitleCase firstName, "User")
        firstName:lastName:_ -> (toTitleCase firstName, toTitleCase lastName)
    where
        localPart = Text.takeWhile (/= '@') emailAddress
        toTitleCase token =
            case Text.uncons token of
                Nothing -> "User"
                Just (firstCharacter, remainingCharacters) ->
                    Text.cons (Char.toUpper firstCharacter) (Text.toLower remainingCharacters)
