{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.PwaInstall
    ( PwaInstallContract
    , PwaInstall
    , PwaInstallState
    , Accepted
    , Dismissed
    , Failed
    , PwaInstallPage
    , PwaInstallButton
    , PwaInstallResult
    , PwaInstallResultState
    , PwaInstalledStatus
    , PwaInstallLink, PwaInstallHome, PwaInstallManual, PwaInstallChooser, PwaInstallGuidePanel
    , PwaInstallGuide, PwaInstallDevice, PwaInstallBrowser, Ios, Android, Windows, Mac, Linux, Chrome, Edge, Safari, Firefox, General
    ) where

import Application.Helper.FrontendContract.DSL

-- | Browser-install workflow vocabulary. Haskell owns the rendered roles,
-- closed result states, and copy; browser install events, prompt objects, and
-- platform detection remain private to the adapter.
data PwaInstall

data PwaInstallState
data Accepted
data Dismissed
data Failed

data PwaInstallPage
data PwaInstallButton
data PwaInstallResult
data PwaInstallResultState
data PwaInstalledStatus
data PwaInstallLink
data PwaInstallHome
data PwaInstallManual
data PwaInstallChooser
data PwaInstallGuidePanel

data PwaInstallGuide
data PwaInstallDevice
data PwaInstallBrowser
data Ios
data Android
data Windows
data Mac
data Linux
data Chrome
data Edge
data Safari
data Firefox
data General

type PwaInstallContract =
    Global PwaInstall
        '[ BrowserGuardSchema (Enum PwaInstallState '[Accepted, Dismissed, Failed])
         , DomAttr PwaInstallPage
         , DomAttr PwaInstallButton
         , DomAttr PwaInstallResult
         , DomAttr PwaInstallResultState
         , DomAttr PwaInstalledStatus
         , DomAttr PwaInstallLink
         , DomAttr PwaInstallHome
         , DomAttr PwaInstallManual
         , DomAttr PwaInstallChooser
         , DomAttr PwaInstallGuidePanel
         , BrowserGuardSchema (Enum PwaInstallGuide '[Ios, Android, Windows, Mac, Linux, Chrome, Edge, Safari, Firefox, General])
         , BrowserGuardSchema (Enum PwaInstallDevice '[Ios, Android, Windows, Mac, Linux, General])
         , BrowserGuardSchema (Enum PwaInstallBrowser '[Chrome, Edge, Safari, Firefox, General])
         ]
