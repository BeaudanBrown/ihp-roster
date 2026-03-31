module Web.View.Dashboard.Index where
import Web.View.Prelude

data IndexView = IndexView
    { liveDemoCount :: !Int
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
                    </div>
                </div>
            </div>
        </div>
    |]

renderLiveDemoCard :: Int -> Html
renderLiveDemoCard liveDemoCount = [hsx|
    <section id="dashboard-live-demo-fragment"
             class="app-panel"
             data-live-fragment-url={pathTo ShowDashboardLiveDemoContentAction}>
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
