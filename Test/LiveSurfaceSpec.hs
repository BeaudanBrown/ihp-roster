module Test.LiveSurfaceSpec where

import Application.Helper.FrontendSurface.Runtime (FrontendSurfaceFragmentKey (..),
                                                   FrontendSurfaceMountConfig (..),
                                                   FrontendSurfaceMountedFragment (..),
                                                   SurfaceImpl (..))
import Application.Helper.Interaction.Types (InteractionCapability (..),
                                             InteractionConflictPolicy (..),
                                             InteractionConflictResolution (..),
                                             InteractionFragmentSelector (..),
                                             InteractionSessionSelector (..),
                                             InteractionStaticSchema (..))
import Application.Helper.LiveResource
import Application.Helper.LiveSurface
import Application.Helper.LiveSurface.Internal (SurfaceFragmentRef (..))
import Application.Helper.LiveUpdate.Runtime (FocusedFieldProtectionConfig (..),
                                              LiveFragmentKey (..),
                                              LiveFragmentProtection (..),
                                              LiveUpdateScope (..),
                                              LiveUpdateWireFragment (..))
import Application.Helper.UiRegion (UiRegionTransitionProfile (..))
import Application.Helper.View.LazySurface
import Application.Helper.View.UiRegion
import Application.Support.LiveUpdates
import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import Generated.Types
import IHP.Prelude
import Test.Hspec
import Test.Support.LiveSurfaceContract
import qualified Text.Blaze.Html as Blaze
import Text.Blaze.Html ((!))
import qualified Text.Blaze.Html.Renderer.Text as HtmlRenderer
import qualified Text.Blaze.Html5 as Html5
import Web.Billing.FrontendSurface
import Web.RosterWeeks.FrontendSurface (RosterMountedFragmentPlan (..),
                                        RosterWeekScopeValue (..),
                                        rosterSurfaceImpl)
import Web.Timesheets.FrontendSurface
import Web.View.Admin.Invites
import Web.View.Admin.VenueSettings
import Web.View.Admin.Xero

