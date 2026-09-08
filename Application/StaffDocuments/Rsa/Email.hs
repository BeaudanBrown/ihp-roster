module Application.StaffDocuments.Rsa.Email
    ( RsaReminderMailProjection (..)
    , completeRsaReminderDelivery
    , isRsaReminderMailKind
    , loadRsaReminderMail
    ) where

import Application.Error.Runtime (ExternalRuntimeCategory (..), externalRuntimeInvariantFailure)
import Application.Helper.Mail
import Application.StaffDocuments.Rsa
import Control.Monad (void)
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude
import Web.Mail.StaffDocuments.RsaReminder (RsaReminderMail (..))

isRsaReminderMailKind :: Text -> Bool
isRsaReminderMailKind = isJust . parseRsaReminderMailKind

data RsaReminderMailProjection
    = RsaReminderMailSkipped !Text
    | RsaReminderMailReady !RsaReminderMail

loadRsaReminderMail ::
    (?modelContext :: ModelContext) =>
    Text ->
    UUID ->
    Text ->
    UUID ->
    Maybe UUID ->
    AppMailSettings ->
    IO RsaReminderMailProjection
loadRsaReminderMail mailKind recipientAccountId recipientAddress staffDocumentId jobVenueId settings =
    case parseRsaReminderMailKind mailKind of
        Nothing -> pure (RsaReminderMailSkipped "unknown_mail_kind")
        Just reminderKind -> do
            maybeDocument <- query @StaffDocument
                |> filterWhere (#id, Id staffDocumentId)
                |> fetchOneOrNothing
            case maybeDocument of
                Nothing -> pure (RsaReminderMailSkipped "domain_reference_missing")
                Just staffDocument -> do
                    today <- utctDay <$> getCurrentTime
                    case guardStillDue today reminderKind staffDocument of
                        Nothing -> pure (RsaReminderMailSkipped "reminder_no_longer_due")
                        Just _ -> do
                            staff <- fetch (Id staffDocument.staffId :: Id Staff)
                            venue <- fetch (Id staffDocument.venueId :: Id Venue)
                            if staff.userId /= Just recipientAccountId
                                then pure (RsaReminderMailSkipped "recipient_no_longer_linked")
                                else if jobVenueId /= Just staffDocument.venueId || staff.venueId /= staffDocument.venueId
                                    then externalRuntimeInvariantFailure JobProvenanceInvariant "RSA reminder venue does not match its document and staff context"
                                    else pure $ RsaReminderMailReady RsaReminderMail
                                        { recipientAddress
                                        , recipientName = staffDisplayName staff
                                        , venue
                                        , staff
                                        , staffDocument
                                        , reminderSubject = rsaReminderSubject reminderKind
                                        , reminderIntro = rsaReminderIntro reminderKind staffDocument
                                        , fromAddress = settings.mailFromAddress
                                        , replyToAddress = settings.mailReplyToAddress
                                        , supportEmail = settings.mailSupportEmail
                                        }

completeRsaReminderDelivery ::
    (?modelContext :: ModelContext) =>
    Text ->
    UUID ->
    IO ()
completeRsaReminderDelivery mailKind staffDocumentId =
    case parseRsaReminderMailKind mailKind of
        Nothing -> externalRuntimeInvariantFailure JobProvenanceInvariant "Unknown RSA reminder mail kind"
        Just reminderKind -> do
            staffDocument <- fetch (Id staffDocumentId :: Id StaffDocument)
            void (markRsaReminderSent reminderKind staffDocument)

staffDisplayName :: Staff -> Text
staffDisplayName staff =
    Text.strip (staff.firstName <> " " <> staff.lastName)
