{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Test.CompileFail.FrontendSurfaceServerDtoBrowserRender where

import Application.Helper.FrontendContract.Surface.DSL
import Application.Helper.FrontendContract.Surface.Dto
import Application.Helper.FrontendContract.Surface.Values
import Data.Text (Text)


data FixtureContract
data FixtureDtoRole
data FixturePayload
data FixtureValue


type FixtureSurface =
    Surface
        FixtureContract
        '[ BrowserRole FixtureDtoRole
         , Dto FixturePayload '[Field FixtureValue 'WireText]
         ]

badServerDtoBrowserRender :: [(Text, Text)]
badServerDtoBrowserRender =
    surfaceBrowserDtoRoleAttrs @FixtureSurface @FixtureDtoRole @FixturePayload
        (surfaceField @FixtureValue ("value" :: Text) &: noSurfaceFields)
