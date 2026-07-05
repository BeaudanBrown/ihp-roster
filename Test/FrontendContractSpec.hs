{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Test.FrontendContractSpec
    ( tests
    ) where

import Application.Helper.FrontendContract.DSL
import Application.Helper.FrontendContract.IR
import Application.Helper.FrontendContract.Reflect
import Application.Helper.FrontendContract.Registry
import Application.Helper.FrontendContract.TypeScript
import IHP.Prelude hiding (Enum)
import Test.Hspec

-- Fixture markers
data App
data FixtureSurface

data UserId
data StaffName
data FavoriteDay
data Note
data StaffRecord
data DraftStaffRecord
data ActiveStatus
data InactiveStatus
data StaffStatus
data CreatedCase
data DeletedCase
data StaffEvent
data OpenDialog
data OverlayRoot
data SurfaceScope
data SurfacePanelFragment

type FixtureContracts =
    '[ Global App
        '[ GlobalSchema (Record StaffRecord
            '[ Field UserId 'WireUUID
             , Field StaffName 'WireText
             , OptionalField FavoriteDay 'WireDay
             , NullableField Note 'WireText
             ])
         , GlobalSchema (Record DraftStaffRecord
            '[ Field StaffName 'WireText
             ])
         , GlobalSchema (Enum StaffStatus '[ActiveStatus, InactiveStatus])
         , GlobalSchema (TaggedUnion StaffEvent
            '[ Case CreatedCase '[Field UserId 'WireUUID]
             , Case DeletedCase '[Field UserId 'WireUUID]
             ])
         , Event OpenDialog '[Field UserId 'WireUUID]
         , DomAttr OverlayRoot
         ]
     , Surface FixtureSurface
        '[ SurfaceSchema (Record SurfaceScope '[Field UserId 'WireUUID])
         , Scope SurfaceScope '[Field UserId 'WireUUID]
         , Fragment SurfacePanelFragment '[Field UserId 'WireUUID]
         , Dto DraftStaffRecord '[Field StaffName 'WireText]
         ]
     ]

data DuplicateName
data DuplicateNameOne
data MissingRecord
data MissingRefField

type DuplicateContracts =
    '[ Global App
        '[ GlobalSchema (Record DuplicateName '[Field StaffName 'WireText])
         , GlobalSchema (Enum DuplicateName '[ActiveStatus])
         ]
     ]

type MissingRefContracts =
    '[ Global App
        '[ GlobalSchema (Record MissingRecord '[Field MissingRefField ('WireRef StaffRecord)])
         ]
     ]

tests :: Spec
tests = describe "FrontendContract foundation" do
    it "reflects the production migration registry globals" do
        let source = either id id (renderFrontendContractTypeScript registeredFrontendContractIR)
        source `shouldContainText` "export type OverlayLane ="
        source `shouldContainText` "export const pageReadyEvent = \"bepis:page-ready\" as const;"
        source `shouldContainText` "export const dialogOverlayMountDomId = \"dialog-overlay-mount\" as const;"
        source `shouldContainText` "export type UiRegionTransitionProfile ="
        source `shouldContainText` "export const lazySurfaceDomAttr = \"data-bepis-lazy-surface\" as const;"
        source `shouldContainText` "export type RosterStaffSortKey ="
        source `shouldContainText` "  | \"shifts\";"
        source `shouldContainText` "export type RosterRosterWeekScope = { venueId: FrontendContractUuid; rosterGroupId: FrontendContractUuid; weekOffset: number };"

    it "reflects a mixed Global and Surface registry" do
        let contract = reflectFrontendContracts @FixtureContracts
        fmap (.globalName) contract.contractGlobals `shouldBe` ["app"]
        fmap (.surfaceName) contract.contractSurfaces `shouldBe` ["fixture"]
        case checkedFrontendContractIR contract of
            Right _          -> pure ()
            Left diagnostics -> expectationFailure (cs (show diagnostics))

    it "validates duplicate declarations and unresolved refs" do
        validateFrontendContractIR (reflectFrontendContracts @DuplicateContracts)
            |> fmap (.diagnosticCode)
            `shouldContain` ["schema-name-collision"]
        validateFrontendContractIR (reflectFrontendContracts @MissingRefContracts)
            |> fmap (.diagnosticCode)
            `shouldContain` ["unresolved-ref"]

    it "renders TypeScript types, constants, guards, parsers, and encoders" do
        let Right source = renderFrontendContractTypeScript (reflectFrontendContracts @FixtureContracts)
        source `shouldContainText` "export type StaffRecord = { userId: FrontendContractUuid; staffName: string; favoriteDay?: FrontendContractDay; note: string | null };"
        source `shouldContainText` "export type StaffStatus ="
        source `shouldContainText` "  | \"inactive-status\";"
        source `shouldContainText` "export type StaffEvent ="
        source `shouldContainText` "{ tag: \"created-case\"; userId: FrontendContractUuid }"
        source `shouldContainText` "export const openDialogEvent = \"bepis:open-dialog\" as const;"
        source `shouldContainText` "export const overlayRootDomAttr = \"data-bepis-overlay-root\" as const;"
        source `shouldContainText` "export function parseStaffRecord(value: unknown): StaffRecord"
        source `shouldContainText` "export function encodeStaffRecord(value: StaffRecord): StaffRecord"
        source `shouldContainText` "export type FixtureSurfaceSurfaceScopeScope = { userId: FrontendContractUuid };"

shouldContainText :: Text -> Text -> Expectation
shouldContainText haystack needle = haystack `shouldSatisfy` (needle `isInfixOf`)
