module Web.Controller.Admin.Xero.ImportedPayItems
    ( archiveXeroImportedPayItemAction
    , importXeroPayItemsAction
    , openXeroPayItemImportAction
    ) where

import Application.Helper.View (ToastOverlayConfig)
import Application.Helper.Xero
import Application.Xero.Admin.ImportedPayItems
import Application.Xero.Admin.ReadModel (fetchActiveCurrentVenueXeroConnection)
import Application.Xero.Admin.ReferenceData (upsertXeroEarningsRate)
import Application.Xero.Connection
import Web.Controller.Admin.Xero.Responses (respondWithXeroPayItemsFragmentAndToast, xeroErrorToast, xeroSuccessToast)
import Web.Controller.Prelude
import Web.View.Admin.Xero.PayItems (renderXeroImportedPayItemImportDialog)

openXeroPayItemImportAction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
openXeroPayItemImportAction = do
    withFetchedXeroEarningsRates "fetch Xero pay items before importing" \connection _now fetchedRates -> do
        activeImports <- fetchActiveImportedXeroPayItems connection
        respondHtml (renderXeroImportedPayItemImportDialog (viableImportedPayItemCandidates activeImports fetchedRates))

importXeroPayItemsAction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
importXeroPayItemsAction = do
    let selectedRateIds = paramList @Text "xeroEarningsRateId"
    if null selectedRateIds
        then respondImportedPayItemMutation (Just (xeroErrorToast "Choose at least one Xero pay item to import."))
        else
            withFetchedXeroEarningsRates "import Xero pay items" \connection now fetchedRates -> do
                imported <- withTransaction do
                    forM_ fetchedRates (upsertXeroEarningsRate connection now)
                    importXeroEarningsRates connection now fetchedRates selectedRateIds
                respondImportedPayItemMutation (Just (xeroSuccessToast ("Imported " <> tshow (length imported) <> " Xero pay item" <> pluralSuffix imported <> ".")))

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
            _ <- archiveImportedXeroPayItem now "Archived from Xero admin" payItem
            respondImportedPayItemMutation (Just (xeroSuccessToast "Archived imported Xero pay item."))

withFetchedXeroEarningsRates :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Text -> (XeroConnection -> UTCTime -> [XeroEarningsRateRef] -> IO ()) -> IO ()
withFetchedXeroEarningsRates actionLabel action = do
    maybeConnection <- fetchActiveCurrentVenueXeroConnection
    case maybeConnection of
        Nothing -> respondImportedPayItemMutation (Just (xeroErrorToast "Connect Xero before importing pay items."))
        Just connection -> do
            readXeroConfig >>= \case
                Left message -> respondImportedPayItemMutation (Just (xeroErrorToast message))
                Right xeroConfig -> do
                    refreshResult <- refreshXeroConnectionAccessWithoutBroadcast xeroConfig connection
                    case refreshResult of
                        Left message -> respondImportedPayItemMutation (Just (xeroErrorToast message))
                        Right (refreshedConnection, accessToken) -> do
                            now <- getCurrentTime
                            xeroClient <- currentXeroClient
                            fetchEarningsRates xeroClient accessToken refreshedConnection.tenantId >>= \case
                                Left err -> respondImportedPayItemMutation (Just (xeroErrorToast ("Could not " <> actionLabel <> ": " <> xeroClientErrorText err)))
                                Right fetchedRates -> action refreshedConnection now fetchedRates

respondImportedPayItemMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Maybe ToastOverlayConfig -> IO ()
respondImportedPayItemMutation maybeToast =
    if isHtmxRequest
        then respondWithXeroPayItemsFragmentAndToast maybeToast
        else do
            setSuccessMessage "Updated imported Xero pay items."
            redirectTo XeroAction

pluralSuffix :: [a] -> Text
pluralSuffix [_] = ""
pluralSuffix _   = "s"
