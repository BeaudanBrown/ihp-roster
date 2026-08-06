module Web.RosterWeeks.Filters
    ( decodeRosterAssignmentFilters
    , defaultRosterAssignmentFilters
    , encodeRosterAssignmentFilters
    , fetchRosterAssignmentFilters
    , normalizeOptionalText
    , parseOptionalShiftTypeId
    , parseOptionalTime
    , setRosterAssignmentFiltersSession
    ) where

import qualified Data.Text as Text
import Data.Time.Format (defaultTimeLocale, parseTimeM)
import Data.Time.LocalTime (TimeOfDay)
import qualified Data.UUID as UUID
import Web.Controller.Prelude
import Web.RosterWeeks.Types


parseOptionalShiftTypeId :: Maybe Text -> Maybe UUID.UUID
parseOptionalShiftTypeId value = UUID.fromText =<< normalizeOptionalText value

parseOptionalTime :: Maybe Text -> Maybe TimeOfDay
parseOptionalTime value =
    case normalizeOptionalText value of
        Nothing -> Nothing
        Just valueText -> parseTimeM True defaultTimeLocale "%H:%M" (cs valueText)

normalizeOptionalText :: Maybe Text -> Maybe Text
normalizeOptionalText = \case
    Nothing -> Nothing
    Just value ->
        let trimmed = Text.strip value
         in if Text.null trimmed then Nothing else Just trimmed

rosterAssignmentFiltersSessionKey :: ByteString
rosterAssignmentFiltersSessionKey = "rosterAssignmentFilters"

defaultRosterAssignmentFilters :: RosterAssignmentFilters
defaultRosterAssignmentFilters =
    RosterAssignmentFilters
        { hideStaffAtIdealShifts = False
        , hideStaffUnavailable = False
        , hideStaffOnApprovedLeave = False
        , hideStaffAlreadyAssignedToday = False
        }

encodeRosterAssignmentFilters :: RosterAssignmentFilters -> Text
encodeRosterAssignmentFilters filters =
    Text.pack
        [ encodeFlag filters.hideStaffAtIdealShifts
        , encodeFlag filters.hideStaffUnavailable
        , encodeFlag filters.hideStaffOnApprovedLeave
        , encodeFlag filters.hideStaffAlreadyAssignedToday
        ]
    where
        encodeFlag True  = '1'
        encodeFlag False = '0'

decodeRosterAssignmentFilters :: Text -> RosterAssignmentFilters
decodeRosterAssignmentFilters encoded =
    case Text.unpack encoded of
        [idealFlag, unavailableFlag, leaveFlag, assignedFlag] ->
            RosterAssignmentFilters
                { hideStaffAtIdealShifts = decodeFlag idealFlag
                , hideStaffUnavailable = decodeFlag unavailableFlag
                , hideStaffOnApprovedLeave = decodeFlag leaveFlag
                , hideStaffAlreadyAssignedToday = decodeFlag assignedFlag
                }
        _ -> defaultRosterAssignmentFilters
    where
        decodeFlag '1' = True
        decodeFlag _   = False

fetchRosterAssignmentFilters :: (?context :: ControllerContext, ?request :: Request) => IO RosterAssignmentFilters
fetchRosterAssignmentFilters = do
    encoded <- getSession @Text rosterAssignmentFiltersSessionKey
    pure (maybe defaultRosterAssignmentFilters decodeRosterAssignmentFilters encoded)

setRosterAssignmentFiltersSession :: (?context :: ControllerContext, ?request :: Request) => RosterAssignmentFilters -> IO ()
setRosterAssignmentFiltersSession filters =
    setSession rosterAssignmentFiltersSessionKey (encodeRosterAssignmentFilters filters)
