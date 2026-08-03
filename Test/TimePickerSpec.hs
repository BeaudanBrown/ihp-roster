module Test.TimePickerSpec where

import Application.Helper.View.TimePicker
import Config
import Control.Exception (evaluate)
import qualified Data.Text as Text
import IHP.Prelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support
import Text.Blaze.Html (Html)
import qualified Text.Blaze.Html.Renderer.Text as HtmlRenderer

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Time picker render helpers" do
        it "renders the global picker from generated roles and exact option payloads" $ withContext do
            withCurrentControllerContext do
                let html = renderText renderQuarterHourTimePickerModal

                html `shouldSatisfy` Text.isInfixOf "id=\"time-picker-modal\""
                html `shouldSatisfy` Text.isInfixOf "aria-labelledby=\"time-picker-modal-title\""
                html `shouldSatisfy` Text.isInfixOf "data-bepis-time-picker-options=\"true\""
                html `shouldSatisfy` Text.isInfixOf "data-bepis-time-picker-option=\"{&quot;label&quot;:&quot;6:00 AM&quot;,&quot;value&quot;:&quot;06:00&quot;}\""
                html `shouldSatisfy` Text.isInfixOf "data-bepis-time-picker-clear=\"true\""
                html `shouldSatisfy` not . Text.isInfixOf "quarter-hour-time-picker-modal"
                html `shouldSatisfy` not . Text.isInfixOf "js-time-picker"
                html `shouldSatisfy` not . Text.isInfixOf "data-time-value"
                html `shouldSatisfy` not . Text.isInfixOf "data-default-start-time"

        it "renders one exact field configuration with generated internal control roles" $ withContext do
            withCurrentControllerContext do
                let config =
                        (defaultTimePickerConfig "startTime" "09:00" "09:00" "13:00" False)
                            { timePickerEmptyLabel = "Start"
                            , timePickerKeyboardEnabled = True
                            , timePickerAutofocus = True
                            , timePickerInvalid = True
                            }
                let html = renderText (renderTimePickerField config)

                html `shouldSatisfy` Text.isInfixOf "data-bepis-time-picker-field=\"true\""
                html `shouldSatisfy` Text.isInfixOf "data-bepis-time-picker-config=\"{&quot;emptyLabel&quot;:&quot;Start&quot;,&quot;rangeEnd&quot;:&quot;13:00&quot;,&quot;rangeStart&quot;:&quot;09:00&quot;,&quot;stepMinutes&quot;:15}\""
                html `shouldSatisfy` Text.isInfixOf "name=\"startTime\" value=\"09:00\" data-bepis-time-picker-value=\"true\""
                html `shouldSatisfy` Text.isInfixOf "data-bepis-time-picker-trigger=\"true\""
                html `shouldSatisfy` Text.isInfixOf "data-bepis-time-picker-keyboard=\"true\""
                html `shouldSatisfy` Text.isInfixOf "autofocus=\"autofocus\""
                html `shouldSatisfy` Text.isInfixOf "aria-invalid=\"true\""
                html `shouldSatisfy` Text.isInfixOf "tabindex=\"-1\""
                html `shouldSatisfy` Text.isInfixOf "data-bepis-time-picker-label=\"true\">9:00 AM"
                html `shouldSatisfy` Text.isInfixOf "data-bepis-time-picker-step-down=\"true\""
                html `shouldSatisfy` Text.isInfixOf "data-bepis-time-picker-step-up=\"true\""
                html `shouldSatisfy` not . Text.isInfixOf "data-time-picker-"
                html `shouldSatisfy` not . Text.isInfixOf "js-time-picker"
                html `shouldSatisfy` not . Text.isInfixOf "data-bepis-toggle"

        it "renders minute precision as a native time input without the picker trigger" $ withContext do
            withCurrentControllerContext do
                let config =
                        (defaultTimePickerConfig "startTime" "12:17" "06:00" "05:45" False)
                            { timePickerStepMinutes = 1
                            , timePickerKeyboardEnabled = True
                            , timePickerAutofocus = True
                            }
                let html = renderText (renderTimePickerField config)

                html `shouldSatisfy` Text.isInfixOf "type=\"time\""
                html `shouldSatisfy` Text.isInfixOf "step=\"60\""
                html `shouldSatisfy` Text.isInfixOf "value=\"12:17\""
                html `shouldSatisfy` Text.isInfixOf "data-bepis-time-picker-keyboard=\"true\""
                html `shouldSatisfy` not . Text.isInfixOf "data-bepis-time-picker-trigger"

        it "keeps optional steps inside the same generated field boundary" $ withContext do
            withCurrentControllerContext do
                let config =
                        (defaultTimePickerConfig "startTime" "" "09:00" "13:00" False)
                            { timePickerShowStepButtons = False
                            , timePickerEmptyLabel = "Start"
                            }
                let html = renderText (renderTimePickerField config)

                html `shouldSatisfy` Text.isInfixOf "data-bepis-time-picker-field=\"true\""
                html `shouldSatisfy` Text.isInfixOf "data-bepis-time-picker-trigger=\"true\""
                html `shouldSatisfy` Text.isInfixOf "data-bepis-time-picker-value=\"true\""
                html `shouldSatisfy` not . Text.isInfixOf "data-bepis-time-picker-step-down"
                html `shouldSatisfy` not . Text.isInfixOf "data-bepis-time-picker-step-up"

        it "rejects a field range that cannot use the canonical Haskell option inventory" $ withContext do
            withCurrentControllerContext do
                let config = defaultTimePickerConfig "startTime" "09:10" "09:10" "13:10" False
                evaluate (Text.length (renderText (renderTimePickerField config)))
                    `shouldThrow` errorCall "Time picker config must use canonical quarter-hour option values"

renderText :: Html -> Text
renderText = cs . HtmlRenderer.renderHtml
