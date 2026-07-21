import {
    encodePasskeyAuthenticationRequest,
    encodePasskeyRegistrationRequest,
    type PasskeyAuthenticationOptions,
    type PasskeyAuthenticationRequest,
    type PasskeyRegistrationOptions,
    type PasskeyRegistrationRequest,
} from "../generated/contracts";
import { arrayBufferToBase64Url, base64UrlToArrayBuffer } from "./base64url";

export function safePasskeyRedirectPath(value: string, origin: string): string | null {
    if (!value.startsWith("/") || value.startsWith("//")) return null;
    try {
        return new URL(value, origin).origin === origin ? value : null;
    } catch (_error) {
        return null;
    }
}

export function registrationOptionsToNative(
    options: PasskeyRegistrationOptions,
): PublicKeyCredentialCreationOptions {
    const authenticatorAttachment = options.authenticatorSelection.authenticatorAttachment;
    return {
        rp: {
            id: options.rp.id,
            name: options.rp.name,
        },
        user: {
            id: base64UrlToArrayBuffer(options.user.id),
            displayName: options.user.displayName,
            name: options.user.name,
        },
        challenge: base64UrlToArrayBuffer(options.challenge),
        pubKeyCredParams: options.pubKeyCredParams.map((parameter) => ({
            type: parameter.type,
            alg: parameter.alg,
        })),
        timeout: options.timeout,
        excludeCredentials: options.excludeCredentials.map((descriptor) => ({
            type: descriptor.type,
            id: base64UrlToArrayBuffer(descriptor.id),
        })),
        authenticatorSelection: {
            ...(authenticatorAttachment === undefined ? {} : { authenticatorAttachment }),
            residentKey: options.authenticatorSelection.residentKey,
            requireResidentKey: options.authenticatorSelection.requireResidentKey,
            userVerification: options.authenticatorSelection.userVerification,
        },
        attestation: options.attestation,
    };
}

export function authenticationOptionsToNative(
    options: PasskeyAuthenticationOptions,
): PublicKeyCredentialRequestOptions {
    return {
        challenge: base64UrlToArrayBuffer(options.challenge),
        timeout: options.timeout,
        rpId: options.rpId,
        allowCredentials: options.allowCredentials.map((descriptor) => ({
            type: descriptor.type,
            id: base64UrlToArrayBuffer(descriptor.id),
        })),
        userVerification: options.userVerification,
    };
}

export function serializeRegistrationCredential(
    credential: PublicKeyCredential,
    name: string | undefined,
): PasskeyRegistrationRequest {
    const response = credential.response;
    if (!(response instanceof AuthenticatorAttestationResponse)) {
        throw new Error("Invalid registration credential response.");
    }

    return encodePasskeyRegistrationRequest({
        rawId: arrayBufferToBase64Url(credential.rawId),
        response: {
            clientDataJSON: arrayBufferToBase64Url(response.clientDataJSON),
            attestationObject: arrayBufferToBase64Url(response.attestationObject),
            transports: typeof response.getTransports === "function"
                ? response.getTransports()
                : [],
        },
        clientExtensionResults: credential.getClientExtensionResults(),
        ...(name === undefined ? {} : { name }),
    });
}

export function serializeAuthenticationCredential(
    credential: PublicKeyCredential,
): PasskeyAuthenticationRequest {
    const response = credential.response;
    if (!(response instanceof AuthenticatorAssertionResponse)) {
        throw new Error("Invalid authentication credential response.");
    }

    return encodePasskeyAuthenticationRequest({
        rawId: arrayBufferToBase64Url(credential.rawId),
        response: {
            clientDataJSON: arrayBufferToBase64Url(response.clientDataJSON),
            authenticatorData: arrayBufferToBase64Url(response.authenticatorData),
            signature: arrayBufferToBase64Url(response.signature),
            userHandle: response.userHandle === null
                ? null
                : arrayBufferToBase64Url(response.userHandle),
        },
        clientExtensionResults: credential.getClientExtensionResults(),
    });
}
