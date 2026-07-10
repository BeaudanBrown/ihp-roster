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

        it "omits manager-only planning details from staff-only viewers" do
            roster <- maybe (expectationFailure "missing roster topic" >> error "missing roster topic") pure (lookupPageHelpTopic (PageHelpTopicId "roster"))
            let rendered = flattenHelpText (filterPageHelpTopic defaultPageHelpContext roster)
            rendered `shouldSatisfy` all (not . Text.isInfixOf "drag")
            rendered `shouldSatisfy` any (Text.isInfixOf "future roster")
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
