module Test.FwcMapdSyncSpec where

import Application.FwcMapd.Sync
import qualified Data.Aeson as Aeson
import Data.Scientific (Scientific)
import Data.Time.Calendar (fromGregorian)
import IHP.Prelude
import Test.Hspec

tests :: Spec
tests =
    describe "FWC MAPD sync curation" do
        it "keeps only latest active adult hourly bar/pub rates and referenced classifications" do
            let asOfDate = fromGregorian 2026 4 24
                award2024 = awardPayload 2024
                award2025 = awardPayload 2025
                level1Classification = classificationPayload 101 2025 "Level 1" (Just "Food and beverage attendant grade 1")
                casinoClassification = classificationPayload 102 2025 "Level 1" (Just "Casino electronic gaming employee grade 1")
                casinoIntroClassification = classificationPayloadWithClause 106 2025 "Introductory level" Nothing (Just "Casino Gaming Employees")
                oldClassification = classificationPayload 103 2024 "Level 2" (Just "Food and beverage attendant grade 2")
                level1Rate =
                    (payRatePayload
                        101
                        2025
                        "AD"
                        "Level 1"
                        (Just "Food and beverage attendant grade 1")
                        Nothing
                        (Just "Weekly")
                        (Just 24.95)
                        (Just "Hourly"))
                        { basePayRateId = Just "BR1" }
                juniorRate =
                    payRatePayload
                        104
                        2025
                        "JN"
                        "19 years of age"
                        (Just "Introductory level")
                        (Just 21.21)
                        (Just "Hourly")
                        Nothing
                        Nothing
                casinoRate =
                    (payRatePayload
                        102
                        2025
                        "AD"
                        "Level 1"
                        (Just "Casino electronic gaming employee grade 1")
                        Nothing
                        (Just "Weekly")
                        (Just 26.38)
                        (Just "Hourly"))
                        { basePayRateId = Just "BR2" }
                weeklyOnlyRate =
                    payRatePayload
                        105
                        2025
                        "AD"
                        "Managerial staff"
                        (Just "Food and beverage supervisor")
                        (Just 60732)
                        (Just "Annual")
                        Nothing
                        Nothing
                casinoIntroRate =
                    payRatePayload
                        106
                        2025
                        "AD"
                        "Introductory level"
                        Nothing
                        Nothing
                        (Just "Weekly")
                        (Just 26.38)
                        (Just "Hourly")
                oldRate =
                    payRatePayload
                        103
                        2024
                        "AD"
                        "Level 2"
                        (Just "Food and beverage attendant grade 2")
                        Nothing
                        (Just "Weekly")
                        (Just 23.55)
                        (Just "Hourly")
                level1Penalty = (penaltyRatePayload 101 2025 "Level 1" (Just "Food and beverage attendant grade 1") "Saturday penalty" (Just 37.50)) { penaltyBasePayRateId = Just "BR1" }
                casinoPenalty = (penaltyRatePayload 102 2025 "Level 1" (Just "Casino electronic gaming employee grade 1") "Saturday penalty" (Just 39.57)) { penaltyBasePayRateId = Just "BR2" }

                (_, awards, classifications, payRates, penalties) =
                    curateAwardData
                        barVenueCurationProfile
                        asOfDate
                        ( 9
                        , [(award2024, Aeson.Null), (award2025, Aeson.Null)]
                        , [(level1Classification, Aeson.Null), (casinoClassification, Aeson.Null), (casinoIntroClassification, Aeson.Null), (oldClassification, Aeson.Null)]
                        , [(level1Rate, Aeson.Null), (juniorRate, Aeson.Null), (casinoRate, Aeson.Null), (weeklyOnlyRate, Aeson.Null), (casinoIntroRate, Aeson.Null), (oldRate, Aeson.Null)]
                        , [(level1Penalty, Aeson.Null), (casinoPenalty, Aeson.Null)]
                        )

            map (awardPayloadPublishedYear . fst) awards `shouldBe` [Just 2025]
            map (specClassificationPayloadFixedId . fst) classifications `shouldBe` [101]
            map (specPayRatePayloadClassificationFixedId . fst) payRates `shouldBe` [Just 101]
            map (specPenaltyRatePayloadClassificationFixedId . fst) penalties `shouldBe` [Just 101]

awardPayloadPublishedYear :: AwardPayload -> Maybe Int
awardPayloadPublishedYear payload = payload.publishedYear