tests :: Spec
tests = describe "LiveSurface contract helpers" do
    it "normalizes fragment refs by containment path" do
        let parent = testFragmentRef RosterContentFragment "roster-content" ["roster-content"]
        let child = testFragmentRef RosterStaffPanelFragment "roster-staff-panel-fragment" ["roster-content", "staff-panel"]
        let duplicateChild = testFragmentRef RosterStaffPanelFragment "roster-staff-panel-fragment-duplicate" ["roster-content", "staff-panel"]
        let grandchild = testFragmentRef RosterRowFragment { rosterDayId = expectUuid "22222222-2222-2222-2222-222222222222", rowIndex = 3 } "roster-row-3" ["roster-content", "day", "22222222", "row", "3"]
        let day = testFragmentRef RosterDaySectionFragment { rosterDayId = expectUuid "22222222-2222-2222-2222-222222222222" } "roster-day-22222222" ["roster-content", "day", "22222222"]
        let sibling = testFragmentRef BillingStatusFragment "billing-status-fragment" ["billing-status-fragment"]

        targetIds (normalizeSurfaceFragmentRefs [child, duplicateChild])
            `shouldBe` ["roster-staff-panel-fragment"]
        targetIds (normalizeSurfaceFragmentRefs [child, parent])
            `shouldBe` ["roster-content"]
        targetIds (normalizeSurfaceFragmentRefs [grandchild, day])
            `shouldBe` ["roster-day-22222222"]
        targetIds (normalizeSurfaceFragmentRefs [child, sibling])
            `shouldBe` ["roster-staff-panel-fragment", "billing-status-fragment"]

    it "normalizes typed surface fragments by containment path" do
        normalizeTypedLiveSurfaceFragments
            testActorLiveSurfaceDefinition
            ()
            [TestActorChild, TestActorDuplicateChild, TestActorParent, TestActorSibling]
            `shouldBe` [TestActorParent, TestActorSibling]

    it "renders normalized actor fragments in OOB mode with extras" do
        let html =
                renderTypedLiveSurfaceFragmentsFromSnapshot
                    testActorLiveSurfaceDefinition
                    ()
                    [TestActorChild, TestActorParent, TestActorSibling]
                    (FragmentOob (Just "outerHTML"))
                    (Html5.toHtml ("extra" :: Text))
                    renderTestActorFragment
                    ("snapshot" :: Text)

        HtmlRenderer.renderHtml html
            `shouldBe` "oob:outerHTML:snapshot:parentoob:outerHTML:snapshot:siblingextra"

    it "renders lazy live fragment mounts from typed surface contracts" do
        let lazyConfig =
                LazyFragmentConfig
                    { lazyFragmentTrigger = "load"
                    , lazyFragmentPlaceholderKind = lazyFragmentPlaceholderSpinner
                    , lazyFragmentAccessibleLabel = "Loading actor parent"
                    , lazyFragmentClasses = ["test-lazy-actor"]
                    , lazyFragmentDelayMs = Just 25
                    , lazyFragmentTransition = UiRegionTransitionNone
                    }
        let lazyDefinition =
                testActorLiveSurfaceDefinition
                    { typedSurfaceFragmentContract = \() fragment ->
                        mkSurfaceFragmentContract
                            (testActorFragmentRef fragment)
                            (liveFragmentResyncOnly "lazy actor fragment")
                            |> fragmentContractWithLazyLoad lazyConfig
                    }
        let eagerHtml = renderLiveSurfaceFragmentMount testActorLiveSurfaceDefinition () TestActorParent (Html5.toHtml ("eager" :: Text))
        let lazyHtml = renderLiveSurfaceFragmentMount lazyDefinition () TestActorParent (Html5.toHtml ("eager" :: Text))
        let lazyOutput = cs (HtmlRenderer.renderHtml lazyHtml)

        HtmlRenderer.renderHtml eagerHtml `shouldBe` "eager"
        lazyOutput `shouldContainText` "id=\"actor-parent\""
        lazyOutput `shouldContainText` "data-bepis-fragment=\"true\""
        lazyOutput `shouldContainText` "data-bepis-lazy-surface=\"true\""
        lazyOutput `shouldContainText` "data-bepis-lazy-retry=\"true\""
        lazyOutput `shouldContainText` "data-bepis-region-transition=\"none\""
        lazyOutput `shouldContainText` "hx-get=\"/actor-parent\""
        lazyOutput `shouldContainText` "hx-trigger=\"load delay:25ms\""
        lazyOutput `shouldContainText` "hx-target=\"this\""
        lazyOutput `shouldContainText` "hx-swap=\"outerHTML\""

    it "derives FrontendSurface live fragment refs and dependencies from a single fragment contract" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let billingScope = BillingScopeValue { billingVenueId = venueId }
        let fragments = billingAffectedMountedFragments billingScope (Set.fromList [billingResource venueId])

        map (.mountedFragmentTargetId) fragments `shouldBe` ["billing-status-fragment"]
        concatMap (billingFragmentDependencies billingScope) fragments `shouldBe` [billingResource venueId]

    it "requires fragment contracts to declare resource dependencies or resync-only intent" do
        let ref = testFragmentRef BillingStatusFragment "billing-status-fragment" ["billing-status-fragment"]
        let dependent = mkSurfaceFragmentContract ref (liveFragmentDependsOn (billingResource (expectUuid "11111111-1111-1111-1111-111111111111")) [])
        let resyncOnly = mkSurfaceFragmentContract ref (liveFragmentResyncOnly "no passive dependency")

        fragmentContractDependencies dependent `shouldBe` DependsOnLiveResources (billingResource (expectUuid "11111111-1111-1111-1111-111111111111") :| [])
        fragmentContractDependencies resyncOnly `shouldBe` ResyncOnlyFragment "no passive dependency"
        fragmentContractLoadPolicy dependent `shouldBe` FragmentEager
        fragmentContractLoadPolicy resyncOnly `shouldBe` FragmentEager

    it "attaches lazy load policy metadata to descriptors and typed contracts" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let lazyConfig =
                LazyFragmentConfig
                    { lazyFragmentTrigger = "revealed"
                    , lazyFragmentPlaceholderKind = "skeleton"
                    , lazyFragmentAccessibleLabel = "Loading secondary test fragment"
                    , lazyFragmentClasses = ["test-secondary-placeholder"]
                    , lazyFragmentDelayMs = Just 150
                    , lazyFragmentTransition = UiRegionTransitionFade
                    }
        let lazyDescriptor =
                liveFragmentDescriptor
                    TestDescriptorSecondary
                    (const (mkSurfaceFragmentRef SupportAwardRatesSectionFragment "test-secondary-fragment" "/test-secondary"))
                    (const (liveFragmentResyncOnly "secondary is resync-only"))
                    |> liveFragmentDescriptorWithLazyLoad lazyConfig
        let eagerDescriptor = lazyDescriptor |> liveFragmentDescriptorWithEagerLoad
        let definition = descriptorToTypedLiveSurfaceDefinition (testDescriptorSurfaceWithFragments venueId [lazyDescriptor])
        let manualContract =
                mkSurfaceFragmentContract
                    (testFragmentRef BillingStatusFragment "billing-status-fragment" ["billing-status-fragment"])
                    (liveFragmentResyncOnly "manual")
                    |> fragmentContractWithLazyLoad lazyConfig

        liveFragmentDescriptorLoadPolicy () lazyDescriptor `shouldBe` FragmentLazy lazyConfig
        liveFragmentDescriptorLoadPolicy () eagerDescriptor `shouldBe` FragmentEager
        typedLiveSurfaceFragmentLoadPolicy definition () TestDescriptorSecondary `shouldBe` FragmentLazy lazyConfig
        fragmentContractLoadPolicy manualContract `shouldBe` FragmentLazy lazyConfig

    it "lowers descriptor defaults into a typed live surface definition" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let definition = descriptorToTypedLiveSurfaceDefinition (testDescriptorSurface venueId)
        let config = mkTypedDefinedLiveSurface definition ()

        config.feature `shouldBe` "test-descriptor"
        config.decorateRequestsWithin `shouldBe` ["#test-descriptor-primary-fragment", "#test-descriptor-secondary-fragment"]
        map (.targetId) config.resyncFragments `shouldBe` ["test-descriptor-primary-fragment", "test-descriptor-secondary-fragment"]
        typedSurfaceDependsOn definition () TestDescriptorPrimary `shouldBe` [billingResource venueId]
        typedSurfaceDependsOn definition () TestDescriptorSecondary `shouldBe` []
        typedLiveSurfaceFragmentLoadPolicy definition () TestDescriptorPrimary `shouldBe` FragmentEager
        typedLiveSurfaceFragmentLoadPolicy definition () TestDescriptorSecondary `shouldBe` FragmentEager

    it "attaches interaction metadata through descriptors" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let definition =
                descriptorToTypedLiveSurfaceDefinition
                    ( testDescriptorSurface venueId
                        |> liveSurfaceDescriptorWithInteraction testInteractionStaticSchema (const testInteractionCapability)
                    )

        definition.typedSurfaceInteractionSchema `shouldBe` testInteractionStaticSchema
        definition.typedSurfaceInteraction () `shouldBe` testInteractionCapability

    it "allows descriptor decorate selectors to be overridden" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let definition = descriptorToTypedLiveSurfaceDefinition ((testDescriptorSurface venueId) |> liveSurfaceDescriptorWithDecorateRequestsWithin (const ["#test-shell"]))

        (mkTypedDefinedLiveSurface definition ()).decorateRequestsWithin `shouldBe` ["#test-shell"]

    it "builds current-venue unit-scope surfaces with safe wire-scope parsing" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let otherVenueId = expectUuid "22222222-2222-2222-2222-222222222222"
        let definition =
                currentVenueUnitScopeSurfaceForVenue
                    "test-current-venue"
                    venueId
                    testBillingVenueScope
                    RequireCurrentVenueOwner
                    [ staticLiveFragmentDescriptor TestDescriptorPrimary BillingStatusFragment "billing-status-fragment" "/billing" (const (liveFragmentDependsOn (billingResource venueId) []))
                    ]

        unSurfaceScope (definition.typedSurfaceScope ()) `shouldBe` BillingScope venueId
        definition.typedSurfaceScopeFromWire (BillingScope venueId) `shouldBe` Just ()
        definition.typedSurfaceScopeFromWire (BillingScope otherVenueId) `shouldBe` Nothing
        definition.typedSurfaceScopeFromWire SupportPlatformScope `shouldBe` Nothing
        (mkTypedDefinedLiveSurface definition ()).decorateRequestsWithin `shouldBe` ["#billing-status-fragment"]

    it "builds keyed current-venue descriptors while preserving explicit local keys" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let otherVenueId = expectUuid "22222222-2222-2222-2222-222222222222"
        let descriptor =
                venueLiveSurfaceDescriptorForVenue
                    "test-keyed-current-venue"
                    venueId
                    testBillingVenueScope
                    RequireCurrentVenueOwner
                    testVenueKeyVenueId
                    TestVenueKey
                    [ staticLiveFragmentDescriptor TestDescriptorPrimary BillingStatusFragment "billing-status-fragment" "/billing" (\key -> liveFragmentDependsOn (billingResource key.testVenueKeyVenueId) [])
                    ]
        let definition = descriptorToTypedLiveSurfaceDefinition descriptor
        let key = TestVenueKey venueId

        unSurfaceScope (definition.typedSurfaceScope key) `shouldBe` BillingScope venueId
        definition.typedSurfaceScopeFromWire (BillingScope venueId) `shouldBe` Just key
        definition.typedSurfaceScopeFromWire (BillingScope otherVenueId) `shouldBe` Nothing
        typedSurfaceDependsOn definition key TestDescriptorPrimary `shouldBe` [billingResource venueId]

    it "builds static fragment descriptors with protection and containment modifiers" do
        let descriptor =
                staticLiveFragmentDescriptor TestDescriptorPrimary BillingStatusFragment "initial-target" "/initial" (const (liveFragmentResyncOnly "static"))
                    |> liveFragmentDescriptorWithFocusedProtection testFocusedProtection
                    |> liveFragmentDescriptorWithPath ["outer", "inner"]
        let ref = descriptor.liveFragmentDescriptorRef ()

        ref.surfaceFragmentContainmentPath `shouldBe` ["outer", "inner"]
        ref.unSurfaceFragmentRef.fragmentKey `shouldBe` BillingStatusFragment
        ref.unSurfaceFragmentRef.targetId `shouldBe` "initial-target"
        ref.unSurfaceFragmentRef.url `shouldBe` "/initial"
        ref.unSurfaceFragmentRef.deferUntilBlur `shouldBe` True
        ref.unSurfaceFragmentRef.protectionPolicy `shouldBe` testFocusedProtection

    it "can retarget fragment descriptors while keeping URL and fragment key stable" do
        let descriptor =
                staticLiveFragmentDescriptor TestDescriptorPrimary BillingStatusFragment "old-target" "/fragment" (const (liveFragmentResyncOnly "static"))
                    |> liveFragmentDescriptorWithTargetId "new-target"
        let ref = descriptor.liveFragmentDescriptorRef ()

        ref.surfaceFragmentContainmentPath `shouldBe` ["new-target"]
        ref.unSurfaceFragmentRef.fragmentKey `shouldBe` BillingStatusFragment
        ref.unSurfaceFragmentRef.targetId `shouldBe` "new-target"
        ref.unSurfaceFragmentRef.url `shouldBe` "/fragment"

    it "renders reusable UI region transition attrs" do
        let html = Html5.div ! uiRegionTransitionAttrs UiRegionTransitionFade $ mempty
        let output = cs (HtmlRenderer.renderHtml html)
        output `shouldContainText` "data-bepis-fragment=\"true\""
        output `shouldContainText` "data-bepis-region-transition=\"fade\""

    it "derives stable kebab and snake names for descriptor defaults" do
        nameToKebab "AdminAnnouncementFragment" `shouldBe` "admin-announcement-fragment"
        nameToSnake "AdminAnnouncementFragment" `shouldBe` "admin_announcement_fragment"
        defaultLiveFragmentTargetId "AdminAnnouncement" "Content" `shouldBe` "admin-announcement-content-fragment"

    it "marks the roster staff panel as a lazy FrontendSurface fragment" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let rosterGroupId = "22222222-2222-2222-2222-222222222222" :: Id RosterGroup
        let surface = rosterSurfaceImpl
                RosterWeekScopeValue { rosterWeekVenueId = venueId, rosterWeekGroupId = rosterGroupId, rosterWeekWeekOffset = 0 }
                RosterMountedFragmentPlan { rosterMountedDayIds = [], rosterMountedRows = [] }
        let staffPanel = find ((== "roster-staff-panel") . (.mountedFragmentKey.fragmentKind)) surface.surfaceImplMountConfig.mountFragments

        case staffPanel of
            Just fragment -> do
                fragment.mountedFragmentTargetId `shouldBe` "roster-staff-panel-fragment"
                fragment.mountedFragmentLoadPolicy `shouldBe` "lazy"
                fragment.mountedFragmentUrl `shouldContainText` "rosterGroupId="
            Nothing -> expectationFailure "expected roster staff panel fragment"

    it "verifies context-free typed surface contracts used by background updates" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let rosterGroupId = "22222222-2222-2222-2222-222222222222" :: Id RosterGroup
        let billingScope = BillingScopeValue { billingVenueId = venueId }
        let timesheetScope = TimesheetWeekScopeValue venueId 1
        let timesheetMountState = TimesheetsMountStateValue True True Nothing
        let timesheetImpl = timesheetsSurfaceImpl timesheetScope timesheetMountState
        let timesheetSurface = timesheetsLegacyLiveSurfaceConfig timesheetImpl timesheetScope
        let invitesKey = AdminInvitesSurfaceKey { adminInvitesRosterGroupId = Just rosterGroupId }
        let surfaces =
                [ timesheetSurface
                , mkTypedDefinedLiveSurface (adminVenueSettingsLiveSurfaceDefinitionForVenue venueId) ()
                , mkTypedDefinedLiveSurface (adminInvitesLiveSurfaceDefinitionForVenue venueId) invitesKey
                , mkTypedDefinedLiveSurface (adminXeroLiveSurfaceDefinitionForVenue venueId) ()
                ]

        forM_ surfaces liveSurfaceConfigShouldRoundTrip
        liveSurfaceConfigShouldExposeRefs
            timesheetSurface
            timesheetSurface.resyncFragments
        let billingFragments = billingSurfaceWireFragments (billingAffectedMountedFragments billingScope (Set.fromList [billingResource venueId]))
        billingFragments `shouldBe`
            [ LiveUpdateWireFragment
                { fragmentKey = BillingStatusFragment
                , targetId = "billing-status-fragment"
                , url = "/ShowBillingStatusFragment"
                , deferUntilBlur = False
                , protectionPolicy = NoProtection
                }
            ]
        let timesheetFragments = timesheetsSurfaceWireFragments (timesheetsCandidateMountedFragments timesheetScope timesheetMountState)
        timesheetFragments `shouldContain`
            [ LiveUpdateWireFragment
                { fragmentKey = TimesheetToolbarFragment
                , targetId = "timesheet-week-toolbar"
                , url = "/ShowTimesheetToolbarFragment?weekOffset=1&showApproved=true&showAllStaff=true"
                , deferUntilBlur = False
                , protectionPolicy = NoProtection
                }
            ]
        timesheetFragments `shouldContain`
            [ LiveUpdateWireFragment
                { fragmentKey = TimesheetDayColumnsFragment
                , targetId = "timesheet-day-columns"
                , url = "/ShowTimesheetDayColumnsFragment?weekOffset=1&showApproved=true&showAllStaff=true"
                , deferUntilBlur = False
                , protectionPolicy = NoProtection
                }
            ]
        timesheetFragments `shouldContain`
            [ LiveUpdateWireFragment
                { fragmentKey = TimesheetDaySectionFragment { dayOffset = 2 }
                , targetId = "timesheet-day-section-2"
                , url = "/ShowTimesheetDaySectionFragment?weekOffset=1&dayOffset=2&showApproved=true&showAllStaff=true"
                , deferUntilBlur = False
                , protectionPolicy = NoProtection
                }
            ]
        typedLiveSurfaceFragmentShouldMapTo
            (adminXeroLiveSurfaceDefinitionForVenue venueId)
            ()
            adminXeroPayItemsFragment
            AdminXeroPayItemsFragment
            "xero-pay-items-data"
            "/ShowAdminXeroPayItemsFragment"
        map (.feature) surfaces `shouldBe` ["timesheets", "admin-venue-config", "admin-invites", "admin-xero"]
        map (.scopeKey) surfaces
            `shouldBe`
                [ "timesheet_week:11111111-1111-1111-1111-111111111111:1"
                , "admin_venue_config:11111111-1111-1111-1111-111111111111"
                , "admin_invites:11111111-1111-1111-1111-111111111111"
                , "admin_xero:11111111-1111-1111-1111-111111111111"
                ]

