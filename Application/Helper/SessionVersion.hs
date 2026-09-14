module Application.Helper.SessionVersion
    ( authenticatedSessionVersionIsCurrent
    , clearAuthenticatedSessionVersion
    , markAuthenticatedSessionVersion
    , sessionVersionSessionKey
    ) where

import Generated.Types
import IHP.ControllerPrelude
import Web.Types ()

sessionVersionSessionKey :: ByteString
sessionVersionSessionKey = "bepis.userSessionVersion"

authenticatedSessionVersionIsCurrent :: (?context :: ControllerContext, ?request :: Request) => IO Bool
authenticatedSessionVersionIsCurrent =
    case currentUserOrNothing @User of
        Nothing -> pure True
        Just user -> do
            sessionVersion <- getSessionEither @Int sessionVersionSessionKey
            pure $
                case sessionVersion of
                    Left NotFoundError -> user.sessionVersion == 0
                    Left (ParseError _) -> False
                    Right version -> version == user.sessionVersion

markAuthenticatedSessionVersion :: (?context :: ControllerContext, ?request :: Request) => User -> IO ()
markAuthenticatedSessionVersion user =
    setSession sessionVersionSessionKey user.sessionVersion

clearAuthenticatedSessionVersion :: (?request :: Request) => IO ()
clearAuthenticatedSessionVersion =
    deleteSession sessionVersionSessionKey
