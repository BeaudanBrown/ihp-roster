{-# LANGUAGE PackageImports #-}

module Application.Helper.OpaqueToken
    ( generateOpaqueToken
    , hashOpaqueToken
    ) where

import qualified "crypton" Crypto.Hash as Hash
import "crypton" Crypto.Random (getRandomBytes)
import qualified Data.ByteArray as ByteArray
import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Base64 as Base64
import qualified Data.Char as Char
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import IHP.Prelude

generateOpaqueToken :: IO Text
generateOpaqueToken = do
    randomBytes <- getRandomBytes 32 :: IO ByteString.ByteString
    pure (TextEncoding.decodeUtf8 (Base64.encode randomBytes))

hashOpaqueToken :: Text -> Text
hashOpaqueToken rawToken =
    bytesToHex (ByteArray.convert (Hash.hash (TextEncoding.encodeUtf8 rawToken) :: Hash.Digest Hash.SHA256))

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
