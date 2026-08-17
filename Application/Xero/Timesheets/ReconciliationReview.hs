{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Application.Xero.Timesheets.ReconciliationReview
    ( XeroTimesheetReconciliationNotice (..)
    , XeroTimesheetReconciliationNoticeSeverity (..)
    , XeroTimesheetReconciliationReview (..)
    , reconciliationReviewAllowsSubmission
    , reconciliationReviewNotices
    , reconciliationReviewSnapshotIsConfirmed
    , reconciliationReviewSnapshotJson
    ) where

import Application.Xero.Timesheets.Reconciliation
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.Bifunctor as Bifunctor
import qualified Data.List as List
import qualified Data.Text as Text
import IHP.Prelude

data XeroTimesheetReconciliationReview = XeroTimesheetReconciliationReview
    { reconciliationReviewEmployeeId :: !Text
    , reconciliationReviewDecision   :: !XeroTimesheetReconciliationDecision
    }
    deriving (Eq, Show)

data XeroTimesheetReconciliationNoticeSeverity
    = ReconciliationWarning
    | ReconciliationBlocker
    deriving (Eq, Show)

data XeroTimesheetReconciliationNotice = XeroTimesheetReconciliationNotice
    { reconciliationNoticeEmployeeId :: !Text
    , reconciliationNoticeSeverity   :: !XeroTimesheetReconciliationNoticeSeverity
    , reconciliationNoticeMessage    :: !Text
    }
    deriving (Eq, Show)

data ReconciliationReviewSnapshot = ReconciliationReviewSnapshot
    { snapshotReviews      :: [XeroTimesheetReconciliationReview]
    , snapshotConfirmed    :: !Bool
    , snapshotStateChanged :: !Bool
    }

reconciliationReviewSnapshotJson :: [XeroTimesheetReconciliationReview] -> Aeson.Value
reconciliationReviewSnapshotJson reviews =
    Aeson.object
        [ "version" Aeson..= (1 :: Int)
        , "confirmed" Aeson..= True
        , "stateChanged" Aeson..= False
        , "employees" Aeson..= map reviewJson (List.sortOn (.reconciliationReviewEmployeeId) reviews)
        ]

reconciliationReviewSnapshotIsConfirmed :: Aeson.Value -> Bool
reconciliationReviewSnapshotIsConfirmed snapshot =
    either (const False) (.snapshotConfirmed) (parseSnapshot snapshot)

reconciliationReviewNotices :: Aeson.Value -> Either Text [XeroTimesheetReconciliationNotice]
reconciliationReviewNotices snapshot = do
    parsed <- parseSnapshot snapshot
    pure (stateChangedNotice parsed <> mapMaybe reviewNotice parsed.snapshotReviews)
  where
    stateChangedNotice parsed
        | parsed.snapshotStateChanged =
            [ XeroTimesheetReconciliationNotice
                { reconciliationNoticeEmployeeId = ""
                , reconciliationNoticeSeverity = ReconciliationWarning
                , reconciliationNoticeMessage = "Xero timesheet state changed after confirmation. Review the latest reconciliation outcome before submitting."
                }
            ]
        | otherwise = []

reconciliationReviewAllowsSubmission :: Aeson.Value -> Either Text Bool
reconciliationReviewAllowsSubmission snapshot =
    all ((/= ReconciliationBlocker) . (.reconciliationNoticeSeverity)) <$> reconciliationReviewNotices snapshot

parseSnapshot :: Aeson.Value -> Either Text ReconciliationReviewSnapshot
parseSnapshot = Bifunctor.first cs . AesonTypes.parseEither parser
  where
    parser = Aeson.withObject "Xero reconciliation review snapshot" \object -> do
        version <- object Aeson..: "version"
        unless (version == (1 :: Int)) (fail "Unsupported Xero reconciliation review snapshot version")
        ReconciliationReviewSnapshot
            <$> object Aeson..: "employees"
            <*> object Aeson..: "confirmed"
            <*> object Aeson..: "stateChanged"

instance Aeson.FromJSON XeroTimesheetReconciliationReview where
    parseJSON = Aeson.withObject "Xero reconciliation review" \object ->
        XeroTimesheetReconciliationReview
            <$> object Aeson..: "employeeId"
            <*> (object Aeson..: "decision" >>= parseDecision)

reviewJson :: XeroTimesheetReconciliationReview -> Aeson.Value
reviewJson review =
    Aeson.object
        [ "employeeId" Aeson..= review.reconciliationReviewEmployeeId
        , "decision" Aeson..= decisionJson review.reconciliationReviewDecision
        ]

parseDecision :: Aeson.Value -> AesonTypes.Parser XeroTimesheetReconciliationDecision
parseDecision = Aeson.withObject "Xero reconciliation decision" \object -> do
    kind <- object Aeson..: "kind" :: AesonTypes.Parser Text
    case kind of
        "create" -> pure CreateXeroTimesheet
        "update" -> UpdateXeroDraft <$> object Aeson..: "timesheetId"
        "replace_missing" -> ReplaceMissingXeroDraft <$> object Aeson..: "priorTimesheetId"
        "in_progress" -> pure XeroSubmissionInProgress
        "block_non_draft" -> BlockXeroNonDraft <$> object Aeson..: "timesheetId" <*> object Aeson..: "status"
        "block_distinct" -> BlockDistinctXeroTimesheets <$> object Aeson..: "timesheetIds"
        "block_unknown_status" -> BlockUnknownXeroStatus <$> object Aeson..: "timesheetId" <*> object Aeson..: "status"
        "block_missing_id" -> BlockMissingXeroTimesheetId <$> object Aeson..: "status"
        _ -> fail "Unknown Xero reconciliation decision kind"

decisionJson :: XeroTimesheetReconciliationDecision -> Aeson.Value
decisionJson CreateXeroTimesheet = Aeson.object ["kind" Aeson..= ("create" :: Text)]
decisionJson (UpdateXeroDraft timesheetId) = Aeson.object ["kind" Aeson..= ("update" :: Text), "timesheetId" Aeson..= timesheetId]
decisionJson (ReplaceMissingXeroDraft priorTimesheetId) = Aeson.object ["kind" Aeson..= ("replace_missing" :: Text), "priorTimesheetId" Aeson..= priorTimesheetId]
decisionJson XeroSubmissionInProgress = Aeson.object ["kind" Aeson..= ("in_progress" :: Text)]
decisionJson (BlockXeroNonDraft timesheetId status) = Aeson.object ["kind" Aeson..= ("block_non_draft" :: Text), "timesheetId" Aeson..= timesheetId, "status" Aeson..= status]
decisionJson (BlockDistinctXeroTimesheets timesheetIds) = Aeson.object ["kind" Aeson..= ("block_distinct" :: Text), "timesheetIds" Aeson..= timesheetIds]
decisionJson (BlockUnknownXeroStatus timesheetId status) = Aeson.object ["kind" Aeson..= ("block_unknown_status" :: Text), "timesheetId" Aeson..= timesheetId, "status" Aeson..= status]
decisionJson (BlockMissingXeroTimesheetId status) = Aeson.object ["kind" Aeson..= ("block_missing_id" :: Text), "status" Aeson..= status]

reviewNotice :: XeroTimesheetReconciliationReview -> Maybe XeroTimesheetReconciliationNotice
reviewNotice review =
    notice <$> case review.reconciliationReviewDecision of
        CreateXeroTimesheet -> Nothing
        UpdateXeroDraft _ -> Nothing
        ReplaceMissingXeroDraft priorTimesheetId ->
            Just (ReconciliationWarning, "Bepis previously created Xero draft " <> priorTimesheetId <> ", but it is now missing. Confirm to create a replacement draft.")
        XeroSubmissionInProgress ->
            Just (ReconciliationBlocker, "A Bepis Xero timesheet submission is still in progress. Wait for it to finish, then review again.")
        BlockXeroNonDraft timesheetId status ->
            Just (ReconciliationBlocker, "Xero timesheet " <> timesheetId <> " is " <> status <> " and cannot be changed by Bepis. Review it in Xero before trying again.")
        BlockDistinctXeroTimesheets timesheetIds ->
            Just (ReconciliationBlocker, "Xero has multiple distinct timesheets for this employee and period (" <> Text.intercalate ", " timesheetIds <> "). Resolve them in Xero, then review again.")
        BlockUnknownXeroStatus timesheetId status ->
            Just (ReconciliationBlocker, "Xero returned an unsupported status for timesheet " <> timesheetId <> statusSuffix status <> ". Review it in Xero or contact support.")
        BlockMissingXeroTimesheetId status ->
            Just (ReconciliationBlocker, "Xero returned a timesheet without an ID" <> statusSuffix status <> ". Refresh Xero data or contact support.")
  where
    notice (severity, message) =
        XeroTimesheetReconciliationNotice
            { reconciliationNoticeEmployeeId = review.reconciliationReviewEmployeeId
            , reconciliationNoticeSeverity = severity
            , reconciliationNoticeMessage = message
            }
    statusSuffix Nothing       = ""
    statusSuffix (Just status) = " (status " <> status <> ")"
