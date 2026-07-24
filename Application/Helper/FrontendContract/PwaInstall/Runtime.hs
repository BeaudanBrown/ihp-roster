{-# LANGUAGE TypeApplications #-}

module Application.Helper.FrontendContract.PwaInstall.Runtime
    ( PwaInstallState (..)
    , PwaInstallDom (..)
    , canonicalPwaInstallDom
    , pwaInstallPageAttrs
    , pwaInstallButtonAttrs
    , pwaInstallResultAttrs
    , pwaInstallResultStateAttrs
    , pwaInstalledStatusAttrs
    ) where

import qualified Application.Helper.FrontendContract.PwaInstall as Contract
import Application.Helper.FrontendContract.Values (domAttrValue,
                                                   enumLiteralValue)
import IHP.Prelude

data PwaInstallState
    = PwaInstallAccepted
    | PwaInstallDismissed
    | PwaInstallFailed
    deriving (Eq, Show)

data PwaInstallDom = PwaInstallDom
    { pwaInstallPageAttribute        :: !Text
    , pwaInstallButtonAttribute      :: !Text
    , pwaInstallResultAttribute      :: !Text
    , pwaInstallResultStateAttribute :: !Text
    , pwaInstalledStatusAttribute    :: !Text
    }
    deriving (Eq, Show)

canonicalPwaInstallDom :: PwaInstallDom
canonicalPwaInstallDom = PwaInstallDom
    { pwaInstallPageAttribute = domAttrValue @Contract.PwaInstallPage
    , pwaInstallButtonAttribute = domAttrValue @Contract.PwaInstallButton
    , pwaInstallResultAttribute = domAttrValue @Contract.PwaInstallResult
    , pwaInstallResultStateAttribute = domAttrValue @Contract.PwaInstallResultState
    , pwaInstalledStatusAttribute = domAttrValue @Contract.PwaInstalledStatus
    }

pwaInstallPageAttrs :: [(Text, Text)]
pwaInstallPageAttrs = roleAttrs canonicalPwaInstallDom.pwaInstallPageAttribute

pwaInstallButtonAttrs :: [(Text, Text)]
pwaInstallButtonAttrs = roleAttrs canonicalPwaInstallDom.pwaInstallButtonAttribute

pwaInstallResultAttrs :: [(Text, Text)]
pwaInstallResultAttrs = roleAttrs canonicalPwaInstallDom.pwaInstallResultAttribute

pwaInstallResultStateAttrs :: PwaInstallState -> [(Text, Text)]
pwaInstallResultStateAttrs state =
    [(canonicalPwaInstallDom.pwaInstallResultStateAttribute, pwaInstallStateValue state)]

pwaInstalledStatusAttrs :: [(Text, Text)]
pwaInstalledStatusAttrs = roleAttrs canonicalPwaInstallDom.pwaInstalledStatusAttribute

pwaInstallStateValue :: PwaInstallState -> Text
pwaInstallStateValue = \case
    PwaInstallAccepted -> enumLiteralValue @Contract.PwaInstallState @Contract.Accepted
    PwaInstallDismissed -> enumLiteralValue @Contract.PwaInstallState @Contract.Dismissed
    PwaInstallFailed -> enumLiteralValue @Contract.PwaInstallState @Contract.Failed

roleAttrs :: Text -> [(Text, Text)]
roleAttrs attribute = [(attribute, "true")]
