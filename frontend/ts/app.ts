// Ordered to preserve the former Layout script startup sequence while esbuild
// shares generated validators and runtime helpers through one module graph.
import "./app-bootstrap";
import "./app-pwa";
import "./app-scrollbars";
import "./app-date-pickers";
import "./app-passkeys";
import "./app-live-updates";
import "./app-interactions";
import "./app-dialog-overlays";
import "./app-toasts";
import "./app-time-picker";
import "./app-horizontal-scroll";
import "./app-roster";
import "./app-xero";
import "./app-toggle-buttons";
import "./app-preferences";
