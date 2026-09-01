{-# LANGUAGE PackageImports #-}

module Application.Helper.OpaqueToken
    ( generateOpaqueToken
    , hashOpaqueToken
    ) where

import Application.Helper.ByteEncoding (bytesToHex)
import qualified "crypton" Crypto.Hash as Hash
import "crypton" Crypto.Random (getRandomBytes)
import qualified Data.ByteArray as ByteArray
import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Base64 as Base64
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
