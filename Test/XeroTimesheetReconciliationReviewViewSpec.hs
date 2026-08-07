module Test.XeroTimesheetReconciliationReviewViewSpec where

import Application.Helper.XeroAdminTypes
import qualified Data.Text as Text
import IHP.Prelude
import Test.Hspec
import Text.Blaze.Html (Html)
import qualified Text.Blaze.Html.Renderer.Text as HtmlRenderer
import Web.View.Admin.Xero.TimesheetPreparation.Review

tests :: Spec
tests =
    describe "Xero timesheet reconciliation review rendering" do
        it "renders replacement warnings and every controlled blocker as actionable alerts" do
            let messages =
                        [ "Bepis previously created Xero draft missing-id, but it is now missing. Confirm to create a replacement draft."
                        , "Xero timesheet approved-id is APPROVED and cannot be changed by Bepis. Review it in Xero before trying again."
                        , "Xero has multiple distinct timesheets for this employee and period (one, two). Resolve them in Xero, then review again."
                        , "Xero returned an unsupported status for timesheet future-id (status FUTURE). Review it in Xero or contact support."
                        , "Xero returned a timesheet without an ID (status DRAFT). Refresh Xero data or contact support."
                        , "A Bepis Xero timesheet submission is still in progress. Wait for it to finish, then review again."
                        ]
                notices = zipWith issue ["warning", "blocker", "blocker", "blocker", "blocker", "blocker"] messages
                html = renderText (renderReconciliationNotices notices)

            html `shouldSatisfy` Text.isInfixOf "Latest Xero check"
            html `shouldSatisfy` Text.isInfixOf "alert-warning"
            length (Text.breakOnAll "alert-danger" html) `shouldBe` 5
            forM_ messages \message -> html `shouldSatisfy` Text.isInfixOf message

        it "renders safe create/update guidance when no warning is required" do
            renderText (renderReconciliationNotices [])
                `shouldSatisfy` Text.isInfixOf "create missing drafts and update only confirmed Xero drafts"
  where
    issue severity message =
        XeroTimesheetIssueView
            { timesheetIssueCode = "xero_reconciliation"
            , timesheetIssueSeverity = severity
            , timesheetIssueMessage = message
            , timesheetIssueHint = Nothing
            }

renderText :: Html -> Text
renderText = cs . HtmlRenderer.renderHtml
