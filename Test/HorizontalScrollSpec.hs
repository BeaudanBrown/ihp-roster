module Test.HorizontalScrollSpec where

import Application.Helper.FrontendContract.HorizontalScroll.Runtime
import Control.Exception (evaluate)
import qualified Data.Text as Text
import IHP.Prelude
import Test.Hspec

nearestItemConfig :: HorizontalSnapConfig
nearestItemConfig = HorizontalSnapNearestItem ".timesheet-day-panel"

tests :: Spec
tests = describe "Horizontal scroll contract runtime" do
    it "serializes generated nearest-item snap and drag roles with exact configuration" do
        horizontalSnapAttrs nearestItemConfig
            `shouldBe`
                [ ("data-bepis-horizontal-scroll-snap", "true")
                , ("data-bepis-horizontal-snap-config", "{\"groupCount\":null,\"groupProperty\":null,\"groupScopeSelector\":null,\"itemSelector\":\".timesheet-day-panel\",\"snapMode\":\"nearest-item\"}")
                ]
        horizontalDragAttrs (HorizontalDragConfig Nothing)
            `shouldBe`
                [ ("data-bepis-horizontal-scroll-drag", "true")
                , ("data-bepis-horizontal-drag-config", "{\"ignoreSelector\":null}")
                ]

    it "serializes generated equal-group CSS configuration" do
        horizontalSnapAttrs (HorizontalSnapEqualGroups (HorizontalSnapGroupProperty
            { horizontalSnapGroupProperty = "--roster-slot-count"
            , horizontalSnapGroupScopeSelector = ".roster-grid-frame"
            }))
            `shouldBe`
                [ ("data-bepis-horizontal-scroll-snap", "true")
                , ("data-bepis-horizontal-snap-config", "{\"groupCount\":null,\"groupProperty\":\"--roster-slot-count\",\"groupScopeSelector\":\".roster-grid-frame\",\"itemSelector\":null,\"snapMode\":\"equal-groups\"}")
                ]

    it "rejects invalid Haskell-owned configuration" do
        evaluate (attrsTextLength (horizontalSnapAttrs (HorizontalSnapNearestItem "  ")))
            `shouldThrow` errorCall "Horizontal snap item selector must not be empty"
        evaluate (attrsTextLength (horizontalSnapAttrs (HorizontalSnapEqualGroups (HorizontalSnapGroupCount 0))))
            `shouldThrow` errorCall "Horizontal snap group count must be positive"
        evaluate (attrsTextLength (horizontalDragAttrs (HorizontalDragConfig (Just ""))))
            `shouldThrow` errorCall "Horizontal drag ignore selector must not be empty"

attrsTextLength :: [(Text, Text)] -> Int
attrsTextLength = Text.length . Text.concat . fmap snd
