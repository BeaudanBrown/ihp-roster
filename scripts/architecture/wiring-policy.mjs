/**
 * @typedef {{ value: string, owner: string, reason: string, source: { path: string, line: number } }} WiringRegistryException
 * @typedef {{
 *   controllerRouteExceptions: readonly WiringRegistryException[],
 *   controllerMountExceptions: readonly WiringRegistryException[],
 *   frontendLayoutExceptions: readonly WiringRegistryException[]
 * }} WiringRegistryPolicy
 */

/**
 * Explicit exceptions to closed application wiring.
 *
 * Custom IHP routes still belong to their controller's AutoRoute registry and
 * are not exceptions. Websocket applications are a separate typed mount kind
 * and are not controller declarations. The frontend app.ts entrypoint is global
 * unless its output asset is listed here with an accountable subsystem owner
 * and specific reason; stale, ownerless, reasonless, or duplicate exceptions fail.
 *
 * Development tooling entrypoint: frontend/ts/dev-live-reload.ts, owned by the
 * frontend build/development runtime. Layout loads its /dev-live-reload.js output
 * only in development to consume IHP reload notifications without production
 * dependencies. It replaces dev-timer-tracking.ts and is outside the production
 * app.ts registry, not an exception to loading that application entrypoint.
 *
 * @type {WiringRegistryPolicy}
 */
export const wiringRegistryPolicy = Object.freeze({
  controllerRouteExceptions: Object.freeze([]),
  controllerMountExceptions: Object.freeze([]),
  frontendLayoutExceptions: Object.freeze([]),
});
