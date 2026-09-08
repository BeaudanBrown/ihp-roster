module Application.StaffDocuments.RsaExtraction
    ( RsaExtractionCandidate (..)
    , RsaExtractionFailure (..)
    , RsaExtractionMethod (..)
    , RsaExtractionResult (..)
    , extractRsaPdfMetadata
    , parseRsaCertificateText
    ) where

import Control.Category ((>>>))
import Control.Exception (try)
import Data.Char (isAlphaNum, isDigit)
import qualified Data.List as List
import qualified Data.Text as Text
import IHP.Prelude
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..))
import System.Process (readProcessWithExitCode)

newtype RsaExtractionMethod = RsaExtractionMethod
    { methodVersion :: Text
    }
    deriving (Eq, Show)

data RsaExtractionFailure
    = RsaExtractionCommandMissing !Text
    | RsaExtractionCommandFailed !Text
    | RsaExtractionNoTextLayer
    deriving (Eq, Show)

data RsaExtractionCandidate = RsaExtractionCandidate
    { issueDate        :: !(Maybe Day)
    , expiryDate       :: !(Maybe Day)
    , issuingAuthority :: !(Maybe Text)
    , documentNumber   :: !(Maybe Text)
    , recipientName    :: !(Maybe Text)
    }
    deriving (Eq, Show)

data RsaExtractionResult = RsaExtractionResult
    { candidate        :: !RsaExtractionCandidate
    , confidence       :: !Int
    , warnings         :: ![Text]
    , extractionMethod :: !RsaExtractionMethod
    , failureReason    :: !(Maybe RsaExtractionFailure)
    , extractedText    :: !Text
    }
    deriving (Eq, Show)

extractRsaPdfMetadata :: FilePath -> IO RsaExtractionResult
extractRsaPdfMetadata pdfPath = do
    command <- fmap (fromMaybe "pdftotext") (lookupEnv "RSA_PDFTOTEXT_COMMAND")
    version <- pdftotextVersion command
    extracted <- try (readProcessWithExitCode command ["-layout", pdfPath, "-"] "")
    case extracted of
        Left (_ :: SomeException) ->
            pure (failureResult version (RsaExtractionCommandMissing (cs command)) "")
        Right (ExitSuccess, stdoutText, _stderrText) ->
            let result = parseRsaCertificateText (cs stdoutText)
             in pure result { extractionMethod = RsaExtractionMethod version }
        Right (_exitCode, _stdoutText, stderrText) ->
            pure (failureResult version (RsaExtractionCommandFailed (trimText (cs stderrText))) "")

parseRsaCertificateText :: Text -> RsaExtractionResult
parseRsaCertificateText rawText =
    let
        normalizedLines = meaningfulLines rawText
        dates = extractDates normalizedLines
        issue = labelledDate ["issue date", "issued", "valid from", "date of issue"] normalizedLines <|> listToMaybe dates
        expiry = labelledDate ["expiry", "expires", "valid until", "valid to"] normalizedLines <|> secondDate dates
        candidate =
            RsaExtractionCandidate
                { issueDate = issue
                , expiryDate = expiry
                , issuingAuthority = findAuthority normalizedLines
                , documentNumber = findDocumentNumber normalizedLines
                , recipientName = findRecipientName normalizedLines
                }
        baseWarnings = parserWarnings rawText normalizedLines candidate dates
        failure = if Text.null (trimText rawText) then Just RsaExtractionNoTextLayer else Nothing
     in
        RsaExtractionResult
            { candidate
            , confidence = confidenceFor candidate baseWarnings failure
            , warnings = baseWarnings
            , extractionMethod = RsaExtractionMethod "text-parser"
            , failureReason = failure
            , extractedText = rawText
            }

failureResult :: Text -> RsaExtractionFailure -> Text -> RsaExtractionResult
failureResult version reason text =
    RsaExtractionResult
        { candidate = emptyCandidate
        , confidence = 0
        , warnings = ["RSA PDF text extraction failed; manual entry is required."]
        , extractionMethod = RsaExtractionMethod version
        , failureReason = Just reason
        , extractedText = text
        }

emptyCandidate :: RsaExtractionCandidate
emptyCandidate =
    RsaExtractionCandidate
        { issueDate = Nothing
        , expiryDate = Nothing
        , issuingAuthority = Nothing
        , documentNumber = Nothing
        , recipientName = Nothing
        }

pdftotextVersion :: String -> IO Text
pdftotextVersion command = do
    result <- try (readProcessWithExitCode command ["-v"] "")
    case result of
        Left (_ :: SomeException) -> pure (cs command <> " unavailable")
        Right (_, stdoutText, stderrText) ->
            pure (firstNonEmpty [cs stdoutText, cs stderrText, cs command] |> Text.lines |> listToMaybe |> fromMaybe (cs command) |> trimText)

