module Test.FrontendSurfaceGhcSpec
    ( tests
    ) where

import Application.Helper.FrontendSurface.Contracts (registeredFrontendSurfaceContractIR)
import Application.Helper.FrontendSurface.Ghc.Lower
import Application.Helper.FrontendSurface.Ghc.Raw
import qualified Data.List as List
import IHP.Prelude
import Test.Hspec

tests :: Spec
tests = describe "FrontendSurface GHC raw lowering" do
    it "lowers deterministic normalized raw lab surfaces to the checked contract IR" do
        lowerRawRegistry labRawRegistry `shouldBe` Right registeredFrontendSurfaceContractIR

    it "reports unsupported normalized primitive nodes before generation" do
        lowerRawRegistry (registryWithPrimitives [scopePrimitive, raw "UnsupportedPrimitive" []])
            `shouldSatisfy` leftContains "unsupported primitive UnsupportedPrimitive"

    it "reports stable diagnostics for malformed raw normalized trees" do
        let cases =
                [ ( registryWithPrimitives [scopePrimitive, unsupportedFamily "Concat '[Broken]"]
                  , "unsupported type family in surface primitive: Concat '[Broken]"
                  )
                , ( registryWithPrimitives [raw "Scope" [marker "LabScope", raw "NotAList" []]]
                  , "expected field list as normalized PromotedList, got NotAList"
                  )
                , ( registryWithPrimitives [raw "Scope" [marker "LabScope", promotedList [fieldWithWire "VenueId" (raw "WireMagic" [])]]]
                  , "unsupported wire type WireMagic"
                  )
                , ( registryWithPrimitives [scopePrimitive, raw "Fragment" [marker "LabPanel", promotedList [], promotedList [raw "MagicOption" []]]]
                  , "unsupported option MagicOption"
                  )
                ]
        forM_ cases \(rawRegistry, expected) ->
            lowerRawRegistry rawRegistry `shouldSatisfy` leftContains expected

    it "runs existing ContractIR validation after raw lowering" do
        lowerRawRegistry (registryWithPrimitives
            [ scopePrimitive
            , raw "Dto" [marker "BadDto", promotedList [fieldWithWire "MissingPayload" (raw "WireRef" [marker "MissingPayload"])] ]
            ])
            `shouldSatisfy` leftContains "field missingPayload references missing dto missing-payload on surface surface-lab"

    it "reports duplicate declarations and invalid reference kinds after GHC lowering" do
        let cases =
                [ ( registryWithPrimitives [scopePrimitive, raw "Fragment" [marker "LabPanel", promotedList [], promotedList []], raw "Fragment" [marker "LabPanel", promotedList [], promotedList []]]
                  , "surface surface-lab has duplicate fragment lab-panel"
                  )
                , ( duplicateSurfaceRegistry
                  , "duplicate surface name surface-lab"
                  )
                , ( registryWithPrimitives [scopePrimitive, raw "Fragment" [marker "LabPanel", promotedList [], promotedList []], raw "HtmxAction" [marker "RefreshPanel", promotedList [], promotedList [raw "Target" [marker "RefreshPanel"]]]]
                  , "htmx action refresh-panel references missing fragment refresh-panel on surface surface-lab"
                  )
                , ( registryWithPrimitives [scopePrimitive, raw "Fragment" [marker "LabPanel", promotedList [], promotedList []], raw "Intent" [marker "MoveLabCard", promotedList [], promotedList [raw "BackedBy" [marker "LabPanel"]]]]
                  , "intent move-lab-card references missing htmx action lab-panel on surface surface-lab"
                  )
                , ( registryWithPrimitives [scopePrimitive, raw "InteractionEffect" [marker "CloneShadow", promotedList [raw "Layer" [marker "MissingLayer"]]]]
                  , "effect clone-shadow references missing layer missing on surface surface-lab"
                  )
                , ( registryWithPrimitives [scopePrimitive, raw "ConflictPolicy" [raw "SessionKind" [marker "DragSession"], raw "AnyFragment" [], raw "Defer" []]]
                  , "conflict policy references missing session drag on surface surface-lab"
                  )
                , ( registryWithPrimitives [scopePrimitive, raw "ClientEvent" [marker "LabCommitted", promotedList [fieldWithWire "Payload" (raw "WireRef" [marker "MissingPayload"])] ]]
                  , "field payload references missing dto missing-payload on surface surface-lab"
                  )
                ]
        forM_ cases \(rawRegistry, expected) ->
            lowerRawRegistry rawRegistry `shouldSatisfy` leftContains expected

