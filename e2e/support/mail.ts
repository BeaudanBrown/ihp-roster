import { expect, type APIRequestContext } from '@playwright/test';
import { E2E_TIMEOUT } from '../timeouts';

type MailHogAddress = {
    Mailbox?: string;
    Domain?: string;
};

type MailHogMessage = {
    Content?: {
        Headers?: Record<string, string[]>;
        Body?: string;
    };
    Raw?: {
        Data?: string;
    };
    To?: MailHogAddress[];
};

function mailhogBaseUrl() {
    return process.env.MAILHOG_BASE_URL ?? 'http://127.0.0.1:8025';
}

function mailhogMessageRecipients(message: MailHogMessage) {
    return (message.To ?? [])
        .map((address) => {
            if (!address.Mailbox || !address.Domain) return null;
            return `${address.Mailbox}@${address.Domain}`.toLowerCase();
        })
        .filter((value): value is string => Boolean(value));
}

function mailhogMessageBody(message: MailHogMessage) {
    const rawBody = message.Content?.Body ?? message.Raw?.Data ?? '';

    return rawBody
        // Quoted-printable soft wraps join onto the next line.
        .replace(/=\r?\n/g, '')
        // Decode quoted-printable byte escapes used in MailHog payloads.
        .replace(/=([0-9A-F]{2})/gi, (_match, hex: string) =>
            String.fromCharCode(Number.parseInt(hex, 16)),
        );
}

export function extractFirstUrl(text: string) {
    const match = text.match(/https?:\/\/[^\s>")]+/);
    if (!match) {
        throw new Error(`Could not find URL in text:\n${text}`);
    }
    return match[0];
}

export function inviteUrlForCurrentBase(rawUrl: string, baseURL: string) {
    const parsed = new URL(rawUrl);
    return new URL(`${parsed.pathname}${parsed.search}`, baseURL).toString();
}

export async function waitForMailhogMessages(
    request: APIRequestContext,
    recipient: string,
    minimumCount = 1,
    timeoutMs = E2E_TIMEOUT.mailhog,
) {
    const normalizedRecipient = recipient.toLowerCase();
    const deadline = Date.now() + timeoutMs;
    let lastCount = 0;

    while (Date.now() < deadline) {
        const response = await request.get(`${mailhogBaseUrl()}/api/v2/messages`);
        expect(response.ok()).toBeTruthy();
        const payload = (await response.json()) as { items?: MailHogMessage[] };
        const matches = (payload.items ?? []).filter((message) =>
            mailhogMessageRecipients(message).includes(normalizedRecipient),
        );
        if (matches.length >= minimumCount) {
            return matches;
        }
        lastCount = matches.length;
        await new Promise((resolve) => setTimeout(resolve, 500));
    }

    throw new Error(
        `Expected at least ${minimumCount} MailHog messages for ${recipient}, but only found ${lastCount} within ${timeoutMs}ms`,
    );
}

export async function waitForMailhogMessage(request: APIRequestContext, recipient: string, timeoutMs = E2E_TIMEOUT.mailhog) {
    const messages = await waitForMailhogMessages(request, recipient, 1, timeoutMs);
    return messages[0];
}

export async function expectMailhogMessageCount(
    request: APIRequestContext,
    recipient: string,
    expectedCount: number,
    timeoutMs = E2E_TIMEOUT.mailhog,
) {
    const normalizedRecipient = recipient.toLowerCase();

    await expect
        .poll(async () => {
            const response = await request.get(`${mailhogBaseUrl()}/api/v2/messages`);
            expect(response.ok()).toBeTruthy();
            const payload = (await response.json()) as { items?: MailHogMessage[] };
            return (payload.items ?? []).filter((message) =>
                mailhogMessageRecipients(message).includes(normalizedRecipient),
            ).length;
        }, {
            timeout: timeoutMs
        })
        .toBe(expectedCount);
}

export function mailhogMessageSubject(message: MailHogMessage) {
    return message.Content?.Headers?.Subject?.[0] ?? '';
}

export function mailhogMessageText(message: MailHogMessage) {
    return mailhogMessageBody(message);
}
