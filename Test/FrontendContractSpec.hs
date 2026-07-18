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
import Application.Helper.FrontendContract.Wire.Carrier
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Aeson.Types as AesonTypes
import Data.Either (isLeft)
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import IHP.Prelude hiding (Enum)
import Test.Hspec
import Test.QuickCheck (property)
import qualified Test.Support.FrontendContractCarrierFixture as CarrierFixture

-- Fixture markers
data App

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

data ParsedCarrierUnion
    = ParsedCarrierCreated !UUID.UUID
    | ParsedCarrierDeleted !UUID.UUID
    deriving (Eq, Show)

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
        source `shouldNotContainText` "export type OverlayLane ="
        source `shouldContainText` "export const pageReadyEvent = \"bepis:page-ready\" as const;"
        source `shouldContainText` "export const dialogOverlayMountDomId = \"dialog-overlay-mount\" as const;"
        source `shouldNotContainText` "intentSubmitEvent"
        source `shouldNotContainText` "appContentMountDomId"
        source `shouldNotContainText` "lazyFragmentDomAttr"
        source `shouldContainText` "export type UiRegionTransitionProfile ="
        source `shouldContainText` "export const lazySurfaceDomAttr = \"data-bepis-lazy-surface\" as const;"
        source `shouldContainText` "export type ToggleConfig = { presentationState: TogglePresentationState; checkedTarget: ToggleTarget; uncheckedTarget: ToggleTarget; transportKey: string; submissionPolicy: ToggleSubmissionPolicy; breakRegionKey: string | null };"
        source `shouldContainText` "export function parseToggleConfig(value: unknown): ToggleConfig"
        source `shouldContainText` "export const toggleInputDomAttr = \"data-bepis-toggle-input\" as const;"
        source `shouldContainText` "export const toggleBreakRegionDomAttr = \"data-bepis-toggle-break-region\" as const;"
        source `shouldContainText` "export type RosterStaffSortKey ="
        source `shouldContainText` "  | \"shifts\";"
        source `shouldContainText` "export type RosterRosterWeekScope = { venueId: FrontendContractUuid; rosterGroupId: FrontendContractUuid; weekOffset: number };"

    it "derives primitive TypeScript aliases from the wire primitive registry" do
        let Right source = renderFrontendContractTypeScript (reflectFrontendContracts @FixtureContracts)
        source `shouldContainText` "export type FrontendContractUuid = string;"
        source `shouldContainText` "export type FrontendContractDay = string;"
        source `shouldContainText` "userId: FrontendContractUuid"
        source `shouldNotContainText` "FrontendSurfaceUUID"
        source `shouldNotContainText` "FrontendSurfaceDay"

    it "reflects global roots without a parallel Surface authoring model" do
        let contract = reflectFrontendContracts @FixtureContracts
        fmap (.globalName) contract.contractGlobals `shouldBe` ["app"]
        contract.contractSurfaces `shouldBe` []
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

    it "maps recursive wire sources without collapsing list, optional, or nullable structure" do
        haskellWireSource (WireListIR WireUuidIR)
            `shouldBe` HaskellListSource HaskellUuidSource
        haskellWireSource (WireOptionalIR (WireListIR (WireNullableIR WireTextIR)))
            `shouldBe` HaskellOptionalSource (HaskellListSource (HaskellNullableSource HaskellTextSource))
        let values :: WireSourceType ('WireList 'WireUUID)
            values = [carrierUuid]
        values `shouldBe` [carrierUuid]

    it "keeps optional absence, present null, required null, and empty lists distinct" do
        let absentOptional = carrierRecordValue [] Nothing Nothing (Just [])
        let presentNull = carrierRecordValue [] (Just Nothing) Nothing (Just [])

        absentOptional
            `shouldBe` Aeson.object
                [ "memberIds" Aeson..= ([] :: [Text])
                , "requiredNote" Aeson..= Aeson.Null
                , "nestedValues" Aeson..= ([] :: [Text])
                ]
        presentNull
            `shouldBe` Aeson.object
                [ "memberIds" Aeson..= ([] :: [Text])
                , "optionalNullableNote" Aeson..= Aeson.Null
                , "requiredNote" Aeson..= Aeson.Null
                , "nestedValues" Aeson..= ([] :: [Text])
                ]
        parseCarrierRecord absentOptional
            `shouldBe` Right ([], Nothing, Nothing, Just [])
        parseCarrierRecord presentNull
            `shouldBe` Right ([], Just Nothing, Nothing, Just [])

    it "rejects missing nullable fields, extra fields, and wrong wire values at the exact boundary" do
        let valid = carrierRecordValue [carrierUuid] Nothing (Just "ready") (Just [Nothing, Just "nested"])
        parseCarrierRecord (removeCarrierField "requiredNote" valid) `shouldSatisfy` isLeft
        parseCarrierRecord (addCarrierField "extra" Aeson.Null valid) `shouldSatisfy` isLeft
        parseCarrierRecord (replaceCarrierField "memberIds" (Aeson.String "not-a-list") valid) `shouldSatisfy` isLeft

    it "round-trips recursive optional and nullable source values through typed direct access" $ property \rawValues includeOptional includeNested ->
        let nestedItems = fmap (fmap Text.pack) (rawValues :: [Maybe String])
            nested = if includeNested then Just nestedItems else Nothing
            optionalValue = if includeOptional then Just (listToMaybe (catMaybes nestedItems)) else Nothing
            encoded = carrierRecordValue [carrierUuid] optionalValue Nothing nested
         in parseCarrierRecord encoded
                == Right ([carrierUuid], optionalValue, Nothing, nested)

    it "builds and parses declaration-complete tagged unions without carrier-side tag dispatch" do
        let created = taggedUnionValueIn @CarrierFixture.CarrierContracts @CarrierFixture.CarrierUnion @CarrierFixture.CarrierCreated
                (requiredField @CarrierFixture.CarrierUserId carrierUuid &: noFields)
        created
            `shouldBe` Aeson.object
                [ "kind" Aeson..= ("carrier-created" :: Text)
                , "carrierUserId" Aeson..= UUID.toText carrierUuid
                ]
        parseCarrierUnion created `shouldBe` Right (ParsedCarrierCreated carrierUuid)
        parseCarrierUnion (Aeson.object ["kind" Aeson..= ("unknown" :: Text)]) `shouldSatisfy` isLeft
        parseCarrierUnion (addCarrierField "extra" Aeson.Null created) `shouldSatisfy` isLeft

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

