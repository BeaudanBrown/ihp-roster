{-# LANGUAGE RankNTypes #-}
module Application.Daysheet.Recipients
    ( addReportRecipient, removeReportRecipient
    , readReportRecipients, activeReportRecipientsInLockedVenue, recipientIdentity
    , RecipientEligibilityFailure (..), withEligibleReportRecipient
    ) where

import Application.Daysheet.Authority (DaysheetAccess, venueId, userId, withAuthority, recordDaysheetAuditEvent)
import qualified Application.Daysheet.Contract as D
import Application.Daysheet.DefinitionCodec (decodeDefinition)
import Application.Daysheet.RecipientError
import Application.Daysheet.ReportLiveUpdates (publishReportDelivery)
import Application.Daysheet.RecipientLocks
import Application.EmailDelivery.Envelope (ExternalRecipient (..))
import Application.Error.Domain (projectDomainError)
import Application.Error.Types
import Application.Helper.Audit.Vocabulary
import Control.Monad.Trans.Except (throwE)
import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude

addReportRecipient :: (?modelContext :: ModelContext) => DaysheetAccess -> Id DaysheetDefinitionVersion -> D.ReportId -> Text -> IO (AppResult DaysheetReportRecipient)
addReportRecipient member versionId (D.ReportId reportId) submittedAddress = withAuthority member [VenueAdmin, VenueOwner] do
    let address = Text.toLower (Text.strip submittedAddress)
    let valid = Text.length address <= 254 && not (Text.any (`elem` ("<>\r\n\NUL" :: String)) address) && case isEmail address of Success -> True; _ -> False
    unless valid (throwE (projectDomainError InvalidAddress))
    version <- liftIO (query @DaysheetDefinitionVersion |> filterWhere (#id, versionId) |> filterWhere (#venueId, member.venueId) |> fetchOneOrNothing)
    published <- maybe (throwE (projectDomainError UnknownReport)) pure version
    definition <- either (const (throwE (projectDomainError InvalidReportDefinition))) pure (decodeDefinition published.definition)
    unless (any (\(D.Report key _ _ _) -> key == D.ReportId reportId) (D.reports definition)) (throwE (projectDomainError UnknownReport))
    existing <- liftIO (query @DaysheetReportRecipient
        |> filterWhere (#venueId, member.venueId) |> filterWhere (#reportId, reportId)
        |> filterWhere (#address, address) |> filterWhere (#removedAt, Nothing)
        |> fetchOneOrNothing)
    case existing of
        Just recipient -> pure recipient
        Nothing -> do
            recipient <- liftIO (newRecord @DaysheetReportRecipient
                |> set #venueId member.venueId |> set #reportId reportId
                |> set #definitionVersionId (unpackId published.id)
                |> set #address address |> set #createdBy member.userId |> createRecord)
            _ <- liftIO (recordDaysheetAuditEvent member DaysheetRecipientAddedAudit "daysheet_report_recipients" (unpackId recipient.id) (Aeson.object ["reportId" Aeson..= reportId]) ApplicationAuditSource)
            liftIO (publishReportDelivery member.venueId)
            pure recipient

removeReportRecipient :: (?modelContext :: ModelContext) => DaysheetAccess -> D.ReportId -> Id DaysheetReportRecipient -> IO (AppResult DaysheetReportRecipient)
removeReportRecipient member (D.ReportId reportId) recipientId = withAuthority member [VenueAdmin, VenueOwner] do
    _ <- liftIO (lockReportRecipient member.venueId reportId (unpackId recipientId))
    stored <- liftIO (query @DaysheetReportRecipient |> filterWhere (#id, recipientId) |> filterWhere (#venueId, member.venueId) |> filterWhere (#reportId, reportId) |> fetchOneOrNothing)
    recipient <- maybe (throwE (projectDomainError UnknownRecipient)) pure stored
    case recipient.removedAt of
        Just _ -> pure recipient
        Nothing -> do
            now <- liftIO getCurrentTime
            removed <- liftIO (recipient |> set #removedAt (Just now) |> set #removedBy (Just member.userId) |> updateRecord)
            _ <- liftIO (recordDaysheetAuditEvent member DaysheetRecipientRemovedAudit "daysheet_report_recipients" (unpackId recipient.id) (Aeson.object ["reportId" Aeson..= reportId]) ApplicationAuditSource)
            liftIO (publishReportDelivery member.venueId)
            pure removed

-- Capture orchestration owns its venue transaction/lock. This read never adds
-- recipients to an existing frozen run and never creates user accounts.
readReportRecipients :: (?modelContext :: ModelContext) => DaysheetAccess -> D.ReportId -> IO (AppResult [DaysheetReportRecipient])
readReportRecipients access report = withAuthority access [Manager, VenueAdmin, VenueOwner] $
    liftIO (activeReportRecipientsInLockedVenue access.venueId report)

-- Only capture interpreters that already hold the venue lock may use this
-- query directly (scheduled captures have system rather than user authority).
activeReportRecipientsInLockedVenue :: (?modelContext :: ModelContext) => UUID -> D.ReportId -> IO [DaysheetReportRecipient]
activeReportRecipientsInLockedVenue venueId (D.ReportId reportId) = query @DaysheetReportRecipient
    |> filterWhere (#venueId, venueId) |> filterWhere (#reportId, reportId)
    |> filterWhere (#removedAt, Nothing) |> orderByAsc #id |> fetch

recipientIdentity :: DaysheetReportRecipient -> ExternalRecipient
recipientIdentity recipient = VenueReportRecipient (unpackId recipient.id) recipient.venueId recipient.reportId

data RecipientEligibilityFailure = RecipientMissing | RecipientRemoved | RecipientVenueInactive | RecipientIdentityMismatch deriving (Eq, Show)

-- The shared transport invokes its resolver/send only inside this guard. The
-- address snapshot is immutable; remove-and-add yields a NEW identity, so old
-- retries stay cancelled even when the same address is later added again.
withEligibleReportRecipient :: (?modelContext :: ModelContext) => ExternalRecipient -> Text -> ((?modelContext :: ModelContext) => IO value) -> IO (Either RecipientEligibilityFailure value)
withEligibleReportRecipient identity address action = withTransaction do
    locked <- lockReportRecipient identity.externalVenueId identity.externalReportId identity.externalRecipientId
    if not locked then pure (Left RecipientMissing) else do
        recipient <- fetch (Id identity.externalRecipientId :: Id DaysheetReportRecipient)
        if recipient.venueId /= identity.externalVenueId || recipient.reportId /= identity.externalReportId || recipient.address /= address
            then pure (Left RecipientIdentityMismatch)
            else if isJust recipient.removedAt then pure (Left RecipientRemoved) else do
                venue <- query @Venue |> filterWhere (#id, Id recipient.venueId) |> fetchOneOrNothing
                case venue of
                    Just current | current.status == Active && isNothing current.closedAt -> Right <$> action
                    _ -> pure (Left RecipientVenueInactive)