testFragmentRef :: LiveFragmentKey -> Text -> [Text] -> SurfaceFragmentRef ()
testFragmentRef fragmentKey target path =
    mkSurfaceFragmentRef fragmentKey target ("/" <> target)
        |> surfaceFragmentRefWithPath path

targetIds :: [SurfaceFragmentRef surface] -> [Text]
targetIds refs =
    map (.targetId) (unSurfaceFragmentRefs refs)

data TestDescriptorSurface

data TestDescriptorFragment
    = TestDescriptorPrimary
    | TestDescriptorSecondary
    deriving (Eq, Show)

data TestInteractionLayer = TestInteractionLayer deriving (Eq, Show)

data TestInteractionSession = TestInteractionSession deriving (Eq, Show)

data TestInteractionIntent = TestInteractionIntent deriving (Eq, Show)

testInteractionStaticSchema :: InteractionStaticSchema TestDescriptorFragment TestInteractionLayer TestInteractionSession TestInteractionIntent
testInteractionStaticSchema =
    emptyInteractionStaticSchema
        { interactionStaticConflictPolicies =
            [ InteractionConflictPolicy
                { conflictPolicySession = InteractionSessionKind TestInteractionSession
                , conflictPolicyFragment = InteractionFragment TestDescriptorPrimary
                , conflictPolicyResolution = DeferLiveFragmentUntilSessionEnds
                , conflictPolicyTimeoutMs = Just 250
                }
            ]
        }

