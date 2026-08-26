module Test.TypedErrorCategorySpec (tests) where

import Application.Error.Boundary (withSynchronousAppErrorFallback)
import Application.Error.ExternalRuntime (externalRuntimeExceptionCategory,
                                          throwExternalRuntimeMessage)
import Application.Error.Parser (parserFailure)
import Application.Error.Runtime (ExternalRuntimeCategory (..), externalRuntimeInvariantFailure)
import Application.Error.Startup (startupInvariantFailure)
import Application.Error.Types (appErrorSafeMessage)
import qualified Control.Exception as Exception
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.Text as Text
import IHP.Prelude
import Test.Hspec

tests :: Spec
tests = describe "Typed error retained categories" do
    it "retains parser rejection as a typed parser result" do
        let parsed = AesonTypes.parseEither (\_ -> parserFailure "rejected fixture parser input") Aeson.Null :: Either String ()
        either (`shouldContain` "rejected fixture parser input") (const (expectationFailure "parser unexpectedly succeeded")) parsed

    it "renders deterministic startup diagnostics" do
        result <- Exception.try @Exception.ErrorCall (Exception.evaluate (startupInvariantFailure "checked registry fixture" :: ()))
        case result of
            Left exception -> cs (Exception.displayException exception) `shouldSatisfy` Text.isInfixOf "Bepis startup invariant failed: checked registry fixture"
            Right () -> expectationFailure "startup invariant unexpectedly returned"

    it "sanitizes external runtime exception display" do
        result <- Exception.try @Exception.SomeException (throwExternalRuntimeMessage ProviderRuntimeInvariant "provider response included a secret" :: IO ())
        case result of
            Left exception -> do
                externalRuntimeExceptionCategory exception `shouldBe` Just ProviderRuntimeInvariant
                cs (Exception.displayException exception) `shouldSatisfy` Text.isPrefixOf "Bepis external runtime boundary failed"
                Exception.displayException exception `shouldNotContain` "provider response included a secret"
            Right () -> expectationFailure "external runtime exception unexpectedly returned"

    it "projects impossible external runtime values at the synchronous request boundary" do
        invariant <- Exception.try @Exception.SomeException (Exception.evaluate (externalRuntimeInvariantFailure PersistedRuntimeInvariant "database cardinality fixture" :: Text))
        case invariant of
            Left exception -> externalRuntimeExceptionCategory exception `shouldBe` Just PersistedRuntimeInvariant
            Right _ -> expectationFailure "runtime invariant unexpectedly returned"
        observed <- withSynchronousAppErrorFallback
            (Exception.evaluate (externalRuntimeInvariantFailure PersistedRuntimeInvariant "database cardinality fixture" :: Text))
            (pure . appErrorSafeMessage)
        observed `shouldBe` "We couldn't complete that request. Please try again."
