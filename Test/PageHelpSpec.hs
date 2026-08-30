module Test.PageHelpSpec where

import Application.Helper.View.PageHelp
import qualified Data.List as List
import IHP.Prelude
import Test.Hspec

managerContext, adminContext, ownerContext, supportContext, founderContext, impersonatingStaffContext :: PageHelpContext
managerContext = defaultPageHelpContext { pageHelpCanManage = True }
adminContext = managerContext { pageHelpCanAdmin = True }
ownerContext = adminContext { pageHelpCanOwn = True }
supportContext = ownerContext { pageHelpIsSupport = True }
founderContext = defaultPageHelpContext { pageHelpIsFounder = True }
impersonatingStaffContext = defaultPageHelpContext { pageHelpIsImpersonating = True }

tests :: Spec
tests = do
    describe "page help registry" do
        it "has unique topic identities that resolve to non-empty authorized help" do
            allPageHelpTopicIds `shouldSatisfy` (not . null)
            allPageHelpTopicIds `shouldBe` List.nub allPageHelpTopicIds
            forM_ allPageHelpTopicIds \topicId -> do
                topic <- requireTopic topicId
                lookupPageHelpTopic topicId `shouldBe` Just topic
                map (\(_, context, _) -> context) audienceCases
                    `shouldSatisfy` (not . all (null . pageHelpTopicSections . (`filterPageHelpTopic` topic)))
                forM_ audienceCases \(_, context, visibleAudiences) -> do
                    let actualItems = pageHelpItemIdentities (filterPageHelpTopic context topic)
                        expectedItems = expectedItemIdentities visibleAudiences topic
                    if context.pageHelpIsFounder
                        then do
                            expectedItems `shouldSatisfy` (`List.isSuffixOf` actualItems)
                            length actualItems `shouldSatisfy` (> length expectedItems)
                        else actualItems `shouldBe` expectedItems

    describe "page help audience policy" do
        forM_ audienceCases \(label, context, expected) ->
            it label do
                filter (fixtureAudienceVisible context) allAudiences `shouldBe` expected

requireTopic :: PageHelpTopicId -> IO PageHelpTopic
requireTopic topicId =
    maybe
        (expectationFailure ("missing topic " <> cs (pageHelpTopicIdToText topicId)) >> pure (fixtureTopic HelpEveryone))
        pure
        (lookupPageHelpTopic topicId)

allAudiences :: [PageHelpAudience]
allAudiences = [minBound .. maxBound]

audienceCases :: [(String, PageHelpContext, [PageHelpAudience])]
audienceCases =
    [ ("staff", defaultPageHelpContext, [HelpEveryone, HelpStaffOnly, HelpUnimpersonatedOnly])
    , ("manager", managerContext, [HelpEveryone, HelpManagerPlus, HelpUnimpersonatedOnly])
    , ("admin", adminContext, [HelpEveryone, HelpManagerPlus, HelpAdminPlus, HelpUnimpersonatedOnly])
    , ("owner", ownerContext, [HelpEveryone, HelpManagerPlus, HelpAdminPlus, HelpOwnerPlus, HelpOwnerOnly, HelpUnimpersonatedOnly])
    , ("support", supportContext, [HelpEveryone, HelpManagerPlus, HelpAdminPlus, HelpOwnerPlus, HelpSupportOnly, HelpUnimpersonatedOnly])
    , ("impersonating staff", impersonatingStaffContext, [HelpEveryone, HelpStaffOnly])
    , ("founder", founderContext, [HelpEveryone, HelpStaffOnly, HelpUnimpersonatedOnly, HelpFounderOnly])
    ]

fixtureAudienceVisible :: PageHelpContext -> PageHelpAudience -> Bool
fixtureAudienceVisible context audience =
    any ((== fixtureSectionTitle) . pageHelpSectionTitle)
        (pageHelpTopicSections (filterPageHelpTopic context (fixtureTopic audience)))

fixtureTopic :: PageHelpAudience -> PageHelpTopic
fixtureTopic audience =
    PageHelpTopic
        { pageHelpTopicId = PageHelpTopicId "fixture"
        , pageHelpTopicTitle = "Fixture"
        , pageHelpTopicSections =
            [ PageHelpSection
                { pageHelpSectionAudience = audience
                , pageHelpSectionTitle = fixtureSectionTitle
                , pageHelpSectionItems =
                    [ PageHelpItem
                        { pageHelpItemAudience = audience
                        , pageHelpItemIconClass = Nothing
                        , pageHelpItemIconLabel = Nothing
                        , pageHelpItemTitle = "fixture-item"
                        , pageHelpItemBody = "fixture-body"
                        , pageHelpItemExampleButton = Nothing
                        }
                    ]
                }
            ]
        }

fixtureSectionTitle :: Text
fixtureSectionTitle = "fixture-section"

type PageHelpItemIdentity = (Text, Text)

pageHelpItemIdentities :: PageHelpTopic -> [PageHelpItemIdentity]
pageHelpItemIdentities topic =
    [ (section.pageHelpSectionTitle, item.pageHelpItemTitle)
    | section <- topic.pageHelpTopicSections
    , item <- section.pageHelpSectionItems
    ]

expectedItemIdentities :: [PageHelpAudience] -> PageHelpTopic -> [PageHelpItemIdentity]
expectedItemIdentities visibleAudiences topic =
    [ (section.pageHelpSectionTitle, item.pageHelpItemTitle)
    | section <- topic.pageHelpTopicSections
    , section.pageHelpSectionAudience `elem` visibleAudiences
    , item <- section.pageHelpSectionItems
    , item.pageHelpItemAudience `elem` visibleAudiences
    ]