testInteractionCapability :: InteractionCapability (SurfaceFragmentRef TestDescriptorSurface) TestDescriptorFragment TestInteractionLayer TestInteractionSession TestInteractionIntent
testInteractionCapability =
    emptyInteractionCapability
        { interactionStaticSchema = testInteractionStaticSchema
        , interactionConflictPolicies = testInteractionStaticSchema.interactionStaticConflictPolicies
        }

data TestVenueKey = TestVenueKey
    { testVenueKeyVenueId :: !UUID.UUID
    }
    deriving (Eq, Show)

testBillingVenueScope :: VenueLiveUpdateScope
testBillingVenueScope =
    venueLiveUpdateScope
        BillingScope
        (\scope -> case scope of
            BillingScope { venueId } -> Just venueId
            _                        -> Nothing)

testFocusedProtection :: LiveFragmentProtection
testFocusedProtection =
    FocusedFieldProtection
        FocusedFieldProtectionConfig
            { activeSelector = "input:focus"
            , fieldKeyAttr = "data-test-field"
            , fieldNameFallback = True
            , containerSelector = Just "form"
            }

testDescriptorSurface :: UUID.UUID -> LiveSurfaceDescriptor TestDescriptorSurface () TestDescriptorFragment EmptyInteractionLayer EmptyInteractionSession EmptyInteractionIntent
testDescriptorSurface venueId =
    testDescriptorSurfaceWithFragments
        venueId
        [ liveFragmentDescriptor
            TestDescriptorPrimary
            (const (mkSurfaceFragmentRef BillingStatusFragment "test-descriptor-primary-fragment" "/test-primary"))
            (const (liveFragmentDependsOn (billingResource venueId) []))
        , liveFragmentDescriptor
            TestDescriptorSecondary
            (const (mkSurfaceFragmentRef SupportAwardRatesSectionFragment "test-descriptor-secondary-fragment" "/test-secondary"))
            (const (liveFragmentResyncOnly "secondary is resync-only"))
        ]

