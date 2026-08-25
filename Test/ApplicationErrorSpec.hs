{-# LANGUAGE DeriveDataTypeable  #-}
{-# LANGUAGE DeriveGeneric       #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Test.ApplicationErrorSpec
    ( tests
    ) where

import Application.Bepis.Action (BepisOperationKind (..), runBepis)
import Application.Error.Boundary
import Application.Error.Domain
import Application.Error.Types
import Application.Error.Wire
import Application.Helper.FrontendContract.Contracts (frontendContractsTypeScript)
import Application.Helper.FrontendContract.IR
import Application.Helper.FrontendContract.TypeScript (renderFrontendContractTypeScript)
import qualified Control.Exception as Exception
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Lazy as LBS
import Data.Either (isLeft)
import qualified Data.Text as Text
import GHC.Generics (Generic)
import IHP.Controller.Response (ResponseException (..))
import IHP.ModelSupport (RecordNotFoundException (..))
import IHP.Prelude
import Network.HTTP.Types (status422, status500)
import Network.Wai (Application)
import qualified Network.Wai as Wai
import Network.Wai.Test
import Test.Hspec

data BoundaryFixtureAction = BoundaryFixtureAction
    deriving (Data, Typeable)

data PayrollPreparationError
    = MissingPayItem
    | ProviderUnavailable
    deriving (Bounded, Enum, Eq, Generic, Show)

data UnsafeSafeMessageError
    = UnsafeSafeMessage
    deriving (Generic)

instance DomainError UnsafeSafeMessageError where
    appErrorProjection UnsafeSafeMessage = AppErrorProjection
        { safeMessage = "<script>unsafe</script>"
        , severity = Blocking
        , recovery = UserFixRequired
        , retryDirective = DoNotRetry
        }

instance DomainError PayrollPreparationError where
    appErrorProjection MissingPayItem = AppErrorProjection
        { safeMessage = "Choose a pay item before continuing."
        , severity = Blocking
        , recovery = UserFixRequired
        , retryDirective = DoNotRetry
        }
    appErrorProjection ProviderUnavailable = AppErrorProjection
        { safeMessage = "The payroll provider is temporarily unavailable."
        , severity = Critical
        , recovery = Retryable
        , retryDirective = RetryUsingBoundaryPolicy
        }

tests :: Spec
tests = describe "typed application errors" do
    it "derives qualified namespaced codes and strips the Error type suffix" do
        domainErrorCodes @PayrollPreparationError
            `shouldBe`
                [ "test.application-error-spec.payroll-preparation/missing-pay-item"
                , "test.application-error-spec.payroll-preparation/provider-unavailable"
                ]
        appErrorCode (projectDomainError MissingPayItem)
            `shouldBe` "test.application-error-spec.payroll-preparation/missing-pay-item"

    it "projects every closed constructor to safe severity, recovery, and retry policy" do
        let projected = map (projectDomainError @PayrollPreparationError) [minBound .. maxBound]
        map appErrorSafeMessage projected
            `shouldBe`
                [ "Choose a pay item before continuing."
                , "The payroll provider is temporarily unavailable."
                ]
        map appErrorSeverity projected `shouldBe` [Blocking, Critical]
        map appErrorRecovery projected `shouldBe` [UserFixRequired, Retryable]
        map appErrorRetryDirective projected `shouldBe` [DoNotRetry, RetryUsingBoundaryPolicy]

    it "rejects mechanically derived code collisions in checked FrontendContract IR" do
        let duplicate = ErrorCodeIR "FirstError.First" "shared/error"
        let collision = ErrorCodeIR "SecondError.Second" "shared/error"
        let contract = FrontendContractIR
                { contractGlobals =
                    [ GlobalIR "Errors" "errors" [GlobalErrorCodesIR [duplicate, collision]]
                    ]
                , contractSurfaces = []
                }
        map (.diagnosticCode) (validateFrontendContractIR contract)
            `shouldContain` ["error-code-collision"]

    it "aggregates multiple ErrorCodes registrations into one generated contract" do
        let contract = FrontendContractIR
                { contractGlobals =
                    [ GlobalIR "First" "first" [GlobalErrorCodesIR [ErrorCodeIR "First.One" "first/one"]]
                    , GlobalIR "Second" "second" [GlobalErrorCodesIR [ErrorCodeIR "Second.Two" "second/two"]]
                    ]
                , contractSurfaces = []
                }
        case renderFrontendContractTypeScript contract of
            Left diagnostic -> expectationFailure (cs diagnostic)
            Right source -> do
                Text.count "export type AppErrorWire =" source `shouldBe` 1
                source `shouldSatisfy` Text.isInfixOf "\"first/one\" | \"second/two\""

    it "emits only the registered safe browser fields" do
        let appError = projectDomainError MissingPayItem
        let encoded = Aeson.toJSON (appErrorToWire appError)
        case encoded of
            Aeson.Object object -> do
                KeyMap.keys object `shouldMatchList` ["code", "severity", "recovery", "safeMessage"]
                object `shouldNotSatisfy` KeyMap.member "retryDirective"
                object `shouldNotSatisfy` KeyMap.member "id"
                object `shouldNotSatisfy` KeyMap.member "technicalContext"
            _ -> expectationFailure "AppErrorWire was not an object"

    it "generates the closed AppErrorWire browser contract" do
        frontendContractsTypeScript `shouldSatisfy` Text.isInfixOf "export type AppErrorWire = { code: AppErrorCode; severity: AppErrorSeverity; recovery: AppErrorRecovery; safeMessage: string };"
        frontendContractsTypeScript `shouldSatisfy` Text.isInfixOf "application.error.foundation.foundation/unexpected-synchronous-error"
        frontendContractsTypeScript `shouldSatisfy` Text.isInfixOf "export function parseAppErrorWire(value: unknown): AppErrorWire"
        frontendContractsTypeScript `shouldSatisfy` Text.isInfixOf "hasExactKeys(value, [\"code\", \"severity\", \"recovery\", \"safeMessage\"])"
        frontendContractsTypeScript `shouldNotSatisfy` Text.isInfixOf "encodeAppErrorWire"
        frontendContractsTypeScript `shouldNotSatisfy` Text.isInfixOf "retryDirective"

    it "selects explicit HTML, HTMX, and JSON request lanes" do
        appErrorRequestKind Wai.defaultRequest `shouldBe` HtmlRequest
        appErrorRequestKind (Wai.defaultRequest { Wai.requestHeaders = [("Accept", "application/json")] }) `shouldBe` JsonRequest
        appErrorRequestKind (Wai.defaultRequest { Wai.requestHeaders = [("HX-Request", "true"), ("Accept", "application/json")] }) `shouldBe` HtmxRequest

    it "adapts JSON failures to the safe fallback shape and blocking status" do
        response <- runErrorResponse (appErrorJsonResponse (projectDomainError MissingPayItem))
        simpleStatus response `shouldBe` status422
        Aeson.eitherDecode (simpleBody response)
            `shouldBe` Right (Aeson.object
                [ "code" Aeson..= ("test.application-error-spec.payroll-preparation/missing-pay-item" :: Text)
                , "severity" Aeson..= ("blocking" :: Text)
                , "recovery" Aeson..= ("user-fix-required" :: Text)
                , "safeMessage" Aeson..= ("Choose a pay item before continuing." :: Text)
                ])

    it "escapes safe messages in HTML and HTMX adapters" do
        let unsafeFixture = projectDomainError UnsafeSafeMessage
        htmlResponse <- runErrorResponse (appErrorHtmlResponse unsafeFixture)
        htmxResponse <- runErrorResponse (appErrorHtmxResponse unsafeFixture)
        LBS.toStrict (simpleBody htmlResponse) `shouldSatisfy` ByteString.isInfixOf "&lt;script&gt;unsafe&lt;/script&gt;"
        LBS.toStrict (simpleBody htmlResponse) `shouldNotSatisfy` ByteString.isInfixOf "<script>"
        LBS.toStrict (simpleBody htmxResponse) `shouldNotSatisfy` ByteString.isInfixOf "<!doctype html>"

    it "preserves IHP response control and asynchronous cancellation" do
        responseResult <- Exception.try @ResponseException $
            withSynchronousAppErrorFallback
                (respondAndStop (Wai.responseLBS status422 [] "kept"))
                (const (pure ()))
        responseResult `shouldSatisfy` isLeft

        notFoundResult <- Exception.try @RecordNotFoundException $
            withSynchronousAppErrorFallback
                (Exception.throwIO (RecordNotFoundException "masked query"))
                (const (pure ()))
        notFoundResult `shouldSatisfy` isLeft

        asyncResult <- Exception.try @Exception.AsyncException $
            withSynchronousAppErrorFallback
                (Exception.throwIO Exception.ThreadKilled)
                (const (pure ()))
        asyncResult `shouldBe` Left Exception.ThreadKilled

    it "converts other synchronous exceptions once at the outer fallback" do
        fallback <- withSynchronousAppErrorFallback
            (Exception.throwIO (userError "private provider detail"))
            (pure . appErrorSafeMessage)
        fallback `shouldBe` "We couldn't complete that request. Please try again."

    it "installs the safe fallback at the production Bepis action boundary" do
        let ?request = Wai.defaultRequest { Wai.requestHeaders = [("Accept", "application/json")] }
        result <- Exception.try @ResponseException $
            runBepis BoundaryFixtureAction BepisIntegrationAction $
                Exception.throwIO (userError "private action detail")
        case result of
            Left (ResponseException response) -> do
                rendered <- runErrorResponse response
                simpleStatus rendered `shouldBe` status500
                LBS.toStrict (simpleBody rendered) `shouldSatisfy` ByteString.isInfixOf "application.error.foundation.foundation/unexpected-synchronous-error"
                LBS.toStrict (simpleBody rendered) `shouldNotSatisfy` ByteString.isInfixOf "private action detail"
            Right () -> expectationFailure "unexpected action exception was not converted"

runErrorResponse :: Wai.Response -> IO SResponse
runErrorResponse response = runSession (request defaultRequest) app
  where
    app :: Application
    app _ respond = respond response
