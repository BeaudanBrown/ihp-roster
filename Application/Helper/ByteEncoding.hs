module Application.Helper.ByteEncoding
    ( bytesToHex
    ) where

import qualified Data.ByteArray.Encoding as ByteArray
import qualified Data.ByteString as ByteString
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text

bytesToHex :: ByteString.ByteString -> Text.Text
bytesToHex bytes = Text.decodeUtf8 (ByteArray.convertToBase ByteArray.Base16 bytes)
