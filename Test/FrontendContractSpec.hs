{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Test.FrontendContractSpec
    ( tests
    ) where

import Application.Helper.FrontendContract.DSL hiding (Enum)
import qualified Application.Helper.FrontendContract.DSL as DSL
import Application.Helper.FrontendContract.IR
import Application.Helper.FrontendContract.Reflect
import Application.Helper.FrontendContract.Registry (validateFrontendContractStartup)
import Application.Helper.FrontendContract.TypeScript
import Application.Helper.FrontendContract.Wire.Carrier
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Aeson.Types as AesonTypes
import Data.Either (isLeft)
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import qualified Data.UUID as UUID
import IHP.ModelSupport (InputValue (..))
import IHP.Prelude
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
data DensityRecord
data DensityField
data NestedRecord
data NestedValues
data CompactClass

data FixtureDensity
    = CompactDensity
    | ComfortableDensity
    deriving (Bounded, Enum, Eq, Show)

instance InputValue FixtureDensity where
    inputValue CompactDensity     = "compact"
    inputValue ComfortableDensity = "comfortable"

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
         , GlobalSchema (Record NestedRecord
            '[ Field NestedValues ('WireOptional ('WireList ('WireNullable 'WireText)))
             ])
         , BrowserInboundSchema (ClosedScalar FixtureDensity)
         , BrowserInboundSchema (Record DensityRecord '[Field DensityField ('WireClosed FixtureDensity)])
         , GlobalSchema (DSL.Enum StaffStatus '[ActiveStatus, InactiveStatus])
         , GlobalSchema (TaggedUnion StaffEvent
            '[ Case CreatedCase '[Field UserId 'WireUUID]
             , Case DeletedCase '[Field UserId 'WireUUID]
             ])
         , Event OpenDialog '[Field UserId 'WireUUID]
         , DomAttr OverlayRoot
         , DomValue CompactClass "is-compact"
         ]
     ]

data DuplicateName
data DuplicateNameOne
data MissingRecord
data MissingRefField

type DuplicateContracts =
    '[ Global App
        '[ GlobalSchema (Record DuplicateName '[Field StaffName 'WireText])
         , GlobalSchema (DSL.Enum DuplicateName '[ActiveStatus])
         ]
     ]

type MissingRefContracts =
    '[ Global App
        '[ GlobalSchema (Record MissingRecord '[Field MissingRefField ('WireRef StaffRecord)])
         ]
     ]

type WrongClosedScalarAuthorityContracts =
    '[ Global App
        '[ BrowserInboundSchema (DSL.Enum FixtureDensity '[ActiveStatus, InactiveStatus])
         , BrowserInboundSchema (Record DensityRecord '[Field DensityField ('WireClosed FixtureDensity)])
         ]
     ]

