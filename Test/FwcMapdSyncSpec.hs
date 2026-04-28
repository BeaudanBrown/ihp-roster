module Test.FwcMapdSyncSpec where

import Application.FwcMapd.Sync
import qualified Application.FwcMapd.Sync as FwcMapd
import Application.Helper.FwcMapd
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy.Char8 as LByteString
import Data.Scientific (Scientific)
import Data.Time.Calendar (fromGregorian)
import Generated.Enums (AwardPenaltyKindEnum (..))
import Generated.Types
import IHP.ControllerPrelude
import IHP.Prelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support

tests :: Spec
tests = do
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
                    payRatePayloadWithBasePayRateId "BR1"
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
                    payRatePayloadWithBasePayRateId "BR2"
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

        it "keeps hospitality weekday time penalties from wage allowances" do
            let asOfDate = fromGregorian 2026 4 24
                eveningAllowance = wageAllowancePayload 2025 "Penalty-Monday to Friday-7.00 pm to midnight" 10 2.81
                lateNightAllowance = wageAllowancePayload 2025 "Penalty-Monday to Friday-midnight to 7.00 am" 15 4.22
                oldAllowance = wageAllowancePayload 2024 "Penalty-Monday to Friday-7.00 pm to midnight" 10 2.65
                unrelatedAllowance = wageAllowancePayload 2025 "First aid allowance" 0 3.14

                wageAllowances =
                    curateWageAllowances
                        barVenueCurationProfile
                        asOfDate
                        [ (eveningAllowance, Aeson.Null)
                        , (lateNightAllowance, Aeson.Null)
                        , (oldAllowance, Aeson.Null)
                        , (unrelatedAllowance, Aeson.Null)
                        ]

            map (normaliseTimePenaltyKind . fst) wageAllowances `shouldBe` [Just EveningAfter7Pm, Just LateNightAfterMidnight]
            map (wageAllowancePayloadAmount . fst) wageAllowances `shouldBe` [Just 2.81, Just 4.22]

        it "keeps casual ordinary penalties for casual base-rate projection but excludes casual overtime" do
            let asOfDate = fromGregorian 2026 4 24
                award2025 = awardPayload 2025
                level1Classification = classificationPayload 101 2025 "Level 1" (Just "Food and beverage attendant grade 1")
                level1Rate =
                    payRatePayloadWithBasePayRateId "BR1"
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
                casualOrdinaryPenalty =
                    (penaltyRatePayload 101 2025 "Level 1" (Just "Food and beverage attendant grade 1") "Casual employees - ordinary hours" (Just 31.19))
                        { penaltyBasePayRateId = Just "BR1" }
                casualOvertimePenalty =
                    (penaltyRatePayload 101 2025 "Level 1" (Just "Food and beverage attendant grade 1") "Casual employees - overtime ordinary hours" (Just 44.10))
                        { penaltyBasePayRateId = Just "BR1" }

                (_, _, _, _, penalties) =
                    curateAwardData
                        barVenueCurationProfile
                        asOfDate
                        ( 9
                        , [(award2025, Aeson.Null)]
                        , [(level1Classification, Aeson.Null)]
                        , [(level1Rate, Aeson.Null)]
                        , [(casualOrdinaryPenalty, Aeson.Null), (casualOvertimePenalty, Aeson.Null)]
                        )

            map (payloadPenaltyDescription . fst) penalties `shouldBe` [Just "Casual employees - ordinary hours"]
            map (normalisePenaltyKind . fst) penalties `shouldBe` [Nothing]

        it "decodes text-ish MAPD fields from numbers and booleans" do
            let decoded =
                    Aeson.eitherDecode
                        (LByteString.pack "{\"classification_fixed_id\":101,\"classification\":\"Level 1\",\"classification_level\":1,\"clauses\":[],\"operative_from\":\"2025-07-01\",\"published_year\":2025}") ::
                        Either String ClassificationPayload

            fmap payloadClassificationLevel decoded `shouldBe` Right (Just "1.0")

    beforeAll testContext do
        describe "FWC MAPD admin data" do
            it "builds the support/admin award-rate view model from current core hospitality rows" $ withContext do
                withCleanDb do
                    award <-
                        newRecord @FwcMapdAward
                            |> set #awardFixedId 9
                            |> set #awardId 9009
                            |> set #code "MA000009"
                            |> set #name "Hospitality Industry (General) Award 2020"
                            |> set #awardOperativeTo (Nothing :: Maybe Day)
                            |> createRecord
                    _ <-
                        newRecord @FwcMapdAward
                            |> set #awardFixedId 99
                            |> set #awardId 9099
                            |> set #code "OLD"
                            |> set #name "Closed Award"
                            |> set #awardOperativeTo (Just (fromGregorian 2024 6 30))
                            |> createRecord
                    coreClassification <-
                        newRecord @FwcMapdClassification
                            |> set #awardFixedId award.awardFixedId
                            |> set #classificationFixedId 101
                            |> set #classification "Level 1"
                            |> set #parentClassificationName (Just "Food and beverage attendant grade 1")
                            |> set #clauseDescription (Just "Hospitality employees")
                            |> set #operativeTo (Nothing :: Maybe Day)
                            |> createRecord
                    _ <-
                        newRecord @FwcMapdClassification
                            |> set #awardFixedId award.awardFixedId
                            |> set #classificationFixedId 102
                            |> set #classification "Level 1"
                            |> set #parentClassificationName (Just "Casino electronic gaming employee grade 1")
                            |> set #operativeTo (Nothing :: Maybe Day)
                            |> createRecord
                    _ <-
                        newRecord @FwcMapdClassification
                            |> set #awardFixedId award.awardFixedId
                            |> set #classificationFixedId 103
                            |> set #classification "Loaded Rate"
                            |> set #clauseDescription (Just "LoadedRates schedule")
                            |> set #operativeTo (Nothing :: Maybe Day)
                            |> createRecord
                    _ <-
                        newRecord @FwcMapdPayRate
                            |> set #awardFixedId award.awardFixedId
                            |> set #classificationFixedId (Just coreClassification.classificationFixedId)
                            |> set #classification coreClassification.classification
                            |> set #parentClassificationName coreClassification.parentClassificationName
                            |> set #employeeRateTypeCode (Just "AD")
                            |> set #calculatedRate (Just 24.95)
                            |> set #calculatedRateType (Just "Hourly")
                            |> set #operativeTo (Nothing :: Maybe Day)
                            |> createRecord
                    _ <-
                        newRecord @FwcMapdPayRate
                            |> set #awardFixedId award.awardFixedId
                            |> set #classificationFixedId (Just coreClassification.classificationFixedId)
                            |> set #classification "Junior Level 1"
                            |> set #employeeRateTypeCode (Just "JN")
                            |> set #calculatedRate (Just 19.95)
                            |> set #calculatedRateType (Just "Hourly")
                            |> set #operativeTo (Nothing :: Maybe Day)
                            |> createRecord

                    adminData <- fetchFwcMapdAdminData

                    map (.code) adminData.currentAwards `shouldBe` ["MA000009"]
                    map (.classificationFixedId) adminData.currentCoreClassifications `shouldBe` [101]
                    map (.classification) adminData.currentCoreAdultPayRates `shouldBe` ["Level 1"]
                    map (.calculatedRate) adminData.currentCoreAdultPayRates `shouldBe` [Just 24.95]

