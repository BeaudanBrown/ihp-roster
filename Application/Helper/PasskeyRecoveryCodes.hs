{-# LANGUAGE PackageImports #-}

module Application.Helper.PasskeyRecoveryCodes
    ( generateRecoveryCode
    , hashRecoveryCode
    , issueInitialRecoveryCodeIfMissing
    , normalizeRecoveryCode
    , verifyAndConsumeRecoveryCode
    ) where

import qualified "crypton" Crypto.Hash as Hash
import "crypton" Crypto.Random (getRandomBytes)
import qualified Data.ByteArray as ByteArray
import qualified Data.ByteString as ByteString
import qualified Data.Char as Char
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import Generated.Types
import IHP.Prelude
import Web.Controller.Prelude

generateRecoveryCode :: IO Text
generateRecoveryCode = do
    randomBytes <- getRandomBytes 12 :: IO ByteString.ByteString
    pure (groupCode (Text.toUpper (bytesToHex randomBytes)))

normalizeRecoveryCode :: Text -> Text
normalizeRecoveryCode =
    Text.toUpper . Text.filter Char.isAlphaNum

hashRecoveryCode :: Text -> Text
hashRecoveryCode code =
    bytesToHex (ByteArray.convert (Hash.hash (TextEncoding.encodeUtf8 (normalizeRecoveryCode code)) :: Hash.Digest Hash.SHA256))

issueInitialRecoveryCodeIfMissing :: (?modelContext :: ModelContext) => Id User -> IO (Maybe Text)
issueInitialRecoveryCodeIfMissing userId = do
    existingCode <-
        query @PasskeyRecoveryCode
            |> filterWhere (#userId, unpackId userId)
            |> fetchExists
    if existingCode
        then pure Nothing
        else do
            recoveryCode <- generateRecoveryCode
            _ <- newRecord @PasskeyRecoveryCode
                |> set #userId (unpackId userId)
                |> set #codeHash (hashRecoveryCode recoveryCode)
                |> createRecord
            pure (Just recoveryCode)

verifyAndConsumeRecoveryCode :: (?modelContext :: ModelContext) => Id User -> Text -> IO Bool
verifyAndConsumeRecoveryCode userId submittedCode = do
    recoveryCode <-
        query @PasskeyRecoveryCode
            |> filterWhere (#userId, unpackId userId)
            |> filterWhere (#codeHash, hashRecoveryCode submittedCode)
            |> filterWhere (#usedAt, Nothing)
            |> fetchOneOrNothing
    case recoveryCode of
        Nothing -> pure False
        Just code -> do
            now <- getCurrentTime
            code
                |> set #usedAt (Just now)
                |> updateRecordDiscardResult
            pure True

groupCode :: Text -> Text
groupCode value =
    Text.intercalate "-" (chunksOfText 4 value)

chunksOfText :: Int -> Text -> [Text]
chunksOfText size value
    | Text.null value = []
    | otherwise =
        let (chunk, rest) = Text.splitAt size value
         in chunk : chunksOfText size rest

bytesToHex :: ByteString.ByteString -> Text
bytesToHex =
    Text.concat . map byteToHex . ByteString.unpack
    where
        byteToHex byte =
            let high = fromIntegral byte `div` (16 :: Int)
                low = fromIntegral byte `mod` (16 :: Int)
             in Text.pack [hexDigit high, hexDigit low]

        hexDigit value
            | value < 10 = Char.chr (Char.ord '0' + value)
            | otherwise = Char.chr (Char.ord 'a' + value - 10)
