"use strict";
(() => {
  // frontend/ts/dev-live-reload.ts
  (function enableDevelopmentLiveReload() {
    const script = document.currentScript;
    const url = script instanceof HTMLScriptElement ? script.dataset.ws : void 0;
    if (!url) return;
    const socket = new WebSocket(url);
    let opened = false;
    socket.onopen = () => {
      opened = true;
    };
    socket.onmessage = ({ data }) => {
      if (data === "reload") {
        window.location.reload();
      } else if (data === "reload_assets") {
        for (const stylesheet of document.querySelectorAll('link[rel="stylesheet"][href]')) {
          const href = new URL(stylesheet.href);
          href.searchParams.set("refresh", String(Date.now()));
          stylesheet.href = href.href;
        }
      }
    };
    socket.onclose = () => {
      if (opened) window.location.reload();
    };
    window.addEventListener("pagehide", () => {
      socket.onmessage = null;
      socket.onclose = null;
      socket.close();
    });
    window.addEventListener("pageshow", (event) => {
      if (event.persisted) window.location.reload();
    });
  })();
})();
