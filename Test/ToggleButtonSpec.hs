{-# LANGUAGE TypeApplications #-}

module Test.ToggleButtonSpec where

import Application.Helper.FrontendContract.Surface.Profile (StaffProfileSectionValue (..))
import qualified Application.Helper.FrontendContract.Surface.Profile as ProfileSurface
import qualified Application.Helper.FrontendContract.Surface.Profile.Action as ProfileAction
import Application.Helper.FrontendContract.Surface.Roster (RosterStaffScopeValue (..))
import qualified Application.Helper.FrontendContract.Surface.Roster as RosterSurface
import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import Application.Helper.View.ToggleButton
import Config
import qualified Data.Text as Text
import IHP.Prelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support
import Text.Blaze.Html (Html)
import qualified Text.Blaze.Html.Renderer.Text as HtmlRenderer
import qualified Text.Blaze.Html5 as Html5

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "App toggle button" do
        it "renders generated roles and an exact boolean transport without legacy DOM agreements" $ withContext do
            withCurrentControllerContext do
                let config = defaultAppToggleButtonConfig "fixed-toggle" (namedBooleanToggleField "enabled") True (Html5.toHtml ("Fixed label" :: Text))
                let html = renderText (renderAppToggleButton config)

                html `shouldSatisfy` Text.isInfixOf "Fixed label"
                html `shouldSatisfy` Text.isInfixOf "data-bepis-toggle-root=\"toggle-transport:fixed-toggle\""
                html `shouldSatisfy` Text.isInfixOf "data-bepis-toggle-input=\"toggle-transport:fixed-toggle\""
                html `shouldSatisfy` Text.isInfixOf "data-bepis-toggle-transport=\"toggle-transport:fixed-toggle\""
                html `shouldSatisfy` Text.isInfixOf "name=\"enabled\" value=\"true\""
                html `shouldSatisfy` Text.isInfixOf "&quot;presentationState&quot;:&quot;checked&quot;"
                html `shouldSatisfy` Text.isInfixOf "&quot;submissionPolicy&quot;:&quot;deferred&quot;"
                html `shouldSatisfy` not . Text.isInfixOf "data-app-toggle"
                html `shouldSatisfy` not . Text.isInfixOf "onchange="
                html `shouldSatisfy` not . Text.isInfixOf "btn-success"

        it "renders both server-declared state labels with only the current state visible" $ withContext do
            withCurrentControllerContext do
                let html = renderText (renderAppToggleButton (defaultAppToggleStateButtonConfig "state-toggle" (namedBooleanToggleField "enabled") False (Html5.toHtml ("Enabled" :: Text)) (Html5.toHtml ("Disabled" :: Text))))

                html `shouldSatisfy` Text.isInfixOf "data-bepis-toggle-label-state=\"checked\" hidden=\"hidden\">Enabled"
                html `shouldSatisfy` Text.isInfixOf "data-bepis-toggle-label-state=\"unchecked\">Disabled"
                html `shouldSatisfy` Text.isInfixOf "aria-pressed=\"false\""

                let checkedHtml = renderText (renderAppToggleButton ((defaultAppToggleStateButtonConfig "checked-state-toggle" (namedBooleanToggleField "enabled") True (Html5.toHtml ("Enabled" :: Text)) (Html5.toHtml ("Disabled" :: Text))) { appToggleRoleSwitch = True }))
                checkedHtml `shouldSatisfy` Text.isInfixOf "data-bepis-toggle-label-state=\"checked\">Enabled"
                checkedHtml `shouldSatisfy` Text.isInfixOf "data-bepis-toggle-label-state=\"unchecked\" hidden=\"hidden\">Disabled"
                checkedHtml `shouldSatisfy` Text.isInfixOf "aria-pressed=\"true\""
                checkedHtml `shouldSatisfy` Text.isInfixOf "aria-checked=\"true\""

        it "keeps presentation state distinct from a typed non-Boolean Action field mapping" $ withContext do
            withCurrentControllerContext do
                let fields = RosterAction.toggleRosterStaffScopeActionFields RosterStaffCurrentGroup
                let binding = surfaceToggleScalarField @RosterSurface.StaffScope fields RosterStaffAllVenue RosterStaffCurrentGroup
                let config =
                        (defaultAppToggleButtonConfig "staff-scope" binding False (Html5.toHtml ("Show all staff" :: Text)))
                            { appToggleSubmitPolicy = ToggleSubmitImmediate }
                let html = renderText (renderAppToggleButton config)

                html `shouldSatisfy` Text.isInfixOf "name=\"staffScope\" value=\"group\""
                html `shouldSatisfy` Text.isInfixOf "&quot;presentationState&quot;:&quot;unchecked&quot;"
                html `shouldSatisfy` Text.isInfixOf "&quot;value&quot;:&quot;all&quot;"
                html `shouldSatisfy` Text.isInfixOf "&quot;value&quot;:&quot;group&quot;"
                html `shouldSatisfy` Text.isInfixOf "&quot;submissionPolicy&quot;:&quot;immediate&quot;"

        it "renders a declaration-typed repeated Action field as value-or-omitted transport" $ withContext do
            withCurrentControllerContext do
                let fields = ProfileAction.updateProfileShiftPreferencesActionFields StaffProfilePreferencesSection (Just ["monday"])
                let binding = surfaceToggleListItemField @ProfileSurface.ShiftPreferenceKeysField fields "monday"
                let uncheckedHtml = renderText (renderAppToggleButton (defaultAppToggleButtonConfig "monday-available" binding False (Html5.toHtml ("Monday" :: Text))))
                let checkedHtml = renderText (renderAppToggleButton (defaultAppToggleButtonConfig "monday-available" binding True (Html5.toHtml ("Monday" :: Text))))

                uncheckedHtml `shouldSatisfy` Text.isInfixOf "name=\"shiftPreferenceKeys\" value=\"\" data-bepis-toggle-transport=\"toggle-transport:monday-available\" disabled=\"disabled\""
                uncheckedHtml `shouldSatisfy` Text.isInfixOf "&quot;tag&quot;:&quot;omitted&quot;"
                checkedHtml `shouldSatisfy` Text.isInfixOf "name=\"shiftPreferenceKeys\" value=\"monday\""

        it "renders a form-local native break fieldset relationship" $ withContext do
            withCurrentControllerContext do
                let region = toggleBreakRegion "timesheet-break-fields"
                let toggle =
                        renderAppToggleButton
                            ((defaultAppToggleButtonConfig "had-break" (namedBooleanToggleField "hadBreak") False (Html5.toHtml ("Had break" :: Text))) { appToggleBreakRegion = Just region })
                let html = renderText (toggle <> renderAppToggleBreakRegion region False "row" (Html5.toHtml ("Break controls" :: Text)))

                html `shouldSatisfy` Text.isInfixOf "aria-controls=\"timesheet-break-fields\""
                html `shouldSatisfy` Text.isInfixOf "&quot;breakRegionKey&quot;:&quot;toggle-break-region:timesheet-break-fields&quot;"
                html `shouldSatisfy` Text.isInfixOf "id=\"timesheet-break-fields\" class=\"row\" data-bepis-toggle-break-region=\"toggle-break-region:timesheet-break-fields\" disabled=\"disabled\" aria-disabled=\"true\""

renderText :: Html -> Text
renderText = cs . HtmlRenderer.renderHtml