specClassificationPayloadFixedId :: ClassificationPayload -> Int
specClassificationPayloadFixedId payload = payload.classificationFixedId

specPayRatePayloadClassificationFixedId :: PayRatePayload -> Maybe Int
specPayRatePayloadClassificationFixedId payload = payload.classificationFixedId

specPenaltyRatePayloadClassificationFixedId :: PenaltyRatePayload -> Maybe Int
specPenaltyRatePayloadClassificationFixedId payload = payload.penaltyClassificationFixedId

awardPayload :: Int -> AwardPayload
awardPayload publishedYear =
    AwardPayload
        { awardFixedId = 9
        , awardId = 9000 + publishedYear
        , code = "MA000009"
        , name = "Hospitality Industry (General) Award 2020"
        , awardOperativeFrom = Just (fromGregorian 2010 1 1)
        , awardOperativeTo = Nothing
        , publishedYear = Just publishedYear
        , versionNumber = Just 1
        , lastModifiedDatetime = Nothing
        }

penaltyRatePayload :: Int -> Int -> Text -> Maybe Text -> Text -> Maybe Scientific -> PenaltyRatePayload
penaltyRatePayload classificationFixedId publishedYear classification parentClassificationName description calculatedValue =
    PenaltyRatePayload
        { penaltyClassificationFixedId = Just classificationFixedId
        , penaltyClassification = classification
        , penaltyClassificationLevel = Nothing
        , penaltyParentClassificationName = parentClassificationName
        , penaltyClauseDescription = Just "Adult full-time and part-time employees-ordinary and penalty rates"
        , penaltyEmployeeRateTypeCode = Just "AD"
        , penaltyBasePayRateId = Nothing
        , penaltyFixedId = Just classificationFixedId
        , penaltyDescription = Just description
        , penaltyText = Nothing
        , penaltyRate = Nothing
        , penaltyRateUnit = Just "Hourly"
        , penaltyCalculatedValue = calculatedValue
        , penaltyOperativeFrom = Just (fromGregorian 2025 7 1)
        , penaltyOperativeTo = Nothing
        , penaltyPublishedYear = Just publishedYear
        , penaltyVersionNumber = Just 1
        , penaltyLastModifiedDatetime = Nothing
        }

classificationPayload :: Int -> Int -> Text -> Maybe Text -> ClassificationPayload
classificationPayload classificationFixedId publishedYear classification parentClassificationName =
    classificationPayloadWithClause classificationFixedId publishedYear classification parentClassificationName Nothing

classificationPayloadWithClause :: Int -> Int -> Text -> Maybe Text -> Maybe Text -> ClassificationPayload
classificationPayloadWithClause classificationFixedId publishedYear classification parentClassificationName clauseDescription =
    ClassificationPayload
        { classificationFixedId
        , classification
        , classificationLevel = Nothing
        , parentClassificationName
        , clauseFixedId = Nothing
        , clauseDescription
        , clauses = Aeson.Array mempty
        , nextDownClassificationFixedId = Nothing
        , nextUpClassificationFixedId = Nothing
        , operativeFrom = Just (fromGregorian 2025 7 1)
        , operativeTo = Nothing
        , publishedYear = Just publishedYear
        , versionNumber = Just 1
        , lastModifiedDatetime = Nothing
        }

payRatePayload ::
    Int ->
    Int ->
    Text ->
    Text ->
    Maybe Text ->
    Maybe Scientific ->
    Maybe Text ->
    Maybe Scientific ->
    Maybe Text ->
    PayRatePayload
payRatePayload classificationFixedId publishedYear employeeRateTypeCode classification parentClassificationName baseRate baseRateType calculatedRate calculatedRateType =
    PayRatePayload
        { classificationFixedId = Just classificationFixedId
        , classification
        , classificationLevel = Nothing
        , parentClassificationName
        , employeeRateTypeCode = Just employeeRateTypeCode
        , basePayRateId = Nothing
        , baseRate
        , baseRateType
        , calculatedPayRateId = Nothing
        , calculatedRate
        , calculatedRateType
        , operativeFrom = Just (fromGregorian 2025 7 1)
        , operativeTo = Nothing
        , publishedYear = Just publishedYear
        , versionNumber = Just 1
        , lastModifiedDatetime = Nothing
        }
