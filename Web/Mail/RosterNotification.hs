module Web.Mail.RosterNotification
    ( RosterNotificationMail (..)
    ) where

import Application.RosterNotification
import Application.VenueTime.Model (storedInstantLocalTime)
import qualified Data.List as List
import qualified Data.Text as Text
import Data.Time.Format (defaultTimeLocale, formatTime)
import IHP.MailPrelude
import qualified Text.Blaze.Html5 as Html
import Web.Mail.Shared

data RosterNotificationMail = RosterNotificationMail
    { notificationSnapshot  :: !RosterNotificationSnapshot
    , notificationRecipient :: !RosterNotificationRecipient
    , rosterUrl             :: !Text
    , fromAddress           :: !Text
    , replyToAddress        :: !Text
    , supportEmail          :: !Text
    }

instance BuildMail RosterNotificationMail where
    subject =
        "Your "
            <> ?mail.notificationSnapshot.snapshotRosterGroupName
            <> " roster for week of "
            <> formatDayShort ?mail.notificationSnapshot.snapshotWeekStart

    to RosterNotificationMail { notificationRecipient } =
        Address
            { addressName = Just notificationRecipient.recipientName
            , addressEmail = notificationRecipient.recipientEmail
            }

    from = bepisFrom ?mail.fromAddress

    replyTo RosterNotificationMail { replyToAddress } = bepisReplyTo replyToAddress

    html = renderMailHtml

    text = renderMailText

recipientShifts :: RosterNotificationMail -> [RosterNotificationShiftSnapshot]
recipientShifts mail =
    orderedShifts
        [ shift
        | shift <- mail.notificationSnapshot.snapshotShifts
        , shift.shiftStaffId == Just mail.notificationRecipient.recipientStaffId
        ]

openShifts :: RosterNotificationMail -> [RosterNotificationShiftSnapshot]
openShifts mail =
    orderedShifts
        [ shift
        | shift <- mail.notificationSnapshot.snapshotShifts
        , isNothing shift.shiftStaffId
        ]

orderedShifts :: [RosterNotificationShiftSnapshot] -> [RosterNotificationShiftSnapshot]
orderedShifts = List.sortOn \shift -> (shift.shiftDate, shift.shiftStartsAt, shift.shiftRosterSlotId)

renderMailHtml :: RosterNotificationMail -> Html.Html
renderMailHtml = Html.pre . Html.toHtml . renderMailText

renderMailText :: RosterNotificationMail -> Text
renderMailText mail =
    Text.intercalate "\n"
        [ "Your live roster is ready."
        , ""
        , "Venue: " <> mail.notificationSnapshot.snapshotVenueName
        , "Roster group: " <> mail.notificationSnapshot.snapshotRosterGroupName
        , "Week: " <> formatWeekRange mail.notificationSnapshot
        , ""
        , "Your shifts"
        , renderShiftListText "You have no assigned shifts in this roster." (recipientShifts mail)
        , ""
        , "Open shifts"
        , renderShiftListText "There are no Open shifts in this roster." (openShifts mail)
        , ""
        , "View the full live roster:"
        , mail.rosterUrl
        ]
        <> supportFooterText mail.supportEmail

renderShiftListText :: Text -> [RosterNotificationShiftSnapshot] -> Text
renderShiftListText emptyCopy shifts
    | null shifts = emptyCopy
    | otherwise = Text.intercalate "\n" (map (("- " <>) . formatShift) shifts)

formatShift :: RosterNotificationShiftSnapshot -> Text
formatShift shift =
    formatDayLong shift.shiftDate
        <> ", "
        <> formatShiftTimeRange shift
        <> " — "
        <> shift.shiftLaneName
        <> maybe "" (" — " <>) shift.shiftTypeName

formatShiftTimeRange :: RosterNotificationShiftSnapshot -> Text
formatShiftTimeRange shift =
    case (shift.shiftStartsAt, shift.shiftEndsAt) of
        (Just startsAt, Just endsAt) ->
            formatLocalTime shift.shiftTimezone startsAt
                <> "–"
                <> formatLocalTime shift.shiftTimezone endsAt
        _ -> "Time to be confirmed"

formatLocalTime :: Text -> UTCTime -> Text
formatLocalTime timezone =
    Text.pack
        . formatTime defaultTimeLocale "%-I:%M %P"
        . (.localTimeOfDay)
        . storedInstantLocalTime timezone

formatDayShort :: Day -> Text
formatDayShort = Text.pack . formatTime defaultTimeLocale "%-d %B"

formatDayLong :: Day -> Text
formatDayLong = Text.pack . formatTime defaultTimeLocale "%A %-d %B"

formatWeekRange :: RosterNotificationSnapshot -> Text
formatWeekRange snapshot =
    Text.pack (formatTime defaultTimeLocale "%-d %B %Y" snapshot.snapshotWeekStart)
        <> "–"
        <> Text.pack (formatTime defaultTimeLocale "%-d %B %Y" snapshot.snapshotWeekEnd)