meaningfulLines :: Text -> [Text]
meaningfulLines =
    Text.lines
        >>> map (Text.unwords . Text.words)
        >>> filter (not . Text.null)

extractDates :: [Text] -> [Day]
extractDates lines =
    List.nub (lines >>= datesInLine)

datesInLine :: Text -> [Day]
datesInLine line =
    numericDatesInLine line <> monthDatesInLine line

numericDatesInLine :: Text -> [Day]
numericDatesInLine line =
    Text.words (Text.map numericDateChar line)
        |> mapMaybe parseNumericDate

numericDateChar :: Char -> Char
numericDateChar char
    | isDigit char || char == '/' || char == '-' = char
    | otherwise = ' '

monthDatesInLine :: Text -> [Day]
monthDatesInLine line =
    let tokens = Text.words (Text.map monthDateChar line)
     in mapMaybe parseMonthDate (windows 3 tokens)

monthDateChar :: Char -> Char
monthDateChar char
    | isAlphaNum char = char
    | otherwise = ' '

parseMonthDate :: [Text] -> Maybe Day
parseMonthDate [dayText, monthText, yearText] =
    parseDay ["%-d %B %Y", "%d %B %Y", "%-d %b %Y", "%d %b %Y"] (Text.unwords [dayText, monthText, yearText])
parseMonthDate _ = Nothing

parseNumericDate :: Text -> Maybe Day
parseNumericDate text =
    parseDay ["%d/%m/%Y", "%-d/%-m/%Y", "%d-%m-%Y", "%-d-%-m-%Y"] text

parseDay :: [String] -> Text -> Maybe Day
parseDay formats text =
    formats
        |> mapMaybe (\format -> parseTimeM True defaultTimeLocale format (cs text))
        |> listToMaybe

labelledDate :: [Text] -> [Text] -> Maybe Day
labelledDate labels lines =
    listToMaybe (filter (containsAny labels) lines >>= datesInLine)

secondDate :: [Day] -> Maybe Day
secondDate (_first:second:_) = Just second
secondDate _                 = Nothing

findDocumentNumber :: [Text] -> Maybe Text
findDocumentNumber lines =
    lines
        |> mapMaybe documentNumberFromLine
        |> listToMaybe

documentNumberFromLine :: Text -> Maybe Text
documentNumberFromLine line
    | not (containsAny ["certificate", "document", "statement", "number", "no.", "identifier"] line) = Nothing
    | otherwise =
        case valueAfterSeparator line of
            Just value -> Just (cleanIdentifier value)
            Nothing ->
                Text.words line
                    |> reverse
                    |> find (Text.any isDigit)
                    |> fmap cleanIdentifier

findAuthority :: [Text] -> Maybe Text
findAuthority lines =
    lines
        |> mapMaybe authorityFromLine
        |> listToMaybe

authorityFromLine :: Text -> Maybe Text
authorityFromLine line
    | containsAny ["issued by", "issuing authority", "training organisation", "rto", "authority"] line =
        Just (fromMaybe line (valueAfterSeparator line) |> cleanCandidateText)
    | otherwise = Nothing

findRecipientName :: [Text] -> Maybe Text
findRecipientName lines =
    labelledRecipientName lines <|> certifyRecipientName lines <|> recipientNameAfterMarker lines

labelledRecipientName :: [Text] -> Maybe Text
labelledRecipientName lines =
    lines
        |> mapMaybe (\line ->
            if containsAny ["awarded to", "recipient", "student name", "participant", "name:"] line
                then valueAfterSeparator line <|> valueAfterPhrase ["awarded to", "recipient", "student name", "participant", "name"] line
                else Nothing)
        |> map cleanName
        |> filter plausibleName
        |> listToMaybe

certifyRecipientName :: [Text] -> Maybe Text
certifyRecipientName lines =
    lines
        |> mapMaybe (valueAfterPhrase recipientMarkerPhrases)
        |> map cleanName
        |> filter plausibleName
        |> listToMaybe

recipientNameAfterMarker :: [Text] -> Maybe Text
recipientNameAfterMarker lines =
    lines
        |> List.tails
        |> mapMaybe recipientNameFromMarkerTail
        |> listToMaybe

recipientNameFromMarkerTail :: [Text] -> Maybe Text
recipientNameFromMarkerTail [] = Nothing
recipientNameFromMarkerTail (line:followingLines)
    | containsAny recipientMarkerPhrases line =
        followingLines
            |> take 4
            |> map cleanName
            |> filter plausibleRecipientLine
            |> listToMaybe
    | otherwise = Nothing

