module Test.FrontendAesonTypeScriptSpikeSpec
    ( tests
    ) where

import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy.Char8 as LBS
import qualified Data.Text as Text
import IHP.Prelude
import Test.Hspec

import Application.Helper.Frontend.AesonTypeScriptSpike

jsonText :: Aeson.ToJSON a => a -> Text
jsonText = cs . LBS.unpack . Aeson.encode

tests :: Spec
tests = describe "Frontend aeson-typescript spike" do
    it "generates a string union for a simple enum" do
        aesonTypeScriptSpikeTypeScript
            `shouldSatisfy` Text.isInfixOf "export type AesonTypeScriptSpikeSimpleEnum = \"alpha\" | \"beta\";"
        jsonText AesonTypeScriptSpikeAlpha `shouldBe` "\"alpha\""

    it "generates a discriminated union with a type tag" do
        aesonTypeScriptSpikeTypeScript `shouldSatisfy` Text.isInfixOf "type: \"select\";"
        jsonText (AesonTypeScriptSpikeSelect (AesonTypeScriptSpikeWireId "item-1"))
            `shouldBe` "{\"type\":\"select\",\"selectedId\":\"item-1\"}"

    it "represents Maybe fields as either nullable or optional based on Aeson options" do
        aesonTypeScriptSpikeTypeScript `shouldSatisfy` Text.isInfixOf "nullableNote: string | null;"
        aesonTypeScriptSpikeTypeScript `shouldSatisfy` Text.isInfixOf "optionalNote?: string;"
        jsonText (AesonTypeScriptSpikeNullableRecord (AesonTypeScriptSpikeWireId "row-1") Nothing)
            `shouldBe` "{\"nullableId\":\"row-1\",\"nullableNote\":null}"
        jsonText (AesonTypeScriptSpikeOptionalRecord "label" Nothing)
            `shouldBe` "{\"optionalLabel\":\"label\"}"

    it "uses a custom string-like wrapper inside nested wire messages" do
        let message =
                AesonTypeScriptSpikeMessage
                    { messageId = AesonTypeScriptSpikeWireId "message-1"
                    , messageMode = AesonTypeScriptSpikeBeta
                    , messageIntent = AesonTypeScriptSpikeClear "cancelled"
                    , messageNullable = AesonTypeScriptSpikeNullableRecord (AesonTypeScriptSpikeWireId "nullable-1") (Just "note")
                    , messageOptional = AesonTypeScriptSpikeOptionalRecord "optional" (Just "present")
                    , messageFragments =
                        [ AesonTypeScriptSpikeNullableRecord (AesonTypeScriptSpikeWireId "fragment-1") Nothing
                        ]
                    }

        aesonTypeScriptSpikeTypeScript `shouldSatisfy` Text.isInfixOf "messageFragments: AesonTypeScriptSpikeNullableRecord[];"
        jsonText message
            `shouldSatisfy` Text.isInfixOf "\"messageId\":\"message-1\""
