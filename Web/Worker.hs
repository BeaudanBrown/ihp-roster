module Web.Worker where

import Application.Job.App ()
import Generated.Types
import IHP.Job.Runner
import IHP.Job.Types
import Web.Types

instance Worker WebApplication where
    workers _ =
        [ worker @AppJob
        ]
