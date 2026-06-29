{-# LANGUAGE ExistentialQuantification #-}

module Application.Helper.Frontend.ContractGroup
    ( FrontendContractGroup (..)
    , FrontendTypedConstant
    , renderFrontendContractGroup
    , typedConstant
    ) where

import Application.Helper.Frontend.Codec (FrontendCodec, SomeFrontendCodec,
                                          renderFrontendContracts,
                                          renderTypedConstant)
import Application.Helper.Frontend.TypeScript (TypeScriptDeclaration (..),
                                               TypeScriptDeclarationOrigin (HaskellSchemaGenerated))
import qualified Data.Text as Text
import IHP.Prelude

data FrontendTypedConstant = forall a. FrontendTypedConstant Text (FrontendCodec a) a

-- | Declares a TypeScript constant whose type is rendered from the same codec
-- used to validate/encode the value.
typedConstant :: Text -> FrontendCodec a -> a -> FrontendTypedConstant
typedConstant = FrontendTypedConstant

-- | One named Haskell-owned browser contract group. Schema modules should
-- describe their codecs/constants here instead of hand-rolling TypeScript
-- declarations, so all groups get duplicate-name checks and consistent errors.
data FrontendContractGroup = FrontendContractGroup
    { contractGroupName      :: !Text
    , contractGroupComment   :: !(Maybe Text)
    , contractGroupCodecs    :: ![SomeFrontendCodec]
    , contractGroupConstants :: ![FrontendTypedConstant]
    }

renderFrontendContractGroup :: FrontendContractGroup -> TypeScriptDeclaration
renderFrontendContractGroup group =
    TypeScriptDeclaration
        { name = group.contractGroupName
        , origin = HaskellSchemaGenerated
        , source = Text.intercalate "\n" (commentSource <> [schemaSource] <> constantSource)
        }
    where
        schemaSource = case renderFrontendContracts group.contractGroupCodecs of
            Right generated -> generated
            Left message -> error ("Unable to render " <> cs group.contractGroupName <> " contract group: " <> cs message)
        commentSource = maybe [] (pure . ("// " <>)) group.contractGroupComment
        constantSource = fmap renderConstant group.contractGroupConstants
        renderConstant (FrontendTypedConstant constantName codec value) = renderTypedConstant constantName codec value