testDescriptorSurfaceWithFragments :: UUID.UUID -> [LiveFragmentDescriptor TestDescriptorSurface () TestDescriptorFragment] -> LiveSurfaceDescriptor TestDescriptorSurface () TestDescriptorFragment EmptyInteractionLayer EmptyInteractionSession EmptyInteractionIntent
testDescriptorSurfaceWithFragments venueId fragments =
    liveSurfaceDescriptor
        "test-descriptor"
        (const (SurfaceScope BillingScope { venueId }))
        (\wireScope -> case wireScope of
            BillingScope { venueId = wireVenueId } | wireVenueId == venueId -> Just ()
            _ -> Nothing)
        (liveSurfaceAuthorizationByRequirement (const (RequireCurrentVenueOwner venueId)))
        fragments

data TestActorSurface

data TestActorFragment
    = TestActorParent
    | TestActorChild
    | TestActorDuplicateChild
    | TestActorSibling
    deriving (Eq, Show)

testActorLiveSurfaceDefinition :: TypedLiveSurfaceDefinition TestActorSurface () TestActorFragment EmptyInteractionLayer EmptyInteractionSession EmptyInteractionIntent
testActorLiveSurfaceDefinition =
    TypedLiveSurfaceDefinition
        { typedSurfaceFeature = "test-actor"
        , typedSurfaceScope = const (SurfaceScope SupportPlatformScope)
        , typedSurfaceScopeFromWire = const (Just ())
        , typedSurfaceDefaultFragments = const [TestActorParent]
        , typedSurfaceFragmentContract = \() fragment ->
            mkSurfaceFragmentContract
                (testActorFragmentRef fragment)
                (liveFragmentResyncOnly "test actor fragment")
        , typedSurfaceDecorateRequestsWithin = const []
        , typedSurfaceAuthorize = LiveSurfaceAuthorization { authorizeLiveSurfaceScope = const (pure True) }
        , typedSurfaceInteractionSchema = emptyInteractionStaticSchema
        , typedSurfaceInteraction = const emptyInteractionCapability
        }

