{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.Surface.Support
    ( SupportAwardRates
    , SupportAwardRatesResource
    , SupportPublicHolidays
    , SupportPublicHolidaysResource
    , SupportSurface
    , SupportPlatform
    , CreatePublicHolidayRefreshJob
    , CreateFwcMapdRefreshJob
    ) where

import Application.Helper.FrontendContract.Surface.DSL

data Support

data SupportPlatform

data SupportAwardRates
data SupportPublicHolidays
data CreatePublicHolidayRefreshJob
data CreateFwcMapdRefreshJob
data OuterHTML

type SupportAwardRatesResource = Resource SupportAwardRates '[]
type SupportPublicHolidaysResource = Resource SupportPublicHolidays '[]

type SupportSurface =
    Surface Support
        '[ Scope SupportPlatform '[] '[ 'Authorize 'SupportSuperAdmin '[] ]
         , Fragment SupportAwardRates '[] '[ 'MountTarget SupportAwardRates '[], 'Eager, 'Live, 'DependsOn SupportAwardRatesResource '[] ]
         , Fragment SupportPublicHolidays '[] '[ 'MountTarget SupportPublicHolidays '[], 'Eager, 'Live, 'DependsOn SupportPublicHolidaysResource '[] ]
         , Action CreatePublicHolidayRefreshJob
            '[]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget ('HtmxId SupportPublicHolidays)
             , 'HtmxSwap 'HtmxOuterHTML
             ]
         , Action CreateFwcMapdRefreshJob
            '[]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget ('HtmxId SupportAwardRates)
             , 'HtmxSwap 'HtmxOuterHTML
             ]
         ]
