{-# LANGUAGE RankNTypes #-}

module Test.Support.EmailDelivery
    ( capturingEmailDeliveryRuntime
    , disabledEmailDeliveryRuntime
    , enabledEmailDeliveryRuntime
    , failingEmailDeliveryRuntime
    ) where

import Application.EmailDelivery (EmailDeliveryRuntime (..))
import IHP.MailPrelude (BuildMail)
import IHP.Prelude
import Test.Hspec (expectationFailure)

capturingEmailDeliveryRuntime :: (forall mail. BuildMail mail => mail -> IO ()) -> EmailDeliveryRuntime
capturingEmailDeliveryRuntime deliverMail =
    EmailDeliveryRuntime
        { deliveryIsDisabled = pure False
        , deliverMail
        }

enabledEmailDeliveryRuntime :: EmailDeliveryRuntime
enabledEmailDeliveryRuntime = capturingEmailDeliveryRuntime (const (pure ()))

disabledEmailDeliveryRuntime :: EmailDeliveryRuntime
disabledEmailDeliveryRuntime =
    EmailDeliveryRuntime
        { deliveryIsDisabled = pure True
        , deliverMail = const (expectationFailure "disabled email delivery must not invoke transport")
        }

failingEmailDeliveryRuntime :: String -> EmailDeliveryRuntime
failingEmailDeliveryRuntime message = capturingEmailDeliveryRuntime (const (ioError (userError message)))
