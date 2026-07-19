{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.OrderedRange
    ( OrderedRangeContract
    , OrderedRange
    , OrderedRangeCrossingPolicy
    , ClampOtherEndpoint
    , OrderedRangeConfig
    , MinimumValue
    , MaximumValue
    , StepValue
    , DefaultStartValue
    , DefaultEndValue
    , ValueLabels
    , CrossingPolicy
    , OrderedRangeState
    , StartValue
    , EndValue
    , Available
    , OrderedRangeClampOtherEndpoint
    , OrderedRangeStartPositionProperty
    , OrderedRangeEndPositionProperty
    , OrderedRangeRoot
    , OrderedRangeStart
    , OrderedRangeEnd
    , OrderedRangeAvailability
    ) where

import Application.Helper.FrontendContract.DSL

-- | Reusable two-endpoint range vocabulary. Haskell owns the allowed values,
-- labels, defaults, initial state, and crossing policy; the browser owns only
-- mechanical presentation over this exact boundary.
data OrderedRange

data OrderedRangeCrossingPolicy
data ClampOtherEndpoint

data OrderedRangeConfig
data MinimumValue
data MaximumValue
data StepValue
data DefaultStartValue
data DefaultEndValue
data ValueLabels
data CrossingPolicy

data OrderedRangeState
data StartValue
data EndValue
data Available

data OrderedRangeClampOtherEndpoint
data OrderedRangeStartPositionProperty
data OrderedRangeEndPositionProperty

data OrderedRangeRoot
data OrderedRangeStart
data OrderedRangeEnd
data OrderedRangeAvailability

type OrderedRangeContract =
    Global OrderedRange
        '[ BrowserGuardSchema (Enum OrderedRangeCrossingPolicy '[ClampOtherEndpoint])
         , BrowserInboundSchema (Record OrderedRangeConfig
            '[ Field MinimumValue 'WireInt
             , Field MaximumValue 'WireInt
             , Field StepValue 'WireInt
             , Field DefaultStartValue 'WireInt
             , Field DefaultEndValue 'WireInt
             , Field ValueLabels ('WireList 'WireText)
             , Field CrossingPolicy ('WireRef OrderedRangeCrossingPolicy)
             ])
         , BrowserInboundSchema (Record OrderedRangeState
            '[ Field StartValue 'WireInt
             , Field EndValue 'WireInt
             , Field Available 'WireBool
             ])
         , Constant OrderedRangeClampOtherEndpoint "clamp-other-endpoint"
         , Constant OrderedRangeStartPositionProperty "--ordered-range-start-position"
         , Constant OrderedRangeEndPositionProperty "--ordered-range-end-position"
         , DomAttr OrderedRangeRoot
         , DomAttr OrderedRangeConfig
         , DomAttr OrderedRangeState
         , DomAttr OrderedRangeStart
         , DomAttr OrderedRangeEnd
         , DomAttr OrderedRangeAvailability
         ]
