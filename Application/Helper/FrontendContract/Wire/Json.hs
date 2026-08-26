{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

module Application.Helper.FrontendContract.Wire.Json
    ( validateContractMarkerValue
    , validateContractMarkerValueWith
    , validateSurfaceScopeValue
    , validateSurfaceFragmentKeyValue
    , validateWireValue
    ) where

import Application.Error.Parser (parserFailure)
import qualified Application.Helper.FrontendContract.IR as Contract
import Application.Helper.FrontendContract.Registry (checkedRegisteredFrontendContract)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.Scientific as Scientific
import Data.Typeable (Proxy (..), Typeable, tyConName, typeRep, typeRepTyCon)
import IHP.Prelude

-- | Validate an Aeson value against the schema or event detail selected by its
-- declaration marker. Carrier code uses this marker-indexed entrypoint so the
-- reflected registry remains the only source of schema names.
checkedContractIR :: Contract.FrontendContractIR
checkedContractIR = Contract.frontendContractIR checkedRegisteredFrontendContract

validateContractMarkerValue :: forall marker. Typeable marker => Aeson.Value -> AesonTypes.Parser ()
validateContractMarkerValue = validateContractMarkerValueWith @marker checkedContractIR

validateContractMarkerValueWith :: forall marker. Typeable marker => Contract.FrontendContractIR -> Aeson.Value -> AesonTypes.Parser ()
validateContractMarkerValueWith contract value =
    case schemaByMarker contract markerName of
        Nothing -> parserFailure ("unknown frontend contract schema marker " <> cs markerName)
        Just schema -> validateSchema contract (schemaLabel schema) schema value
  where
    markerName = typeMarker @marker

-- Schema refs in checked IR carry their reflected target name. Keep this
-- lookup private; Haskell carrier callers select roots by marker.
validateContractValueWithName :: Contract.FrontendContractIR -> Text -> Aeson.Value -> AesonTypes.Parser ()
validateContractValueWithName contract name value =
    case schemaByName contract name of
        Nothing     -> parserFailure ("unknown frontend contract schema " <> cs name)
        Just schema -> validateSchema contract name schema value

schemaByMarker :: Contract.FrontendContractIR -> Text -> Maybe Contract.SchemaIR
schemaByMarker contract marker =
    listToMaybe
        [ schema
        | schema <- contractSchemas contract
        , snd (Contract.schemaNameAndMarker schema) == marker
        ]

schemaByName :: Contract.FrontendContractIR -> Text -> Maybe Contract.SchemaIR
schemaByName contract name =
    listToMaybe
        [ schema
        | schema <- contractSchemas contract
        , schemaName schema == name
        ]

contractSchemas :: Contract.FrontendContractIR -> [Contract.SchemaIR]
contractSchemas contract =
    [ schema | global <- contract.contractGlobals, Contract.GlobalSchemaIR _ schema <- global.globalPrimitives ]
        <> [ Contract.RecordIR marker (marker <> "EventDetail") fields
           | global <- contract.contractGlobals
           , Contract.GlobalEventIR _ marker _ fields <- global.globalPrimitives
           ]
        <> concatMap (map (.surfaceDtoSchema) . (.surfaceDtos)) contract.contractSurfaces

schemaLabel :: Contract.SchemaIR -> Text
schemaLabel = schemaName

schemaName :: Contract.SchemaIR -> Text
schemaName = \case
    Contract.RecordIR _ name _ -> name
    Contract.EnumIR _ name _ -> name
    Contract.ClosedScalarIR _ name _ -> name
    Contract.LiteralEnumIR _ name _ -> name
    Contract.TaggedUnionIR _ name _ _ -> name

validateSchema :: Contract.FrontendContractIR -> Text -> Contract.SchemaIR -> Aeson.Value -> AesonTypes.Parser ()
validateSchema contract label = \case
    Contract.RecordIR _ _ fields -> validateFieldObject contract label fields
    Contract.EnumIR _ _ values -> validateStringMember label values
    Contract.ClosedScalarIR _ _ values -> validateStringMember label values
    Contract.LiteralEnumIR _ _ values -> validateStringMember label (fmap snd values)
    Contract.TaggedUnionIR _ _ discriminator cases -> validateTaggedUnion contract label discriminator cases

validateTaggedUnion :: Contract.FrontendContractIR -> Text -> Text -> [Contract.UnionCaseIR] -> Aeson.Value -> AesonTypes.Parser ()
validateTaggedUnion contract label discriminator cases value =
    case value of
        Aeson.Object object -> do
            tag <- parseTextField object discriminator
            case find ((== tag) . (.unionCaseTag)) cases of
                Nothing -> parserFailure (cs label <> " has unsupported " <> cs discriminator <> " " <> cs tag)
                Just unionCase -> do
                    forM_ unionCase.unionCaseFields \field -> validateField contract object field
                    let allowed = AesonKey.fromText discriminator : fmap (AesonKey.fromText . (.fieldName)) unionCase.unionCaseFields
                    rejectUnknownKeys (label <> ":" <> tag) allowed object
        _ -> parserFailure (cs label <> " must be an object")

validateStringMember :: Text -> [Text] -> Aeson.Value -> AesonTypes.Parser ()
validateStringMember label allowed = \case
    Aeson.String value | value `elem` allowed -> pure ()
    Aeson.String value -> parserFailure (cs label <> " has unsupported value " <> cs value)
    _ -> parserFailure (cs label <> " must be a string")

validateSurfaceScopeValue :: Aeson.Value -> AesonTypes.Parser ()
validateSurfaceScopeValue = validateSurfaceScopeValueWith checkedContractIR

validateSurfaceScopeValueWith :: Contract.FrontendContractIR -> Aeson.Value -> AesonTypes.Parser ()
validateSurfaceScopeValueWith contract = \case
    Aeson.Object object -> do
        surfaceName <- parseTextField object surfaceFieldName
        scope <- parseRequiredField object scopeFieldName
        case find ((== surfaceName) . (.surfaceName)) contract.contractSurfaces of
            Nothing -> parserFailure ("unknown surface scope " <> cs surfaceName)
            Just surfaceIR ->
                case surfaceIR.surfaceScopes of
                    [scopeIR] -> validateFieldObject contract ("surface scope " <> surfaceName) scopeIR.scopeFields scope
                    [] -> parserFailure ("surface " <> cs surfaceName <> " has no registered scope")
                    _ -> parserFailure ("surface " <> cs surfaceName <> " has multiple registered scopes")
        rejectUnknownKeys "SurfaceScope" (fmap AesonKey.fromText [surfaceFieldName, scopeFieldName]) object
    _ -> parserFailure "SurfaceScope must be an object"
  where
    surfaceFieldName = Contract.surfaceWireFieldName Contract.SurfaceWireSurfaceField
    scopeFieldName = Contract.surfaceWireFieldName Contract.SurfaceWireScopeField

validateSurfaceFragmentKeyValue :: Aeson.Value -> AesonTypes.Parser ()
validateSurfaceFragmentKeyValue = validateSurfaceFragmentKeyValueWith checkedContractIR

validateSurfaceFragmentKeyValueWith :: Contract.FrontendContractIR -> Aeson.Value -> AesonTypes.Parser ()
validateSurfaceFragmentKeyValueWith contract = \case
    Aeson.Object object -> do
        surfaceName <- parseTextField object surfaceFieldName
        kind <- parseTextField object kindFieldName
        params <- parseRequiredField object paramsFieldName
        case find ((== surfaceName) . (.surfaceName)) contract.contractSurfaces of
            Nothing -> parserFailure ("unknown surface fragment " <> cs surfaceName)
            Just surfaceIR ->
                case [fragment.fragmentParams | fragment <- surfaceIR.surfaceFragments, fragment.fragmentName == kind] of
                    [fields] -> validateFieldObject contract ("surface fragment " <> surfaceName <> ":" <> kind) fields params
                    [] -> parserFailure ("unknown fragment " <> cs kind <> " on surface " <> cs surfaceName)
                    _ -> parserFailure ("duplicate fragment " <> cs kind <> " on surface " <> cs surfaceName)
        rejectUnknownKeys "SurfaceFragmentKey" (fmap AesonKey.fromText [surfaceFieldName, kindFieldName, paramsFieldName]) object
    _ -> parserFailure "SurfaceFragmentKey must be an object"
  where
    surfaceFieldName = Contract.surfaceWireFieldName Contract.SurfaceWireSurfaceField
    kindFieldName = Contract.surfaceWireFieldName Contract.SurfaceWireKindField
    paramsFieldName = Contract.surfaceWireFieldName Contract.SurfaceWireParamsField

validateFieldObject :: Contract.FrontendContractIR -> Text -> [Contract.FieldIR] -> Aeson.Value -> AesonTypes.Parser ()
validateFieldObject contract label fields value =
    case value of
        Aeson.Null | null fields -> pure ()
        Aeson.Object object -> do
            forM_ fields \field -> validateField contract object field
            rejectUnknownKeys label (fmap (AesonKey.fromText . (.fieldName)) fields) object
        _ -> parserFailure (cs label <> " must be an object")

validateField :: Contract.FrontendContractIR -> KeyMap.KeyMap Aeson.Value -> Contract.FieldIR -> AesonTypes.Parser ()
validateField contract object field = do
    let key = AesonKey.fromText field.fieldName
    case (KeyMap.lookup key object, field.fieldPresence) of
        (Nothing, Contract.OptionalFieldPresence) -> pure ()
        (Nothing, _) -> parserFailure ("missing required field " <> cs field.fieldName)
        (Just Aeson.Null, Contract.NullableFieldPresence) -> pure ()
        (Just fieldValue, _) -> validateWireValueWith contract field.fieldName field.fieldWire fieldValue

validateWireValue :: Text -> Contract.WireIR -> Aeson.Value -> AesonTypes.Parser ()
validateWireValue = validateWireValueWith checkedContractIR

validateWireValueWith :: Contract.FrontendContractIR -> Text -> Contract.WireIR -> Aeson.Value -> AesonTypes.Parser ()
validateWireValueWith contract fieldName wire value =
    case wire of
        Contract.WireTextIR -> expectString
        Contract.WireIntIR -> expectInt
        Contract.WireBoolIR -> expectBool
        Contract.WireUuidIR -> expectString
        Contract.WireDayIR -> expectString
        Contract.WireClosedIR refName _ _ -> validateContractValueWithName contract refName value
        Contract.WireDomainIR {} -> expectString
        Contract.WireUnknownIR -> pure ()
        Contract.WireListIR inner -> case value of
            Aeson.Array items -> mapM_ (validateWireValueWith contract fieldName inner) items
            _ -> typeError "array"
        Contract.WireMapIR _key valueWire -> case value of
            Aeson.Object object -> mapM_ (validateWireValueWith contract fieldName valueWire) (KeyMap.elems object)
            _ -> typeError "object"
        Contract.WireOptionalIR inner ->
            if value == Aeson.Null then pure () else validateWireValueWith contract fieldName inner value
        Contract.WireNullableIR inner ->
            if value == Aeson.Null then pure () else validateWireValueWith contract fieldName inner value
        Contract.WireRefIR refName -> validateContractValueWithName contract refName value
        Contract.WireSurfaceScopeIR -> validateSurfaceScopeValueWith contract value
        Contract.WireSurfaceFragmentKeyIR -> validateSurfaceFragmentKeyValueWith contract value
    where
        expectString = case value of
            Aeson.String _ -> pure ()
            _              -> typeError "string"
        expectInt = case value of
            Aeson.Number number | Scientific.isInteger number -> pure ()
            _ -> typeError "integer"
        expectBool = case value of
            Aeson.Bool _ -> pure ()
            _            -> typeError "boolean"
        typeError expected = parserFailure ("field " <> cs fieldName <> " must be " <> expected)

parseTextField :: KeyMap.KeyMap Aeson.Value -> Text -> AesonTypes.Parser Text
parseTextField object name =
    case KeyMap.lookup (AesonKey.fromText name) object of
        Just (Aeson.String value) -> pure value
        Just _                    -> parserFailure (cs name <> " must be a string")
        Nothing                   -> parserFailure ("missing required field " <> cs name)

parseRequiredField :: KeyMap.KeyMap Aeson.Value -> Text -> AesonTypes.Parser Aeson.Value
parseRequiredField object name =
    case KeyMap.lookup (AesonKey.fromText name) object of
        Just value -> pure value
        Nothing    -> parserFailure ("missing required field " <> cs name)

typeMarker :: forall marker. Typeable marker => Text
typeMarker = cs (tyConName (typeRepTyCon (typeRep (Proxy @marker))))

rejectUnknownKeys :: Text -> [AesonKey.Key] -> KeyMap.KeyMap Aeson.Value -> AesonTypes.Parser ()
rejectUnknownKeys label allowed object =
    case filter (`notElem` allowed) (KeyMap.keys object) of
        [] -> pure ()
        unknownKey : _ -> parserFailure (cs label <> " has unknown field " <> AesonKey.toString unknownKey)