type DuplicateFieldContracts =
    '[ Global App '[GlobalSchema (Record DuplicateNameOne '[Field StaffName 'WireText, Field StaffName 'WireText])] ]

type DuplicateValueContracts =
    '[ Global App '[GlobalSchema (DSL.Enum StaffStatus '[ActiveStatus, ActiveStatus])] ]

type DuplicateCaseContracts =
    '[ Global App '[GlobalSchema (TaggedUnion StaffEvent '[Case CreatedCase '[], Case CreatedCase '[]])] ]

tests :: Spec
tests = describe "FrontendContract foundation" do
    it "reflects fixture names, primitive kinds, ordered fields, recursive wires, presence and union cases into semantic IR" do
        reflectFrontendContracts @FixtureContracts `shouldBe` expectedFixtureIR

    it "validates the reflected fixture without a parallel Surface authoring model" do
        case checkedFrontendContractIR (reflectFrontendContracts @FixtureContracts) of
            Right checked    -> frontendContractIR checked `shouldBe` expectedFixtureIR
            Left diagnostics -> expectationFailure (cs (show diagnostics))

    it "rejects invalid startup registries with deterministic diagnostics before traffic" do
        let invalidContract = reflectFrontendContracts @DuplicateContracts
        validateFrontendContractStartup invalidContract
            `shouldBe` Left "schema-name-collision: Duplicate schema name DuplicateName from DuplicateName\n"

    it "validates duplicate declarations and unresolved refs" do
        validateFrontendContractIR (reflectFrontendContracts @DuplicateContracts)
            |> fmap (.diagnosticCode)
            `shouldContain` ["schema-name-collision"]
        validateFrontendContractIR (reflectFrontendContracts @MissingRefContracts)
            |> fmap (.diagnosticCode)
            `shouldContain` ["unresolved-ref"]
        validateFrontendContractIR (reflectFrontendContracts @WrongClosedScalarAuthorityContracts)
            |> fmap (.diagnosticCode)
            `shouldContain` ["unregistered-closed-scalar"]

    it "rejects duplicate fields, enum values and union cases at their semantic boundary" do
        fmap (.diagnosticCode) (validateFrontendContractIR (reflectFrontendContracts @DuplicateFieldContracts))
            `shouldBe` ["field-name-collision"]
        fmap (.diagnosticCode) (validateFrontendContractIR (reflectFrontendContracts @DuplicateValueContracts))
            `shouldBe` ["enum-value-collision"]
        fmap (.diagnosticCode) (validateFrontendContractIR (reflectFrontendContracts @DuplicateCaseContracts))
            `shouldBe` ["union-case-collision"]

    it "reflects DSL-owned closed scalars into exact typed Haskell carriers" do
        let density :: WireSourceType ('WireClosed FixtureDensity)
            density = ComfortableDensity
        density `shouldBe` ComfortableDensity
        let encoded = recordValueIn @FixtureContracts @DensityRecord
                (requiredField @DensityField density &: noFields)
        encoded `shouldBe` Aeson.object ["density" Aeson..= ("comfortable" :: Text)]
        AesonTypes.parseEither
            (parseRecordIn @FixtureContracts @DensityRecord (\(parsedDensity, ()) -> pure parsedDensity))
            encoded
            `shouldBe` Right ComfortableDensity
        AesonTypes.parseEither
            (parseRecordIn @FixtureContracts @DensityRecord (\(parsedDensity, ()) -> pure parsedDensity))
            (Aeson.object ["density" Aeson..= ("wide" :: Text)])
            `shouldSatisfy` isLeft

    it "maps recursive wire sources without collapsing list, optional, or nullable structure" do
        haskellWireSource (WireListIR WireUuidIR)
            `shouldBe` HaskellListSource HaskellUuidSource
        haskellWireSource (WireOptionalIR (WireListIR (WireNullableIR WireTextIR)))
            `shouldBe` HaskellOptionalSource (HaskellListSource (HaskellNullableSource HaskellTextSource))
        haskellWireSource WireUnknownIR `shouldBe` HaskellJsonSource
        let values :: WireSourceType ('WireList 'WireUUID)
            values = [carrierUuid]
        let platformValue :: WireSourceType 'WireUnknown
            platformValue = Aeson.object ["native" Aeson..= True]
        values `shouldBe` [carrierUuid]
        platformValue `shouldBe` Aeson.object ["native" Aeson..= True]

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
        let deleted = taggedUnionValueIn @CarrierFixture.CarrierContracts @CarrierFixture.CarrierUnion @CarrierFixture.CarrierDeleted
                (requiredField @CarrierFixture.CarrierUserId carrierUuid &: noFields)
        deleted
            `shouldBe` Aeson.object
                [ "kind" Aeson..= ("carrier-deleted" :: Text)
                , "carrierUserId" Aeson..= UUID.toText carrierUuid
                ]
        parseCarrierUnion created `shouldBe` Right (ParsedCarrierCreated carrierUuid)
        parseCarrierUnion deleted `shouldBe` Right (ParsedCarrierDeleted carrierUuid)
        parseCarrierUnion (removeCarrierField "carrierUserId" deleted) `shouldSatisfy` isLeft
        parseCarrierUnion (replaceCarrierField "carrierUserId" (Aeson.Bool True) deleted) `shouldSatisfy` isLeft
        parseCarrierUnion (Aeson.object ["kind" Aeson..= ("unknown" :: Text)]) `shouldSatisfy` isLeft
        parseCarrierUnion (addCarrierField "extra" Aeson.Null created) `shouldSatisfy` isLeft

    it "renders the representative fixture to the canonical TypeScript golden" do
        source <- renderFixtureTypeScript (reflectFrontendContracts @FixtureContracts)
        expected <- TextIO.readFile "Test/Fixtures/frontend-contract/representative.ts.golden"
        -- splitOn preserves the final empty segment: line-local diffs still
        -- enforce exact output, including the terminal newline.
        Text.splitOn "\n" source `shouldBe` Text.splitOn "\n" expected

    it "reports validation diagnostics instead of rendering invalid IR" do
        renderFrontendContractTypeScript (reflectFrontendContracts @DuplicateContracts)
            `shouldBe` Left "Duplicate schema name DuplicateName from DuplicateName"

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

renderFixtureTypeScript :: FrontendContractIR -> IO Text
renderFixtureTypeScript contract =
    case renderFrontendContractTypeScript contract of
        Left diagnostics -> fail ("FrontendContract fixture renderer failed:\n" <> cs diagnostics)
        Right source     -> pure source

-- Literal semantic oracle: no production registry, naming helper or renderer
-- is used to construct the expected projection.
expectedFixtureIR :: FrontendContractIR
expectedFixtureIR = FrontendContractIR
    [ GlobalIR "App" "app"
        [ GlobalSchemaIR BrowserBidirectionalIR (RecordIR "StaffRecord" "StaffRecord"
            [ FieldIR "UserId" "userId" WireUuidIR RequiredField
            , FieldIR "StaffName" "staffName" WireTextIR RequiredField
            , FieldIR "FavoriteDay" "favoriteDay" WireDayIR OptionalFieldPresence
            , FieldIR "Note" "note" WireTextIR NullableFieldPresence
            ])
        , GlobalSchemaIR BrowserBidirectionalIR (RecordIR "DraftStaffRecord" "DraftStaffRecord"
            [FieldIR "StaffName" "staffName" WireTextIR RequiredField])
        , GlobalSchemaIR BrowserBidirectionalIR (RecordIR "NestedRecord" "NestedRecord"
            [FieldIR "NestedValues" "nestedValues" (WireOptionalIR (WireListIR (WireNullableIR WireTextIR))) RequiredField])
        , GlobalSchemaIR BrowserInboundIR (ClosedScalarIR "FixtureDensity" "FixtureDensity" ["compact", "comfortable"])
        , GlobalSchemaIR BrowserInboundIR (RecordIR "DensityRecord" "DensityRecord"
            [FieldIR "DensityField" "density" (WireClosedIR "FixtureDensity" "Test.FrontendContractSpec" "FixtureDensity") RequiredField])
        , GlobalSchemaIR BrowserBidirectionalIR (EnumIR "StaffStatus" "StaffStatus" ["active-status", "inactive-status"])
        , GlobalSchemaIR BrowserBidirectionalIR (TaggedUnionIR "StaffEvent" "StaffEvent" "tag"
            [ UnionCaseIR "CreatedCase" "created-case" [FieldIR "UserId" "userId" WireUuidIR RequiredField]
            , UnionCaseIR "DeletedCase" "deleted-case" [FieldIR "UserId" "userId" WireUuidIR RequiredField]
            ])
        , GlobalEventIR BrowserTypeOnlyIR "OpenDialog" "bepis:open-dialog" [FieldIR "UserId" "userId" WireUuidIR RequiredField]
        , GlobalDomAttrIR "OverlayRoot" "data-bepis-overlay-root"
        , GlobalDomValueIR "CompactClass" "is-compact"
        ]
    ]
    []
