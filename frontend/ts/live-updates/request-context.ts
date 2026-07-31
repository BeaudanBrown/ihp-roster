import type { FrontendSurfaceMountedFragmentConfig } from "../generated/contracts";

export type SurfaceFragmentRequestDecorator = (
    url: string,
    fragment: FrontendSurfaceMountedFragmentConfig,
    target: HTMLElement,
) => string;

type RequestContextGlobal = typeof globalThis & {
    __bepisSurfaceFragmentRequestDecorators?: Set<SurfaceFragmentRequestDecorator>;
};

function decorators(): Set<SurfaceFragmentRequestDecorator> {
    const runtimeGlobal = globalThis as RequestContextGlobal;
    runtimeGlobal.__bepisSurfaceFragmentRequestDecorators ??= new Set();
    return runtimeGlobal.__bepisSurfaceFragmentRequestDecorators;
}

export function registerSurfaceFragmentRequestDecorator(decorator: SurfaceFragmentRequestDecorator): () => void {
    decorators().add(decorator);
    return () => decorators().delete(decorator);
}

export function decorateSurfaceFragmentRequest(
    url: string,
    fragment: FrontendSurfaceMountedFragmentConfig,
    target: HTMLElement,
): string {
    let decoratedUrl = url;
    for (const decorator of decorators()) decoratedUrl = decorator(decoratedUrl, fragment, target);
    return decoratedUrl;
}
