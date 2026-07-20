{-# LANGUAGE LambdaCase       #-}
{-# LANGUAGE TypeApplications #-}

module Application.Helper.FrontendContract.Surface.SemanticIR
    ( BrowserAttributeIR (..)
    , CompleteSetSortComparatorDirectionIR (..)
    , CompleteSetSortDirectionIR (..)
    , CompleteSetSortValueTypeIR (..)
    , LinkedHighlightActivationIR (..)
    , LinkedHighlightEffectIR (..)
    , InteractionEffectClassIR (..)
    , InteractionEffectIR (..)
    , InteractionEffectKindIR (..)
    , InteractionEffectLifecycleIR (..)
    , InteractionEffectSemanticIR (..)
    , InteractionEffectSourceIR (..)
    , ScopeAuthIR (..)
    , ScopeAuthPolicyIR (..)
    , cloneShadowCopyEffectIR
    , cloneShadowEffectIR
    , dropzoneHighlightEffectIR
    , interactionEffectBrowserKind
    , interactionEffectClassName
    , interactionEffectClassNames
    , interactionEffectLayerName
    , interactionEffectSemanticName
    , interactionEffectSourceName
    , completeSetSortComparatorDirectionName
    , completeSetSortDirectionName
    , completeSetSortValueTypeName
    , linkedHighlightActivationName
    , linkedHighlightEffectName
    , scopeAuthFieldNames
    , scopeAuthPolicy
    , scopeAuthPolicyFieldCount
    , scopeAuthPolicyName
    ) where

import qualified Application.Helper.FrontendContract.Interaction as Interaction
import Application.Helper.FrontendContract.Naming (FrontendSurfaceNameContext (..),
                                                   deriveFrontendSurfaceTypeName)
import IHP.Prelude

data Hover
data Focus
data Keyboard
data Pin
data MatchingSource
data MatchingMember
data OrderedMemberBounds

data TextValueType
data IntegerValueType
data OpaqueValueType
data SelectedComparatorDirection
data AscendingComparatorDirection
data AscendingDirection
data DescendingDirection

data CurrentVenuePolicy
data CurrentVenueUserPolicy
data CurrentVenueStaffPolicy
data CurrentVenueRosterGroupPolicy
data CurrentVenueAdminPolicy
data CurrentVenueManagerPolicy
data CurrentVenueOwnerPolicy
data CurrentVenueAdminRosterGroupPolicy
data SupportSuperAdminPolicy

-- Authorization behavior remains closed. Field names are reflected identities;
-- consumers may parse the named values but must not redispatch on policy text.
data ScopeAuthPolicyIR
    = CurrentVenuePolicyIR
    | CurrentVenueUserPolicyIR
    | CurrentVenueStaffPolicyIR
    | CurrentVenueRosterGroupPolicyIR
    | CurrentVenueAdminPolicyIR
    | CurrentVenueManagerPolicyIR
    | CurrentVenueOwnerPolicyIR
    | CurrentVenueAdminRosterGroupPolicyIR
    | SupportSuperAdminPolicyIR
    deriving (Eq, Show)

data ScopeAuthIR
    = AuthorizeCurrentVenueIR !Text
    | AuthorizeCurrentVenueUserIR !Text !Text
    | AuthorizeCurrentVenueStaffIR !Text !Text
    | AuthorizeCurrentVenueRosterGroupIR !Text !Text
    | AuthorizeCurrentVenueAdminIR !Text
    | AuthorizeCurrentVenueManagerIR !Text
    | AuthorizeCurrentVenueOwnerIR !Text
    | AuthorizeCurrentVenueAdminRosterGroupIR !Text !Text
    | AuthorizeSupportSuperAdminIR
    | NoAuthIR
    | InvalidAuthorizeIR !ScopeAuthPolicyIR ![Text]
    deriving (Eq, Show)

scopeAuthPolicy :: ScopeAuthIR -> Maybe ScopeAuthPolicyIR
scopeAuthPolicy = \case
    AuthorizeCurrentVenueIR {}                 -> Just CurrentVenuePolicyIR
    AuthorizeCurrentVenueUserIR {}             -> Just CurrentVenueUserPolicyIR
    AuthorizeCurrentVenueStaffIR {}            -> Just CurrentVenueStaffPolicyIR
    AuthorizeCurrentVenueRosterGroupIR {}      -> Just CurrentVenueRosterGroupPolicyIR
    AuthorizeCurrentVenueAdminIR {}            -> Just CurrentVenueAdminPolicyIR
    AuthorizeCurrentVenueManagerIR {}          -> Just CurrentVenueManagerPolicyIR
    AuthorizeCurrentVenueOwnerIR {}            -> Just CurrentVenueOwnerPolicyIR
    AuthorizeCurrentVenueAdminRosterGroupIR {} -> Just CurrentVenueAdminRosterGroupPolicyIR
    AuthorizeSupportSuperAdminIR                -> Just SupportSuperAdminPolicyIR
    NoAuthIR                                    -> Nothing
    InvalidAuthorizeIR policy _                 -> Just policy

scopeAuthFieldNames :: ScopeAuthIR -> [Text]
scopeAuthFieldNames = \case
    AuthorizeCurrentVenueIR venueId -> [venueId]
    AuthorizeCurrentVenueUserIR venueId userId -> [venueId, userId]
    AuthorizeCurrentVenueStaffIR venueId staffId -> [venueId, staffId]
    AuthorizeCurrentVenueRosterGroupIR venueId rosterGroupId -> [venueId, rosterGroupId]
    AuthorizeCurrentVenueAdminIR venueId -> [venueId]
    AuthorizeCurrentVenueManagerIR venueId -> [venueId]
    AuthorizeCurrentVenueOwnerIR venueId -> [venueId]
    AuthorizeCurrentVenueAdminRosterGroupIR venueId rosterGroupId -> [venueId, rosterGroupId]
    AuthorizeSupportSuperAdminIR -> []
    NoAuthIR -> []
    InvalidAuthorizeIR _ fields -> fields

scopeAuthPolicyFieldCount :: ScopeAuthPolicyIR -> Int
scopeAuthPolicyFieldCount = \case
    CurrentVenuePolicyIR                 -> 1
    CurrentVenueUserPolicyIR             -> 2
    CurrentVenueStaffPolicyIR            -> 2
    CurrentVenueRosterGroupPolicyIR      -> 2
    CurrentVenueAdminPolicyIR            -> 1
    CurrentVenueManagerPolicyIR          -> 1
    CurrentVenueOwnerPolicyIR            -> 1
    CurrentVenueAdminRosterGroupPolicyIR -> 2
    SupportSuperAdminPolicyIR            -> 0

scopeAuthPolicyName :: ScopeAuthPolicyIR -> Text
scopeAuthPolicyName = \case
    CurrentVenuePolicyIR                 -> deriveFrontendSurfaceTypeName @CurrentVenuePolicy AuthorizationPolicyName
    CurrentVenueUserPolicyIR             -> deriveFrontendSurfaceTypeName @CurrentVenueUserPolicy AuthorizationPolicyName
    CurrentVenueStaffPolicyIR            -> deriveFrontendSurfaceTypeName @CurrentVenueStaffPolicy AuthorizationPolicyName
    CurrentVenueRosterGroupPolicyIR      -> deriveFrontendSurfaceTypeName @CurrentVenueRosterGroupPolicy AuthorizationPolicyName
    CurrentVenueAdminPolicyIR            -> deriveFrontendSurfaceTypeName @CurrentVenueAdminPolicy AuthorizationPolicyName
    CurrentVenueManagerPolicyIR          -> deriveFrontendSurfaceTypeName @CurrentVenueManagerPolicy AuthorizationPolicyName
    CurrentVenueOwnerPolicyIR            -> deriveFrontendSurfaceTypeName @CurrentVenueOwnerPolicy AuthorizationPolicyName
    CurrentVenueAdminRosterGroupPolicyIR -> deriveFrontendSurfaceTypeName @CurrentVenueAdminRosterGroupPolicy AuthorizationPolicyName
    SupportSuperAdminPolicyIR            -> deriveFrontendSurfaceTypeName @SupportSuperAdminPolicy AuthorizationPolicyName

-- | One generated Surface-owned browser attribute. Roles identify adapter
-- participants; states carry adapter-owned values. Both use the same checked,
-- collision-validated attribute representation after reflection.
data BrowserAttributeIR = BrowserAttributeIR
    { browserAttributeMarker       :: !Text
    , browserAttributeName         :: !Text
    , browserAttributeDomAttribute :: !Text
    }
    deriving (Eq, Show)

data LinkedHighlightActivationIR
    = LinkedHighlightHoverActivationIR
    | LinkedHighlightFocusActivationIR
    | LinkedHighlightKeyboardActivationIR
    | LinkedHighlightPinActivationIR !BrowserAttributeIR
    deriving (Eq, Show)

data LinkedHighlightEffectIR
    = LinkedHighlightMatchingSourceEffectIR
    | LinkedHighlightMatchingMemberEffectIR
    | LinkedHighlightOrderedMemberBoundsEffectIR !BrowserAttributeIR
    deriving (Eq, Show)

linkedHighlightActivationName :: LinkedHighlightActivationIR -> Text
linkedHighlightActivationName = \case
    LinkedHighlightHoverActivationIR -> deriveFrontendSurfaceTypeName @Hover DomTokenName
    LinkedHighlightFocusActivationIR -> deriveFrontendSurfaceTypeName @Focus DomTokenName
    LinkedHighlightKeyboardActivationIR -> deriveFrontendSurfaceTypeName @Keyboard DomTokenName
    LinkedHighlightPinActivationIR {} -> deriveFrontendSurfaceTypeName @Pin DomTokenName

linkedHighlightEffectName :: LinkedHighlightEffectIR -> Text
linkedHighlightEffectName = \case
    LinkedHighlightMatchingSourceEffectIR -> deriveFrontendSurfaceTypeName @MatchingSource DomTokenName
    LinkedHighlightMatchingMemberEffectIR -> deriveFrontendSurfaceTypeName @MatchingMember DomTokenName
    LinkedHighlightOrderedMemberBoundsEffectIR {} -> deriveFrontendSurfaceTypeName @OrderedMemberBounds DomTokenName

data CompleteSetSortValueTypeIR
    = CompleteSetSortTextIR
    | CompleteSetSortIntegerIR
    | CompleteSetSortOpaqueIR
    deriving (Eq, Show)

data CompleteSetSortComparatorDirectionIR
    = CompleteSetSortSelectedDirectionIR
    | CompleteSetSortAscendingComparatorIR
    deriving (Eq, Show)

data CompleteSetSortDirectionIR
    = CompleteSetSortAscendingIR
    | CompleteSetSortDescendingIR
    deriving (Eq, Show)

completeSetSortValueTypeName :: CompleteSetSortValueTypeIR -> Text
completeSetSortValueTypeName = \case
    CompleteSetSortTextIR -> deriveFrontendSurfaceTypeName @TextValueType SortValueTypeName
    CompleteSetSortIntegerIR -> deriveFrontendSurfaceTypeName @IntegerValueType SortValueTypeName
    CompleteSetSortOpaqueIR -> deriveFrontendSurfaceTypeName @OpaqueValueType SortValueTypeName

completeSetSortComparatorDirectionName :: CompleteSetSortComparatorDirectionIR -> Text
completeSetSortComparatorDirectionName = \case
    CompleteSetSortSelectedDirectionIR -> deriveFrontendSurfaceTypeName @SelectedComparatorDirection SortComparatorDirectionName
    CompleteSetSortAscendingComparatorIR -> deriveFrontendSurfaceTypeName @AscendingComparatorDirection SortComparatorDirectionName

completeSetSortDirectionName :: CompleteSetSortDirectionIR -> Text
completeSetSortDirectionName = \case
    CompleteSetSortAscendingIR -> deriveFrontendSurfaceTypeName @AscendingDirection SortDirectionName
    CompleteSetSortDescendingIR -> deriveFrontendSurfaceTypeName @DescendingDirection SortDirectionName

-- Effect behavior, lifecycle, classes, and source are explicit checked fields.
-- Browser spellings are derived from typed markers only when rendered.
data InteractionEffectSemanticIR
    = CloneShadowEffectSemanticIR
    | CloneShadowCopyEffectSemanticIR
    | DropzoneHighlightEffectSemanticIR
    deriving (Eq, Show)

data InteractionEffectLifecycleIR
    = SessionGlobalEffectLifecycleIR
    | ContextualTargetEffectLifecycleIR
    deriving (Eq, Show)

data InteractionEffectKindIR
    = CloneShadowEffectKindIR
    | DropzoneHighlightEffectKindIR
    deriving (Eq, Show)

data InteractionEffectClassIR
    = PointerCloneShadowClassIR
    | PointerCloneShadowCopyClassIR
    | DropzoneHighlightClassIR
    deriving (Eq, Show)

data InteractionEffectSourceIR
    = PointerMarkerEffectSourceIR
    deriving (Eq, Show)

data InteractionEffectIR = InteractionEffectIR
    { interactionEffectSemantic           :: !InteractionEffectSemanticIR
    , interactionEffectLifecycle          :: !InteractionEffectLifecycleIR
    , interactionEffectKind               :: !InteractionEffectKindIR
    , interactionEffectLayer              :: !(Maybe Text)
    , interactionEffectClasses            :: ![InteractionEffectClassIR]
    , interactionEffectSource             :: !(Maybe InteractionEffectSourceIR)
    , interactionEffectPreserveGrabOffset :: !(Maybe Bool)
    }
    deriving (Eq, Show)

cloneShadowEffectIR :: Text -> InteractionEffectIR
cloneShadowEffectIR layer = InteractionEffectIR
    { interactionEffectSemantic = CloneShadowEffectSemanticIR
    , interactionEffectLifecycle = SessionGlobalEffectLifecycleIR
    , interactionEffectKind = CloneShadowEffectKindIR
    , interactionEffectLayer = Just layer
    , interactionEffectClasses = [PointerCloneShadowClassIR]
    , interactionEffectSource = Just PointerMarkerEffectSourceIR
    , interactionEffectPreserveGrabOffset = Just True
    }

cloneShadowCopyEffectIR :: Text -> InteractionEffectIR
cloneShadowCopyEffectIR layer = InteractionEffectIR
    { interactionEffectSemantic = CloneShadowCopyEffectSemanticIR
    , interactionEffectLifecycle = SessionGlobalEffectLifecycleIR
    , interactionEffectKind = CloneShadowEffectKindIR
    , interactionEffectLayer = Just layer
    , interactionEffectClasses = [PointerCloneShadowClassIR, PointerCloneShadowCopyClassIR]
    , interactionEffectSource = Just PointerMarkerEffectSourceIR
    , interactionEffectPreserveGrabOffset = Just True
    }

dropzoneHighlightEffectIR :: InteractionEffectIR
dropzoneHighlightEffectIR = InteractionEffectIR
    { interactionEffectSemantic = DropzoneHighlightEffectSemanticIR
    , interactionEffectLifecycle = ContextualTargetEffectLifecycleIR
    , interactionEffectKind = DropzoneHighlightEffectKindIR
    , interactionEffectLayer = Nothing
    , interactionEffectClasses = [DropzoneHighlightClassIR]
    , interactionEffectSource = Nothing
    , interactionEffectPreserveGrabOffset = Nothing
    }

interactionEffectSemanticName :: InteractionEffectIR -> Text
interactionEffectSemanticName effect =
    case effect.interactionEffectSemantic of
        CloneShadowEffectSemanticIR       -> deriveFrontendSurfaceTypeName @Interaction.CloneShadow ActionName
        CloneShadowCopyEffectSemanticIR   -> deriveFrontendSurfaceTypeName @Interaction.CloneShadowCopy ActionName
        DropzoneHighlightEffectSemanticIR -> deriveFrontendSurfaceTypeName @Interaction.DropzoneHighlight ActionName

interactionEffectBrowserKind :: InteractionEffectIR -> Text
interactionEffectBrowserKind effect =
    case effect.interactionEffectKind of
        CloneShadowEffectKindIR       -> deriveFrontendSurfaceTypeName @Interaction.CloneShadow ActionName
        DropzoneHighlightEffectKindIR -> deriveFrontendSurfaceTypeName @Interaction.DropzoneHighlight ActionName

interactionEffectClassName :: InteractionEffectClassIR -> Text
interactionEffectClassName = \case
    PointerCloneShadowClassIR     -> deriveFrontendSurfaceTypeName @Interaction.BepisPointerCloneShadow DomTokenName
    PointerCloneShadowCopyClassIR -> deriveFrontendSurfaceTypeName @Interaction.BepisPointerCloneShadowCopy DomTokenName
    DropzoneHighlightClassIR      -> deriveFrontendSurfaceTypeName @Interaction.BepisDropzoneHighlight DomTokenName

interactionEffectClassNames :: InteractionEffectIR -> [Text]
interactionEffectClassNames effect =
    map interactionEffectClassName effect.interactionEffectClasses

interactionEffectSourceName :: InteractionEffectSourceIR -> Text
interactionEffectSourceName PointerMarkerEffectSourceIR =
    deriveFrontendSurfaceTypeName @Interaction.PointerMarker ActionName

interactionEffectLayerName :: InteractionEffectIR -> Maybe Text
interactionEffectLayerName = (.interactionEffectLayer)