awardPayloadPublishedYear :: AwardPayload -> Maybe Int
awardPayloadPublishedYear payload = payload.publishedYear

specClassificationPayloadFixedId :: ClassificationPayload -> Int
specClassificationPayloadFixedId payload = payload.classificationFixedId

specPayRatePayloadClassificationFixedId :: PayRatePayload -> Maybe Int
specPayRatePayloadClassificationFixedId payload = payload.classificationFixedId

specPenaltyRatePayloadClassificationFixedId :: PenaltyRatePayload -> Maybe Int
specPenaltyRatePayloadClassificationFixedId payload = payload.penaltyClassificationFixedId

payloadPenaltyDescription :: PenaltyRatePayload -> Maybe Text
payloadPenaltyDescription payload = payload.penaltyDescription

payloadClassificationLevel :: ClassificationPayload -> Maybe Text
payloadClassificationLevel payload = payload.classificationLevel

wageAllowancePayloadAmount :: WageAllowancePayload -> Maybe Scientific
wageAllowancePayloadAmount payload = payload.wageAllowanceAmount

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

payRatePayloadWithBasePayRateId :: Text -> PayRatePayload -> PayRatePayload
payRatePayloadWithBasePayRateId value payload =
    payload { FwcMapd.basePayRateId = Just value }

wageAllowancePayload :: Int -> Text -> Scientific -> Scientific -> WageAllowancePayload
wageAllowancePayload publishedYear allowance rate allowanceAmount =
    WageAllowancePayload
        { wageAllowanceFixedId = Just (2000 + publishedYear)
        , wageAllowanceClauseFixedId = Just 738
        , wageAllowanceClauses = Just "29.2"
        , wageAllowance = Just allowance
        , wageAllowanceType = Just "Detail"
        , wageAllowanceIsAllPurpose = Just False
        , wageAllowanceRate = Just rate
        , wageAllowanceBaseRate = Just 1068.4
        , wageAllowanceBasePayRateId = Just "BR89895"
        , wageAllowanceRateUnit = Just "Percent"
        , wageAllowanceAmount = Just allowanceAmount
        , wageAllowancePaymentFrequency = Just "per hour or part thereof"
        , wageAllowanceOperativeFrom = Just (fromGregorian 2025 7 1)
        , wageAllowanceOperativeTo = Nothing
        , wageAllowancePublishedYear = Just publishedYear
        , wageAllowanceVersionNumber = Just 1
        , wageAllowanceLastModifiedDatetime = Nothing
        }
