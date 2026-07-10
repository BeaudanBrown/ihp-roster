module Test.FrontendSurfaceGhcSpec
    ( tests
    ) where

import Application.Helper.FrontendContract.Registry (registeredFrontendContractIRForSurfaceContract)
import Application.Helper.FrontendContract.Surface.ContractIR (FragmentIR (..),
                                                               OptionIR (..),
                                                               SurfaceContractIR (..),
                                                               SurfaceIR (..))
import Application.Helper.FrontendContract.Surface.Contracts (registeredFrontendSurfaceContractIR)
import Application.Helper.FrontendContract.Surface.Ghc.Lower
import Application.Helper.FrontendContract.Surface.Ghc.Raw
import Application.Helper.FrontendContract.TypeScript (renderFrontendContractTypeScript)
import qualified Data.List as List
import qualified Data.Text as Text
import IHP.Prelude
import Test.Hspec

tests :: Spec
tests = describe "FrontendSurface GHC raw lowering" do
    it "lowers deterministic normalized raw lab surfaces to the checked contract IR" do
        lowerRawRegistry labRawRegistry `shouldBe` Right (expectedRegisteredSurface "surface-lab")

    it "lowers deterministic normalized raw timesheets surfaces to the checked contract IR" do
        lowerRawRegistry timesheetsRawRegistry `shouldBe` Right (expectedRegisteredSurface "timesheets")

    it "lowers deterministic normalized raw roster surfaces to the checked contract IR" do
        lowerRawRegistry rosterRawRegistry `shouldBe` Right (expectedRegisteredSurface "roster")

    it "reports unsupported normalized primitive nodes before generation" do
        lowerRawRegistry (registryWithPrimitives [scopePrimitive, raw "UnsupportedPrimitive" []])
            `shouldSatisfy` leftContains "unsupported primitive UnsupportedPrimitive"

    it "reports stable diagnostics for malformed raw normalized trees" do
        let cases =
                [ ( registryWithPrimitives [scopePrimitive, unsupportedFamily "Concat '[Broken]"]
                  , "unsupported type family in surface primitive: Concat '[Broken]"
                  )
                , ( registryWithPrimitives [raw "Scope" [marker "LabScope", raw "NotAList" [], promotedList [raw "NoAuth" []]]]
                  , "expected field list as normalized PromotedList, got NotAList"
                  )
                , ( registryWithPrimitives [raw "Scope" [marker "LabScope", promotedList [fieldWithWire "VenueId" (raw "WireMagic" [])], promotedList [raw "NoAuth" []]]]
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

    it "lowers contained child surface topology from fragment options" do
        let result = lowerRawRegistry (registryWithSurfaces
                [ rawSurfaceWithPrimitives "ParentSurface" "Parent"
                    [ scopePrimitive
                    , raw "Fragment" [marker "ParentContent", promotedList [], promotedList [raw "ContainsSurface" [marker "Child"]]]
                    ]
                , rawSurfaceWithPrimitives "ChildSurface" "Child" [scopePrimitive]
                ])
        fmap (map (.surfaceFragments) . (.contractSurfaces)) result
            `shouldBe` Right
                [ [FragmentIR
                    { fragmentMarker = "ParentContent"
                    , fragmentName = "parent-content"
                    , fragmentParams = []
                    , fragmentOptions = [ContainsSurfaceOption "child"]
                    }]
                , []
                ]

    it "renders generated TypeScript topology for contained child surfaces" do
        let rawRegistry = registryWithSurfaces
                [ rawSurfaceWithPrimitives "ParentSurface" "Parent"
                    [ scopePrimitive
                    , raw "Fragment" [marker "ParentContent", promotedList [], promotedList [raw "ContainsSurface" [marker "Child"]]]
                    ]
                , rawSurfaceWithPrimitives "ChildSurface" "Child" [scopePrimitive]
                ]
        case lowerRawRegistry rawRegistry of
            Left diagnostics -> expectationFailure ("expected valid registry: " ++ cs (show diagnostics :: Text))
            Right contract -> do
                let rendered = either error id (renderFrontendContractTypeScript (registeredFrontendContractIRForSurfaceContract contract))
                rendered `shouldContainText` "\"containedSurfaces\":{\"parent-content\":[\"child\"]}"
                rendered `shouldContainText` "export type FrontendSurfaceContainmentEdge"
                rendered `shouldContainText` "export const FrontendSurfaceContainmentTopology = ["
                rendered `shouldContainText` "{ parentSurface: \"parent\", parentFragment: \"parent-content\", childSurface: \"child\" }"
                rendered `shouldContainText` "export function isFrontendSurfaceContainmentEdge"

    it "reports invalid and cyclic contained child surface references after GHC lowering" do
        let cases =
                [ ( registryWithPrimitives
                        [ scopePrimitive
                        , raw "Fragment" [marker "LabPanel", promotedList [], promotedList [raw "ContainsSurface" [marker "MissingSurface"]]]
                        ]
                  , "surface surface-lab fragment lab-panel contains missing surface missing"
                  )
                , ( registryWithSurfaces
                        [ rawSurfaceWithPrimitives "ParentSurface" "Parent"
                            [ scopePrimitive
                            , raw "Fragment" [marker "ParentContent", promotedList [], promotedList [raw "ContainsSurface" [marker "Child"]]]
                            ]
                        , rawSurfaceWithPrimitives "ChildSurface" "Child"
                            [ scopePrimitive
                            , raw "Fragment" [marker "ChildContent", promotedList [], promotedList [raw "ContainsSurface" [marker "Parent"]]]
                            ]
                        ]
                  , "surface containment cycle includes parent"
                  )
                ]
        forM_ cases \(rawRegistry, expected) ->
            lowerRawRegistry rawRegistry `shouldSatisfy` leftContains expected

    it "reports duplicate declarations and invalid reference kinds after GHC lowering" do
        let cases =
                [ ( registryWithPrimitives [scopePrimitive, raw "Fragment" [marker "LabPanel", promotedList [], promotedList []], raw "Fragment" [marker "LabPanel", promotedList [], promotedList []]]
                  , "surface surface-lab has duplicate fragment lab-panel"
                  )
                , ( duplicateSurfaceRegistry
                  , "duplicate surface name surface-lab"
                  )
                , ( registryWithPrimitives [scopePrimitive, raw "Fragment" [marker "LabPanel", promotedList [], promotedList []], raw "Action" [marker "RefreshPanel", promotedList [], promotedList [raw "Target" [marker "RefreshPanel"]]]]
                  , "htmx action refresh-panel references missing fragment refresh-panel on surface surface-lab"
                  )
                , ( registryWithPrimitives [scopePrimitive, raw "Fragment" [marker "LabPanel", promotedList [], promotedList []], raw "Intent" [marker "MoveLabCard", promotedList [], promotedList [raw "BackedBy" [marker "LabPanel"]]]]
                  , "intent move-lab-card references missing htmx action lab-panel on surface surface-lab"
                  )
                , ( registryWithPrimitives [scopePrimitive, raw "Session" [marker "DragSession", promotedList [raw "Effect" [marker "CloneShadow", promotedList [raw "Target" [marker "MissingFragment"]]]]]]
                  , "effect clone-shadow references missing fragment missing on surface surface-lab"
                  )
                , ( registryWithPrimitives [scopePrimitive, raw "ConflictPolicy" [raw "SessionKind" [marker "DragSession"], raw "AnyFragment" [], raw "Defer" []]]
                  , "conflict policy references missing session drag on surface surface-lab"
                  )
                , ( registryWithPrimitives [scopePrimitive, raw "Event" [marker "LabCommitted", promotedList [fieldWithWire "Payload" (raw "WireRef" [marker "MissingPayload"])] ]]
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
    , raw "Action"
        [ marker "RefreshPanel"
        , promotedList [field "PanelId" "WireUUID"]
        , promotedList
            [ raw "Target" [marker "LabPanel"]
            , raw "HtmxMethod" [raw "HtmxPost" []]
            , raw "HtmxTarget" [marker "LabPanelTarget"]
            , raw "HtmxSwap" [marker "OuterHtml"]
            , raw "HtmxInclude" [marker "LabPanelInclude"]
            , raw "HtmxPushUrl" [raw "HtmxPushUrlFalse" []]
            , raw "CustomHtmx" [marker "LabPanelCustomHtmx", symbol "lab fixture covers auditable custom HTMX metadata"]
            ]
        ]
    , raw "Intent"
        [ marker "MoveLabCard"
        , promotedList [field "SourceItemKey" "WireText", field "TargetDropzoneKey" "WireText"]
        , promotedList [raw "BackedBy" [marker "RefreshPanel"]]
        ]
    , raw "Session" [marker "DragSession", promotedList [raw "Layer" [marker "DragPreview"], raw "Effect" [marker "CloneShadow", promotedList [raw "Layer" [marker "DragPreview"]]], raw "Effect" [marker "DropzoneHighlight", promotedList []]]]
    , raw "ConflictPolicy" [raw "SessionKind" [marker "DragSession"], raw "FragmentKind" [marker "LabPanel"], raw "Defer" []]
    , raw "Event" [marker "LabCommitted", promotedList [field "PanelId" "WireUUID"]]
    , raw "DomToken" [marker "LabRoot"]
    , raw "DomToken" [marker "LabDropzone"]
    , raw "DomToken" [marker "LabPanelTarget"]
    , raw "DomToken" [marker "LabPanelInclude"]
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

timesheetsRawRegistry :: RawRegistry
timesheetsRawRegistry =
    registryWithSurfaces
        [ rawSurfaceWithPrimitives "TimesheetsSurface" "Timesheets"
            [ raw "Scope"
                [ marker "TimesheetWeek"
                , promotedList [field "VenueId" "WireUUID", field "WeekOffset" "WireInt"]
                , promotedList [raw "Authorize" [raw "CurrentVenue" [], promotedList [marker "VenueId"]]]
                ]
            , raw "MountState"
                [ marker "TimesheetsMountState"
                , promotedList
                    [ field "ShowApproved" "WireBool"
                    , field "ShowAllStaff" "WireBool"
                    , fieldWithWire "StaffFilterId" (raw "WireOptional" [raw "WireUUID" []])
                    ]
                ]
            , raw "Fragment" [marker "TimesheetToolbar", promotedList [], promotedList ([raw "Eager" [], raw "Live" []] <> timesheetWeekDependencyOptions)]
            , raw "Fragment" [marker "TimesheetDayColumns", promotedList [], promotedList ([raw "Eager" [], raw "Live" []] <> timesheetWeekDependencyOptions)]
            , raw "Fragment"
                [ marker "TimesheetDaySection"
                , promotedList [field "DayOffset" "WireInt"]
                , promotedList
                    [ raw "Lazy" [promotedList [raw "DependsOnFragment" [marker "TimesheetDayColumns"]]]
                    , raw "Live" []
                    , dependsOn "TimesheetDay" [field "VenueId" "WireUUID", field "WeekOffset" "WireInt", field "DayOffset" "WireInt"] [fromScope "VenueId", fromScope "WeekOffset", fromFragment "DayOffset"]
                    , dependsOn "TimesheetWeekBoundaryConfig" [field "VenueId" "WireUUID"] [fromScope "VenueId"]
                    , dependsOn "TimePickerConfig" [field "VenueId" "WireUUID"] [fromScope "VenueId"]
                    ]
                ]
            , raw "Action" [marker "NavigateTimesheetWeek", promotedList timesheetActionFieldsRaw, promotedList (timesheetGetOptions "week navigation serializes through the timesheet week shell with hx-sync=closest shell:replace")]
            , raw "Action" [marker "UpdateTimesheetFilters", promotedList timesheetActionFieldsRaw, promotedList (timesheetGetOptions "filter changes serialize through the timesheet week shell with hx-sync=closest shell:replace")]
            , raw "Action" [marker "ApproveTimesheetEntry", promotedList timesheetActionFieldsRaw, promotedList timesheetPostOptions]
            , raw "Action" [marker "UnapproveTimesheetEntry", promotedList timesheetActionFieldsRaw, promotedList timesheetPostOptions]
            ]
        ]

rosterRawRegistry :: RawRegistry
rosterRawRegistry =
    registryWithSurfaces
        [ rawSurfaceWithPrimitives "RosterSurface" "Roster"
            [ raw "Scope"
                [ marker "RosterWeek"
                , promotedList [field "VenueId" "WireUUID", field "RosterGroupId" "WireUUID", field "WeekOffset" "WireInt"]
                , promotedList [raw "Authorize" [raw "CurrentVenueRosterGroup" [], promotedList [marker "VenueId", marker "RosterGroupId"]]]
                ]
            , raw "Fragment" [marker "RosterContent", promotedList [], promotedList ([raw "Eager" [], raw "Live" []] <> rosterWeekDependencyOptions <> [raw "Contains" [marker "RosterGridToolbar"], raw "Contains" [marker "RosterGridFrame"]])]
            , raw "Fragment" [marker "RosterGridToolbar", promotedList [], promotedList ([raw "Eager" [], raw "Live" []] <> rosterWeekDependencyOptions)]
            , raw "Fragment"
                [ marker "RosterGridFrame"
                , promotedList []
                , promotedList
                    ( [ raw "Eager" [], raw "Live" [] ]
                        <> rosterWeekDependencyOptions
                        <> [ raw "Contains" [marker "RosterDayColumns"]
                           , raw "Contains" [marker "RosterDayRail"]
                           , raw "Contains" [marker "RosterWageRail"]
                           , raw "Contains" [marker "RosterSlotsGrid"]
                           , raw "Contains" [marker "RosterDaySection"]
                           ]
                    )
                ]
            , raw "Fragment" [marker "RosterDayColumns", promotedList [], promotedList ([raw "Eager" [], raw "Live" []] <> rosterWeekDependencyOptions)]
            , raw "Fragment" [marker "RosterDayRail", promotedList [], promotedList ([raw "Eager" [], raw "Live" []] <> rosterWeekDependencyOptions)]
            , raw "Fragment" [marker "RosterWageRail", promotedList [], promotedList ([raw "Eager" [], raw "Live" []] <> rosterWeekDependencyOptions)]
            , raw "Fragment" [marker "RosterSlotsGrid", promotedList [], promotedList ([raw "Eager" [], raw "Live" []] <> rosterWeekDependencyOptions)]
            , raw "Fragment" [marker "RosterStaffPanel", promotedList [], promotedList [raw "Lazy" [promotedList [raw "DependsOnFragment" [marker "RosterContent"]]], raw "Live" [], rosterWeekResourceDependency]]
            , raw "Fragment" [marker "RosterStaffSelfServiceLeaveFormFragment", promotedList [], promotedList [raw "Eager" [], raw "Live" [], raw "ResyncOnly" []]]
            , raw "Fragment" [marker "RosterWeekOverview", promotedList [], promotedList [raw "Lazy" [promotedList [raw "DependsOnFragment" [marker "RosterContent"]]], rosterWeekResourceDependency]]
            , raw "Fragment"
                [ marker "RosterDaySection"
                , promotedList [field "RosterDayId" "WireUUID"]
                , promotedList ([raw "Lazy" [promotedList [raw "DependsOnFragment" [marker "RosterGridFrame"], raw "Contains" [marker "RosterRow"]]], raw "Live" []] <> rosterDayDependencyOptions)
                ]
            , raw "Fragment"
                [ marker "RosterRow"
                , promotedList [field "RosterDayId" "WireUUID", field "RowIndex" "WireInt"]
                , promotedList ([raw "Lazy" [promotedList [raw "DependsOnFragment" [marker "RosterDaySection"]]], raw "Live" []] <> rosterDayDependencyOptions)
                ]
            , raw "Action" [marker "NavigateRosterWeek", promotedList [field "WeekOffset" "WireInt", field "RosterGroupId" "WireUUID"], promotedList [raw "HtmxMethod" [raw "HtmxGet" []], raw "HtmxTarget" [marker "RosterWeekShell"], raw "HtmxPushUrl" [raw "HtmxPushUrlTrue" []], rosterShellSyncCustomHtmx "roster week navigation serializes through the stable roster week shell"]]
            , raw "Action" [marker "ToggleRosterWarnings", promotedList [field "ShowRosterWarnings" "WireBool"], promotedList (rosterPostNoneOptions "preference toggles serialize through the stable roster week shell")]
            , raw "Action" [marker "ToggleRosterWageEstimates", promotedList [field "ShowWageEstimates" "WireBool"], promotedList (rosterPostNoneOptions "preference toggles serialize through the stable roster week shell")]
            , raw "Action" [marker "SortRosterWeek", promotedList [], promotedList (rosterPostTargetNoneOptions "RosterContent" "sort mutations serialize through the stable roster week shell")]
            , raw "Action" [marker "ToggleRosterWeekLiveStatus", promotedList [field "IsLive" "WireBool"], promotedList [raw "HtmxMethod" [raw "HtmxPost" []], raw "HtmxTarget" [marker "RosterContent"], raw "HtmxSwap" [marker "OuterHTML"], raw "HtmxPushUrl" [raw "HtmxPushUrlFalse" []], rosterShellSyncCustomHtmx "live toggle serializes through the stable roster week shell"]]
            , raw "Action" [marker "ToggleRosterAssignmentFilters", promotedList [field "HideStaffAtIdealShifts" "WireBool", field "HideStaffUnavailable" "WireBool", field "HideStaffOnApprovedLeave" "WireBool", field "HideStaffAlreadyAssignedToday" "WireBool"], promotedList (rosterPostNoneOptions "assignment filter toggles serialize through the stable roster week shell")]
            , raw "Action" [marker "CopyRosterWeek", promotedList [], promotedList (rosterPostTargetOuterHtmlOptions "RosterContent" "copy mutations serialize through the stable roster week shell" <> [raw "CustomHtmx" [marker "CopyRosterWeekCustomHtmx", symbol "copy previous week requires a destructive overwrite confirmation"]])]
            , raw "Action" [marker "CreateRosterSelfServiceLeaveRequest", promotedList [field "StartDate" "WireDay", field "EndDate" "WireDay", field "Reason" "WireText"], promotedList [raw "HtmxMethod" [raw "HtmxPost" []], raw "HtmxTarget" [marker "RosterStaffSelfServiceLeaveFormFragment"], raw "HtmxSwap" [marker "OuterHTML"], raw "HtmxPushUrl" [raw "HtmxPushUrlFalse" []]]]
            , raw "Action" [marker "CreateRosterWeekSlotDefinition", promotedList [], promotedList (rosterPostTargetNoneOptions "RosterContent" "slot-definition mutations serialize through the stable roster week shell")]
            , raw "Action" [marker "DeleteRosterWeekSlotDefinition", promotedList [], promotedList [raw "HtmxMethod" [raw "HtmxDelete" []], raw "HtmxTarget" [marker "RosterContent"], raw "HtmxSwap" [marker "None"], raw "HtmxPushUrl" [raw "HtmxPushUrlFalse" []], rosterShellSyncCustomHtmx "slot-definition mutations serialize through the stable roster week shell"]]
            , raw "Action" [marker "ToggleRosterDayClosed", promotedList [], promotedList (rosterPostNoneOptions "day row mutations serialize through the stable roster week shell")]
            , raw "Action" [marker "AddRosterRow", promotedList [], promotedList (rosterPostNoneOptions "day row mutations serialize through the stable roster week shell")]
            , raw "Action" [marker "RemoveRosterRow", promotedList [], promotedList (rosterPostNoneOptions "day row mutations serialize through the stable roster week shell")]
            , raw "Action" [marker "ToggleRosterStaffScope", promotedList [field "StaffScope" "WireText"], promotedList [raw "HtmxMethod" [raw "HtmxGet" []], raw "HtmxTarget" [marker "RosterStaffPanel"], raw "HtmxSwap" [marker "OuterHTML"], raw "HtmxPushUrl" [raw "HtmxPushUrlFalse" []]]]
            , raw "ActivationRef" [marker "RosterLayoutModeActivationRef", promotedList [raw "Submits" [marker "SetRosterLayoutMode"], raw "ValueField" [marker "RosterLayoutMode"]]]
            , raw "Action" [marker "SetRosterLayoutMode", promotedList [field "RosterLayoutMode" "WireText"], promotedList [raw "Target" [marker "RosterContent"]]]
            , raw "Intent" [marker "SetRosterLayoutMode", promotedList [field "RosterLayoutMode" "WireText"], promotedList [raw "BackedBy" [marker "SetRosterLayoutMode"]]]
            , raw "Session" [marker "DragSession", promotedList [raw "Layer" [marker "DragPreviewLayer"], raw "Effect" [marker "CloneShadow", promotedList [raw "Layer" [marker "DragPreviewLayer"]]], raw "Effect" [marker "DropzoneHighlight", promotedList []]]]
            , raw "SourceRef" [marker "ShiftDragSource", promotedList [raw "SessionOption" [marker "DragSession"], raw "Submits" [marker "MoveRosterShiftToSlot"], raw "SourceField" [marker "SourceItemKey"], raw "CompatibleDropzone" [marker "ShiftSlotDropzone"], raw "CompatibleDropzone" [marker "DayColumnDropzone"], raw "CompatibleDropzone" [marker "DeleteShiftDropzone"], raw "ModifierVariant" [marker "Copy", marker "DuplicateRosterShiftToDay", promotedList [raw "Effect" [marker "CloneShadowCopy", promotedList [raw "Layer" [marker "DragPreviewLayer"]]], raw "Effect" [marker "DropzoneHighlight", promotedList []]]]]]
            , raw "SourceRef" [marker "StaffDragSource", promotedList [raw "SessionOption" [marker "DragSession"], raw "Submits" [marker "DropRosterStaff"], raw "SourceField" [marker "SourceItemKey"], raw "CompatibleDropzone" [marker "ExistingShiftDropzone"], raw "CompatibleDropzone" [marker "StaffCreateDropzone"]]]
            , raw "DropzoneRef" [marker "ShiftSlotDropzone", promotedList [raw "SessionOption" [marker "DragSession"], raw "TargetField" [marker "TargetDropzoneKey"]]]
            , raw "DropzoneRef" [marker "StaffCreateDropzone", promotedList [raw "SessionOption" [marker "DragSession"], raw "TargetField" [marker "TargetDropzoneKey"]]]
            , raw "DropzoneRef" [marker "DayColumnDropzone", promotedList [raw "SessionOption" [marker "DragSession"], raw "TargetField" [marker "TargetDropzoneKey"]]]
            , raw "DropzoneRef" [marker "ExistingShiftDropzone", promotedList [raw "SessionOption" [marker "DragSession"], raw "TargetField" [marker "TargetDropzoneKey"]]]
            , raw "DropzoneRef" [marker "DeleteShiftDropzone", promotedList [raw "SessionOption" [marker "DragSession"], raw "TargetField" [marker "TargetDropzoneKey"]]]
            , raw "Action" [marker "MoveRosterShiftToSlot", promotedList dragDropFieldsRaw, promotedList [raw "Target" [marker "RosterContent"]]]
            , raw "Intent" [marker "MoveRosterShiftToSlot", promotedList dragDropFieldsRaw, promotedList [raw "SessionOption" [marker "DragSession"], raw "BackedBy" [marker "MoveRosterShiftToSlot"]]]
            , raw "Action" [marker "DuplicateRosterShiftToDay", promotedList dragDropFieldsRaw, promotedList [raw "Target" [marker "RosterContent"]]]
            , raw "Intent" [marker "DuplicateRosterShiftToDay", promotedList dragDropFieldsRaw, promotedList [raw "SessionOption" [marker "DragSession"], raw "BackedBy" [marker "DuplicateRosterShiftToDay"]]]
            , raw "Action" [marker "DropRosterStaff", promotedList dragDropFieldsRaw, promotedList [raw "Target" [marker "RosterContent"]]]
            , raw "Intent" [marker "DropRosterStaff", promotedList dragDropFieldsRaw, promotedList [raw "SessionOption" [marker "DragSession"], raw "BackedBy" [marker "DropRosterStaff"]]]
            , raw "DomToken" [marker "RosterContent"]
            , raw "DomToken" [marker "RosterWeekShell"]
            , raw "DomToken" [marker "RosterDaySection"]
            , raw "DomToken" [marker "RosterStaffPanel"]
            , raw "DomToken" [marker "RosterStaffSelfServiceLeaveFormFragment"]
            ]
        ]

timesheetActionFieldsRaw :: [RawType]
timesheetActionFieldsRaw =
    [ field "WeekOffset" "WireInt"
    , field "ShowApproved" "WireBool"
    , field "ShowAllStaff" "WireBool"
    , optionalField "StaffFilterId" "WireUUID"
    ]

timesheetGetOptions :: String -> [RawType]
timesheetGetOptions reason =
    [ raw "HtmxMethod" [raw "HtmxGet" []]
    , raw "HtmxSwap" [marker "None"]
    , raw "HtmxPushUrl" [raw "HtmxPushUrlTrue" []]
    , raw "CustomHtmx" [marker "TimesheetWeekShellSyncCustomHtmx", symbol reason]
    ]

timesheetPostOptions :: [RawType]
timesheetPostOptions =
    [ raw "HtmxMethod" [raw "HtmxPost" []]
    , raw "HtmxSwap" [marker "None"]
    , raw "HtmxPushUrl" [raw "HtmxPushUrlFalse" []]
    ]

rosterShellSyncCustomHtmx :: String -> RawType
rosterShellSyncCustomHtmx reason =
    raw "CustomHtmx" [marker "RosterWeekShellSyncCustomHtmx", symbol reason]

rosterPostNoneOptions :: String -> [RawType]
rosterPostNoneOptions reason =
    [ raw "HtmxMethod" [raw "HtmxPost" []]
    , raw "HtmxSwap" [marker "None"]
    , raw "HtmxPushUrl" [raw "HtmxPushUrlFalse" []]
    , rosterShellSyncCustomHtmx reason
    ]

rosterPostTargetNoneOptions :: String -> String -> [RawType]
rosterPostTargetNoneOptions target reason =
    [ raw "HtmxMethod" [raw "HtmxPost" []]
    , raw "HtmxTarget" [marker target]
    , raw "HtmxSwap" [marker "None"]
    , raw "HtmxPushUrl" [raw "HtmxPushUrlFalse" []]
    , rosterShellSyncCustomHtmx reason
    ]

rosterPostTargetOuterHtmlOptions :: String -> String -> [RawType]
rosterPostTargetOuterHtmlOptions target reason =
    [ raw "HtmxMethod" [raw "HtmxPost" []]
    , raw "HtmxTarget" [marker target]
    , raw "HtmxSwap" [marker "OuterHTML"]
    , raw "HtmxPushUrl" [raw "HtmxPushUrlFalse" []]
    , rosterShellSyncCustomHtmx reason
    ]

timesheetWeekDependencyOptions :: [RawType]
timesheetWeekDependencyOptions =
    [ dependsOn "TimesheetWeek" [field "VenueId" "WireUUID", field "WeekOffset" "WireInt"] [fromScope "VenueId", fromScope "WeekOffset"]
    , dependsOn "TimesheetWeekBoundaryConfig" [field "VenueId" "WireUUID"] [fromScope "VenueId"]
    , dependsOn "TimePickerConfig" [field "VenueId" "WireUUID"] [fromScope "VenueId"]
    ]

rosterWeekResourceDependency :: RawType
rosterWeekResourceDependency =
    dependsOn "RosterWeek" [field "RosterGroupId" "WireUUID", field "WeekOffset" "WireInt"] [fromScope "RosterGroupId", fromScope "WeekOffset"]

rosterWeekDependencyOptions :: [RawType]
rosterWeekDependencyOptions =
    [ rosterWeekResourceDependency
    , dependsOn "RosterEndTimesConfig" [field "VenueId" "WireUUID"] [fromScope "VenueId"]
    , dependsOn "RosterWeekBoundaryConfig" [field "VenueId" "WireUUID"] [fromScope "VenueId"]
    ]

rosterDayDependencyOptions :: [RawType]
rosterDayDependencyOptions =
    [ dependsOn "RosterDay" [field "RosterDayId" "WireUUID"] [fromFragment "RosterDayId"]
    , dependsOn "RosterEndTimesConfig" [field "VenueId" "WireUUID"] [fromScope "VenueId"]
    , dependsOn "RosterWeekBoundaryConfig" [field "VenueId" "WireUUID"] [fromScope "VenueId"]
    ]

dragDropFieldsRaw :: [RawType]
dragDropFieldsRaw =
    [ field "SourceItemKey" "WireText"
    , field "TargetDropzoneKey" "WireText"
    , optionalField "SessionKind" "WireText"
    , optionalField "PointerId" "WireText"
    , optionalField "PointerType" "WireText"
    , optionalField "StartClientX" "WireText"
    , optionalField "StartClientY" "WireText"
    , optionalField "CurrentClientX" "WireText"
    , optionalField "CurrentClientY" "WireText"
    , optionalField "DeltaX" "WireText"
    , optionalField "DeltaY" "WireText"
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
    , promotedList [raw "NoAuth" []]
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

symbol :: String -> RawType
symbol value = RawType
    { rawTypeNode = "LitTy"
    , rawTypePretty = "\"" <> value <> "\""
    , rawTypeName = Just value
    , rawTypeSource = Nothing
    , rawTypeArgs = []
    }

dependsOn :: String -> [RawType] -> [RawType] -> RawType
dependsOn resourceName resourceFields sources =
    raw "DependsOn" [raw "Resource" [marker resourceName, promotedList resourceFields], promotedList sources]

fromScope :: String -> RawType
fromScope name = raw "FromScope" [marker name]

fromFragment :: String -> RawType
fromFragment name = raw "FromFragment" [marker name]

unsupportedFamily :: String -> RawType
unsupportedFamily pretty = RawType
    { rawTypeNode = "UnsupportedTypeFamily"
    , rawTypePretty = pretty
    , rawTypeName = Just "UnsupportedTypeFamily"
    , rawTypeSource = Nothing
    , rawTypeArgs = []
    }

expectedRegisteredSurface :: Text -> SurfaceContractIR
expectedRegisteredSurface surfaceName =
    SurfaceContractIR
        { contractSurfaces = filter (\surface -> surface.surfaceName == surfaceName) registeredFrontendSurfaceContractIR.contractSurfaces
        }

leftContains :: String -> Either [String] a -> Bool
leftContains expected = \case
    Left diagnostics -> any (expected `List.isInfixOf`) diagnostics
    Right _ -> False

shouldContainText :: Text -> Text -> Expectation
shouldContainText actual expected =
    actual `shouldSatisfy` Text.isInfixOf expected
