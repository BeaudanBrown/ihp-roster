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

type PwaInstallContract =
    Global PwaInstall
        '[ BrowserGuardSchema (Enum PwaInstallState '[Accepted, Dismissed, Failed])
         , DomAttr PwaInstallPage
         , DomAttr PwaInstallButton
         , DomAttr PwaInstallResult
         , DomAttr PwaInstallResultState
         , DomAttr PwaInstalledStatus
         ]
