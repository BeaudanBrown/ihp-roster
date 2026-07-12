module Application.Architecture.Contracts
    ( architectureContractsJson
    ) where

import Application.Bepis.Architecture (bepisArchitectureContractsValue)
import Application.Helper.FrontendContract.Surface.Architecture (frontendSurfaceArchitectureContractsValue)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.ByteString.Lazy as LBS
import IHP.Prelude

-- | Script/tooling-owned architecture contract bundle. Keeping this composition
-- outside Application.Bepis.Prelude avoids making ordinary request code depend
-- on architecture-only FrontendSurface rendering.
architectureContractsJson :: LBS.ByteString
architectureContractsJson = Aeson.encode architectureContractsValue

architectureContractsValue :: Aeson.Value
architectureContractsValue =
    case bepisArchitectureContractsValue of
        Aeson.Object object ->
            object
                |> KeyMap.insert "frontendSurfaceContracts" frontendSurfaceArchitectureContractsValue
                |> KeyMap.insert "generatedBy" (Aeson.String "Application.Architecture.Contracts")
                |> Aeson.Object
        other -> other
