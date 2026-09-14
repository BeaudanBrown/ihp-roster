module Main where
import IHP.Prelude

import Application.Helper.Profiling.Runtime (withDiagnosticProfilingRuntime)
import Application.Helper.Telemetry (withTelemetryRuntime)
import Config
import IHP.FrameworkConfig
import IHP.RouterSupport
import qualified IHP.Server
import Web.FrontController () -- Mounted controller instance.
import Web.Types

instance FrontController RootApplication where
    controllers = [
            mountFrontController WebApplication
        ]

main :: IO ()
main = withDiagnosticProfilingRuntime (withTelemetryRuntime (IHP.Server.run config))
