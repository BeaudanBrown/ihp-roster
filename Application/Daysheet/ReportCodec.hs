{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- | Versioned, server-only selected results. Decoding never calls the evaluator
-- or loads current definitions/references: frozen values and display copy stay
-- as captured, even if calculation or formatting implementations later change.
module Application.Daysheet.ReportCodec
    ( encodeReportContent, decodeReportContent, ReportCodecError (..)
    ) where

import Prelude
import qualified Application.Daysheet.Contract as D
import Application.Daysheet.Report
import Application.Daysheet.Wire (literalJson, parseProjectedLiteralJson)
import Data.Aeson
import qualified Data.Aeson.Types as Aeson
import qualified Data.ByteString.Lazy as ByteString
import Data.Text (Text)
import qualified Data.Text as Text
import GHC.Generics (Generic)

-- These are storage errors, not user-supplied parser diagnostics.
data ReportCodecError = ReportPayloadTooLarge | InvalidReportPayload deriving (Eq, Show)

options :: Options
options = defaultOptions { rejectUnknownFields = True }

encodeReportContent :: ReportContent -> Either ReportCodecError Value
encodeReportContent content = do
    let value = object ["version" .= (1 :: Int), "content" .= content]
    decoded <- decodeReportContent value
    if decoded == content then Right value else Left InvalidReportPayload

decodeReportContent :: Value -> Either ReportCodecError ReportContent
decodeReportContent value
    | ByteString.length (encode value) > 16777216 = Left ReportPayloadTooLarge
    | otherwise = either (const (Left InvalidReportPayload)) Right (Aeson.parseEither parser value)
  where
    parser = withObject "frozen selected report" \record -> do
        version <- record .: "version"
        if length record /= 2 || (version :: Int) /= 1 then fail "invalid report envelope" else pure ()
        content <- record .: "content"
        if all safeText (reportText content) then pure content else fail "invalid report text"

-- PostgreSQL JSONB cannot preserve NUL. Check all labels, messages and resolved
-- display values, not just text literals that passed through the input codec.
safeText :: Text -> Bool
safeText = not . Text.any (== '\NUL')

reportText :: ReportContent -> [Text]
reportText (ReportContent title sections) = title : concatMap sectionText sections
  where
    sectionText (ReportSection title blocks) = title : concatMap blockText blocks
    blockText = \case
        ReportInstructions text -> [text]
        ReportField label cell -> label : cellText cell
        ReportAdvisory check -> checkText check
        ReportRowAdvisories label rows -> label : concatMap (\(name, check) -> name : checkText check) rows
        ReportTable label columns grouping groups -> label : columns <> maybe [] pure grouping <> concatMap groupText groups
    groupText (ReportGroup heading rows) = maybe [] cellText heading <> concatMap (concatMap cellText) rows
    cellText = \case
        ReportUnavailable reason -> [reason]
        ReportValue (D.TextLiteral text) display -> [text, display]
        ReportValue _ display -> [display]
    checkText = \case
        ReportPassed message -> [message]
        ReportConcern message -> [message]
        ReportNotEvaluated reason -> [reason]

-- A projection resolves nominal identities before this boundary. In particular,
-- accepting a raw ChoiceId here would smuggle definition identity into reports.
instance ToJSON ReportCell where
    toJSON (ReportValue literal display) = object ["kind" .= ("value" :: Text), "literal" .= literalJson literal, "display" .= display]
    toJSON (ReportUnavailable reason) = object ["kind" .= ("unavailable" :: Text), "reason" .= reason]
instance FromJSON ReportCell where
    parseJSON = withObject "report cell" \record -> do
        kind <- record .: "kind"
        case (kind :: Text) of
            "value" | length record == 3 -> do
                literal <- record .: "literal" >>= parseProjectedLiteralJson
                case literal of
                    D.ChoiceLiteral _ -> fail "unresolved report identity"
                    _ -> ReportValue literal <$> record .: "display"
            "unavailable" | length record == 2 -> ReportUnavailable <$> record .: "reason"
            _ -> fail "invalid report cell"

deriving instance Generic ReportCheck
instance ToJSON ReportCheck where toJSON = genericToJSON options
instance FromJSON ReportCheck where parseJSON = genericParseJSON options
deriving instance Generic ReportGroup
instance ToJSON ReportGroup where toJSON = genericToJSON options
instance FromJSON ReportGroup where parseJSON = genericParseJSON options
deriving instance Generic ReportBlock
instance ToJSON ReportBlock where toJSON = genericToJSON options
instance FromJSON ReportBlock where parseJSON = genericParseJSON options
deriving instance Generic ReportSection
instance ToJSON ReportSection where toJSON = genericToJSON options
instance FromJSON ReportSection where parseJSON = genericParseJSON options
deriving instance Generic ReportContent
instance ToJSON ReportContent where toJSON = genericToJSON options
instance FromJSON ReportContent where parseJSON = genericParseJSON options
