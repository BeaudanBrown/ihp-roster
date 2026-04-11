module Web.RosterWeeks.Filters
    ( decodeRosterAssignmentFilters
    , defaultRosterAssignmentFilters
    , encodeRosterAssignmentFilters
    , fetchRosterAssignmentFilters
    , normalizeOptionalSlotFlag
    , normalizeOptionalText
    , parseOptionalStaffId
    , parseOptionalTime
    , rosterAssignmentFiltersFromParams
    , setRosterAssignmentFiltersSession
    ) where

import Data.Time.Format (defaultTimeLocale, parseTimeM)
import Data.Time.LocalTime (TimeOfDay)
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import Web.Controller.Prelude
import Web.RosterWeeks.Types

parseOptionalStaffId :: Maybe Text -> Maybe UUID.UUID
parseOptionalStaffId value = UUID.fromText =<< normalizeOptionalText value

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

normalizeOptionalSlotFlag :: Maybe Text -> Either Text (Maybe Text)
normalizeOptionalSlotFlag value =
    case Text.toUpper <$> normalizeOptionalText value of
        Just normalized | Text.length normalized > 2 ->
            Left "Flags can only be 1 or 2 characters."
        normalized -> Right normalized

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

rosterAssignmentFiltersFromParams :: (?context :: ControllerContext, ?request :: Request) => RosterAssignmentFilters
rosterAssignmentFiltersFromParams =
    RosterAssignmentFilters
        { hideStaffAtIdealShifts = isJust (paramOrNothing @Text "hideStaffAtIdealShifts")
        , hideStaffUnavailable = isJust (paramOrNothing @Text "hideStaffUnavailable")
        , hideStaffOnApprovedLeave = isJust (paramOrNothing @Text "hideStaffOnApprovedLeave")
        , hideStaffAlreadyAssignedToday = isJust (paramOrNothing @Text "hideStaffAlreadyAssignedToday")
        }

fetchRosterAssignmentFilters :: (?context :: ControllerContext, ?request :: Request) => IO RosterAssignmentFilters
fetchRosterAssignmentFilters = do
    encoded <- getSession @Text rosterAssignmentFiltersSessionKey
    pure (maybe defaultRosterAssignmentFilters decodeRosterAssignmentFilters encoded)

setRosterAssignmentFiltersSession :: (?context :: ControllerContext, ?request :: Request) => RosterAssignmentFilters -> IO ()
setRosterAssignmentFiltersSession filters =
    setSession rosterAssignmentFiltersSessionKey (encodeRosterAssignmentFilters filters)