labRawRegistry :: RawRegistry
labRawRegistry = registryWithPrimitives
    [ scopePrimitive
    , raw "MountState"
        [ marker "LabViewState"
        , promotedList
            [ field "ShowArchived" "WireBool"
            , optionalField "StaffFilterId" "WireUUID"
            ]
        ]
    , raw "Fragment" [marker "LabShell", promotedList [], promotedList [raw "Eager" []]]
    , raw "Fragment"
        [ marker "LabPanel"
        , promotedList [field "PanelId" "WireUUID"]
        , promotedList [raw "Lazy" [promotedList [raw "Trigger" [marker "Load"], raw "Placeholder" [marker "Panel"]]]]
        ]
    , raw "HtmxAction"
        [ marker "RefreshPanel"
        , promotedList [field "PanelId" "WireUUID"]
        , promotedList [raw "Target" [marker "LabPanel"]]
        ]
    , raw "Intent"
        [ marker "MoveLabCard"
        , promotedList [field "SourceItemKey" "WireText", field "TargetDropzoneKey" "WireText"]
        , promotedList [raw "BackedBy" [marker "RefreshPanel"]]
        ]
    , raw "Session" [marker "DragSession", promotedList []]
    , raw "DisposableLayer" [marker "DragPreview"]
    , raw "InteractionEffect" [marker "CloneShadow", promotedList [raw "Layer" [marker "DragPreview"]]]
    , raw "InteractionEffect" [marker "DropzoneHighlight", promotedList []]
    , raw "ConflictPolicy" [raw "SessionKind" [marker "DragSession"], raw "FragmentKind" [marker "LabPanel"], raw "Defer" []]
    , raw "LoadPolicy" [marker "Panel"]
    , raw "OverlayLane" [marker "Dialog"]
    , raw "ClientEvent" [marker "LabCommitted", promotedList [field "PanelId" "WireUUID"]]
    , raw "DomToken" [marker "LabRoot"]
    , raw "DomToken" [marker "LabDropzone"]
    , raw "Dto"
        [ marker "LabPayload"
        , promotedList
            [ field "Label" "WireText"
            , optionalField "Count" "WireInt"
            , nullableField "Note" "WireText"
            , fieldWithWire "Tags" (raw "WireList" [raw "WireText" []])
            , field "DueDay" "WireDay"
            , fieldWithWire "MaybeRank" (raw "WireOptional" [raw "WireInt" []])
            , fieldWithWire "MaybeMemo" (raw "WireNullable" [raw "WireText" []])
            , fieldWithWire "RelatedPayload" (raw "WireRef" [marker "LabRelatedPayload"])
            ]
        ]
    , raw "Dto" [marker "LabRelatedPayload", promotedList [field "Label" "WireText"]]
    ]

registryWithPrimitives :: [RawType] -> RawRegistry
registryWithPrimitives primitives =
    registryWithSurfaces [rawSurfaceWithPrimitives "SurfaceLabSurface" "SurfaceLab" primitives]

duplicateSurfaceRegistry :: RawRegistry
duplicateSurfaceRegistry =
    registryWithSurfaces
        [ rawSurfaceWithPrimitives "SurfaceLabSurface" "SurfaceLab" [scopePrimitive]
        , rawSurfaceWithPrimitives "SurfaceLabSurfaceCopy" "SurfaceLab" [scopePrimitive]
        ]

registryWithSurfaces :: [RawSurface] -> RawRegistry
registryWithSurfaces surfaces =
    RawRegistry
        { rawRegistryModule = "Test.FrontendSurfaceGhcSpec"
        , rawRegistryExport = "RegisteredFrontendSurfaces"
        , rawRegistrySource = "test"
        , rawRegistryKind = "[SurfaceSpec]"
        , rawRegistryRhs = promotedList (map rawSurfaceReference surfaces)
        , rawRegistrySurfaces = surfaces
        }

rawSurfaceWithPrimitives :: String -> String -> [RawType] -> RawSurface
rawSurfaceWithPrimitives surfaceName markerName primitives =
    let normalizedSurface = raw "Surface" [marker markerName, promotedList primitives]
     in RawSurface
            { rawSurfaceName = surfaceName
            , rawSurfaceSource = "test"
            , rawSurfaceReference = marker surfaceName
            , rawSurfaceExpanded = normalizedSurface
            , rawSurfaceNormalized = normalizedSurface
            }

scopePrimitive :: RawType
scopePrimitive = raw "Scope"
    [ marker "LabScope"
    , promotedList [field "VenueId" "WireUUID", field "WeekOffset" "WireInt"]
    ]

field :: String -> String -> RawType
field name wire = fieldWithWire name (raw wire [])

optionalField :: String -> String -> RawType
optionalField name wire = raw "OptionalField" [marker name, raw wire []]

nullableField :: String -> String -> RawType
nullableField name wire = raw "NullableField" [marker name, raw wire []]

fieldWithWire :: String -> RawType -> RawType
fieldWithWire name wire = raw "Field" [marker name, wire]

marker :: String -> RawType
marker name = raw name []

promotedList :: [RawType] -> RawType
promotedList elements = RawType
    { rawTypeNode = "PromotedList"
    , rawTypePretty = "'[]"
    , rawTypeName = Just "[]"
    , rawTypeSource = Nothing
    , rawTypeArgs = elements
    }

raw :: String -> [RawType] -> RawType
raw name args = RawType
    { rawTypeNode = "TyConApp"
    , rawTypePretty = name
    , rawTypeName = Just name
    , rawTypeSource = Nothing
    , rawTypeArgs = args
    }

unsupportedFamily :: String -> RawType
unsupportedFamily pretty = RawType
    { rawTypeNode = "UnsupportedTypeFamily"
    , rawTypePretty = pretty
    , rawTypeName = Just "UnsupportedTypeFamily"
    , rawTypeSource = Nothing
    , rawTypeArgs = []
    }

leftContains :: String -> Either [String] a -> Bool
leftContains expected = \case
    Left diagnostics -> any (expected `List.isInfixOf`) diagnostics
    Right _ -> False
