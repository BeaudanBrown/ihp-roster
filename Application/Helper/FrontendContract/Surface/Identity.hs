{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Application.Helper.FrontendContract.Surface.Identity
    ( SurfaceScopeIdentitySegment (..)
    , canonicalFrontendSurfaceScopeKeyFromFields
    , canonicalFrontendSurfaceScopeKeyFromTypedValues
    ) where

import Application.Error.Parser (parserFailure)
import Application.Helper.FrontendContract.Surface.Identity.Types
import qualified Application.Helper.FrontendContract.IR as Contract
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Aeson.Key
import qualified Data.Aeson.KeyMap as Aeson.KeyMap
import qualified Data.Aeson.Types as Aeson
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Scientific as Scientific
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import qualified Data.UUID as UUID
import IHP.Prelude

canonicalFrontendSurfaceScopeKeyFromTypedValues :: Text -> [SurfaceScopeIdentitySegment] -> Text
canonicalFrontendSurfaceScopeKeyFromTypedValues surfaceName segments =
    Text.intercalate ":" (surfaceName : fmap renderSegment segments)
  where
    renderSegment (SurfaceScopePresent value) = escapeSegment value
    renderSegment SurfaceScopeMissing         = "~missing"
    renderSegment SurfaceScopeNull            = "~null"

-- | Canonicalize a scope already checked and constructed through a
-- marker-indexed Surface declaration. Unlike the wire-boundary entrypoint this
-- does not require membership in the production registry, so unregistered
-- compiled fixtures exercise the exact same stable-key algorithm.
canonicalFrontendSurfaceScopeKeyFromFields ::
    Text ->
    [Contract.FieldIR] ->
    Aeson.Value ->
    Aeson.Parser Text
canonicalFrontendSurfaceScopeKeyFromFields surfaceName fields scopePayload = do
    object <-
        case scopePayload of
            Aeson.Object value -> pure value
            Aeson.Null | null fields -> pure mempty
            _ -> parserFailure ("Invalid frontend Surface scope payload: " <> cs surfaceName)
    segments <- mapM (canonicalFieldSegment object) fields
    pure (Text.intercalate ":" (surfaceName : segments))

canonicalFieldSegment :: Aeson.Object -> Contract.FieldIR -> Aeson.Parser Text
canonicalFieldSegment object field =
    case Aeson.KeyMap.lookup (Aeson.Key.fromText field.fieldName) object of
        Nothing | field.fieldPresence == Contract.OptionalFieldPresence -> pure "~missing"
        Nothing -> parserFailure ("Missing frontend Surface scope field: " <> cs field.fieldName)
        Just Aeson.Null | field.fieldPresence == Contract.NullableFieldPresence -> pure "~null"
        Just value -> canonicalWireSegment field.fieldWire value

canonicalWireSegment :: Contract.WireIR -> Aeson.Value -> Aeson.Parser Text
canonicalWireSegment wire value =
    case wire of
        Contract.WireTextIR -> escapedText value
        Contract.WireIntIR ->
            case value of
                Aeson.Number number -> maybe (parserFailure "Surface scope integer is out of range") (pure . tshow) (Scientific.toBoundedInteger @Int number)
                _ -> parserFailure "Surface scope integer must be an integer"
        Contract.WireBoolIR ->
            case value of
                Aeson.Bool True -> pure "true"
                Aeson.Bool False -> pure "false"
                _ -> parserFailure "Surface scope boolean must be a boolean"
        Contract.WireUuidIR ->
            case value of
                Aeson.String text -> maybe (parserFailure "Surface scope UUID is malformed") (pure . UUID.toText) (UUID.fromText text)
                _ -> parserFailure "Surface scope UUID must be a string"
        Contract.WireDayIR -> escapedText value
        Contract.WireClosedIR {} -> escapedText value
        Contract.WireDomainIR {} -> escapedText value
        Contract.WireOptionalIR inner -> canonicalWireSegment inner value
        Contract.WireNullableIR _ | value == Aeson.Null -> pure "~null"
        Contract.WireNullableIR inner -> canonicalWireSegment inner value
        Contract.WireListIR _ -> canonicalJsonSegment value
        Contract.WireMapIR _ _ -> canonicalJsonSegment value
        Contract.WireRefIR _ -> canonicalJsonSegment value
        Contract.WireUnknownIR -> canonicalJsonSegment value
        Contract.WireSurfaceScopeIR -> parserFailure "Nested Surface scopes cannot define scope identity"
        Contract.WireSurfaceFragmentKeyIR -> parserFailure "Surface fragment keys cannot define scope identity"
    where
        escapedText = \case
            Aeson.String text -> pure (escapeSegment text)
            _ -> parserFailure "Surface scope text must be a string"

canonicalJsonSegment :: Aeson.Value -> Aeson.Parser Text
canonicalJsonSegment = pure . escapeSegment . TextEncoding.decodeUtf8 . LBS.toStrict . Aeson.encode

escapeSegment :: Text -> Text
escapeSegment =
    Text.replace ":" "%3A"
        . Text.replace "~" "%7E"
        . Text.replace "%" "%25"
