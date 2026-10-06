module Test.EmailDeliveryStatusSpec where

import Application.EmailDelivery.Status
import qualified Data.Aeson as Aeson
import Generated.Types
import IHP.ControllerPrelude
import Test.Hspec

tests :: Spec
tests = describe "Shared email delivery status" do
    it "keeps every queue phase separate from provider evidence" do
        forM_ [(JobStatusNotStarted, DeliveryQueued), (JobStatusRunning, DeliverySending), (JobStatusRetry, DeliveryRetrying), (JobStatusFailed, DeliveryFailed), (JobStatusTimedOut, DeliveryFailed)] \(status, expected) -> do
            let progress = deliveryProgress (newRecord @AppJob |> set #status status) Nothing
            progress.queue `shouldBe` expected
            progress.provider `shouldBe` ProviderUnknown
    it "does not turn successful queue completion into provider acceptance or delivery" do
        let sent = newRecord @AppJob |> set #status JobStatusSucceeded |> set #result (Aeson.object ["deliveryStatus" Aeson..= ("sent" :: Text)])
        (deliveryProgress sent Nothing).queue `shouldBe` DeliveryFinished
        (deliveryProgress sent Nothing).provider `shouldBe` ProviderUnknown
        forM_ ["delivery_skipped", "delivery_disabled"] \status -> do
            (deliveryProgress (sent |> set #result (Aeson.object ["deliveryStatus" Aeson..= (status :: Text)])) Nothing).queue `shouldBe` DeliverySkipped
        (deliveryProgress (sent |> set #result Aeson.Null) Nothing).queue `shouldBe` DeliveryUnavailable
    it "retains acceptance alongside retry, failure or removal and requires provider confirmation" do
        let at = UTCTime (fromGregorian 2030 1 1) 0
        let accepted = newRecord @EmailDeliveryProviderState |> set #smtpAcceptedAt (Just at) |> set #providerStatus "unknown"
        let retry = newRecord @AppJob |> set #status JobStatusRetry
        let progress = deliveryProgress retry (Just accepted)
        progress.provider `shouldBe` ProviderAccepted
        progress.queue `shouldBe` DeliveryRetrying
        (cancelPendingDelivery progress).provider `shouldBe` ProviderAccepted
        (cancelPendingDelivery progress).queue `shouldBe` DeliveryCancelled
        (deliveryProgress (retry |> set #status JobStatusFailed) (Just accepted)).provider `shouldBe` ProviderAccepted
        let confirmed = accepted |> set #providerStatus "delivered" |> set #providerStatusAt (Just at)
        (deliveryProgress retry (Just confirmed)).provider `shouldBe` ProviderConfirmed
        (deliveryProgress retry (Just confirmed)).providerObservedAt `shouldBe` Just at
        forM_ ["bounced", "complained", "failed", "suppressed"] \status -> do
            (deliveryProgress retry (Just (accepted |> set #providerStatus status))).provider `shouldBe` ProviderFailed
        let finished = progress { queue = DeliveryFinished }
        cancelPendingDelivery finished `shouldBe` finished
