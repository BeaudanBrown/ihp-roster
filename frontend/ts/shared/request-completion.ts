// Follow-up work belongs to the initiating element's exact request lifetime,
// never to all network traffic or every refresh on the page.
const scopes = new WeakMap<EventTarget, Set<Promise<void>>>();

export function beginRequestCompletion(target: EventTarget): () => Promise<void> {
    const work = new Set<Promise<void>>();
    scopes.set(target, work);
    return async () => {
        while (work.size > 0) await Promise.allSettled([...work]);
        if (scopes.get(target) === work) scopes.delete(target);
    };
}

export function trackRequestCompletion(target: EventTarget | null, completion: Promise<void>): void {
    const work = target === null ? undefined : scopes.get(target);
    if (!work) return;
    work.add(completion);
    void completion.then(() => work.delete(completion), () => work.delete(completion));
}
