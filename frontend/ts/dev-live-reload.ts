// Development-only IHP notification client; never patches application DOM.
(function enableDevelopmentLiveReload() {
    const script = document.currentScript;
    const url = script instanceof HTMLScriptElement ? script.dataset.ws : undefined;
    if (!url) return;

    const socket = new WebSocket(url);
    let opened = false;
    socket.onopen = () => { opened = true; };
    socket.onmessage = ({ data }) => {
        if (data === "reload") {
            window.location.reload();
        } else if (data === "reload_assets") {
            for (const stylesheet of document.querySelectorAll<HTMLLinkElement>('link[rel="stylesheet"][href]')) {
                const href = new URL(stylesheet.href);
                href.searchParams.set("refresh", String(Date.now()));
                stylesheet.href = href.href;
            }
        }
    };
    socket.onclose = () => { if (opened) window.location.reload(); };

    // Navigation must not trigger another reload; restore a fresh client on BFCache return.
    window.addEventListener("pagehide", () => {
        socket.onmessage = null;
        socket.onclose = null;
        socket.close();
    });
    window.addEventListener("pageshow", (event) => {
        if (event.persisted) window.location.reload();
    });
})();
