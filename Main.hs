module Main where
import IHP.Prelude

import Application.Helper.Profiling.Runtime (withDiagnosticProfilingRuntime)
import Application.Helper.Telemetry (withTelemetryRuntime)
import Config
import IHP.FrameworkConfig
import IHP.Job.Types
import IHP.RouterSupport
import qualified IHP.Server
import Web.FrontController
import Web.Types
import Web.Worker ()

instance FrontController RootApplication where
    controllers = [
            mountFrontController WebApplication
        ]

instance Worker RootApplication where
    workers _ = workers WebApplication

main :: IO ()
main = withDiagnosticProfilingRuntime (withTelemetryRuntime (IHP.Server.run config))
