module Test.SurfaceGuardSpec where

import Application.Helper.FrontendContract.Surface.ContractIR
import Application.Helper.FrontendContract.Surface.Contracts (registeredFrontendSurfaceContractIR)
import IHP.Prelude
import Test.Hspec

tests :: Spec
tests = describe "FrontendSurface structural guard" do
    it "accepts the complete reflected production registry" do
        checkedSurfaceContractIR registeredFrontendSurfaceContractIR
            `shouldBe` Right registeredFrontendSurfaceContractIR

    it "gives every mounted fragment exactly one reflected target declaration" do
        let fragments = concatMap (.surfaceFragments) registeredFrontendSurfaceContractIR.contractSurfaces
            mountTargets fragment = [target | MountTargetOption target _ <- fragment.fragmentOptions]
        map (length . mountTargets) fragments `shouldSatisfy` all (== 1)

    it "resolves every typed HTMX target through an owned DOM declaration" do
        let unresolvedTargets =
                [ (surface.surfaceName, action.htmxActionName, reference)
                | surface <- registeredFrontendSurfaceContractIR.contractSurfaces
                , let ownedTargets =
                        surface.surfaceDomTokens
                            <> [target | fragment <- surface.surfaceFragments, MountTargetOption target _ <- fragment.fragmentOptions]
                , action <- surface.surfaceHtmxActions
                , HtmxOption (HtmxActionTargetIR syntax) <- action.htmxActionOptions
                , reference <- htmxSyntaxReferences syntax
                , reference `notElem` ownedTargets
                ]
        unresolvedTargets `shouldBe` []
