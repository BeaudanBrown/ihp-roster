-- Diagnostic callbacks for disposable verification services, never gate authority.
module Test.VerificationPhase (verificationReady) where

import qualified Control.Exception as Exception
import Control.Monad (void)
import IHP.Prelude
import qualified Prelude
import System.Environment (lookupEnv)
import System.FilePath ((</>))
import qualified System.Process as Process
import Text.Read (readMaybe)

-- Only constant public phase names and the launcher's numeric shard scope cross
-- this boundary. No URLs, database names, tokens or job payloads are emitted.
verificationReady :: String -> IO ()
verificationReady phase = do
    target <- lookupEnv "BEPIS_VERIFICATION_EVENTS"
    case target of
        Just value | value /= "" -> do
            scriptsRoot <- lookupEnv "BEPIS_SCRIPTS_ROOT"
            scopeText <- lookupEnv "BEPIS_VERIFICATION_SCOPE"
            case (scriptsRoot, scopeText >>= readMaybe @Int) of
                (Just root, Just scope) | scope >= 0 && scope <= 65535 ->
                    void $ Exception.try @Exception.IOException $
                        Process.withCreateProcess
                            ((Process.proc "python3"
                                [ "-S", root </> "../../../scripts/profiling/verification-measure.py"
                                , "event", "--phase", phase, "--scope", Prelude.show scope, "--edge", "ready"
                                ])
                                { Process.std_in = Process.NoStream
                                , Process.std_out = Process.NoStream
                                , Process.std_err = Process.Inherit
                                , Process.close_fds = True
                                })
                            (\_ _ _ process -> Process.waitForProcess process)
                _ -> pure ()
        _ -> pure ()
