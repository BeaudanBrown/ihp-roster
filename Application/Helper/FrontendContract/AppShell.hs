{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.AppShell
    ( AppShellContract
    , AppShell
    , PartialNavigate
    ) where

import Application.Helper.FrontendContract.App (AppContentMount)
import Application.Helper.FrontendContract.DSL

data AppShell

data PartialNavigate

type AppShellContract =
    Global AppShell
        '[ AppShellAction PartialNavigate
            '[]
            '[ AppShellHtmxMethod 'AppShellGet
             , AppShellHtmxTarget AppContentMount
             , AppShellHtmxSwap "innerHTML"
             , AppShellHtmxPushUrl 'AppShellPushUrlTrue
             ]
         ]
