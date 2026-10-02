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
    , pwaInstallLinkAttrs, pwaInstallHomeAttrs, pwaInstallManualAttrs, pwaInstallChooserAttrs
    , PwaInstallGuide (..), pwaInstallGuideValue, pwaInstallGuidePanelAttrs
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

pwaInstallLinkAttrs, pwaInstallHomeAttrs, pwaInstallManualAttrs, pwaInstallChooserAttrs :: [(Text, Text)]
pwaInstallLinkAttrs = roleAttrs (domAttrValue @Contract.PwaInstallLink)
pwaInstallHomeAttrs = roleAttrs (domAttrValue @Contract.PwaInstallHome)
pwaInstallManualAttrs = roleAttrs (domAttrValue @Contract.PwaInstallManual)
pwaInstallChooserAttrs = roleAttrs (domAttrValue @Contract.PwaInstallChooser)

-- Device and browser panels are server-owned; selection is disposable browser state.
data PwaInstallGuide = IosGuide | AndroidGuide | WindowsGuide | MacGuide | LinuxGuide
    | ChromeGuide | EdgeGuide | SafariGuide | FirefoxGuide | GeneralGuide
    deriving (Eq, Show)

pwaInstallGuidePanelAttrs :: PwaInstallGuide -> [(Text, Text)]
pwaInstallGuidePanelAttrs guide = [(domAttrValue @Contract.PwaInstallGuidePanel, pwaInstallGuideValue guide)]

pwaInstallGuideValue :: PwaInstallGuide -> Text
pwaInstallGuideValue = \case
    IosGuide -> enumLiteralValue @Contract.PwaInstallGuide @Contract.Ios
    AndroidGuide -> enumLiteralValue @Contract.PwaInstallGuide @Contract.Android
    WindowsGuide -> enumLiteralValue @Contract.PwaInstallGuide @Contract.Windows
    MacGuide -> enumLiteralValue @Contract.PwaInstallGuide @Contract.Mac
    LinuxGuide -> enumLiteralValue @Contract.PwaInstallGuide @Contract.Linux
    ChromeGuide -> enumLiteralValue @Contract.PwaInstallGuide @Contract.Chrome
    EdgeGuide -> enumLiteralValue @Contract.PwaInstallGuide @Contract.Edge
    SafariGuide -> enumLiteralValue @Contract.PwaInstallGuide @Contract.Safari
    FirefoxGuide -> enumLiteralValue @Contract.PwaInstallGuide @Contract.Firefox
    GeneralGuide -> enumLiteralValue @Contract.PwaInstallGuide @Contract.General

pwaInstallStateValue :: PwaInstallState -> Text
pwaInstallStateValue = \case
    PwaInstallAccepted -> enumLiteralValue @Contract.PwaInstallState @Contract.Accepted
    PwaInstallDismissed -> enumLiteralValue @Contract.PwaInstallState @Contract.Dismissed
    PwaInstallFailed -> enumLiteralValue @Contract.PwaInstallState @Contract.Failed

roleAttrs :: Text -> [(Text, Text)]
roleAttrs attribute = [(attribute, "true")]
