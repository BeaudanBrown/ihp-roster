{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}

module Application.Helper.FrontendContract.Registry
    ( RegisteredFrontendContracts
    , checkedRegisteredFrontendContract
    , ensureRegisteredFrontendContract
    , registeredFrontendContractIR
    , validateFrontendContractStartup
    , validateRegisteredFrontendContract
    ) where

import Application.Helper.FrontendContract.App
import Application.Helper.FrontendContract.AppShell
import Application.Helper.FrontendContract.ClosedScalars
import Application.Helper.FrontendContract.DSL
import Application.Helper.FrontendContract.Error
import Application.Helper.FrontendContract.FeedbackDiagnostics
import Application.Helper.FrontendContract.HorizontalScroll
import Application.Helper.FrontendContract.Interaction
import Application.Helper.FrontendContract.IR
import Application.Helper.FrontendContract.LiveUpdate
import Application.Helper.FrontendContract.OrderedRange
import Application.Helper.FrontendContract.Overlay
import Application.Helper.FrontendContract.Passkey
import Application.Helper.FrontendContract.PwaInstall
import Application.Helper.FrontendContract.Reflect
import Application.Helper.FrontendContract.Surface.ContractIR (SurfaceContractIR (..))
import Application.Helper.FrontendContract.Surface.Reflect (ReflectSurfaceRegistry (..))
import Application.Helper.FrontendContract.Surface.Registry (RegisteredFrontendSurfaces)
import Application.Helper.FrontendContract.TimePicker
import Application.Helper.FrontendContract.Toggle
import Application.Helper.FrontendContract.UiRegion
import Application.Helper.FrontendContract.XeroCandidateFilter
import Control.Exception (Exception)
import qualified Control.Exception as Exception
import qualified Data.Bifunctor as Bifunctor
import qualified Data.Text.IO as Text
import IHP.Prelude
import System.Exit (exitFailure)
import System.IO (stderr)

-- | Root frontend browser contract registry. Global roots live here; Surface
-- roots are appended from the registered surface contract registry.
type RegisteredFrontendContracts =
    '[ AppContract
     , AppErrorContract
     , ClosedScalarContract
     , OverlayContract
     , AppShellContract
     , UiRegionContract
     , InteractionContract
     , ToggleContract
     , TimePickerContract
     , OrderedRangeContract
     , HorizontalScrollContract
     , PasskeyContract
     , PwaInstallContract
     , FeedbackDiagnosticsContract
     , XeroCandidateFilterContract
     , LiveUpdateContract
     ] :: [FrontendContractSpec]

reflectedRegisteredFrontendContractIR :: FrontendContractIR
reflectedRegisteredFrontendContractIR = FrontendContractIR
    { contractGlobals = reflectedGlobals.contractGlobals
    , contractSurfaces = reflectedSurfaces.contractSurfaces
    }
  where
    reflectedGlobals = reflectFrontendContracts @RegisteredFrontendContracts
    reflectedSurfaces = SurfaceContractIR
        { contractSurfaces = reflectSurfaceRegistry @RegisteredFrontendSurfaces
        }

newtype FrontendContractStartupException = FrontendContractStartupException Text
    deriving (Show)

instance Exception FrontendContractStartupException

registeredFrontendContractValidation :: Either [ContractDiagnostic] CheckedFrontendContract
registeredFrontendContractValidation = checkedFrontendContractIR reflectedRegisteredFrontendContractIR

checkedRegisteredFrontendContract :: CheckedFrontendContract
checkedRegisteredFrontendContract =
    case registeredFrontendContractValidation of
        Right checked -> checked
        Left diagnostics -> Exception.throw (FrontendContractStartupException (renderContractDiagnostics diagnostics))

validateFrontendContractStartup :: FrontendContractIR -> Either Text CheckedFrontendContract
validateFrontendContractStartup contract =
    Bifunctor.first renderContractDiagnostics (checkedFrontendContractIR contract)

validateRegisteredFrontendContract :: Either Text CheckedFrontendContract
validateRegisteredFrontendContract = validateFrontendContractStartup reflectedRegisteredFrontendContractIR

-- | Compatibility projection for tooling and tests. It can only be obtained
-- by unwrapping the opaque validated registry.
registeredFrontendContractIR :: FrontendContractIR
registeredFrontendContractIR = frontendContractIR checkedRegisteredFrontendContract

-- | Startup gate. Invalid programmer-owned contracts are rendered once before
-- listeners start and terminate the process without entering request handling.
ensureRegisteredFrontendContract :: IO ()
ensureRegisteredFrontendContract =
    case validateRegisteredFrontendContract of
        Right _ -> pure ()
        Left diagnostics -> do
            Text.hPutStrLn stderr "Invalid FrontendContract registry:"
            Text.hPutStr stderr diagnostics
            exitFailure
