(function enablePasskeys() {
    if (typeof window === 'undefined') return;

    function initPasskeyAuth(event) {
        const root = event && event.detail && event.detail.target instanceof HTMLElement
            ? event.detail.target
            : document;

        root.querySelectorAll('.js-passkey-login').forEach(function (container) {
            if (container.dataset.passkeyInitialized === 'true') return;
            container.dataset.passkeyInitialized = 'true';

            const button = container.querySelector('.js-passkey-login-button');
            if (!button) return;

            button.addEventListener('click', function () {
                void runPasskeyLogin(container, button);
            });
        });

        root.querySelectorAll('.js-passkey-first-login').forEach(function (container) {
            if (container.dataset.passkeyInitialized === 'true') return;
            container.dataset.passkeyInitialized = 'true';

            const button = container.querySelector('.js-passkey-first-login-button');
            if (!button) return;

            button.addEventListener('click', function (event) {
                event.preventDefault();
                void runPasskeyFirstLogin(container, button);
            });
        });

        root.querySelectorAll('.js-passkey-register').forEach(function (container) {
            if (container.dataset.passkeyInitialized === 'true') return;
            container.dataset.passkeyInitialized = 'true';

            const button = container.querySelector('.js-passkey-register-button');
            if (!button) return;

            button.addEventListener('click', function () {
                void runPasskeyRegistration(container, button);
            });
        });

        root.querySelectorAll('.js-passkey-setup-prompt').forEach(function (container) {
            if (container.dataset.passkeyInitialized === 'true') return;
            container.dataset.passkeyInitialized = 'true';
            initPasskeySetupPrompt(container);
        });
    }

    async function runPasskeyFirstLogin(container, button) {
        if (!window.PublicKeyCredential || !window.navigator.credentials) {
            redirectToFallback(container);
            return;
        }

        const originalText = button.textContent;
        button.textContent = 'Checking for passkey...';

        try {
            const beginResponse = await postJson(container.dataset.beginUrl, {});
            const credential = await window.navigator.credentials.get({
                publicKey: authenticationOptionsToNative(beginResponse),
                signal: timeoutSignal(10000),
            });
            if (!credential) throw new Error('No passkey was selected.');

            const finishResponse = await postJson(
                container.dataset.finishUrl,
                serializeAuthenticationCredential(credential)
            );

            markPasskeySeen(finishResponse.userId);
            redirectAfterPasskeySuccess(container, finishResponse);
        } catch (error) {
            redirectToFallback(container);
        } finally {
            button.textContent = originalText;
        }
    }

    async function runPasskeyLogin(container, button) {
        await withPasskeyButton(container, button, async function () {
            setPasskeyStatus(container, 'info', 'Waiting for your passkey...');
            const beginResponse = await postJson(container.dataset.beginUrl, {});
            const credential = await window.navigator.credentials.get({
                publicKey: authenticationOptionsToNative(beginResponse),
            });
            if (!credential) throw new Error('No passkey was selected.');

            const finishResponse = await postJson(
                container.dataset.finishUrl,
                serializeAuthenticationCredential(credential)
            );

            markPasskeySeen(finishResponse.userId);
            setPasskeyStatus(container, 'success', 'Signed in.');
            redirectAfterPasskeySuccess(container, finishResponse);
        });
    }

    async function runPasskeyRegistration(container, button) {
        await withPasskeyButton(container, button, async function () {
            setPasskeyStatus(container, 'info', 'Waiting for your passkey...');
            const beginResponse = await postJson(container.dataset.beginUrl, {});
            const credential = await window.navigator.credentials.create({
                publicKey: registrationOptionsToNative(beginResponse),
            });
            if (!credential) throw new Error('Passkey registration was cancelled.');

            const finishResponse = await postJson(
                container.dataset.finishUrl,
                serializeRegistrationCredential(credential)
            );

            markPasskeySeen(finishResponse.userId);
            setPasskeyStatus(container, 'success', finishResponse.message || 'Passkey added.');
            redirectAfterPasskeySuccess(container, finishResponse);
        });
    }

    function initPasskeySetupPrompt(container) {
        const userId = container.dataset.userId;
        const mode = container.dataset.mode;

        if (!window.PublicKeyCredential || !window.navigator.credentials || !userId) {
            container.remove();
            return;
        }

        if (isPasskeyPromptDismissed(userId)) {
            container.remove();
            return;
        }

        if (mode === 'additional-device' && hasPasskeySeen(userId)) {
            container.remove();
            return;
        }

        container.classList.remove('d-none');

        const setupButton = container.querySelector('.js-passkey-setup-button');
        if (setupButton) {
            setupButton.addEventListener('click', function () {
                void runPasskeyRegistration(container, setupButton);
            });
        }

        const dismissButton = container.querySelector('.js-passkey-setup-dismiss');
        if (dismissButton) {
            dismissButton.addEventListener('click', function () {
                dismissPasskeyPrompt(userId);
                container.remove();
            });
        }
    }

    async function withPasskeyButton(container, button, callback) {
        if (!window.PublicKeyCredential || !window.navigator.credentials) {
            setPasskeyStatus(container, 'danger', 'Passkeys are not supported in this browser.');
            return;
        }

        const originalHtml = button.innerHTML;
        button.disabled = true;
        button.innerHTML = '<span class="spinner-border spinner-border-sm me-2"></span>Please wait';

        try {
            await callback();
        } catch (error) {
            setPasskeyStatus(container, 'danger', error.message || 'Passkey request failed.');
        } finally {
            button.disabled = false;
            button.innerHTML = originalHtml;
        }
    }

    async function postJson(url, payload) {
        const response = await window.fetch(url, {
            method: 'POST',
            credentials: 'same-origin',
            headers: {
                Accept: 'application/json',
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(payload),
        });

        const json = await response.json().catch(function () {
            return {};
        });
        if (!response.ok) {
            throw new Error(json.error || 'Passkey request failed.');
        }
        return json;
    }

    function setPasskeyStatus(container, tone, message) {
        if (!container) return;
        const targetId = container.dataset.statusId;
        if (!targetId) return;
        const element = document.getElementById(targetId);
        if (!element) return;

        element.className = `alert alert-${tone} mt-3`;
        element.textContent = message;
    }

    function redirectAfterPasskeySuccess(container, response) {
        const redirectTo = response.redirectTo || container.dataset.successRedirect;
        if (!redirectTo) return;
        window.location.assign(redirectTo);
    }

    function redirectToFallback(container) {
        window.location.assign(container.dataset.fallbackUrl || '/NewSession');
    }

    function timeoutSignal(timeoutMs) {
        if (!window.AbortController) return undefined;

        const controller = new window.AbortController();
        window.setTimeout(function () {
            controller.abort();
        }, timeoutMs);
        return controller.signal;
    }

    function localStorageKey(userId, key) {
        return `ihpRoster.${key}.${userId}`;
    }

    function markPasskeySeen(userId) {
        if (!userId) return;
        try {
            window.localStorage.setItem(localStorageKey(userId, 'passkeySeen'), '1');
        } catch (error) {
            // Local storage is a UX hint only; auth must not depend on it.
        }
    }

    function hasPasskeySeen(userId) {
        try {
            return window.localStorage.getItem(localStorageKey(userId, 'passkeySeen')) === '1';
        } catch (error) {
            return false;
        }
    }

    function dismissPasskeyPrompt(userId) {
        const thirtyDaysMs = 30 * 24 * 60 * 60 * 1000;
        try {
            window.localStorage.setItem(
                localStorageKey(userId, 'passkeyPromptDismissedUntil'),
                String(Date.now() + thirtyDaysMs)
            );
        } catch (error) {
            // Ignore; dismissal is best-effort browser-local state.
        }
    }

    function isPasskeyPromptDismissed(userId) {
        try {
            const dismissedUntil = Number(window.localStorage.getItem(localStorageKey(userId, 'passkeyPromptDismissedUntil')) || '0');
            return dismissedUntil > Date.now();
        } catch (error) {
            return false;
        }
    }

    function base64UrlToBuffer(value) {
        const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
        const padded = normalized + '='.repeat((4 - normalized.length % 4) % 4);
        const binary = window.atob(padded);
        const bytes = new Uint8Array(binary.length);

        for (let index = 0; index < binary.length; index += 1) {
            bytes[index] = binary.charCodeAt(index);
        }

        return bytes.buffer;
    }

    function bufferToBase64Url(buffer) {
        const bytes = new Uint8Array(buffer);
        let binary = '';

        bytes.forEach(function (byte) {
            binary += String.fromCharCode(byte);
        });

        return window.btoa(binary)
            .replace(/\+/g, '-')
            .replace(/\//g, '_')
            .replace(/=+$/g, '');
    }

    function serializeRegistrationCredential(credential) {
        return {
            rawId: bufferToBase64Url(credential.rawId),
            response: {
                clientDataJSON: bufferToBase64Url(credential.response.clientDataJSON),
                attestationObject: bufferToBase64Url(credential.response.attestationObject),
                transports: typeof credential.response.getTransports === 'function'
                    ? credential.response.getTransports()
                    : [],
            },
            clientExtensionResults: credential.getClientExtensionResults(),
        };
    }

    function serializeAuthenticationCredential(credential) {
        return {
            rawId: bufferToBase64Url(credential.rawId),
            response: {
                clientDataJSON: bufferToBase64Url(credential.response.clientDataJSON),
                authenticatorData: bufferToBase64Url(credential.response.authenticatorData),
                signature: bufferToBase64Url(credential.response.signature),
                userHandle: credential.response.userHandle
                    ? bufferToBase64Url(credential.response.userHandle)
                    : null,
            },
            clientExtensionResults: credential.getClientExtensionResults(),
        };
    }

    function registrationOptionsToNative(options) {
        if (!options.user || !options.user.id) {
            throw new Error('Invalid registration options.');
        }

        return {
            ...options,
            challenge: base64UrlToBuffer(options.challenge),
            user: {
                ...options.user,
                id: base64UrlToBuffer(options.user.id),
            },
            excludeCredentials: (options.excludeCredentials || []).map(function (descriptor) {
                return {
                    ...descriptor,
                    id: base64UrlToBuffer(descriptor.id),
                };
            }),
        };
    }

    function authenticationOptionsToNative(options) {
        return {
            ...options,
            challenge: base64UrlToBuffer(options.challenge),
            allowCredentials: (options.allowCredentials || []).map(function (descriptor) {
                return {
                    ...descriptor,
                    id: base64UrlToBuffer(descriptor.id),
                };
            }),
        };
    }

    document.addEventListener('app:page-ready', initPasskeyAuth);
})();
