module Web.View.Dashboard.Index where

import Application.Helper.View
import Web.View.Prelude

newtype IndexView = IndexView
    { liveDemoCount :: Int
    }

instance View IndexView where
    html IndexView { .. } = [hsx|
        <div class="row justify-content-center py-5">
            <div class="col-12 col-xl-8">
                <div class="app-panel">
                    <div class="app-panel-body d-flex flex-column gap-4">
                        <div class="d-flex flex-column gap-2">
                            <span class="text-uppercase small fw-semibold app-muted">Starter Dashboard</span>
                            <h1 class="h3 mb-0">Signed in as {currentUser.email}</h1>
                            <p class="app-muted mb-0">
                                This dashboard stays intentionally generic. The live demo below is the reusable
                                example consumer for the shared HTMX and websocket transport in this template.
                            </p>
                        </div>

                        <section id="dashboard-live-shell"
                                 data-live-update-owner="true"
                                 data-live-update-client-enabled="true"
                                 data-live-update-scope="dashboard-live-demo"
                                 data-live-updates-path="/live-updates">
                            {renderLiveDemoCard liveDemoCount}
                        </section>

                        <section class="app-panel">
                            <div class="app-panel-body d-flex flex-column gap-3">
                                <div>
                                    <h2 class="h5 mb-1">Runtime Rehydration Demo</h2>
                                    <p class="app-muted mb-0">
                                        Open the dialog below to inspect starter-template behavior after an HTMX swap.
                                        It demonstrates the shared overlay mount, flatpickr rehydration, and the reusable
                                        quarter-hour picker without any roster-specific code.
                                    </p>
                                </div>

                                <div class="d-flex flex-wrap gap-3">
                                    <button type="button"
                                            class="btn btn-outline-secondary"
                                            hx-get={ShowDashboardRuntimeDemoAction}
                                            hx-target={"#" <> dialogOverlayMountId}
                                            hx-swap="innerHTML"
                                            hx-push-url="false">
                                        Open Runtime Dialog
                                    </button>
                                    <span class="app-muted small align-self-center">
                                        Future pages can reuse this pattern for HTMX dialogs that need JS re-processing on swap.
                                    </span>
                                </div>
                            </div>
                        </section>
                    </div>
                </div>
            </div>
        </div>
    |]

renderLiveDemoCard :: Int -> Html
renderLiveDemoCard liveDemoCount = [hsx|
    <section id="dashboard-live-demo-fragment"
             class="app-panel"
             data-live-fragment-url={pathTo ShowDashboardLiveDemoContentAction}
             data-live-fragment-defer-until-blur="true">
        <div class="app-panel-body d-flex flex-column gap-3">
            <div class="d-flex flex-wrap justify-content-between align-items-start gap-3">
                <div>
                    <h2 class="h5 mb-1">Live Update Demo</h2>
                    <p class="app-muted mb-0">
                        Open the dashboard in two tabs, then increment from one tab to verify the other tab
                    updates over the shared websocket transport.
                    </p>
                </div>
                <span class="badge text-bg-primary px-3 py-2" id="dashboard-live-demo-count">
                    Live count: {tshow liveDemoCount}
                </span>
            </div>

            <div class="d-flex flex-column gap-2">
                <label class="form-label mb-0" for="dashboard-live-demo-notes">Deferred Refresh Field</label>
                <input id="dashboard-live-demo-notes"
                       type="text"
                       class="form-control"
                       placeholder="Focus here in another tab, then increment elsewhere to test blur-delayed refetch"/>
                <span class="app-muted small">
                    This fragment opts into blur-delayed invalidation handling. External live updates wait until the focused field blurs before the fragment is refetched.
                </span>
            </div>

            <form method="POST"
                  action={IncrementDashboardLiveDemoAction}
                  hx-post={IncrementDashboardLiveDemoAction}
                  hx-target="#dashboard-live-demo-fragment"
                  hx-swap="outerHTML"
                  class="d-flex flex-column flex-md-row align-items-md-center gap-3">
                <button type="submit" class="btn btn-primary">
                    Increment Live Demo
                </button>
                <span class="app-muted small">
                    The actor tab updates from the HTMX response. Other subscribed tabs refetch the same fragment after a websocket invalidation.
                </span>
            </form>
        </div>
    </section>
|]

renderDashboardRuntimeDemoDialog :: Html
renderDashboardRuntimeDemoDialog =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = "Runtime Rehydration Demo"
        , dialogOverlayBody = [hsx|
            <div class="d-flex flex-column gap-3">
                <p class="app-muted mb-0">
                    This dialog is loaded via HTMX into the shared overlay mount. Its controls prove that
                    `app:page-ready` re-initializes date inputs and the quarter-hour picker after swaps.
                </p>

                <div>
                    <label class="form-label" for="dashboard-runtime-demo-date">Date Field</label>
                    <input id="dashboard-runtime-demo-date"
                           type="date"
                           class="form-control"
                           value="2026-04-01"/>
                </div>

                <div>
                    <label class="form-label">Quarter-Hour Time Field</label>
                    <div id="dashboard-runtime-demo-time-field">
                        {renderTimePickerField "demoTime" "09:15" "06:00" "23:45" False}
                    </div>
                </div>
            </div>
        |]
        , dialogOverlayButtons =
            [ OverlayButton
                { overlayButtonLabel = "Close"
                , overlayButtonClass = "btn btn-outline-secondary"
                , overlayButtonAction = OverlayCloseAction
                }
            ]
        , dialogOverlayDialogClass = ""
        }
