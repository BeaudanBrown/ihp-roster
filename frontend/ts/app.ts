import type { OverlayLane } from "./generated/contracts";

// App-owned browser behavior is split by concern across the app-*.js files
// loaded from Web.View.Layout.scripts. Keep this file as a compatibility
// endpoint for deployments and cached pages that still request /app.js.
type _GeneratedContractSmokeTest = OverlayLane;
