module Web.Controller.Admin.Xero.ImportedPayItems
    ( archiveXeroImportedPayItemAction
    , importXeroPayItemsAction
    , openXeroPayItemImportAction
    ) where

import Application.Helper.LiveResource (LiveMutationResult (..))
import Application.Helper.View (ToastOverlayConfig (..),
                                ToastOverlayPosition (ToastBottomCenter),
                                renderToastOverlayHostOob)
import Application.Helper.Xero
import Application.Xero.Admin.ImportedPayItems
import Application.Xero.Admin.ReadModel (fetchActiveCurrentVenueXeroConnection)
import Application.Xero.Connection
import Web.Admin.Xero.Mutations
import Web.Controller.Admin.Xero.Responses (respondWithXeroPayItemsFragmentAndToast,
                                            respondWithXeroPayItemsFragmentAndToastAndCloseDialog,
                                            xeroErrorToast, xeroSuccessToast)
import Web.Controller.Prelude
import Web.View.Admin.Xero.PayItems (renderXeroImportedPayItemImportDialog,
                                     renderXeroImportedPayItemImportErrorDialog,
                                     renderXeroImportedPayItemImportLoadingDialog)

openXeroPayItemImportAction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
openXeroPayItemImportAction = do
    let shouldLoadCandidates = paramOrDefault @Bool False "loadCandidates"
    if isHtmxRequest && not shouldLoadCandidates
        then respondHtml renderXeroImportedPayItemImportLoadingDialog
        else
            withFetchedXeroEarningsRates "fetch Xero pay items before importing" respondImportedPayItemDialogError \connection _now fetchedRates -> do
                activeImports <- fetchActiveImportedXeroPayItems connection
                respondHtml (renderXeroImportedPayItemImportDialog (viableImportedPayItemCandidates activeImports fetchedRates))

importXeroPayItemsAction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
importXeroPayItemsAction = do
    let selectedRateIds = paramList @Text "xeroEarningsRateId"
    withFetchedXeroEarningsRates "import Xero pay items" respondImportedPayItemDialogToast \connection now fetchedRates -> do
        if null selectedRateIds
            then do
                activeImports <- fetchActiveImportedXeroPayItems connection
                respondImportedPayItemDialog (viableImportedPayItemCandidates activeImports fetchedRates) (Just (xeroErrorToast "Choose at least one Xero pay item to import."))
            else do
                LiveMutationResult { liveMutationValue = imported } <- importXeroEarningsRatesMutation connection now fetchedRates selectedRateIds
                respondImportedPayItemImportSuccess (Just (xeroSuccessToast ("Imported " <> tshow (length imported) <> " Xero pay item" <> pluralSuffix imported <> ".")))

archiveXeroImportedPayItemAction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id XeroImportedPayItem -> IO ()
archiveXeroImportedPayItemAction importedPayItemId = do
    maybePayItem <-
        query @XeroImportedPayItem
            |> filterWhere (#id, importedPayItemId)
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> fetchOneOrNothing
    case maybePayItem of
        Nothing -> respondImportedPayItemMutation (Just (xeroErrorToast "Imported Xero pay item was not found."))
        Just payItem -> do
            now <- getCurrentTime
            _ <- archiveImportedXeroPayItemMutation now "Archived from Xero admin" payItem
            respondImportedPayItemMutation (Just (xeroSuccessToast "Archived imported Xero pay item."))

withFetchedXeroEarningsRates :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Text -> (ToastOverlayConfig -> IO ()) -> (XeroConnection -> UTCTime -> [XeroEarningsRateRef] -> IO ()) -> IO ()
withFetchedXeroEarningsRates actionLabel respondError action = do
    maybeConnection <- fetchActiveCurrentVenueXeroConnection
    case maybeConnection of
        Nothing -> respondError (xeroErrorToast "Connect Xero before importing pay items.")
        Just connection -> do
            readXeroConfig >>= \case
                Left message -> respondError (xeroErrorToast message)
                Right xeroConfig -> do
                    refreshResult <- refreshXeroConnectionAccessWithoutBroadcast xeroConfig connection
                    case refreshResult of
                        Left message -> respondError (xeroErrorToast message)
                        Right (refreshedConnection, accessToken) -> do
                            now <- getCurrentTime
                            xeroClient <- currentXeroClient
                            fetchEarningsRates xeroClient accessToken refreshedConnection.tenantId >>= \case
                                Left err -> respondError (xeroErrorToast ("Could not " <> actionLabel <> ": " <> xeroClientErrorText err))
                                Right fetchedRates -> action refreshedConnection now fetchedRates

respondImportedPayItemMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Maybe ToastOverlayConfig -> IO ()
respondImportedPayItemMutation maybeToast =
    if isHtmxRequest
        then respondWithXeroPayItemsFragmentAndToast maybeToast
        else do
            setSuccessMessage "Updated imported Xero pay items."
            redirectTo XeroAction

respondImportedPayItemImportSuccess :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Maybe ToastOverlayConfig -> IO ()
respondImportedPayItemImportSuccess maybeToast =
    if isHtmxRequest
        then respondWithXeroPayItemsFragmentAndToastAndCloseDialog maybeToast
        else do
            setSuccessMessage "Updated imported Xero pay items."
            redirectTo XeroAction

respondImportedPayItemDialog :: (?context :: ControllerContext, ?request :: Request) => [XeroImportedPayItemCandidate] -> Maybe ToastOverlayConfig -> IO ()
respondImportedPayItemDialog candidates maybeToast =
    if isHtmxRequest
        then respondHtml $
            mconcat
                [ renderXeroImportedPayItemImportDialog candidates
                , maybe mempty (\toast -> renderToastOverlayHostOob ToastBottomCenter [toast]) maybeToast
                ]
        else do
            maybe (pure ()) (setErrorMessage . (.toastOverlayMessage)) maybeToast
            redirectTo XeroAction

respondImportedPayItemDialogToast :: (?context :: ControllerContext, ?request :: Request) => ToastOverlayConfig -> IO ()
respondImportedPayItemDialogToast toast =
    if isHtmxRequest
        then respondHtml (renderToastOverlayHostOob ToastBottomCenter [toast])
        else do
            setErrorMessage toast.toastOverlayMessage
            redirectTo XeroAction

respondImportedPayItemDialogError :: (?context :: ControllerContext, ?request :: Request) => ToastOverlayConfig -> IO ()
respondImportedPayItemDialogError toast =
    if isHtmxRequest
        then respondHtml $
            mconcat
                [ renderXeroImportedPayItemImportErrorDialog toast.toastOverlayMessage
                , renderToastOverlayHostOob ToastBottomCenter [toast]
                ]
        else do
            setErrorMessage toast.toastOverlayMessage
            redirectTo XeroAction

pluralSuffix :: [a] -> Text
pluralSuffix [_] = ""
pluralSuffix _   = "s"