carrierUuid :: UUID.UUID
carrierUuid =
    fromMaybe (error "invalid carrier UUID fixture") (UUID.fromText "11111111-1111-1111-1111-111111111111")

carrierRecordValue ::
    [UUID.UUID] ->
    Maybe (Maybe Text) ->
    Maybe Text ->
    Maybe [Maybe Text] ->
    Aeson.Value
carrierRecordValue memberIds optionalNullableNote requiredNote nestedValues =
    recordValueIn @CarrierFixture.CarrierContracts @CarrierFixture.CarrierRecord
        ( requiredField @CarrierFixture.MemberIds memberIds
            &: optionalField @CarrierFixture.OptionalNullableNote optionalNullableNote
            &: nullableField @CarrierFixture.RequiredNote requiredNote
            &: requiredField @CarrierFixture.NestedValues nestedValues
            &: noFields
        )

parseCarrierRecord ::
    Aeson.Value ->
    Either String ([UUID.UUID], Maybe (Maybe Text), Maybe Text, Maybe [Maybe Text])
parseCarrierRecord =
    AesonTypes.parseEither $
        parseRecordIn @CarrierFixture.CarrierContracts @CarrierFixture.CarrierRecord \
            (memberIds, (optionalNullableNote, (requiredNote, (nestedValues, ())))) ->
                pure (memberIds, optionalNullableNote, requiredNote, nestedValues)

parseCarrierUnion :: Aeson.Value -> Either String ParsedCarrierUnion
parseCarrierUnion =
    AesonTypes.parseEither $
        parseTaggedUnionIn @CarrierFixture.CarrierContracts @CarrierFixture.CarrierUnion
            ( unionCase @CarrierFixture.CarrierCreated
                (\(userId, ()) -> pure (ParsedCarrierCreated userId))
                |: unionCase @CarrierFixture.CarrierDeleted
                    (\(userId, ()) -> pure (ParsedCarrierDeleted userId))
                |: noUnionCases
            )

addCarrierField :: Text -> Aeson.Value -> Aeson.Value -> Aeson.Value
addCarrierField name value = \case
    Aeson.Object object -> Aeson.Object (KeyMap.insert (AesonKey.fromText name) value object)
    other               -> other

removeCarrierField :: Text -> Aeson.Value -> Aeson.Value
removeCarrierField name = \case
    Aeson.Object object -> Aeson.Object (KeyMap.delete (AesonKey.fromText name) object)
    other               -> other

replaceCarrierField :: Text -> Aeson.Value -> Aeson.Value -> Aeson.Value
replaceCarrierField = addCarrierField

shouldContainText :: Text -> Text -> Expectation
shouldContainText haystack needle = haystack `shouldSatisfy` (needle `isInfixOf`)

shouldNotContainText :: Text -> Text -> Expectation
shouldNotContainText haystack needle = haystack `shouldSatisfy` not . (needle `isInfixOf`)
