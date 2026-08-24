{-# LANGUAGE AllowAmbiguousTypes  #-}
{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE GADTs                #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE TypeApplications     #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}

-- | Complete request parsing for Surface-owned action and intent fields.
--
-- Route parameters, CSRF details, and unrelated request context are deliberately
-- ignored. Every field declared by the selected action or intent is parsed in
-- declaration order before a nominal operation-indexed bundle is returned.
module Application.Helper.FrontendContract.Surface.Request
    ( KnownSurfaceRequestFields
    , SurfaceRequestFieldError (..)
    , SurfaceRequestFieldErrorKind (..)
    , actionParamsPresent
    , attachSurfaceRequestFieldErrors
    , surfaceRequestFieldErrorsMessage
    , parseActionParamPairs
    , parseActionParams
    , parseIntentParamPairs
    , parseIntentParams
    , parseDeclaredRequestParamPairs
    , parseDeclaredRequestParams
    , parseSurfaceActionParamPairs
    , parseSurfaceActionParams
    , parseSurfaceIntentParamPairs
    , parseSurfaceIntentParams
    ) where

import Application.Helper.FrontendContract.ClosedScalar (KnownClosedScalar,
                                                         closedScalarLiterals,
                                                         parseClosedScalarLiteral)
import qualified Application.Helper.FrontendContract.Naming as Naming
import Application.Helper.FrontendContract.Surface.Diagnostics (AssertSurfaceFieldValue,
                                                                SurfaceFieldPresence (..))
import Application.Helper.FrontendContract.Surface.DSL
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.NominalText (NominalText (parseNominalText))
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as Aeson.Types
import qualified Data.Bifunctor as Bifunctor
import qualified Data.ByteString as ByteString
import Data.Kind (Type)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text.Encoding
import qualified Data.Text.Encoding.Error as Text.Encoding.Error
import Data.Time (defaultTimeLocale, parseTimeM)
import Data.Typeable (Typeable)
import qualified Data.UUID as UUID
import IHP.Controller.Param (allParams)
import IHP.ModelSupport.Types (MetaBag, Violation (TextViolation))
import IHP.Prelude
import Network.Wai (Request)
import Text.Read (reads)

data SurfaceRequestFieldErrorKind
    = MissingSurfaceRequestField
    | MalformedSurfaceRequestField
    deriving (Eq, Show)

data SurfaceRequestFieldError = SurfaceRequestFieldError
    { surfaceRequestFieldErrorName    :: !Text
    , surfaceRequestFieldErrorKind    :: !SurfaceRequestFieldErrorKind
    , surfaceRequestFieldErrorMessage :: !Text
    }
    deriving (Eq, Show)

-- | Attach parse failures to an IHP model's normal field annotation bag. This
-- keeps malformed transport values on the same validation path as domain
-- validation rather than silently replacing them with defaults.
attachSurfaceRequestFieldErrors ::
    ( HasField "meta" model MetaBag
    , SetField "meta" model MetaBag
    ) =>
    [SurfaceRequestFieldError] ->
    model ->
    model
attachSurfaceRequestFieldErrors errors =
    modify #meta (modify #annotations (surfaceRequestAnnotations <>))
  where
    surfaceRequestAnnotations =
        [ (surfaceRequestFieldErrorName, TextViolation surfaceRequestFieldErrorMessage)
        | SurfaceRequestFieldError { surfaceRequestFieldErrorName, surfaceRequestFieldErrorMessage } <- errors
        ]

surfaceRequestFieldErrorsMessage :: [SurfaceRequestFieldError] -> Text
surfaceRequestFieldErrorsMessage errors =
    Text.intercalate "; "
        [ surfaceRequestFieldErrorName <> " " <> surfaceRequestFieldErrorMessage
        | SurfaceRequestFieldError { surfaceRequestFieldErrorName, surfaceRequestFieldErrorMessage } <- errors
        ]

-- | Parse one non-Surface nominal declaration through the same exact field
-- evaluator used by Surface actions and intents.
parseDeclaredRequestParams ::
    forall owner fields.
    ( ?request :: Request
    , KnownSurfaceRequestFields fields
    ) =>
    Either [SurfaceRequestFieldError] (DeclaredRequestFields owner fields)
parseDeclaredRequestParams =
    parseDeclaredRequestParamPairs @owner @fields allParams

-- | Pure pair-based form of 'parseDeclaredRequestParams'.
parseDeclaredRequestParamPairs ::
    forall owner fields.
    KnownSurfaceRequestFields fields =>
    [(ByteString, Maybe ByteString)] ->
    Either [SurfaceRequestFieldError] (DeclaredRequestFields owner fields)
parseDeclaredRequestParamPairs params =
    parsedDeclaredRequestFields @owner
        <$> parseSurfaceRequestFields @fields params

-- | Whether the active request carries at least one field from one generated
-- operation-local Action contract. Generated facades expose named witnesses.
actionParamsPresent ::
    forall operation.
    ( ?request :: Request
    , KnownSurfaceRequestFields (ActionFieldSpecs operation)
    ) =>
    Bool
actionParamsPresent =
    surfaceRequestParamsPresent @(ActionFieldSpecs operation) allParams

-- | Parse one generated operation-local Action contract from the active IHP
-- request. Generated modules are the production call seam.
parseActionParams ::
    forall operation.
    ( ?request :: Request
    , KnownSurfaceRequestFields (ActionFieldSpecs operation)
    ) =>
    Either [SurfaceRequestFieldError] (ActionFields operation)
parseActionParams =
    parseActionParamPairs @operation allParams

-- | Pure pair-based form of 'parseActionParams'.
parseActionParamPairs ::
    forall operation.
    KnownSurfaceRequestFields (ActionFieldSpecs operation) =>
    [(ByteString, Maybe ByteString)] ->
    Either [SurfaceRequestFieldError] (ActionFields operation)
parseActionParamPairs params =
    parsedActionFields @operation
        <$> parseSurfaceRequestFields @(ActionFieldSpecs operation) params

-- | Parse one generated operation-local Intent contract from the active IHP
-- request. Generated modules are the production call seam.
parseIntentParams ::
    forall operation.
    ( ?request :: Request
    , KnownSurfaceRequestFields (IntentFieldSpecs operation)
    ) =>
    Either [SurfaceRequestFieldError] (IntentFields operation)
parseIntentParams =
    parseIntentParamPairs @operation allParams

-- | Pure pair-based form of 'parseIntentParams'.
parseIntentParamPairs ::
    forall operation.
    KnownSurfaceRequestFields (IntentFieldSpecs operation) =>
    [(ByteString, Maybe ByteString)] ->
    Either [SurfaceRequestFieldError] (IntentFields operation)
parseIntentParamPairs params =
    parsedIntentFields @operation
        <$> parseSurfaceRequestFields @(IntentFieldSpecs operation) params

-- | Parse one action's complete declared field contract from the active IHP
-- request. Unknown parameters are intentionally ignored because route and
-- framework context are outside the Surface bundle.
parseSurfaceActionParams ::
    forall spec action.
    ( ?request :: Request
    , KnownSurfaceRequestFields (SurfaceActionFieldSpecs spec action)
    ) =>
    Either [SurfaceRequestFieldError] (SurfaceActionFields spec action)
parseSurfaceActionParams =
    parseSurfaceActionParamPairs @spec @action allParams

-- | Pure pair-based form of 'parseSurfaceActionParams', used at adapter and
-- contract-test boundaries.
parseSurfaceActionParamPairs ::
    forall spec action.
    KnownSurfaceRequestFields (SurfaceActionFieldSpecs spec action) =>
    [(ByteString, Maybe ByteString)] ->
    Either [SurfaceRequestFieldError] (SurfaceActionFields spec action)
parseSurfaceActionParamPairs params =
    parsedSurfaceActionFields @spec @action
        <$> parseSurfaceRequestFields @(SurfaceActionFieldSpecs spec action) params

-- | Parse one intent's complete declared field contract from the active IHP
-- request.
parseSurfaceIntentParams ::
    forall spec intent.
    ( ?request :: Request
    , KnownSurfaceRequestFields (SurfaceIntentFieldSpecs spec intent)
    ) =>
    Either [SurfaceRequestFieldError] (SurfaceIntentFields spec intent)
parseSurfaceIntentParams =
    parseSurfaceIntentParamPairs @spec @intent allParams

-- | Pure pair-based form of 'parseSurfaceIntentParams'.
parseSurfaceIntentParamPairs ::
    forall spec intent.
    KnownSurfaceRequestFields (SurfaceIntentFieldSpecs spec intent) =>
    [(ByteString, Maybe ByteString)] ->
    Either [SurfaceRequestFieldError] (SurfaceIntentFields spec intent)
parseSurfaceIntentParamPairs params =
    parsedSurfaceIntentFields @spec @intent
        <$> parseSurfaceRequestFields @(SurfaceIntentFieldSpecs spec intent) params

data ParsedSurfaceFields (fields :: [FieldSpec]) where
    ParsedNoSurfaceFields ::
        ParsedSurfaceFields '[]
    ParsedRequiredSurfaceField ::
        forall marker wire rest.
        ( Typeable marker
        , KnownSurfaceWireValue wire
        , AssertSurfaceFieldValue 'SurfaceRequired marker wire (SurfaceWireValue wire)
        ) =>
        SurfaceWireValue wire ->
        ParsedSurfaceFields rest ->
        ParsedSurfaceFields (('Field marker wire) ': rest)
    ParsedOptionalSurfaceField ::
        forall marker wire rest.
        ( Typeable marker
        , KnownSurfaceWireValue wire
        , AssertSurfaceFieldValue 'SurfaceOptional marker wire (Maybe (SurfaceWireValue wire))
        ) =>
        Maybe (SurfaceWireValue wire) ->
        ParsedSurfaceFields rest ->
        ParsedSurfaceFields (('OptionalField marker wire) ': rest)
    ParsedNullableSurfaceField ::
        forall marker wire rest.
        ( Typeable marker
        , KnownSurfaceWireValue wire
        , AssertSurfaceFieldValue 'SurfaceNullable marker wire (Maybe (SurfaceWireValue wire))
        ) =>
        Maybe (SurfaceWireValue wire) ->
        ParsedSurfaceFields rest ->
        ParsedSurfaceFields (('NullableField marker wire) ': rest)

parsedDeclaredRequestFields ::
    forall owner fields.
    ParsedSurfaceFields fields ->
    DeclaredRequestFields owner fields
parsedDeclaredRequestFields ParsedNoSurfaceFields = noDeclaredRequestFields
parsedDeclaredRequestFields (ParsedRequiredSurfaceField @marker @wire value rest) =
    declaredRequestFields @owner @fields @'SurfaceRequired @marker @wire
        (surfaceField @marker @wire value)
        (parsedSurfaceFieldsValue rest)
parsedDeclaredRequestFields (ParsedOptionalSurfaceField @marker @wire value rest) =
    declaredRequestFields @owner @fields @'SurfaceOptional @marker @wire
        (surfaceOptionalField @marker @wire value)
        (parsedSurfaceFieldsValue rest)
parsedDeclaredRequestFields (ParsedNullableSurfaceField @marker @wire value rest) =
    declaredRequestFields @owner @fields @'SurfaceNullable @marker @wire
        (surfaceNullableField @marker @wire value)
        (parsedSurfaceFieldsValue rest)

parsedActionFields ::
    forall operation.
    ParsedSurfaceFields (ActionFieldSpecs operation) ->
    ActionFields operation
parsedActionFields ParsedNoSurfaceFields = noActionFields
parsedActionFields (ParsedRequiredSurfaceField @marker @wire value rest) =
    actionFields @operation @'SurfaceRequired @marker @wire
        (surfaceField @marker @wire value)
        (parsedSurfaceFieldsValue rest)
parsedActionFields (ParsedOptionalSurfaceField @marker @wire value rest) =
    actionFields @operation @'SurfaceOptional @marker @wire
        (surfaceOptionalField @marker @wire value)
        (parsedSurfaceFieldsValue rest)
parsedActionFields (ParsedNullableSurfaceField @marker @wire value rest) =
    actionFields @operation @'SurfaceNullable @marker @wire
        (surfaceNullableField @marker @wire value)
        (parsedSurfaceFieldsValue rest)

parsedIntentFields ::
    forall operation.
    ParsedSurfaceFields (IntentFieldSpecs operation) ->
    IntentFields operation
parsedIntentFields ParsedNoSurfaceFields = noIntentFields
parsedIntentFields (ParsedRequiredSurfaceField @marker @wire value rest) =
    intentFields @operation @'SurfaceRequired @marker @wire
        (surfaceField @marker @wire value)
        (parsedSurfaceFieldsValue rest)
parsedIntentFields (ParsedOptionalSurfaceField @marker @wire value rest) =
    intentFields @operation @'SurfaceOptional @marker @wire
        (surfaceOptionalField @marker @wire value)
        (parsedSurfaceFieldsValue rest)
parsedIntentFields (ParsedNullableSurfaceField @marker @wire value rest) =
    intentFields @operation @'SurfaceNullable @marker @wire
        (surfaceNullableField @marker @wire value)
        (parsedSurfaceFieldsValue rest)

parsedSurfaceActionFields ::
    forall spec action.
    ParsedSurfaceFields (SurfaceActionFieldSpecs spec action) ->
    SurfaceActionFields spec action
parsedSurfaceActionFields ParsedNoSurfaceFields = noSurfaceActionFields
parsedSurfaceActionFields (ParsedRequiredSurfaceField @marker @wire value rest) =
    surfaceActionFields @spec @action @'SurfaceRequired @marker @wire
        (surfaceField @marker @wire value)
        (parsedSurfaceFieldsValue rest)
parsedSurfaceActionFields (ParsedOptionalSurfaceField @marker @wire value rest) =
    surfaceActionFields @spec @action @'SurfaceOptional @marker @wire
        (surfaceOptionalField @marker @wire value)
        (parsedSurfaceFieldsValue rest)
parsedSurfaceActionFields (ParsedNullableSurfaceField @marker @wire value rest) =
    surfaceActionFields @spec @action @'SurfaceNullable @marker @wire
        (surfaceNullableField @marker @wire value)
        (parsedSurfaceFieldsValue rest)

parsedSurfaceIntentFields ::
    forall spec intent.
    ParsedSurfaceFields (SurfaceIntentFieldSpecs spec intent) ->
    SurfaceIntentFields spec intent
parsedSurfaceIntentFields ParsedNoSurfaceFields = noSurfaceIntentFields
parsedSurfaceIntentFields (ParsedRequiredSurfaceField @marker @wire value rest) =
    surfaceIntentFields @spec @intent @'SurfaceRequired @marker @wire
        (surfaceField @marker @wire value)
        (parsedSurfaceFieldsValue rest)
parsedSurfaceIntentFields (ParsedOptionalSurfaceField @marker @wire value rest) =
    surfaceIntentFields @spec @intent @'SurfaceOptional @marker @wire
        (surfaceOptionalField @marker @wire value)
        (parsedSurfaceFieldsValue rest)
parsedSurfaceIntentFields (ParsedNullableSurfaceField @marker @wire value rest) =
    surfaceIntentFields @spec @intent @'SurfaceNullable @marker @wire
        (surfaceNullableField @marker @wire value)
        (parsedSurfaceFieldsValue rest)

parsedSurfaceFieldsValue :: ParsedSurfaceFields fields -> SurfaceFields fields
parsedSurfaceFieldsValue = \case
    ParsedNoSurfaceFields -> noSurfaceFields
    ParsedRequiredSurfaceField @marker @wire value rest ->
        prependRequiredSurfaceField @marker @wire value (parsedSurfaceFieldsValue rest)
    ParsedOptionalSurfaceField @marker @wire value rest ->
        prependOptionalSurfaceField @marker @wire value (parsedSurfaceFieldsValue rest)
    ParsedNullableSurfaceField @marker @wire value rest ->
        prependNullableSurfaceField @marker @wire value (parsedSurfaceFieldsValue rest)

class KnownSurfaceRequestFields (fields :: [FieldSpec]) where
    surfaceRequestFieldNames :: [ByteString]
    parseSurfaceRequestFields ::
        [(ByteString, Maybe ByteString)] ->
        Either [SurfaceRequestFieldError] (ParsedSurfaceFields fields)

instance KnownSurfaceRequestFields '[] where
    surfaceRequestFieldNames = []
    parseSurfaceRequestFields _ = Right ParsedNoSurfaceFields

instance
    ( Typeable marker
    , KnownSurfaceWireValue wire
    , KnownSurfaceRequestWire wire
    , KnownSurfaceRequestFields rest
    , AssertSurfaceFieldValue 'SurfaceRequired marker wire (SurfaceWireValue wire)
    ) => KnownSurfaceRequestFields (('Field marker wire) ': rest) where
    surfaceRequestFieldNames = cs (surfaceMarkerFieldName @marker) : surfaceRequestFieldNames @rest
    parseSurfaceRequestFields params =
        combineFieldResult requiredValue (parseSurfaceRequestFields @rest params) $ \value rest ->
            ParsedRequiredSurfaceField @marker @wire value rest
      where
        requiredValue =
            case requestParamValues @marker params of
                [] -> Left [missingFieldError @marker]
                rawValues ->
                    Bifunctor.first (pure . malformedFieldError @marker) (parseSurfaceRequestWireValues @wire rawValues)

instance
    ( Typeable marker
    , KnownSurfaceWireValue wire
    , KnownSurfaceRequestWire wire
    , KnownSurfaceRequestFields rest
    , AssertSurfaceFieldValue 'SurfaceOptional marker wire (Maybe (SurfaceWireValue wire))
    ) => KnownSurfaceRequestFields (('OptionalField marker wire) ': rest) where
    surfaceRequestFieldNames = cs (surfaceMarkerFieldName @marker) : surfaceRequestFieldNames @rest
    parseSurfaceRequestFields params =
        combineFieldResult optionalValue (parseSurfaceRequestFields @rest params) $ \value rest ->
            ParsedOptionalSurfaceField @marker @wire value rest
      where
        optionalValue =
            case requestParamValues @marker params of
                [] -> Right Nothing
                [rawValue]
                    | ByteString.null rawValue -> Right Nothing
                rawValues ->
                    Bifunctor.first (pure . malformedFieldError @marker) (Just <$> parseSurfaceRequestWireValues @wire rawValues)

instance
    ( Typeable marker
    , KnownSurfaceWireValue wire
    , KnownSurfaceRequestWire wire
    , KnownSurfaceRequestFields rest
    , AssertSurfaceFieldValue 'SurfaceNullable marker wire (Maybe (SurfaceWireValue wire))
    ) => KnownSurfaceRequestFields (('NullableField marker wire) ': rest) where
    surfaceRequestFieldNames = cs (surfaceMarkerFieldName @marker) : surfaceRequestFieldNames @rest
    parseSurfaceRequestFields params =
        combineFieldResult nullableValue (parseSurfaceRequestFields @rest params) $ \value rest ->
            ParsedNullableSurfaceField @marker @wire value rest
      where
        nullableValue =
            case requestParamValues @marker params of
                [] -> Left [missingFieldError @marker]
                [rawValue]
                    | ByteString.null rawValue -> Right Nothing
                rawValues ->
                    Bifunctor.first (pure . malformedFieldError @marker) (Just <$> parseSurfaceRequestWireValues @wire rawValues)

surfaceRequestParamsPresent ::
    forall fields.
    KnownSurfaceRequestFields fields =>
    [(ByteString, Maybe ByteString)] ->
    Bool
surfaceRequestParamsPresent params =
    any (\(name, _) -> name `elem` surfaceRequestFieldNames @fields) params

combineFieldResult ::
    Either [SurfaceRequestFieldError] field ->
    Either [SurfaceRequestFieldError] rest ->
    (field -> rest -> result) ->
    Either [SurfaceRequestFieldError] result
combineFieldResult fieldResult restResult build =
    case (fieldResult, restResult) of
        (Right field, Right rest)           -> Right (build field rest)
        (Left fieldErrors, Left restErrors) -> Left (fieldErrors <> restErrors)
        (Left fieldErrors, Right _)         -> Left fieldErrors
        (Right _, Left restErrors)          -> Left restErrors

requestParamValues :: forall marker. Typeable marker => [(ByteString, Maybe ByteString)] -> [ByteString]
requestParamValues params =
    [ fromMaybe "" maybeValue
    | (name, maybeValue) <- params
    , name == cs (surfaceMarkerFieldName @marker)
    ]

missingFieldError :: forall marker. Typeable marker => SurfaceRequestFieldError
missingFieldError =
    SurfaceRequestFieldError
        { surfaceRequestFieldErrorName = surfaceMarkerFieldName @marker
        , surfaceRequestFieldErrorKind = MissingSurfaceRequestField
        , surfaceRequestFieldErrorMessage = "is required by the Surface request contract"
        }

malformedFieldError :: forall marker. Typeable marker => Text -> SurfaceRequestFieldError
malformedFieldError message =
    SurfaceRequestFieldError
        { surfaceRequestFieldErrorName = surfaceMarkerFieldName @marker
        , surfaceRequestFieldErrorKind = MalformedSurfaceRequestField
        , surfaceRequestFieldErrorMessage = message
        }

surfaceMarkerFieldName :: forall marker. Typeable marker => Text
surfaceMarkerFieldName =
    Naming.deriveFrontendSurfaceTypeName @marker Naming.FieldName

class KnownSurfaceRequestWire (wire :: WireType) where
    parseSurfaceRequestWire :: ByteString -> Either Text (SurfaceWireValue wire)
    parseSurfaceRequestWireValues :: [ByteString] -> Either Text (SurfaceWireValue wire)
    parseSurfaceRequestWireValues [] = Left "must be present"
    parseSurfaceRequestWireValues [rawValue] = parseSurfaceRequestWire @wire rawValue
    parseSurfaceRequestWireValues _ = Left "must be submitted once"

instance KnownSurfaceRequestWire 'WireText where
    parseSurfaceRequestWire =
        Bifunctor.first (const "must be valid UTF-8 text") . Text.Encoding.decodeUtf8'

instance KnownSurfaceRequestWire 'WireInt where
    parseSurfaceRequestWire rawValue =
        case reads (cs rawValue) of
            [(value, "")] -> Right value
            _             -> Left "must be an integer"

instance KnownSurfaceRequestWire 'WireBool where
    parseSurfaceRequestWire rawValue =
        case Text.toLower (decodeLenient rawValue) of
            "true"  -> Right True
            "false" -> Right False
            "on"    -> Right True
            "off"   -> Right False
            _       -> Left "must be true or false"

instance KnownSurfaceRequestWire 'WireUUID where
    parseSurfaceRequestWire rawValue =
        maybe (Left "must be a UUID") Right (UUID.fromASCIIBytes rawValue)

instance KnownSurfaceRequestWire 'WireDay where
    parseSurfaceRequestWire rawValue =
        maybe
            (Left "must be a date in YYYY-MM-DD format")
            Right
            (parseTimeM True defaultTimeLocale "%F" (cs rawValue))

instance KnownClosedScalar value => KnownSurfaceRequestWire ('WireClosed value) where
    parseSurfaceRequestWire rawValue = do
        literal <- Bifunctor.first (const "must be valid UTF-8 text") (Text.Encoding.decodeUtf8' rawValue)
        maybe
            (Left ("must be one of: " <> Text.intercalate ", " (closedScalarLiterals @value)))
            Right
            (parseClosedScalarLiteral @value literal)

instance NominalText value => KnownSurfaceRequestWire ('WireDomain value) where
    parseSurfaceRequestWire rawValue = do
        literal <- Bifunctor.first (const "must be valid UTF-8 text") (Text.Encoding.decodeUtf8' rawValue)
        parseNominalText literal

instance (KnownSurfaceWireValue inner, KnownSurfaceRequestWire inner) => KnownSurfaceRequestWire ('WireList inner) where
    parseSurfaceRequestWire = parseJsonWire @('WireList inner)
    parseSurfaceRequestWireValues [rawValue]
        | "[" `ByteString.isPrefixOf` rawValue = parseSurfaceRequestWire @('WireList inner) rawValue
    parseSurfaceRequestWireValues rawValues = mapM (parseSurfaceRequestWire @inner) rawValues

instance KnownSurfaceRequestWire inner => KnownSurfaceRequestWire ('WireOptional inner) where
    parseSurfaceRequestWire rawValue
        | ByteString.null rawValue = Right Nothing
        | otherwise = Just <$> parseSurfaceRequestWire @inner rawValue

instance KnownSurfaceRequestWire inner => KnownSurfaceRequestWire ('WireNullable inner) where
    parseSurfaceRequestWire rawValue
        | ByteString.null rawValue = Right Nothing
        | otherwise = Just <$> parseSurfaceRequestWire @inner rawValue

instance KnownSurfaceRequestWire ('WireRef dto) where
    parseSurfaceRequestWire rawValue =
        Bifunctor.first (const "must be valid JSON") (Aeson.eitherDecodeStrict' rawValue)

parseJsonWire :: forall wire. KnownSurfaceWireValue wire => ByteString -> Either Text (SurfaceWireValue wire)
parseJsonWire rawValue = do
    jsonValue <- Bifunctor.first (const "must be valid JSON") (Aeson.eitherDecodeStrict' rawValue)
    Bifunctor.first Text.pack (Aeson.Types.parseEither (parseSurfaceWireValue @wire) jsonValue)

decodeLenient :: ByteString -> Text
decodeLenient = Text.Encoding.decodeUtf8With Text.Encoding.Error.lenientDecode