recipientMarkerPhrases :: [Text]
recipientMarkerPhrases =
    [ "this is to certify that"
    , "certify that"
    , "awarded to"
    ]

parserWarnings :: Text -> [Text] -> RsaExtractionCandidate -> [Day] -> [Text]
parserWarnings rawText lines candidate dates =
    concat
        [ ["No text was extracted from the PDF; manual entry is required." | Text.null (trimText rawText)]
        , ["Extracted text does not contain an obvious RSA keyword." | not (containsAny ["rsa", "responsible service of alcohol"] (Text.unlines lines)) && not (Text.null (trimText rawText))]
        , ["Issue date was not confidently detected." | isNothing candidate.issueDate]
        , ["Expiry date was not confidently detected." | isNothing candidate.expiryDate]
        , ["Document number was not confidently detected." | isNothing candidate.documentNumber]
        , ["Issuing authority was not confidently detected." | isNothing candidate.issuingAuthority]
        , ["Recipient name was not confidently detected." | isNothing candidate.recipientName]
        , ["Multiple dates were found; confirm issue and expiry dates before saving." | length dates > 2]
        ]

confidenceFor :: RsaExtractionCandidate -> [Text] -> Maybe RsaExtractionFailure -> Int
confidenceFor _ _ (Just _) = 0
confidenceFor candidate warnings Nothing =
    max 0 (min 100 (fieldScore - warningPenalty))
  where
    fieldScore =
        sum
            [ maybe 0 (const 20) candidate.issueDate
            , maybe 0 (const 25) candidate.expiryDate
            , maybe 0 (const 20) candidate.documentNumber
            , maybe 0 (const 20) candidate.issuingAuthority
            , maybe 0 (const 15) candidate.recipientName
            ]
    warningPenalty = length warnings * 5

containsAny :: [Text] -> Text -> Bool
containsAny needles haystack =
    let folded = Text.toCaseFold haystack
     in any (`Text.isInfixOf` folded) needles

valueAfterSeparator :: Text -> Maybe Text
valueAfterSeparator line =
    [":", "-"]
        |> mapMaybe (\separator -> case Text.breakOn separator line of
            (_before, after) | not (Text.null after) -> Just (Text.drop (Text.length separator) after)
            _ -> Nothing)
        |> map cleanCandidateText
        |> filter (not . Text.null)
        |> listToMaybe

valueAfterPhrase :: [Text] -> Text -> Maybe Text
valueAfterPhrase phrases line =
    phrases
        |> mapMaybe (\phrase ->
            let folded = Text.toCaseFold line
                (before, after) = Text.breakOn phrase folded
             in if Text.null after
                    then Nothing
                    else Just (Text.drop (Text.length before + Text.length phrase) line))
        |> map cleanCandidateText
        |> filter (not . Text.null)
        |> listToMaybe

cleanIdentifier :: Text -> Text
cleanIdentifier =
    Text.takeWhile (\char -> isAlphaNum char || char `elem` ("-/_." :: String))
        . cleanCandidateText

cleanName :: Text -> Text
cleanName =
    Text.words
        >>> takeWhile (\word -> not (Text.toCaseFold word `elem` ["has", "successfully", "completed", "for", "in"]))
        >>> Text.unwords
        >>> cleanCandidateText

cleanCandidateText :: Text -> Text
cleanCandidateText =
    trimText
        >>> Text.dropWhile (\char -> char == ':' || char == '-' || char == '#')
        >>> trimText
        >>> Text.dropAround (not . isAlphaNum)

plausibleName :: Text -> Bool
plausibleName name =
    let wordsCount = length (Text.words name)
     in wordsCount >= 2 && wordsCount <= 5 && not (Text.any isDigit name)

plausibleRecipientLine :: Text -> Bool
plausibleRecipientLine name =
    plausibleName name && not (containsAny nonRecipientLineKeywords name)

nonRecipientLineKeywords :: [Text]
nonRecipientLineKeywords =
    [ "certificate"
    , "completion"
    , "responsible service"
    , "alcohol"
    , "program"
    , "course"
    , "approved"
    , "commission"
    , "licence"
    , "license"
    , "valid"
    , "officer"
    ]

windows :: Int -> [a] -> [[a]]
windows size values
    | length values < size = []
    | otherwise = take size values : windows size (drop 1 values)

firstNonEmpty :: [Text] -> Text
firstNonEmpty values =
    values
        |> map trimText
        |> find (not . Text.null)
        |> fromMaybe ""

trimText :: Text -> Text
trimText = Text.strip
