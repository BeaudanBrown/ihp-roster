module Application.EmailDelivery.Correlation
    ( CorrelatedMail (..)
    , emailDeliveryMessageId
    , markSmtpAccepted
    , prepareProviderCorrelation
    ) where

import Generated.Types
import IHP.ControllerPrelude
import IHP.MailPrelude hiding (query)

data CorrelatedMail mail = CorrelatedMail
    { wrappedMail    :: !mail
    , correlationMessageId      :: !Text
    , correlationIdempotencyKey :: !Text
    }

instance BuildMail mail => BuildMail (CorrelatedMail mail) where
    subject = let ?mail = ?mail.wrappedMail in subject
    to correlated = to correlated.wrappedMail
    replyTo correlated = replyTo correlated.wrappedMail
    cc correlated = cc correlated.wrappedMail
    bcc correlated = bcc correlated.wrappedMail
    headers correlated =
        [ ("Message-ID", correlated.correlationMessageId)
        , ("Resend-Idempotency-Key", correlated.correlationIdempotencyKey)
        ] <> headers correlated.wrappedMail
    from = let ?mail = ?mail.wrappedMail in from
    html correlated = html correlated.wrappedMail
    text correlated = text correlated.wrappedMail
    attachments correlated = attachments correlated.wrappedMail

emailDeliveryMessageId :: AppJob -> Text
emailDeliveryMessageId appJob = "<" <> tshow (unpackId appJob.id) <> "@notifications.bepis.lol>"

prepareProviderCorrelation ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    IO EmailDeliveryProviderState
prepareProviderCorrelation appJob = do
    existing <-
        query @EmailDeliveryProviderState
            |> filterWhere (#emailDeliveryJobId, Id (unpackId appJob.id))
            |> fetchOneOrNothing
    case existing of
        Just state -> pure state
        Nothing ->
            newRecord @EmailDeliveryProviderState
                |> set #emailDeliveryJobId (Id (unpackId appJob.id))
                |> set #messageId (emailDeliveryMessageId appJob)
                |> set #providerEmailId Nothing
                |> set #smtpAcceptedAt Nothing
                |> set #providerStatus "unknown"
                |> set #providerStatusAt Nothing
                |> createRecord

markSmtpAccepted ::
    (?modelContext :: ModelContext) =>
    EmailDeliveryProviderState ->
    UTCTime ->
    IO EmailDeliveryProviderState
markSmtpAccepted state acceptedAt =
    state
        |> set #smtpAcceptedAt (Just acceptedAt)
        |> updateRecord