testActorFragmentRef :: TestActorFragment -> SurfaceFragmentRef TestActorSurface
testActorFragmentRef TestActorParent =
    mkSurfaceFragmentRef RosterContentFragment "actor-parent" "/actor-parent"
testActorFragmentRef TestActorChild =
    mkSurfaceFragmentRef RosterStaffPanelFragment "actor-child" "/actor-child"
        |> surfaceFragmentRefWithPath ["actor-parent", "actor-child"]
testActorFragmentRef TestActorDuplicateChild =
    mkSurfaceFragmentRef RosterStaffPanelFragment "actor-duplicate-child" "/actor-duplicate-child"
        |> surfaceFragmentRefWithPath ["actor-parent", "actor-child"]
testActorFragmentRef TestActorSibling =
    mkSurfaceFragmentRef BillingStatusFragment "actor-sibling" "/actor-sibling"

renderTestActorFragment :: FragmentRenderMode -> Text -> TestActorFragment -> Maybe Blaze.Html
renderTestActorFragment renderMode snapshot fragment =
    Just (Html5.toHtml (modeLabel renderMode <> ":" <> snapshot <> ":" <> fragmentLabel fragment))

modeLabel :: FragmentRenderMode -> Text
modeLabel FragmentPlain                 = "plain"
modeLabel (FragmentOob Nothing)         = "oob:none"
modeLabel (FragmentOob (Just swapAttr)) = "oob:" <> swapAttr

fragmentLabel :: TestActorFragment -> Text
fragmentLabel TestActorParent         = "parent"
fragmentLabel TestActorChild          = "child"
fragmentLabel TestActorDuplicateChild = "duplicate-child"
fragmentLabel TestActorSibling        = "sibling"

shouldContainText :: HasCallStack => Text -> Text -> Expectation
shouldContainText actual expected =
    Text.isInfixOf expected actual `shouldBe` True

expectUuid :: Text -> UUID.UUID
expectUuid value =
    fromMaybe (error ("Invalid UUID fixture: " <> cs value)) (UUID.fromText value)
