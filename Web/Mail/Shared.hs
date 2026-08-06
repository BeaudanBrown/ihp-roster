module Web.Mail.Shared
    ( bepisFrom
    , bepisReplyTo
    , supportFooterText
    ) where

import IHP.MailPrelude
import qualified Text.Blaze.Html5 as Html

bepisFrom :: Text -> Address
bepisFrom fromAddress =
    Address
        { addressName = Just "Bepis"
        , addressEmail = fromAddress
        }

bepisReplyTo :: Text -> Maybe Address
bepisReplyTo replyToAddress =
    Just
        Address
            { addressName = Just "Bepis Support"
            , addressEmail = replyToAddress
            }


supportFooterText :: Text -> Text
supportFooterText supportEmail =
    "\n\nYou’re receiving this because this email address is associated with a Bepis account, venue, or invitation."
        <> "\n\nIf this wasn’t expected, you can ignore this email or contact "
        <> supportEmail
        <> "."
