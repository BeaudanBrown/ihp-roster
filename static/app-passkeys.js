"use strict";
(() => {
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

  // frontend/ts/generated/contracts.ts
  var pageReadyEvent = "bepis:page-ready";

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

  // frontend/ts/app-passkeys.ts
  (function enablePasskeys() {
    if (typeof window === "undefined") return;
    function initPasskeyAuth(event) {
      const target = detailTarget(event, "target");
      const root = isDomRoot(target) ? target : document;
      root.querySelectorAll(".js-passkey-login").forEach(function(container) {
        if (container.dataset.passkeyInitialized === "true") return;
        container.dataset.passkeyInitialized = "true";
        const button = container.querySelector(".js-passkey-login-button");
        if (button === null) return;
        button.addEventListener("click", function() {
          void runPasskeyLogin(container, button);
        });
      });
      root.querySelectorAll(".js-passkey-register").forEach(function(container) {
        if (container.dataset.passkeyInitialized === "true") return;
        container.dataset.passkeyInitialized = "true";
        const button = container.querySelector(".js-passkey-register-button");
        if (button === null) return;
        button.addEventListener("click", function() {
          void runPasskeyRegistration(container, button);
        });
      });
      root.querySelectorAll(".js-passkey-setup-prompt").forEach(function(container) {
        if (container.dataset.passkeyInitialized === "true") return;
        container.dataset.passkeyInitialized = "true";
        initPasskeySetupPrompt(container);
      });
    }
    async function runPasskeyLogin(container, button) {
      await withPasskeyButton(container, button, async function() {
        setPasskeyStatus(container, "info", "Waiting for your passkey...");
        const beginResponse = await postJson(container.dataset.beginUrl);
        const credential = await window.navigator.credentials.get({
          publicKey: authenticationOptionsToNative(beginResponse)
        });
        if (!(credential instanceof PublicKeyCredential)) throw new Error("No passkey was selected.");
        const finishResponse = await postJson(
          container.dataset.finishUrl,
          serializeAuthenticationCredential(credential)
        );
        markPasskeySeen(finishResponse.userId);
        setPasskeyStatus(container, "success", "Signed in.");
        redirectAfterPasskeySuccess(container, finishResponse);
      });
    }
    async function runPasskeyRegistration(container, button) {
      await withPasskeyButton(container, button, async function() {
        setPasskeyStatus(container, "info", "Waiting for your passkey...");
        const beginResponse = await postJson(container.dataset.beginUrl);
        const credential = await window.navigator.credentials.create({
          publicKey: registrationOptionsToNative(beginResponse)
        });
        if (!(credential instanceof PublicKeyCredential)) throw new Error("Passkey registration was cancelled.");
        const finishResponse = await postJson(
          container.dataset.finishUrl,
          registrationPayload(container, credential)
        );
        markPasskeySeen(finishResponse.userId);
        if (finishResponse.recoveryCode) {
          setRecoveryCodeStatus(container, finishResponse.recoveryCode, container.dataset.successRedirect);
        } else {
          setPasskeyStatus(container, "success", finishResponse.message || "Passkey added.");
          redirectAfterPasskeySuccess(container, finishResponse);
        }
      });
    }
    function initPasskeySetupPrompt(container) {
      const userId = container.dataset.userId;
      const mode = container.dataset.mode;
      if (!passkeysAreAvailable() || userId === void 0 || userId === "") {
        container.remove();
        document.body.classList.remove("modal-open");
        return;
      }
      if (isPasskeyPromptDismissed(userId)) {
        container.remove();
        document.body.classList.remove("modal-open");
        return;
      }
      if (mode === "additional-device" && hasPasskeySeen(userId)) {
        container.remove();
        document.body.classList.remove("modal-open");
        return;
      }
      container.classList.remove("d-none");
      document.body.classList.add("modal-open");
      const dismissButton = container.querySelector('[data-dialog-overlay-close="true"]');
      if (dismissButton !== null) {
        dismissButton.addEventListener("click", function(event) {
          event.preventDefault();
          dismissPasskeyPrompt(userId);
          container.remove();
          document.body.classList.remove("modal-open");
        });
      }
    }
    async function withPasskeyButton(container, button, callback) {
      if (!passkeysAreAvailable()) {
        setPasskeyStatus(container, "danger", "Passkeys are not supported in this browser.");
        return;
      }
      const originalHtml = button.innerHTML;
      button.disabled = true;
      button.innerHTML = '<span class="spinner-border spinner-border-sm me-2"></span>Please wait';
      try {
        await callback();
      } catch (error) {
        setPasskeyStatus(container, "danger", error instanceof Error ? error.message : "Passkey request failed.");
      } finally {
        button.disabled = false;
        button.innerHTML = originalHtml;
      }
    }
    async function postJson(url, payload) {
      const hasPayload = payload !== void 0;
      const response = await window.fetch(url ?? "", {
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
      const json = await response.json().catch(function() {
        return {};
      });
      if (!response.ok) {
        if (typeof json.redirectTo === "string") {
          window.location.assign(json.redirectTo);
        }
        throw new Error(typeof json.error === "string" ? json.error : "Passkey request failed.");
      }
      return json;
    }
    function setPasskeyStatus(container, tone, message) {
      const element = passkeyStatusElement(container);
      if (element === null) return;
      element.className = `alert alert-${tone} mt-3`;
      element.textContent = message;
    }
    function setRecoveryCodeStatus(container, recoveryCode, successRedirect) {
      const element = passkeyStatusElement(container);
      if (element === null) return;
      element.className = "alert alert-warning mt-3";
      element.textContent = "";
      const title = document.createElement("strong");
      title.textContent = "Save this recovery code now.";
      const body = document.createElement("p");
      body.className = "mb-2";
      body.textContent = "This code is shown once and can be used if you lose access to your passkey.";
      const code = document.createElement("code");
      code.className = "d-block fs-5 my-2 user-select-all";
      code.textContent = recoveryCode;
      element.append(title, body, code);
      if (successRedirect !== void 0 && successRedirect !== "") {
        const link = document.createElement("a");
        link.className = "btn btn-sm btn-primary mt-2";
        link.href = successRedirect;
        link.textContent = "I have saved it";
        element.append(link);
      }
    }
    function passkeyStatusElement(container) {
      const targetId = container.dataset.statusId;
      if (targetId === void 0 || targetId === "") return null;
      const element = document.getElementById(targetId);
      return element instanceof HTMLElement ? element : null;
    }
    function redirectAfterPasskeySuccess(container, response) {
      const redirectTo = response.redirectTo || container.dataset.successRedirect;
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
    function registrationPayload(container, credential) {
      const payload = serializeRegistrationCredential(credential);
      const nameInput = container.querySelector(".js-passkey-name");
      if (nameInput !== null && nameInput.value.trim()) {
        payload.name = nameInput.value.trim();
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
        excludeCredentials: (options.excludeCredentials || []).map(function(descriptor) {
          return {
            ...descriptor,
            id: base64UrlToArrayBuffer(descriptor.id)
          };
        })
      };
    }
    function authenticationOptionsToNative(options) {
      if (typeof options.challenge !== "string") {
        throw new Error("Invalid authentication options.");
      }
      return {
        ...options,
        challenge: base64UrlToArrayBuffer(options.challenge),
        allowCredentials: (options.allowCredentials || []).map(function(descriptor) {
          return {
            ...descriptor,
            id: base64UrlToArrayBuffer(descriptor.id)
          };
        })
      };
    }
    function passkeysAreAvailable() {
      return typeof window.PublicKeyCredential === "function" && window.navigator.credentials !== void 0;
    }
    onAppPageReady(initPasskeyAuth);
  })();
})();
