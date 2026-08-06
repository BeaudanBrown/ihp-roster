module Test.OrderedRangeSpec where

import Application.Helper.FrontendContract.OrderedRange.Runtime
import Application.Helper.FrontendContract.Surface.Profile (StaffProfileSectionValue (..))
import qualified Application.Helper.FrontendContract.Surface.Profile.Action as ProfileAction
import Application.Helper.StaffShiftPreferences
import Config
import Control.Exception (evaluate)
import qualified Data.Text as Text
import IHP.Prelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support
import Text.Blaze.Html (Html)
import qualified Text.Blaze.Html.Renderer.Text as HtmlRenderer
import Web.View.StaffProfileForm (renderShiftPreferenceDayRow)

fixtureConfig :: OrderedRangeBrowserConfig
fixtureConfig = OrderedRangeBrowserConfig
    { orderedRangeMinimumValue = 5
    , orderedRangeMaximumValue = 7
    , orderedRangeStepValue = 1
    , orderedRangeDefaultStartValue = 5
    , orderedRangeDefaultEndValue = 7
    , orderedRangeValueLabels = ["5 AM", "6 AM", "7 AM"]
    , orderedRangeCrossingPolicy = ClampOtherEndpoint
    }

fixtureState :: OrderedRangeBrowserState
fixtureState = OrderedRangeBrowserState
    { orderedRangeStartValue = 6
    , orderedRangeEndValue = 7
    , orderedRangeAvailable = True
    }

pureTests :: Spec
pureTests = do
    describe "Ordered range contract runtime" do
        it "serializes exact generated configuration, state, and roles" do
            orderedRangeConfigJson fixtureConfig
                `shouldBe` "{\"crossingPolicy\":\"clamp-other-endpoint\",\"defaultEndValue\":7,\"defaultStartValue\":5,\"maximumValue\":7,\"minimumValue\":5,\"stepValue\":1,\"valueLabels\":[\"5 AM\",\"6 AM\",\"7 AM\"]}"
            orderedRangeStateJson fixtureConfig fixtureState
                `shouldBe` "{\"available\":true,\"endValue\":7,\"startValue\":6}"
            orderedRangeRootAttrs fixtureConfig fixtureState
                `shouldBe`
                    [ ("data-bepis-ordered-range-root", "true")
                    , ("data-bepis-ordered-range-config", orderedRangeConfigJson fixtureConfig)
                    , ("data-bepis-ordered-range-state", orderedRangeStateJson fixtureConfig fixtureState)
                    ]
            orderedRangeStartAttrs fixtureConfig
                `shouldBe`
                    [ ("data-bepis-ordered-range-start", "true")
                    , ("min", "5")
                    , ("max", "7")
                    , ("step", "1")
                    ]
            orderedRangeEndAttrs fixtureConfig
                `shouldBe`
                    [ ("data-bepis-ordered-range-end", "true")
                    , ("min", "5")
                    , ("max", "7")
                    , ("step", "1")
                    ]
            orderedRangeAvailabilityAttrs
                `shouldBe` [("data-bepis-ordered-range-availability", "true")]
            orderedRangePositionStyle fixtureConfig fixtureState
                `shouldBe` "--ordered-range-start-position: 50.000%; --ordered-range-end-position: 100.000%;"

        it "rejects incomplete semantic value inventories and invalid initial state" do
            let missingLabel = fixtureConfig { orderedRangeValueLabels = ["5 AM", "6 AM"] }
            evaluate (Text.length (orderedRangeConfigJson missingLabel))
                `shouldThrow` errorCall "Ordered range labels must cover every allowed value"
            let crossedState = fixtureState { orderedRangeStartValue = 7, orderedRangeEndValue = 6 }
            evaluate (Text.length (orderedRangeStateJson fixtureConfig crossedState))
                `shouldThrow` errorCall "Ordered range start value must not exceed end value"

databaseTests :: Spec
databaseTests = aroundAll withDatabaseTestContext do
    describe "Shift preference ordered range rendering" do
        it "renders generated roles and Haskell-owned state without legacy DOM names" $ withContext do
            withCurrentControllerContext do
                let fields = ProfileAction.updateProfileShiftPreferencesActionFields StaffProfilePreferencesSection (Just ["2"])
                let weekday = PreferenceWeekday { weekdayIndex = 2, label = "Tuesday" }
                let selection = ShiftPreferenceSelection { weekdayIndex = 2, startHour = 6, endHour = 17 }
                let html = renderText (renderShiftPreferenceDayRow fields [selection] weekday)

                html `shouldSatisfy` Text.isInfixOf "data-bepis-ordered-range-root=\"true\""
                html `shouldSatisfy` Text.isInfixOf "data-bepis-ordered-range-config=\"{&quot;crossingPolicy&quot;:&quot;clamp-other-endpoint&quot;"
                html `shouldSatisfy` Text.isInfixOf "data-bepis-ordered-range-state=\"{&quot;available&quot;:true,&quot;endValue&quot;:17,&quot;startValue&quot;:6}\""
                html `shouldSatisfy` Text.isInfixOf "data-bepis-ordered-range-availability=\"true\""
                html `shouldSatisfy` Text.isInfixOf "data-bepis-ordered-range-start=\"true\""
                html `shouldSatisfy` Text.isInfixOf "data-bepis-ordered-range-end=\"true\""
                html `shouldSatisfy` Text.isInfixOf "name=\"shiftPreferenceStartHour:2\" value=\"6\""
                html `shouldSatisfy` Text.isInfixOf "name=\"shiftPreferenceEndHour:2\" value=\"17\""
                html `shouldSatisfy` Text.isInfixOf "<label class=\"visually-hidden\" for=\"shiftPreferenceStart-2\">Earliest preferred start</label>"
                html `shouldSatisfy` Text.isInfixOf "<label class=\"visually-hidden\" for=\"shiftPreferenceEnd-2\">Latest preferred start</label>"
                html `shouldSatisfy` Text.isInfixOf "<output class=\"shift-preference-range__bubble shift-preference-range__bubble--start\" for=\"shiftPreferenceStart-2\" aria-hidden=\"true\">6 AM</output>"
                html `shouldSatisfy` Text.isInfixOf "<output class=\"shift-preference-range__bubble shift-preference-range__bubble--end\" for=\"shiftPreferenceEnd-2\" aria-hidden=\"true\">5 PM</output>"
                html `shouldSatisfy` not . Text.isInfixOf "data-shift-preference"
                html `shouldSatisfy` not . Text.isInfixOf "data-min-hour"
                html `shouldSatisfy` not . Text.isInfixOf "data-max-hour"
                html `shouldSatisfy` not . Text.isInfixOf "is-unavailable"

renderText :: Html -> Text
renderText = cs . HtmlRenderer.renderHtml
