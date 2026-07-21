"use strict";
(() => {
  // frontend/ts/generated/contracts.ts
  function isRecord(value) {
    return typeof value === "object" && value !== null && !Array.isArray(value);
  }
  function hasExactKeys(value, keys, requiredKeys = keys) {
    const valueKeys = Object.keys(value);
    return valueKeys.every((key) => keys.includes(key)) && requiredKeys.every((key) => Object.prototype.hasOwnProperty.call(value, key));
  }
  var pageReadyEvent = "bepis:page-ready";
  var dialogDismissedEvent = "bepis:dialog-dismissed";
  var dialogCloseDomAttr = "data-bepis-dialog-close";
  function isPasskeySetupPromptMode(value) {
    return typeof value === "string" && ["first-passkey", "additional-device"].includes(value);
  }
  function isPasskeyFlowConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["tag", "beginUrl", "finishUrl", "successRedirect", "statusKey", "waitingMessage", "successMessage", "unsupportedMessage", "failureMessage", "pendingLabel", "cancelledMessage"], ["tag", "beginUrl", "finishUrl", "statusKey", "waitingMessage", "successMessage", "unsupportedMessage", "failureMessage", "pendingLabel", "cancelledMessage"]) && value["tag"] === "login" && typeof value["beginUrl"] === "string" && typeof value["finishUrl"] === "string" && (!("successRedirect" in value) || typeof value["successRedirect"] === "string") && typeof value["statusKey"] === "string" && typeof value["waitingMessage"] === "string" && typeof value["successMessage"] === "string" && typeof value["unsupportedMessage"] === "string" && typeof value["failureMessage"] === "string" && typeof value["pendingLabel"] === "string" && typeof value["cancelledMessage"] === "string" || isRecord(value) && hasExactKeys(value, ["tag", "beginUrl", "finishUrl", "successRedirect", "statusKey", "waitingMessage", "successMessage", "unsupportedMessage", "failureMessage", "pendingLabel", "cancelledMessage"], ["tag", "beginUrl", "finishUrl", "statusKey", "waitingMessage", "successMessage", "unsupportedMessage", "failureMessage", "pendingLabel", "cancelledMessage"]) && value["tag"] === "registration" && typeof value["beginUrl"] === "string" && typeof value["finishUrl"] === "string" && (!("successRedirect" in value) || typeof value["successRedirect"] === "string") && typeof value["statusKey"] === "string" && typeof value["waitingMessage"] === "string" && typeof value["successMessage"] === "string" && typeof value["unsupportedMessage"] === "string" && typeof value["failureMessage"] === "string" && typeof value["pendingLabel"] === "string" && typeof value["cancelledMessage"] === "string" || isRecord(value) && hasExactKeys(value, ["tag", "promptUserKey", "setupPromptMode"], ["tag", "promptUserKey", "setupPromptMode"]) && value["tag"] === "setup-prompt" && typeof value["promptUserKey"] === "string" && isPasskeySetupPromptMode(value["setupPromptMode"]);
  }
  function parsePasskeyFlowConfig(value) {
    if (isPasskeyFlowConfig(value)) return value;
    throw new Error("Invalid PasskeyFlowConfig");
  }
  var passkeyFirstPasskeyMode = "first-passkey";
  var passkeyAdditionalDeviceMode = "additional-device";
  var passkeyLoginDomAttr = "data-bepis-passkey-login";
  var passkeyRegistrationDomAttr = "data-bepis-passkey-registration";
  var passkeySetupPromptDomAttr = "data-bepis-passkey-setup-prompt";
  var passkeyActionButtonDomAttr = "data-bepis-passkey-action-button";
  var passkeyDeviceNameDomAttr = "data-bepis-passkey-device-name";
  var passkeyStatusDomAttr = "data-bepis-passkey-status";
  var passkeyRecoveryDomAttr = "data-bepis-passkey-recovery";
  var passkeyDismissalDomAttr = "data-bepis-passkey-dismissal";
  var passkeyFlowConfigDomAttr = "data-bepis-passkey-flow-config";

  // frontend/ts/passkeys/base64url.ts
  function base64UrlToArrayBuffer(value) {
    const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
    const padded = normalized + "=".repeat((4 - normalized.length % 4) % 4);
    const binary = globalThis.atob(padded);
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) {
      bytes[index] = binary.charCodeAt(index);
    }
    return bytes.buffer;
  }
  function arrayBufferToBase64Url(buffer) {
    const bytes = new Uint8Array(buffer);
    let binary = "";
    bytes.forEach(function(byte) {
      binary += String.fromCharCode(byte);
    });
    return globalThis.btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
  }

  // frontend/ts/passkeys/storage.ts
  function localStorageKeyForPasskey(userId, key) {
    return `ihpRoster.${key}.${userId}`;
  }

  // frontend/ts/shared/dom.ts
  function isElement(value) {
    return typeof Element !== "undefined" && value instanceof Element;
  }
  function isDocument(value) {
    return typeof Document !== "undefined" && value instanceof Document;
  }
  function isDocumentFragment(value) {
    return typeof DocumentFragment !== "undefined" && value instanceof DocumentFragment;
  }
  function isDomRoot(value) {
    return isElement(value) || isDocument(value) || isDocumentFragment(value);
  }

  // frontend/ts/shared/exhaustive.ts
  function assertNever(value, message = "Unexpected generated union variant") {
    throw new Error(`${message}: ${JSON.stringify(value)}`);
  }

  // frontend/ts/shared/lifecycle.ts
  function eventDetailRecord(event) {
    if (typeof CustomEvent === "undefined" || !(event instanceof CustomEvent)) return null;
    if (event.detail === null || typeof event.detail !== "object") return null;
    return event.detail;
  }
  function detailTarget(event, key) {
    return eventDetailRecord(event)?.[key];
  }
  function onAppPageReady(handler) {
    if (typeof document === "undefined") return;
    document.addEventListener(pageReadyEvent, handler);
  }

  // frontend/ts/app-passkeys.ts
  var PasskeyStatusError = class extends Error {
    constructor(statusMessage) {
      super(statusMessage);
      this.statusMessage = statusMessage;
    }
  };
  var initializedPasskeyFlows = /* @__PURE__ */ new WeakSet();
  var automaticPromptDismissals = /* @__PURE__ */ new WeakSet();
  var passkeyFlowSelector = [
    passkeyLoginDomAttr,
    passkeyRegistrationDomAttr,
    passkeySetupPromptDomAttr
  ].map(roleSelector).join(",");
  function parsePasskeyFlowConfiguration(raw) {
    const config = parsePasskeyFlowConfig(JSON.parse(raw));
    switch (config.tag) {
      case "login":
      case "registration":
        requirePasskeyConfigText("begin URL", config.beginUrl);
        requirePasskeyConfigText("finish URL", config.finishUrl);
        if (config.successRedirect !== void 0) {
          requirePasskeyConfigText("success redirect", config.successRedirect);
        }
        requirePasskeyConfigText("status relationship", config.statusKey);
        requirePasskeyConfigText("waiting message", config.waitingMessage);
        requirePasskeyConfigText("success message", config.successMessage);
        requirePasskeyConfigText("unsupported message", config.unsupportedMessage);
        requirePasskeyConfigText("failure message", config.failureMessage);
        requirePasskeyConfigText("pending label", config.pendingLabel);
        requirePasskeyConfigText("cancelled message", config.cancelledMessage);
        return config;
      case "setup-prompt":
        requirePasskeyConfigText("prompt user key", config.promptUserKey);
        return config;
      default:
        return assertNever(config, "Unexpected generated passkey flow");
    }
  }
  function requirePasskeyConfigText(fieldName, value) {
    if (value.trim().length === 0) {
      throw new Error(`PasskeyFlowConfig ${fieldName} must not be empty`);
    }
  }
  function roleSelector(attribute) {
    return `[${attribute}]`;
  }
  function defaultDiagnosticReporter(diagnostic2) {
    console.error?.("Invalid generated passkey configuration", diagnostic2);
  }
  function diagnostic(element, code, message) {
    return {
      code,
      elementId: element.id || null,
      message
    };
  }
  function rootsWithRole(root, attribute) {
    const selector = roleSelector(attribute);
    const roots = Array.from(root.querySelectorAll(selector));
    if (root instanceof HTMLElement && root.matches(selector)) roots.unshift(root);
    return roots;
  }
  function ownedElements(root, attribute) {
    return Array.from(root.querySelectorAll(roleSelector(attribute))).filter((element) => element.closest(passkeyFlowSelector) === root);
  }
  function roleIsTrue(element, attribute) {
    return element.getAttribute(attribute) === "true";
  }
  function parseFlowForRoot(root, report) {
    const rawConfig = root.getAttribute(passkeyFlowConfigDomAttr);
    try {
      if (rawConfig === null) throw new Error(`Missing ${passkeyFlowConfigDomAttr}`);
      return parsePasskeyFlowConfiguration(rawConfig);
    } catch (error) {
      report(diagnostic(
        root,
        "invalid-flow-config",
        error instanceof Error ? error.message : String(error)
      ));
      return null;
    }
  }
  function expectedFlowRole(config) {
    switch (config.tag) {
      case "login":
        return passkeyLoginDomAttr;
      case "registration":
        return passkeyRegistrationDomAttr;
      case "setup-prompt":
        return passkeySetupPromptDomAttr;
      default:
        return assertNever(config, "Unexpected generated passkey flow");
    }
  }
  function validateFlowRole(root, config, report) {
    const expected = expectedFlowRole(config);
    const roleAttributes = [
      passkeyLoginDomAttr,
      passkeyRegistrationDomAttr,
      passkeySetupPromptDomAttr
    ].filter((attribute) => root.hasAttribute(attribute));
    if (roleAttributes.length !== 1 || roleAttributes[0] !== expected || !roleIsTrue(root, expected)) {
      report(diagnostic(root, "invalid-flow-role", `Passkey flow ${config.tag} must have exactly its generated root role`));
      return false;
    }
    return true;
  }
  function readAction(root, report) {
    const actions = ownedElements(root, passkeyActionButtonDomAttr);
    if (actions.length !== 1 || !(actions[0] instanceof HTMLButtonElement) || !roleIsTrue(actions[0], passkeyActionButtonDomAttr)) {
      report(diagnostic(root, "invalid-action-relationship", "Passkey login or registration requires one local generated action button"));
      return null;
    }
    return actions[0];
  }
  function readStatus(root, config, expectsRecovery, report) {
    const messages = ownedElements(root, passkeyStatusDomAttr).filter((element) => element.getAttribute(passkeyStatusDomAttr) === config.statusKey);
    if (messages.length !== 1) {
      report(diagnostic(root, "invalid-status-relationship", "Passkey flow requires one matching local generated status relationship"));
      return null;
    }
    const message = messages[0];
    const region = message.parentElement;
    if (!(region instanceof HTMLElement) || region.getAttribute("role") !== "status" || message.closest(passkeyFlowSelector) !== root) {
      report(diagnostic(message, "invalid-status-relationship", "Passkey status must be inside its local native status region"));
      return null;
    }
    const recoveries = ownedElements(root, passkeyRecoveryDomAttr).filter((element) => element.getAttribute(passkeyRecoveryDomAttr) === config.statusKey);
    if (recoveries.length !== (expectsRecovery ? 1 : 0)) {
      report(diagnostic(root, "invalid-recovery-relationship", `Passkey flow requires ${expectsRecovery ? 1 : 0} local recovery region(s)`));
      return null;
    }
    if (!expectsRecovery) {
      return { message, region, recovery: null, recoveryCode: null };
    }
    const recovery = recoveries[0];
    const recoveryCodes = Array.from(recovery.querySelectorAll("code")).filter((element) => element.closest(passkeyFlowSelector) === root);
    const recoveryLinks = Array.from(recovery.querySelectorAll("a")).filter((element) => element.closest(passkeyFlowSelector) === root);
    const expectedLinkCount = config.successRedirect === void 0 ? 0 : 1;
    if (recoveryCodes.length !== 1 || recoveryLinks.length !== expectedLinkCount) {
      report(diagnostic(recovery, "invalid-recovery-relationship", "Passkey recovery region must contain its server-rendered code and continuation copy"));
      return null;
    }
    return {
      message,
      region,
      recovery,
      recoveryCode: recoveryCodes[0]
    };
  }
  function readLoginControl(root, config, report) {
    const action = readAction(root, report);
    const status = readStatus(root, config, false, report);
    if (action === null || status === null) return null;
    if (ownedElements(root, passkeyDeviceNameDomAttr).length !== 0) {
      report(diagnostic(root, "invalid-device-name-relationship", "Passkey login must not contain a registration device-name role"));
      return null;
    }
    return { root, action, config, status };
  }
  function readRegistrationControl(root, config, report) {
    const action = readAction(root, report);
    const status = readStatus(root, config, true, report);
    const deviceNames = ownedElements(root, passkeyDeviceNameDomAttr);
    if (deviceNames.length !== 1 || !(deviceNames[0] instanceof HTMLInputElement) || !roleIsTrue(deviceNames[0], passkeyDeviceNameDomAttr)) {
      report(diagnostic(root, "invalid-device-name-relationship", "Passkey registration requires one local generated device-name input"));
      return null;
    }
    if (action === null || status === null) return null;
    return { root, action, config, deviceName: deviceNames[0], status };
  }
  function readPromptControl(root, config, report) {
    const dismissals = ownedElements(root, passkeyDismissalDomAttr);
    if (dismissals.length !== 1 || !(dismissals[0] instanceof HTMLButtonElement) || !roleIsTrue(dismissals[0], passkeyDismissalDomAttr)) {
      report(diagnostic(root, "invalid-dismissal-relationship", "Passkey setup prompt requires one local generated dismissal control"));
      return null;
    }
    if (!roleIsTrue(dismissals[0], dialogCloseDomAttr)) {
      report(diagnostic(dismissals[0], "invalid-overlay-dismissal-role", "Passkey prompt dismissal must use the generated dialog-close role"));
      return null;
    }
    return { root, config, dismissal: dismissals[0] };
  }
  function initializePasskeyRoot(root, report = defaultDiagnosticReporter) {
    if (initializedPasskeyFlows.has(root)) return;
    initializedPasskeyFlows.add(root);
    const config = parseFlowForRoot(root, report);
    if (config === null || !validateFlowRole(root, config, report)) return;
    switch (config.tag) {
      case "login": {
        const control = readLoginControl(root, config, report);
        if (control === null) return;
        control.action.addEventListener("click", () => {
          void runPasskeyLogin(control);
        });
        return;
      }
      case "registration": {
        const control = readRegistrationControl(root, config, report);
        if (control === null) return;
        control.action.addEventListener("click", () => {
          void runPasskeyRegistration(control);
        });
        return;
      }
      case "setup-prompt": {
        const control = readPromptControl(root, config, report);
        if (control === null) return;
        initializePasskeySetupPrompt(control);
        return;
      }
      default:
        assertNever(config, "Unexpected generated passkey flow");
    }
  }
  function initializePasskeySetupPrompt(control) {
    control.root.addEventListener(dialogDismissedEvent, () => {
      if (automaticPromptDismissals.has(control.root)) {
        automaticPromptDismissals.delete(control.root);
        return;
      }
      dismissPasskeyPrompt(control.config.promptUserKey);
    }, { once: true });
    if (!passkeysAreAvailable() || isPasskeyPromptDismissed(control.config.promptUserKey) || promptModeAlreadyConfigured(control.config)) {
      automaticPromptDismissals.add(control.root);
      control.dismissal.click();
    }
  }
  function promptModeAlreadyConfigured(config) {
    switch (config.setupPromptMode) {
      case passkeyFirstPasskeyMode:
        return false;
      case passkeyAdditionalDeviceMode:
        return hasPasskeySeen(config.promptUserKey);
      default:
        return assertNever(config.setupPromptMode, "Unexpected generated passkey setup prompt mode");
    }
  }
  async function runPasskeyLogin(control) {
    await withPasskeyButton(control, async () => {
      setPasskeyStatus(control.status, "info", control.config.waitingMessage);
      const beginResponse = await postJson(control.config.beginUrl, control.config.failureMessage);
      const credential = await window.navigator.credentials.get({
        publicKey: authenticationOptionsToNative(beginResponse)
      });
      if (!(credential instanceof PublicKeyCredential)) throw new PasskeyStatusError(control.config.cancelledMessage);
      const finishResponse = await postJson(
        control.config.finishUrl,
        control.config.failureMessage,
        serializeAuthenticationCredential(credential)
      );
      markPasskeySeen(finishResponse.userId);
      setPasskeyStatus(control.status, "success", control.config.successMessage);
      redirectAfterPasskeySuccess(control.config, finishResponse);
    });
  }
  async function runPasskeyRegistration(control) {
    await withPasskeyButton(control, async () => {
      setPasskeyStatus(control.status, "info", control.config.waitingMessage);
      const beginResponse = await postJson(control.config.beginUrl, control.config.failureMessage);
      const credential = await window.navigator.credentials.create({
        publicKey: registrationOptionsToNative(beginResponse)
      });
      if (!(credential instanceof PublicKeyCredential)) throw new PasskeyStatusError(control.config.cancelledMessage);
      const finishResponse = await postJson(
        control.config.finishUrl,
        control.config.failureMessage,
        registrationPayload(control, credential)
      );
      markPasskeySeen(finishResponse.userId);
      if (finishResponse.recoveryCode) {
        setRecoveryCodeStatus(control.status, finishResponse.recoveryCode);
      } else {
        setPasskeyStatus(control.status, "success", control.config.successMessage);
        redirectAfterPasskeySuccess(control.config, finishResponse);
      }
    });
  }
  async function withPasskeyButton(control, callback) {
    if (!passkeysAreAvailable()) {
      setPasskeyStatus(control.status, "danger", control.config.unsupportedMessage);
      return;
    }
    const originalHtml = control.action.innerHTML;
    control.action.disabled = true;
    const spinner = document.createElement("span");
    spinner.className = "spinner-border spinner-border-sm me-2";
    spinner.setAttribute("aria-hidden", "true");
    control.action.replaceChildren(spinner, document.createTextNode(control.config.pendingLabel));
    try {
      await callback();
    } catch (error) {
      setPasskeyStatus(
        control.status,
        "danger",
        passkeyStatusMessageForError(control.config, error)
      );
    } finally {
      control.action.disabled = false;
      control.action.innerHTML = originalHtml;
    }
  }
  function passkeyStatusMessageForError(config, error) {
    if (error instanceof PasskeyStatusError) return error.statusMessage;
    if (isPasskeyCancellation(error)) return config.cancelledMessage;
    return config.failureMessage;
  }
  function isPasskeyCancellation(error) {
    return typeof DOMException !== "undefined" && error instanceof DOMException && (error.name === "AbortError" || error.name === "NotAllowedError");
  }
  async function postJson(url, failureMessage, payload) {
    const hasPayload = payload !== void 0;
    const response = await window.fetch(url, {
      method: "POST",
      credentials: "same-origin",
      headers: hasPayload ? {
        Accept: "application/json",
        "Content-Type": "application/json"
      } : {
        Accept: "application/json"
      },
      body: hasPayload ? JSON.stringify(payload) : void 0
    });
    const json = await response.json().catch(() => ({}));
    if (!response.ok) {
      if (typeof json.redirectTo === "string") {
        window.location.assign(json.redirectTo);
      }
      throw new PasskeyStatusError(failureMessage);
    }
    return json;
  }
  function setPasskeyStatus(status, tone, message) {
    status.message.hidden = false;
    status.message.textContent = message;
    if (status.recovery !== null) status.recovery.hidden = true;
    setPasskeyStatusTone(status.region, tone);
  }
  function setRecoveryCodeStatus(status, recoveryCode) {
    if (status.recovery === null || status.recoveryCode === null) return;
    status.message.hidden = true;
    status.recoveryCode.textContent = recoveryCode;
    status.recovery.hidden = false;
    setPasskeyStatusTone(status.region, "warning");
  }
  function setPasskeyStatusTone(region, tone) {
    region.classList.remove("d-none", "alert-info", "alert-success", "alert-danger", "alert-warning");
    region.classList.add(`alert-${tone}`);
  }
  function redirectAfterPasskeySuccess(config, response) {
    const redirectTo = response.redirectTo || config.successRedirect;
    if (redirectTo === void 0 || redirectTo === "") return;
    window.location.assign(redirectTo);
  }
  function localStorageKey(userId, key) {
    return localStorageKeyForPasskey(userId, key);
  }
  function markPasskeySeen(userId) {
    if (userId === void 0 || userId === "") return;
    try {
      window.localStorage.setItem(localStorageKey(userId, "passkeySeen"), "1");
    } catch (_error) {
    }
  }
  function hasPasskeySeen(userId) {
    try {
      return window.localStorage.getItem(localStorageKey(userId, "passkeySeen")) === "1";
    } catch (_error) {
      return false;
    }
  }
  function dismissPasskeyPrompt(userId) {
    const thirtyDaysMs = 30 * 24 * 60 * 60 * 1e3;
    try {
      window.localStorage.setItem(
        localStorageKey(userId, "passkeyPromptDismissedUntil"),
        String(Date.now() + thirtyDaysMs)
      );
    } catch (_error) {
    }
  }
  function isPasskeyPromptDismissed(userId) {
    try {
      const dismissedUntil = Number(window.localStorage.getItem(localStorageKey(userId, "passkeyPromptDismissedUntil")) || "0");
      return dismissedUntil > Date.now();
    } catch (_error) {
      return false;
    }
  }
  function registrationPayload(control, credential) {
    const payload = serializeRegistrationCredential(credential);
    if (control.deviceName.value.trim()) {
      payload.name = control.deviceName.value.trim();
    }
    return payload;
  }
  function serializeRegistrationCredential(credential) {
    const response = credential.response;
    if (!(response instanceof AuthenticatorAttestationResponse)) {
      throw new Error("Invalid registration credential response.");
    }
    return {
      rawId: arrayBufferToBase64Url(credential.rawId),
      response: {
        clientDataJSON: arrayBufferToBase64Url(response.clientDataJSON),
        attestationObject: arrayBufferToBase64Url(response.attestationObject),
        transports: typeof response.getTransports === "function" ? response.getTransports() : []
      },
      clientExtensionResults: credential.getClientExtensionResults()
    };
  }
  function serializeAuthenticationCredential(credential) {
    const response = credential.response;
    if (!(response instanceof AuthenticatorAssertionResponse)) {
      throw new Error("Invalid authentication credential response.");
    }
    return {
      rawId: arrayBufferToBase64Url(credential.rawId),
      response: {
        clientDataJSON: arrayBufferToBase64Url(response.clientDataJSON),
        authenticatorData: arrayBufferToBase64Url(response.authenticatorData),
        signature: arrayBufferToBase64Url(response.signature),
        userHandle: response.userHandle ? arrayBufferToBase64Url(response.userHandle) : null
      },
      clientExtensionResults: credential.getClientExtensionResults()
    };
  }
  function registrationOptionsToNative(options) {
    if (typeof options.challenge !== "string" || options.user === void 0 || typeof options.user.id !== "string") {
      throw new Error("Invalid registration options.");
    }
    return {
      ...options,
      challenge: base64UrlToArrayBuffer(options.challenge),
      user: {
        ...options.user,
        id: base64UrlToArrayBuffer(options.user.id)
      },
      excludeCredentials: (options.excludeCredentials || []).map((descriptor) => ({
        ...descriptor,
        id: base64UrlToArrayBuffer(descriptor.id)
      }))
    };
  }
  function authenticationOptionsToNative(options) {
    if (typeof options.challenge !== "string") {
      throw new Error("Invalid authentication options.");
    }
    return {
      ...options,
      challenge: base64UrlToArrayBuffer(options.challenge),
      allowCredentials: (options.allowCredentials || []).map((descriptor) => ({
        ...descriptor,
        id: base64UrlToArrayBuffer(descriptor.id)
      }))
    };
  }
  function passkeysAreAvailable() {
    return typeof window.PublicKeyCredential === "function" && window.navigator.credentials !== void 0;
  }
  (function enablePasskeys() {
    if (typeof window === "undefined") return;
    function initPasskeys(event) {
      const target = detailTarget(event, "target");
      const root = isDomRoot(target) ? target : document;
      rootsWithRole(root, passkeyLoginDomAttr).forEach((element) => initializePasskeyRoot(element));
      rootsWithRole(root, passkeyRegistrationDomAttr).forEach((element) => initializePasskeyRoot(element));
      rootsWithRole(root, passkeySetupPromptDomAttr).forEach((element) => initializePasskeyRoot(element));
    }
    onAppPageReady(initPasskeys);
  })();
})();
