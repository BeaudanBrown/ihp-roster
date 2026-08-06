{-# LANGUAGE AllowAmbiguousTypes  #-}
{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE TypeApplications     #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}

module Application.Helper.FrontendContract.Toggle.Runtime
    ( ToggleBreakRegion
    , ToggleDomAttributes (..)
    , ToggleFieldBinding
    , TogglePresentationState (..)
    , ToggleSubmissionPolicy (..)
    , ToggleTarget (..)
    , ToggleScalarFieldValue
    , ToggleListItemValue
    , canonicalToggleDomAttributes
    , namedBooleanToggleField
    , surfaceToggleListItemField
    , surfaceToggleScalarField
    , toggleBreakRegion
    , toggleBreakRegionId
    , toggleBreakRegionKey
    , toggleConfigJson
    , toggleFieldName
    , togglePresentationState
    , togglePresentationStateValue
    , toggleTargetForState
    , toggleTransportKey
    ) where

import Application.Helper.FrontendContract.ClosedScalar (KnownClosedScalar)
import Application.Helper.FrontendContract.Surface.DSL (WireType (..))
import Application.Helper.FrontendContract.Surface.Values hiding ((&:))
import qualified Application.Helper.FrontendContract.Toggle as Contract
import Application.Helper.FrontendContract.Values (domAttrValue,
                                                   enumLiteralValue)
import Application.Helper.FrontendContract.Wire.Carrier
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import Data.Typeable (Typeable)
import IHP.Prelude

-- | Closed browser presentation state. This remains distinct from either wire
-- target: an inverted toggle can be checked while submitting @false@.
data TogglePresentationState
    = ToggleChecked
    | ToggleUnchecked
    deriving (Eq, Show)

-- | Whether the generic browser adapter submits the containing form after it
-- has synchronized the form-local transport control.
data ToggleSubmissionPolicy
    = ToggleSubmitDeferred
    | ToggleSubmitImmediate
    deriving (Eq, Show)

-- | Exact transport behavior for one presentation state. Omission is explicit
-- for repeated/list fields; scalar fields always carry a concrete value.
data ToggleTarget
    = ToggleTargetValue !Text
    | ToggleTargetOmitted
    deriving (Eq, Show)

-- | Opaque, declaration-checked association between a form field and its two
-- browser target states.
data ToggleFieldBinding = ToggleFieldBinding
    { fieldBindingName            :: !Text
    , fieldBindingCheckedTarget   :: !ToggleTarget
    , fieldBindingUncheckedTarget :: !ToggleTarget
    }
    deriving (Eq, Show)

-- | Opaque relationship to a native fieldset controlled by a toggle. Browser
-- lookup remains inside the containing form and does not depend on this id;
-- the id exists for the native aria-controls relationship.
data ToggleBreakRegion = ToggleBreakRegion
    { breakRegionId  :: !Text
    , breakRegionKey :: !Text
    }
    deriving (Eq, Show)

data ToggleDomAttributes = ToggleDomAttributes
    { toggleRootAttribute        :: !Text
    , toggleInputAttribute       :: !Text
    , toggleLabelStateAttribute  :: !Text
    , toggleTransportAttribute   :: !Text
    , toggleBreakRegionAttribute :: !Text
    , toggleConfigAttribute      :: !Text
    }
    deriving (Eq, Show)

canonicalToggleDomAttributes :: ToggleDomAttributes
canonicalToggleDomAttributes = ToggleDomAttributes
    { toggleRootAttribute = domAttrValue @Contract.ToggleRoot
    , toggleInputAttribute = domAttrValue @Contract.ToggleInput
    , toggleLabelStateAttribute = domAttrValue @Contract.ToggleLabelState
    , toggleTransportAttribute = domAttrValue @Contract.ToggleTransport
    , toggleBreakRegionAttribute = domAttrValue @Contract.ToggleBreakRegion
    , toggleConfigAttribute = domAttrValue @Contract.ToggleConfig
    }

-- | Scalar values supported by a checkbox presentation. The value remains the
-- declaration's Haskell source type until this final text transport boundary.
class KnownToggleScalarWire (wire :: WireType) where
    toggleScalarTarget :: SurfaceWireValue wire -> ToggleTarget

instance KnownToggleScalarWire 'WireText where
    toggleScalarTarget = ToggleTargetValue . surfaceWireText @'WireText

instance KnownToggleScalarWire 'WireInt where
    toggleScalarTarget = ToggleTargetValue . surfaceWireText @'WireInt

instance KnownToggleScalarWire 'WireBool where
    toggleScalarTarget = ToggleTargetValue . surfaceWireText @'WireBool

instance KnownToggleScalarWire 'WireUUID where
    toggleScalarTarget = ToggleTargetValue . surfaceWireText @'WireUUID

instance KnownToggleScalarWire 'WireDay where
    toggleScalarTarget = ToggleTargetValue . surfaceWireText @'WireDay

instance KnownClosedScalar value => KnownToggleScalarWire ('WireClosed value) where
    toggleScalarTarget = ToggleTargetValue . surfaceWireText @('WireClosed value)

type family ToggleScalarFieldValue (lookup :: SurfaceFieldLookup) :: Type where
    ToggleScalarFieldValue ('SurfaceFieldRequired wire) = SurfaceWireValue wire
    ToggleScalarFieldValue ('SurfaceFieldOptional wire) = SurfaceWireValue wire
    ToggleScalarFieldValue ('SurfaceFieldNullable wire) = SurfaceWireValue wire

class KnownToggleScalarField (lookup :: SurfaceFieldLookup) where
    scalarFieldTarget :: ToggleScalarFieldValue lookup -> ToggleTarget

instance KnownToggleScalarWire wire => KnownToggleScalarField ('SurfaceFieldRequired wire) where
    scalarFieldTarget = toggleScalarTarget @wire

instance KnownToggleScalarWire wire => KnownToggleScalarField ('SurfaceFieldOptional wire) where
    scalarFieldTarget = toggleScalarTarget @wire

instance KnownToggleScalarWire wire => KnownToggleScalarField ('SurfaceFieldNullable wire) where
    scalarFieldTarget = toggleScalarTarget @wire

-- | Construct a scalar binding only after a complete generated Action bundle
-- proves that the marker belongs to that operation. Checked and unchecked
-- values must have the field's declared wire source type.
surfaceToggleScalarField ::
    forall marker bundle.
    ( SurfaceFieldBundle bundle
    , Typeable marker
    , KnownSurfaceFieldLookup (LookupSurfaceField marker (SurfaceFieldBundleSpecs bundle))
    , KnownToggleScalarField (LookupSurfaceField marker (SurfaceFieldBundleSpecs bundle))
    ) =>
    bundle ->
    ToggleScalarFieldValue (LookupSurfaceField marker (SurfaceFieldBundleSpecs bundle)) ->
    ToggleScalarFieldValue (LookupSurfaceField marker (SurfaceFieldBundleSpecs bundle)) ->
    ToggleFieldBinding
surfaceToggleScalarField fields checkedValue uncheckedValue =
    checkedToggleFieldBinding
        (surfaceFieldNameFrom @marker fields)
        (scalarFieldTarget @(LookupSurfaceField marker (SurfaceFieldBundleSpecs bundle)) checkedValue)
        (scalarFieldTarget @(LookupSurfaceField marker (SurfaceFieldBundleSpecs bundle)) uncheckedValue)

type family ToggleListItemValue (lookup :: SurfaceFieldLookup) :: Type where
    ToggleListItemValue ('SurfaceFieldRequired ('WireList inner)) = SurfaceWireValue inner
    ToggleListItemValue ('SurfaceFieldOptional ('WireList inner)) = SurfaceWireValue inner
    ToggleListItemValue ('SurfaceFieldNullable ('WireList inner)) = SurfaceWireValue inner

class KnownToggleListField (lookup :: SurfaceFieldLookup) where
    listItemTarget :: ToggleListItemValue lookup -> ToggleTarget

instance KnownSurfaceWireValue inner => KnownToggleListField ('SurfaceFieldRequired ('WireList inner)) where
    listItemTarget = ToggleTargetValue . surfaceWireText @inner

instance KnownSurfaceWireValue inner => KnownToggleListField ('SurfaceFieldOptional ('WireList inner)) where
    listItemTarget = ToggleTargetValue . surfaceWireText @inner

instance KnownSurfaceWireValue inner => KnownToggleListField ('SurfaceFieldNullable ('WireList inner)) where
    listItemTarget = ToggleTargetValue . surfaceWireText @inner

-- | Construct one repeated-field transport. The checked state contributes one
-- declaration-typed list item; the unchecked state explicitly omits it.
surfaceToggleListItemField ::
    forall marker bundle.
    ( SurfaceFieldBundle bundle
    , Typeable marker
    , KnownSurfaceFieldLookup (LookupSurfaceField marker (SurfaceFieldBundleSpecs bundle))
    , KnownToggleListField (LookupSurfaceField marker (SurfaceFieldBundleSpecs bundle))
    ) =>
    bundle ->
    ToggleListItemValue (LookupSurfaceField marker (SurfaceFieldBundleSpecs bundle)) ->
    ToggleFieldBinding
surfaceToggleListItemField fields itemValue =
    checkedToggleFieldBinding
        (surfaceFieldNameFrom @marker fields)
        (listItemTarget @(LookupSurfaceField marker (SurfaceFieldBundleSpecs bundle)) itemValue)
        ToggleTargetOmitted

-- | Native business forms outside a Surface request declaration can still use
-- the capability without spelling boolean wire mappings at the feature view.
namedBooleanToggleField :: Text -> ToggleFieldBinding
namedBooleanToggleField fieldName =
    checkedToggleFieldBinding
        fieldName
        (toggleScalarTarget @'WireBool True)
        (toggleScalarTarget @'WireBool False)

checkedToggleFieldBinding :: Text -> ToggleTarget -> ToggleTarget -> ToggleFieldBinding
checkedToggleFieldBinding fieldName checkedTarget uncheckedTarget
    | Text.null (Text.strip fieldName) = error "Toggle transport field name must not be empty"
    | checkedTarget == uncheckedTarget = error "Toggle checked and unchecked transport targets must differ"
    | otherwise = ToggleFieldBinding
        { fieldBindingName = fieldName
        , fieldBindingCheckedTarget = checkedTarget
        , fieldBindingUncheckedTarget = uncheckedTarget
        }

toggleFieldName :: ToggleFieldBinding -> Text
toggleFieldName = (.fieldBindingName)

togglePresentationState :: Bool -> TogglePresentationState
togglePresentationState True  = ToggleChecked
togglePresentationState False = ToggleUnchecked

togglePresentationStateValue :: TogglePresentationState -> Text
togglePresentationStateValue = presentationStateText

toggleTargetForState :: ToggleFieldBinding -> TogglePresentationState -> ToggleTarget
toggleTargetForState binding ToggleChecked   = binding.fieldBindingCheckedTarget
toggleTargetForState binding ToggleUnchecked = binding.fieldBindingUncheckedTarget

toggleTransportKey :: Text -> Text
toggleTransportKey inputId
    | Text.null (Text.strip inputId) = error "Toggle input id must not be empty"
    | otherwise = "toggle-transport:" <> inputId

toggleBreakRegion :: Text -> ToggleBreakRegion
toggleBreakRegion regionId
    | Text.null (Text.strip regionId) = error "Toggle break region id must not be empty"
    | otherwise = ToggleBreakRegion
        { breakRegionId = regionId
        , breakRegionKey = "toggle-break-region:" <> regionId
        }

toggleBreakRegionId :: ToggleBreakRegion -> Text
toggleBreakRegionId = (.breakRegionId)

toggleBreakRegionKey :: ToggleBreakRegion -> Text
toggleBreakRegionKey = (.breakRegionKey)

data ToggleConfigValue = ToggleConfigValue
    { configPresentationState :: !TogglePresentationState
    , configCheckedTarget     :: !ToggleTarget
    , configUncheckedTarget   :: !ToggleTarget
    , configTransportKey      :: !Text
    , configSubmissionPolicy  :: !ToggleSubmissionPolicy
    , configBreakRegionKey    :: !(Maybe Text)
    }

toggleConfigJson :: Text -> ToggleFieldBinding -> Bool -> ToggleSubmissionPolicy -> Maybe ToggleBreakRegion -> Text
toggleConfigJson inputId binding checked submissionPolicy maybeBreakRegion =
    TextEncoding.decodeUtf8 (LBS.toStrict (Aeson.encode config))
  where
    config = ToggleConfigValue
        { configPresentationState = togglePresentationState checked
        , configCheckedTarget = binding.fieldBindingCheckedTarget
        , configUncheckedTarget = binding.fieldBindingUncheckedTarget
        , configTransportKey = toggleTransportKey inputId
        , configSubmissionPolicy = submissionPolicy
        , configBreakRegionKey = toggleBreakRegionKey <$> maybeBreakRegion
        }

instance ContractReference Contract.TogglePresentationState where
    type ContractReferenceValue Contract.TogglePresentationState = TogglePresentationState
    contractReferenceJson = Aeson.String . presentationStateText
    parseContractReference = Aeson.withText "TogglePresentationState" \value ->
        case value of
            _ | value == presentationStateText ToggleChecked -> pure ToggleChecked
            _ | value == presentationStateText ToggleUnchecked -> pure ToggleUnchecked
            _ -> fail "Unknown TogglePresentationState"

instance ContractReference Contract.ToggleSubmissionPolicy where
    type ContractReferenceValue Contract.ToggleSubmissionPolicy = ToggleSubmissionPolicy
    contractReferenceJson = Aeson.String . submissionPolicyText
    parseContractReference = Aeson.withText "ToggleSubmissionPolicy" \value ->
        case value of
            _ | value == submissionPolicyText ToggleSubmitDeferred -> pure ToggleSubmitDeferred
            _ | value == submissionPolicyText ToggleSubmitImmediate -> pure ToggleSubmitImmediate
            _ -> fail "Unknown ToggleSubmissionPolicy"

instance ContractReference Contract.ToggleTarget where
    type ContractReferenceValue Contract.ToggleTarget = ToggleTarget
    contractReferenceJson = Aeson.toJSON
    parseContractReference = Aeson.parseJSON

instance Aeson.ToJSON ToggleTarget where
    toJSON (ToggleTargetValue value) =
        taggedUnionValue @Contract.ToggleTarget @Contract.Value
            (requiredField @Contract.Value value &: noFields)
    toJSON ToggleTargetOmitted =
        taggedUnionValue @Contract.ToggleTarget @Contract.Omitted noFields

instance Aeson.FromJSON ToggleTarget where
    parseJSON =
        parseTaggedUnion @Contract.ToggleTarget
            ( unionCase @Contract.Value (\(value, ()) -> pure (ToggleTargetValue value))
                |: unionCase @Contract.Omitted (\() -> pure ToggleTargetOmitted)
                |: noUnionCases
            )

instance Aeson.ToJSON ToggleConfigValue where
    toJSON ToggleConfigValue { configPresentationState, configCheckedTarget, configUncheckedTarget, configTransportKey, configSubmissionPolicy, configBreakRegionKey } =
        recordValue @Contract.ToggleConfig
            ( requiredField @Contract.PresentationState configPresentationState
                &: requiredField @Contract.CheckedTarget configCheckedTarget
                &: requiredField @Contract.UncheckedTarget configUncheckedTarget
                &: requiredField @Contract.TransportKey configTransportKey
                &: requiredField @Contract.SubmissionPolicy configSubmissionPolicy
                &: nullableField @Contract.BreakRegionKey configBreakRegionKey
                &: noFields
            )

presentationStateText :: TogglePresentationState -> Text
presentationStateText ToggleChecked =
    enumLiteralValue @Contract.TogglePresentationState @Contract.Checked
presentationStateText ToggleUnchecked =
    enumLiteralValue @Contract.TogglePresentationState @Contract.Unchecked

submissionPolicyText :: ToggleSubmissionPolicy -> Text
submissionPolicyText ToggleSubmitDeferred =
    enumLiteralValue @Contract.ToggleSubmissionPolicy @Contract.Deferred
submissionPolicyText ToggleSubmitImmediate =
    enumLiteralValue @Contract.ToggleSubmissionPolicy @Contract.Immediate
