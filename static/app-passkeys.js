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

        root.querySelectorAll('.js-passkey-register').forEach(function (container) {
            if (container.dataset.passkeyInitialized === 'true') return;
            container.dataset.passkeyInitialized = 'true';

            const button = container.querySelector('.js-passkey-register-button');
            if (!button) return;

            button.addEventListener('click', function () {
                void runPasskeyRegistration(container, button);
            });
        });
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

            setPasskeyStatus(container, 'success', finishResponse.message || 'Passkey added.');
            redirectAfterPasskeySuccess(container, finishResponse);
        });
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
