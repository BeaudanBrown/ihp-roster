module Application.Helper.FwcMapd where

import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Scientific (Scientific)
import Generated.Types
import IHP.ControllerPrelude

data FwcMapdAdminData = FwcMapdAdminData
    { latestSyncRun           :: !(Maybe FwcMapdSyncRun)
    , currentAwards           :: ![FwcMapdAward]
    , currentCoreClassifications :: ![FwcMapdClassification]
    , currentCoreAdultPayRates :: ![FwcMapdDisplayPayRate]
    , rateTypeBreakdown       :: ![(Text, Int)]
    }
    deriving (Eq, Show)

data FwcMapdDisplayPayRate = FwcMapdDisplayPayRate
    { awardCode                 :: !Text
    , awardName                 :: !Text
    , classification            :: !Text
    , classificationLevel       :: !(Maybe Text)
    , parentClassificationName  :: !(Maybe Text)
    , clauseDescription         :: !(Maybe Text)
    , employeeRateTypeCode      :: !(Maybe Text)
    , baseRate                  :: !(Maybe Scientific)
    , baseRateType              :: !(Maybe Text)
    , calculatedRate            :: !(Maybe Scientific)
    , calculatedRateType        :: !(Maybe Text)
    , operativeFrom             :: !(Maybe Day)
    }
    deriving (Eq, Show)

fetchFwcMapdAdminData :: (?modelContext :: ModelContext) => IO FwcMapdAdminData
fetchFwcMapdAdminData = do
    latestSyncRun <-
        query @FwcMapdSyncRun
            |> orderByDesc #startedAt
            |> fetchOneOrNothing

    currentAwards <-
        query @FwcMapdAward
            |> filterWhere (#awardOperativeTo, Nothing :: Maybe Day)
            |> orderBy #code
            |> fetch

    currentClassifications <-
        query @FwcMapdClassification
            |> filterWhere (#operativeTo, Nothing :: Maybe Day)
            |> fetch

    currentPayRates <-
        query @FwcMapdPayRate
            |> filterWhere (#operativeTo, Nothing :: Maybe Day)
            |> fetch

    let currentAwardByFixedId =
            currentAwards
                |> map (\award -> (award.awardFixedId, award))
                |> Map.fromList
        relevantClassifications =
            currentClassifications
                |> filter isCoreHospitalityClassification
                |> List.sortOn (\classification -> (classification.awardFixedId, classification.classification))
        relevantClassificationByFixedId =
            relevantClassifications
                |> map (\classification -> (classification.classificationFixedId, classification))
                |> Map.fromList
        relevantPayRates =
            currentPayRates
                |> filter (\payRate -> maybe False (`Map.member` relevantClassificationByFixedId) payRate.classificationFixedId)
                |> filter hasPayableAmount
        currentCoreAdultPayRates =
            relevantPayRates
                |> filter (\payRate -> payRate.employeeRateTypeCode == Just "AD")
                |> mapMaybe (mkDisplayPayRate currentAwardByFixedId relevantClassificationByFixedId)
                |> List.sortOn (\payRate -> (payRate.awardCode, payRate.classification, payRate.parentClassificationName, payRate.baseRate, payRate.calculatedRate))
        rateTypeBreakdown :: [(Text, Int)]
        rateTypeBreakdown = []
    pure
        FwcMapdAdminData
            { latestSyncRun = latestSyncRun
            , currentAwards = currentAwards
            , currentCoreClassifications = relevantClassifications
            , currentCoreAdultPayRates = currentCoreAdultPayRates
            , rateTypeBreakdown = rateTypeBreakdown
            }

mkDisplayPayRate :: Map.Map Int FwcMapdAward -> Map.Map Int FwcMapdClassification -> FwcMapdPayRate -> Maybe FwcMapdDisplayPayRate
mkDisplayPayRate currentAwardByFixedId classificationsByFixedId payRate = do
    award <- Map.lookup payRate.awardFixedId currentAwardByFixedId
    classificationFixedId <- payRate.classificationFixedId
    classificationRecord <- Map.lookup classificationFixedId classificationsByFixedId
    pure
        FwcMapdDisplayPayRate
            { awardCode = award.code
            , awardName = award.name
            , classification = payRate.classification
            , classificationLevel = payRate.classificationLevel
            , parentClassificationName = payRate.parentClassificationName
            , clauseDescription = classificationRecord.clauseDescription
            , employeeRateTypeCode = payRate.employeeRateTypeCode
            , baseRate = payRate.baseRate
            , baseRateType = payRate.baseRateType
            , calculatedRate = payRate.calculatedRate
            , calculatedRateType = payRate.calculatedRateType
            , operativeFrom = payRate.operativeFrom
            }

isCoreHospitalityClassification :: FwcMapdClassification -> Bool
isCoreHospitalityClassification classification =
    not (hasExcludedKeyword searchableText)
        && not (containsLoadedRates classification.clauseDescription)
    where
        searchableText =
            Text.toLower
                ( Text.intercalate
                    " "
                    ( filter (not . Text.null)
                        [ classification.classification
                        , fromMaybe "" classification.classificationLevel
                        , fromMaybe "" classification.parentClassificationName
                        , fromMaybe "" classification.clauseDescription
                        ]
                    )
                )

containsLoadedRates :: Maybe Text -> Bool
containsLoadedRates =
    maybe False (Text.isInfixOf "loadedrates" . Text.toLower)

hasExcludedKeyword :: Text -> Bool
hasExcludedKeyword searchableText =
    any (`Text.isInfixOf` searchableText) excludedKeywords

excludedKeywords :: [Text]
excludedKeywords =
    [ "casino"
    , "gaming"
    , "surveillance"
    , "airport catering"
    ]

hasPayableAmount :: FwcMapdPayRate -> Bool
hasPayableAmount payRate =
    isJust payRate.baseRate || isJust payRate.calculatedRate
