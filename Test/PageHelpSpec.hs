module Test.PageHelpSpec where

import Application.Helper.View.PageHelp
import qualified Data.Text as Text
import IHP.Prelude
import Test.Hspec

managerContext :: PageHelpContext
managerContext = defaultPageHelpContext { pageHelpCanManage = True }

ownerContext :: PageHelpContext
ownerContext = defaultPageHelpContext { pageHelpCanManage = True, pageHelpCanAdmin = True, pageHelpCanOwn = True }

supportContext :: PageHelpContext
supportContext = ownerContext { pageHelpIsSupport = True }

tests :: Spec
tests = do
    describe "page help registry" do
        it "registers all scoped topics" do
            map pageHelpTopicIdToText allPageHelpTopicIds
                `shouldBe` ["roster", "profile", "timesheets", "leave", "admin", "xero", "billing"]

        it "keeps every scoped topic non-empty for a representative authorized audience" do
            forM_ topicContexts \(topicId, context) -> do
                topic <- maybe (expectationFailure ("missing topic " <> cs (pageHelpTopicIdToText topicId)) >> error "missing topic") pure (lookupPageHelpTopic topicId)
                pageHelpTopicSections (filterPageHelpTopic context topic)
                    `shouldSatisfy` (not . null)

    describe "roster help role filtering" do
        it "shows manager planning details to managers" do
            roster <- maybe (expectationFailure "missing roster topic" >> error "missing roster topic") pure (lookupPageHelpTopic (PageHelpTopicId "roster"))
            let rendered = flattenHelpText (filterPageHelpTopic managerContext roster)
            rendered `shouldSatisfy` any (Text.isInfixOf "drag")
            rendered `shouldSatisfy` any (Text.isInfixOf "Ctrl")
            rendered `shouldSatisfy` any (Text.isInfixOf "Option, or Alt")
            rendered `shouldSatisfy` any (Text.isInfixOf "Publish when the roster is ready")
            rendered `shouldSatisfy` any (Text.isInfixOf "hide the Staff/Settings panel temporarily")
            rendered `shouldSatisfy` all (not . Text.isInfixOf "Templates side-panel tab")
            rendered `shouldSatisfy` any (Text.isInfixOf "press Escape")
            rendered `shouldSatisfy` any (Text.isInfixOf "panel stays stacked below the roster")
            rendered `shouldSatisfy` any (Text.isInfixOf "Part-time shifts")
            rendered `shouldSatisfy` any (Text.isInfixOf "pay configuration warning")

        it "omits manager-only planning details from staff-only viewers" do
            roster <- maybe (expectationFailure "missing roster topic" >> error "missing roster topic") pure (lookupPageHelpTopic (PageHelpTopicId "roster"))
            let rendered = flattenHelpText (filterPageHelpTopic defaultPageHelpContext roster)
            rendered `shouldSatisfy` all (not . Text.isInfixOf "drag")
            rendered `shouldSatisfy` all (not . Text.isInfixOf "Publish when the roster is ready")
            rendered `shouldSatisfy` all (not . Text.isInfixOf "Staff/Settings panel")
            rendered `shouldSatisfy` any (Text.isInfixOf "future roster")

    describe "timesheet help copy" do
        it "explains origin semantics without relying on removed form banners" do
            timesheets <- maybe (expectationFailure "missing timesheets topic" >> error "missing timesheets topic") pure (lookupPageHelpTopic (PageHelpTopicId "timesheets"))
            let rendered = flattenHelpText (filterPageHelpTopic managerContext timesheets)
            rendered `shouldSatisfy` any (Text.isInfixOf "without an origin warning")
            rendered `shouldSatisfy` any (Text.isInfixOf "no separate origin banner")
            rendered `shouldSatisfy` any (Text.isInfixOf "saved to your account")
            rendered `shouldSatisfy` any (Text.isInfixOf "every active Timesheet-eligible staff member")
            rendered `shouldSatisfy` any (Text.isInfixOf "eye to pin")
            rendered `shouldSatisfy` any (Text.isInfixOf "panel stays stacked below the week")
            rendered `shouldSatisfy` any (Text.isInfixOf "never filters the week")
            rendered `shouldSatisfy` all (not . Text.isInfixOf "Each saved entry shows its own pay preview")

    describe "unavailability help copy" do
        it "explains the manager SidePanel and admin blackout location" do
            leave <- maybe (expectationFailure "missing leave topic" >> error "missing leave topic") pure (lookupPageHelpTopic (PageHelpTopicId "leave"))
            let managerHelp = flattenHelpText (filterPageHelpTopic managerContext leave)
            let adminHelp = flattenHelpText (filterPageHelpTopic ownerContext leave)
            managerHelp `shouldSatisfy` any (Text.isInfixOf "panel stays stacked below the requests")
            managerHelp `shouldSatisfy` any (Text.isInfixOf "including trial profiles")
            managerHelp `shouldSatisfy` any (Text.isInfixOf "eye to pin")
            adminHelp `shouldSatisfy` any (Text.isInfixOf "Open Settings")

    describe "billing help role filtering" do
        it "keeps payer actions owner-only while showing diagnostics to founder support" do
            billing <- maybe (expectationFailure "missing billing topic" >> error "missing billing topic") pure (lookupPageHelpTopic (PageHelpTopicId "billing"))
            let ownerHelp = flattenHelpText (filterPageHelpTopic ownerContext billing)
            let supportHelp = flattenHelpText (filterPageHelpTopic supportContext billing)
            ownerHelp `shouldSatisfy` any (Text.isInfixOf "Subscribe")
            ownerHelp `shouldSatisfy` all (not . Text.isInfixOf "Synchronize with Stripe")
            supportHelp `shouldSatisfy` any (Text.isInfixOf "Synchronize with Stripe")
            supportHelp `shouldSatisfy` all (not . Text.isInfixOf "Subscribe")
            supportHelp `shouldSatisfy` all (not . Text.isInfixOf "manual read-only")
  where
    topicContexts =
        [ (PageHelpTopicId "roster", managerContext)
        , (PageHelpTopicId "profile", defaultPageHelpContext)
        , (PageHelpTopicId "timesheets", managerContext)
        , (PageHelpTopicId "leave", managerContext)
        , (PageHelpTopicId "admin", ownerContext)
        , (PageHelpTopicId "xero", ownerContext)
        , (PageHelpTopicId "billing", supportContext)
        ]

flattenHelpText :: PageHelpTopic -> [Text]
flattenHelpText topic =
    [ item.pageHelpItemTitle <> " " <> item.pageHelpItemBody
    | section <- topic.pageHelpTopicSections
    , item <- section.pageHelpSectionItems
    ]
