module Test.RosterTemplateSurfaceSpec where

import Test.Hspec
import Web.RosterTemplates.FrontendSurface

tests :: Spec
tests = describe "Roster Template Designer Surface" do
    it "owns reference-target role and compatibility state attributes" do
        rosterTemplateReferenceTargetAttrs `shouldContain`
            [ ("data-bepis-roster-template-designer-template-reference-target", "true")
            , ("data-bepis-roster-template-designer-template-reference-compatibility", "compatible")
            ]
